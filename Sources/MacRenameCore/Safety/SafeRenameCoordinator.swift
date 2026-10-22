import Darwin
import Foundation

/// A conservative, local-only rename path for explicitly selected objects.
/// Never expands a directory selection, runs a shell, or sends file contents.
/// Destination replacement is prevented atomically by the kernel. Another
/// process with the same user's privileges can still replace a source between
/// the last identity check and rename; use private, quiescent directories.
public actor SafeRenameCoordinator {
    private let journalDirectory: URL
    private var plans: [UUID: [SafeFileSnapshot]] = [:]

    public init(journalDirectory: URL) {
        self.journalDirectory = journalDirectory
    }

    public func preview(_ requests: [SafeRenameRequest]) throws -> SafeRenamePlan {
        guard !requests.isEmpty, requests.count <= 500 else {
            throw SafeFS.fail("Select between 1 and 500 objects per batch.")
        }
        var snapshots: [SafeFileSnapshot] = []
        var entries: [SafeRenamePlanEntry] = []
        var sources = Set<String>()
        var targets = Set<String>()
        for request in requests {
            var issues: [String] = []
            do {
                guard SafeFS.validAbsoluteURL(request.sourceURL), SafeFS.validBasename(request.sourceURL.lastPathComponent) else {
                    throw SafeFS.fail("The selected path is not a supported absolute local filename.")
                }
                guard SafeFS.validBasename(request.proposedName) else {
                    throw SafeFS.fail("The proposed name must be a single visible filename of at most 255 bytes, without path separators or control characters.")
                }
                let source = request.sourceURL
                let parent = source.deletingLastPathComponent()
                guard SafeFS.validAbsoluteURL(parent.appendingPathComponent(request.proposedName)) else {
                    throw SafeFS.fail("The proposed full path exceeds the supported path limit.")
                }
                let fd = try SafeFS.openDirectory(parent)
                defer { close(fd) }
                let parentIdentity = try SafeFS.identity(fd: fd)
                if let expected = request.expectedParentIdentity {
                    guard FolderAssistIdentity(try SafeFS.folderAssistStat(fd: fd)) == expected else {
                        throw SafeFS.fail("The observed parent folder was replaced; the suggestion is no longer valid.")
                    }
                }
                guard parentIdentity.owner == getuid(), parentIdentity.mode & 0o022 == 0 else {
                    throw SafeFS.fail("The parent folder must belong to you and must not be writable by other users.")
                }
                let identity = try SafeFS.identity(at: source.lastPathComponent, parentFD: fd)
                try Self.protectionCheck(source: source, destinationName: request.proposedName, isDirectory: identity.isDirectory)
                guard source.lastPathComponent != request.proposedName else { throw SafeFS.fail("The name is already unchanged.") }
                guard SafeFS.folded(source.lastPathComponent) != SafeFS.folded(request.proposedName) else {
                    throw SafeFS.fail("Case-only renames require a temporary name and are intentionally refused.")
                }
                if !identity.isDirectory {
                    guard SafeFilenameExtension.suffix(for: source.lastPathComponent) == SafeFilenameExtension.suffix(for: request.proposedName) else {
                        throw SafeFS.fail("The complete file extension and its capitalization must remain unchanged.")
                    }
                }
                let sourceKey = "\(parentIdentity.device):\(parentIdentity.inode):\(SafeFS.folded(source.lastPathComponent))"
                let targetKey = "\(parentIdentity.device):\(parentIdentity.inode):\(SafeFS.folded(request.proposedName))"
                guard sources.insert(sourceKey).inserted else { throw SafeFS.fail("The same source was selected more than once.") }
                guard targets.insert(targetKey).inserted else { throw SafeFS.fail("Multiple suggestions have the same case-insensitive destination.") }
                try SafeFS.ensureDestinationAbsent(request.proposedName, parentFD: fd)
                let (fingerprint, digest) = try SafeFS.fingerprint(name: source.lastPathComponent, parentFD: fd)
                if let expected = request.expectedSourceIdentity {
                    let current = try SafeFS.folderAssistStat(at: source.lastPathComponent, parentFD: fd)
                    guard FolderAssistIdentity(current) == expected,
                          current.st_mode & 0o022 == 0,
                          fingerprint.sameObject(as: SafeFileIdentity(current)) else {
                        throw SafeFS.fail("The observed folder was replaced or is writable by other users; the suggestion is no longer valid.")
                    }
                }
                if let expected = request.expectedParentIdentity {
                    guard FolderAssistIdentity(try SafeFS.folderAssistStat(fd: fd)) == expected else {
                        throw SafeFS.fail("The observed parent folder changed while being checked.")
                    }
                }
                snapshots.append(SafeFileSnapshot(parentURL: parent, sourceName: source.lastPathComponent,
                    destinationName: request.proposedName, parentIdentity: parentIdentity, identity: fingerprint, digest: digest))
            } catch { issues.append(error.localizedDescription) }
            entries.append(SafeRenamePlanEntry(sourceURL: request.sourceURL, proposedName: request.proposedName, issues: issues))
        }
        let id = UUID()
        if entries.allSatisfy(\.isReady) {
            if plans.count >= 32 { plans.removeAll() }
            plans[id] = snapshots
        }
        return SafeRenamePlan(id: id, entries: entries)
    }

    /// Confirmation must be obtained by the UI after showing this exact plan.
    /// Preflight errors throw before mutation. Once a journal is written,
    /// partial failures are returned in the receipt and retained for recovery.
    public func execute(_ plan: SafeRenamePlan, confirmedByUser: Bool) throws -> SafeRenameReceipt {
        guard confirmedByUser else { throw SafeFS.fail("Explicit user confirmation is required after preview.") }
        guard plan.canExecute, let snapshots = plans.removeValue(forKey: plan.id), snapshots.count == plan.entries.count else {
            throw SafeFS.fail("This plan is blocked, expired, or already used; create a fresh preview.")
        }
        // Validate every object before beginning; cycles/swaps are rejected by
        // destination-absence checks rather than using temporary filenames.
        for snapshot in snapshots { try validateBeforeRename(snapshot, undo: false) }
        // Different UI entry points share this actor but may retain independent
        // previews. Inspect only private journal metadata here; historical
        // document paths must not be probed or recovered as a side effect.
        guard try !history(recoverInterrupted: false).contains(where: \.requiresRecovery) else {
            throw SafeFS.fail("An interrupted operation requires history recovery before a new rename.")
        }
        var journal = SafeJournal(id: plan.id, records: snapshots.map { SafeJournalRecord(snapshot: $0, phase: .planned) })
        try writeJournal(journal)
        for index in journal.records.indices {
            let snapshot = journal.records[index].snapshot
            do {
                try validateBeforeRename(snapshot, undo: false)
                journal.records[index].phase = .attempting
                try writeJournal(journal)
                let parentFD = try SafeFS.checkedParent(snapshot)
                defer { close(parentFD) }
                try SafeFS.verifyParentPath(snapshot, fd: parentFD)
                try SafeFS.verify(snapshot, name: snapshot.sourceName, parentFD: parentFD, exactMetadata: true)
                try SafeFS.ensureDestinationAbsent(snapshot.destinationName, parentFD: parentFD)
                try SafeFS.renameExclusive(from: snapshot.sourceName, to: snapshot.destinationName, parentFD: parentFD)
                try SafeFS.verify(snapshot, name: snapshot.destinationName, parentFD: parentFD, exactMetadata: false)
                journal.records[index].phase = .completed
                try writeJournal(journal)
                try SafeFS.verifyParentPath(snapshot, fd: parentFD)
            } catch {
                journal.failures.append("Stopped at \(snapshot.sourceName): \(error.localizedDescription)")
                do { try writeJournal(journal) } catch { journal.failures.append("Journal update failed; reopen history before further operations: \(error.localizedDescription)") }
                break
            }
        }
        return receipt(journal)
    }

    /// Loads only this coordinator's private journals. Recovery observes paths
    /// and fingerprints; it never moves a file automatically.
    public func history(recoverInterrupted: Bool = true) throws -> [SafeRenameReceipt] {
        let fd = try openJournalDirectory()
        defer { close(fd) }
        let filenames = try SafeFS.names(in: fd).filter { $0.hasSuffix(".json") }.sorted()
        guard filenames.count <= 10_000 else { throw SafeFS.fail("Too many journal files; review the private history folder.") }
        var result: [(createdAt: Date, receipt: SafeRenameReceipt)] = []
        for filename in filenames {
            guard let id = UUID(uuidString: String(filename.dropLast(5))) else { continue }
            var journal = try readJournal(id)
            if recoverInterrupted, reconcile(&journal) { try writeJournal(journal) }
            result.append((journal.createdAt, receipt(journal)))
        }
        return result.sorted { $0.createdAt < $1.createdAt }.map(\.receipt)
    }

    /// Reconcile one receipt only, after the UI obtains access to its parents.
    /// Other historical documents are not accessed as a side effect.
    public func recover(_ suppliedReceipt: SafeRenameReceipt) throws -> SafeRenameReceipt {
        var journal = try readJournal(suppliedReceipt.id)
        if reconcile(&journal) { try writeJournal(journal) }
        return receipt(journal)
    }

    private func reconcile(_ journal: inout SafeJournal) -> Bool {
        var changed = false
        for index in journal.records.indices where journal.records[index].phase == .attempting || journal.records[index].phase == .undoAttempting {
            let record = journal.records[index]
            let sourceMatches = matches(record.snapshot, atDestination: false)
            let destinationMatches = matches(record.snapshot, atDestination: true)
            if sourceMatches && !destinationMatches {
                journal.records[index].phase = record.phase == .undoAttempting ? .undone : .planned
                changed = true
            } else if destinationMatches && !sourceMatches {
                journal.records[index].phase = .completed
                changed = true
            } else {
                let message = "Recovery requires manual review for \(record.snapshot.sourceName); neither location can be identified unambiguously."
                if !journal.failures.contains(message) { journal.failures.append(message); changed = true }
            }
        }
        return changed
    }

    public func undo(_ suppliedReceipt: SafeRenameReceipt, confirmedByUser: Bool) throws -> SafeRenameReceipt {
        guard confirmedByUser else { throw SafeFS.fail("Explicit user confirmation is required before undo.") }
        // Never accept caller-provided paths. The UUID selects a validated
        // private journal, whose stored identities are checked again below.
        var journal = try readJournal(suppliedReceipt.id)
        guard !journal.records.contains(where: { $0.phase == .attempting || $0.phase == .undoAttempting }) else {
            throw SafeFS.fail("An interrupted operation requires history recovery before undo.")
        }
        let indices = journal.records.indices.reversed().filter { journal.records[$0].phase == .completed }
        guard !indices.isEmpty else { throw SafeFS.fail("No completed renames remain to undo.") }
        for index in indices {
            let snapshot = journal.records[index].snapshot
            do {
                try validateBeforeRename(snapshot, undo: true)
                journal.records[index].phase = .undoAttempting
                try writeJournal(journal)
                let fd = try SafeFS.checkedParent(snapshot)
                defer { close(fd) }
                try SafeFS.verifyParentPath(snapshot, fd: fd)
                try SafeFS.verify(snapshot, name: snapshot.destinationName, parentFD: fd, exactMetadata: false)
                try SafeFS.ensureDestinationAbsent(snapshot.sourceName, parentFD: fd)
                try SafeFS.renameExclusive(from: snapshot.destinationName, to: snapshot.sourceName, parentFD: fd)
                try SafeFS.verify(snapshot, name: snapshot.sourceName, parentFD: fd, exactMetadata: false)
                journal.records[index].phase = .undone
                try writeJournal(journal)
                try SafeFS.verifyParentPath(snapshot, fd: fd)
            } catch {
                journal.failures.append("Undo stopped at \(snapshot.destinationName): \(error.localizedDescription)")
                do { try writeJournal(journal) } catch { journal.failures.append("Journal update failed; reopen history before further operations.") }
                break
            }
        }
        return receipt(journal)
    }

    private func validateBeforeRename(_ snapshot: SafeFileSnapshot, undo: Bool) throws {
        let name = undo ? snapshot.destinationName : snapshot.sourceName
        try Self.protectionCheck(source: snapshot.parentURL.appendingPathComponent(name),
            destinationName: undo ? snapshot.sourceName : snapshot.destinationName, isDirectory: snapshot.identity.isDirectory)
        let fd = try SafeFS.checkedParent(snapshot)
        defer { close(fd) }
        try SafeFS.verifyParentPath(snapshot, fd: fd)
        try SafeFS.verify(snapshot, name: name, parentFD: fd, exactMetadata: !undo)
        try SafeFS.ensureDestinationAbsent(undo ? snapshot.sourceName : snapshot.destinationName, parentFD: fd)
    }

    private func matches(_ snapshot: SafeFileSnapshot, atDestination: Bool) -> Bool {
        do {
            let fd = try SafeFS.checkedParent(snapshot)
            defer { close(fd) }
            try SafeFS.verify(snapshot, name: atDestination ? snapshot.destinationName : snapshot.sourceName, parentFD: fd, exactMetadata: false)
            return true
        } catch { return false }
    }

    private func receipt(_ journal: SafeJournal) -> SafeRenameReceipt {
        SafeRenameReceipt(id: journal.id,
            completed: journal.records.filter { $0.phase == .completed }.map {
                SafeRenameRecord(sourceURL: $0.snapshot.sourceURL, destinationURL: $0.snapshot.destinationURL)
            }, failures: journal.failures, journalURL: journalURL(journal.id),
            requiresRecovery: journal.records.contains { $0.phase == .attempting || $0.phase == .undoAttempting },
            recoveryParentURLs: Array(Set(journal.records.filter {
                $0.phase == .completed || $0.phase == .attempting || $0.phase == .undoAttempting
            }.map { $0.snapshot.parentURL })).sorted { $0.path < $1.path })
    }

    static func protectionCheck(source: URL, destinationName: String, isDirectory: Bool,
                                maximumDirectoryEntries: Int? = nil) throws {
        let protectedNames: Set<String> = ["agents.md", "skill.md", "claude.md", "makefile", "dockerfile", "gemfile", "rakefile", "license", "license.md", "readme", "readme.md", "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "cargo.toml", "cargo.lock", "package.swift", "package.resolved", "pyproject.toml", "setup.py", "requirements.txt", "cmakelists.txt", "go.mod", "go.sum", "project.yml", "info.plist", "main.tex", "thesis.tex"]
        let packageSuffixes = [".app", ".bundle", ".framework", ".plugin", ".photoslibrary", ".photolibrary", ".aplibrary", ".sparsebundle", ".xcodeproj", ".xcworkspace", ".pages", ".numbers", ".key"]
        let name = source.lastPathComponent.lowercased()
        guard !protectedNames.contains(name), !protectedNames.contains(destinationName.lowercased()) else {
            throw SafeFS.fail("A fixed filename used by an application or project is protected.")
        }
        guard !packageSuffixes.contains(where: { name.hasSuffix($0) || destinationName.lowercased().hasSuffix($0) }) else {
            throw SafeFS.fail("Application packages, document packages, and libraries are protected.")
        }
        let codeSuffixes: Set<String> = ["tex", "sty", "cls", "bib", "swift", "py", "js", "ts", "tsx", "jsx", "c", "h", "cpp", "sh", "zsh", "toml", "yaml", "yml", "xcconfig"]
        if !isDirectory && codeSuffixes.contains(source.pathExtension.lowercased()) {
            throw SafeFS.fail("Source code, TeX dependencies, and configuration files are protected.")
        }
        let projectMarkers: Set<String> = [".git", ".hg", ".svn", ".latexmkrc", "latexmkrc", "main.tex", "Main.tex", "thesis.tex", "Thesis.tex", "package.json", "Cargo.toml", "cargo.toml", "Package.swift", "package.swift", "pyproject.toml", "setup.py", "CMakeLists.txt", "cmakelists.txt", "go.mod", "project.yml"]
        // Recognizable dependency layouts are protected without listing broad
        // ancestors. Arbitrary project layouts cannot be inferred from a name;
        // the UI also requires users to confirm independent documents/exports.
        let dependencyFolders: Set<String> = ["sources", "src", "assets", "resources", "include", "headers", "frameworks", "pods", "carthage", "node_modules", ".build", "tests", "__pycache__"]
        let dependencySuffixes = [".xcassets", ".playground", ".playgroundbook", ".xcplayground"]
        var folder = isDirectory ? source : source.deletingLastPathComponent()
        while true {
            let folderName = folder.lastPathComponent.lowercased()
            if dependencyFolders.contains(folderName) || dependencySuffixes.contains(where: { folderName.hasSuffix($0) }) {
                throw SafeFS.fail("This is a recognized engineering dependency folder; use an independent export copy.")
            }
            // Ancestors need search access only. Listing every ancestor would
            // unnecessarily request access to the user's whole Documents folder.
            let fd = try SafeFS.openDirectory(folder, readingContents: false)
            do {
                for marker in projectMarkers {
                    var value = stat()
                    let result = marker.withCString { fstatat(fd, $0, &value, AT_SYMLINK_NOFOLLOW) }
                    if result == 0 {
                        throw SafeFS.fail("This object is inside a protected engineering or TeX project; use an independent export copy.")
                    }
                    guard errno == ENOENT || errno == ENOTDIR else {
                        throw SafeFS.posix("Check project protection without listing ancestor folders")
                    }
                }
                close(fd)
            } catch { close(fd); throw error }
            if folder == source.deletingLastPathComponent() {
                // The explicitly authorized parent can also be checked for
                // Xcode project names whose stem is not known in advance.
                let parent = try SafeFS.openDirectory(folder)
                let hasProject: Bool
                do {
                    hasProject = try SafeFS.names(in: parent, maximumCount: maximumDirectoryEntries).contains { $0.lowercased().hasSuffix(".xcodeproj") || $0.lowercased().hasSuffix(".xcworkspace") }
                    close(parent)
                } catch { close(parent); throw error }
                if hasProject { throw SafeFS.fail("The selected folder contains an Xcode project and is protected.") }
            }
            if packageSuffixes.contains(where: { folder.lastPathComponent.lowercased().hasSuffix($0) }) {
                throw SafeFS.fail("Items inside application packages or libraries are protected.")
            }
            if folder.path == "/" { break }
            folder = folder.deletingLastPathComponent()
        }
    }

    private func journalURL(_ id: UUID) -> URL { journalDirectory.appendingPathComponent(id.uuidString + ".json") }

    private func openJournalDirectory() throws -> Int32 {
        guard SafeFS.validAbsoluteURL(journalDirectory) else { throw SafeFS.fail("Invalid private history directory.") }
        // Create the application's private parent under an existing, no-follow
        // directory, then the history leaf. Never follow links or chmod an
        // existing user directory to make it fit our policy.
        let parentURL = journalDirectory.deletingLastPathComponent()
        let ancestor = try SafeFS.openDirectory(parentURL.deletingLastPathComponent())
        defer { close(ancestor) }
        let parentName = parentURL.lastPathComponent
        guard SafeFS.validBasename(parentName) else { throw SafeFS.fail("Invalid application history parent name.") }
        let parentCreated = parentName.withCString { mkdirat(ancestor, $0, 0o700) }
        guard parentCreated == 0 || errno == EEXIST else { throw SafeFS.posix("Create private application folder") }
        let parent = parentName.withCString { openat(ancestor, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard parent >= 0 else { throw SafeFS.posix("Open private application folder") }
        defer { close(parent) }
        let parentIdentity = try SafeFS.identity(fd: parent)
        guard parentIdentity.owner == getuid(), parentIdentity.mode & 0o077 == 0 else {
            throw SafeFS.fail("The application history parent must be owned by you with permissions 0700.")
        }
        let leaf = journalDirectory.lastPathComponent
        guard SafeFS.validBasename(leaf) else { throw SafeFS.fail("Invalid private history folder name.") }
        let created = leaf.withCString { mkdirat(parent, $0, 0o700) }
        guard created == 0 || errno == EEXIST else { throw SafeFS.posix("Create private history folder") }
        let fd = leaf.withCString { openat(parent, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw SafeFS.posix("Open private history folder") }
        do {
            let identity = try SafeFS.identity(fd: fd)
            guard identity.owner == getuid(), identity.mode & 0o077 == 0 else {
                throw SafeFS.fail("The history directory must be owned by you with permissions 0700.")
            }
            return fd
        } catch { close(fd); throw error }
    }

    private func writeJournal(_ journal: SafeJournal) throws {
        let fd = try openJournalDirectory()
        defer { close(fd) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(journal)
        guard data.count <= 4 * 1024 * 1024 else { throw SafeFS.fail("Journal size exceeds the safety limit.") }
        let temporary = ".pending_" + UUID().uuidString
        let file = temporary.withCString { openat(fd, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard file >= 0 else { throw SafeFS.posix("Create private journal") }
        defer { close(file); temporary.withCString { _ = unlinkat(fd, $0, 0) } }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(file, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw SafeFS.posix("Write journal")
                }
                guard count > 0 else { throw SafeFS.fail("Writing the journal made no progress.") }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw SafeFS.posix("Synchronize journal") }
        let name = journal.id.uuidString + ".json"
        let status = temporary.withCString { temporaryName in name.withCString { renameat(fd, temporaryName, fd, $0) } }
        guard status == 0, fsync(fd) == 0 else { throw SafeFS.posix("Commit journal") }
    }

    private func readJournal(_ id: UUID) throws -> SafeJournal {
        let fd = try openJournalDirectory()
        defer { close(fd) }
        let file = (id.uuidString + ".json").withCString { openat(fd, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) }
        guard file >= 0 else { throw SafeFS.posix("Open journal") }
        defer { close(file) }
        let identity = try SafeFS.identity(fd: file)
        guard identity.isRegular, identity.owner == getuid(), identity.links == 1, identity.mode & 0o077 == 0,
              identity.size > 0, identity.size <= 4 * 1024 * 1024 else { throw SafeFS.fail("Invalid journal ownership, type, permissions, or size.") }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 { if errno == EINTR { continue }; throw SafeFS.posix("Read journal") }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 4 * 1024 * 1024 else { throw SafeFS.fail("Journal grew beyond the safety limit.") }
        }
        guard try SafeFS.identity(fd: file) == identity else { throw SafeFS.fail("Journal changed while being read.") }
        let journal = try JSONDecoder().decode(SafeJournal.self, from: data)
        guard journal.schema == 1, journal.id == id, journal.createdAt.timeIntervalSinceReferenceDate.isFinite,
              !journal.records.isEmpty, journal.records.count <= 500,
              journal.failures.count <= 2000 else { throw SafeFS.fail("Invalid journal schema or record count.") }
        var sources = Set<String>()
        var targets = Set<String>()
        for record in journal.records {
            let snapshot = record.snapshot
            guard SafeFS.validAbsoluteURL(snapshot.parentURL), SafeFS.validAbsoluteURL(snapshot.sourceURL),
                  SafeFS.validAbsoluteURL(snapshot.destinationURL),
                  SafeFS.validBasename(snapshot.sourceName), SafeFS.validBasename(snapshot.destinationName),
                  snapshot.identity.owner == getuid(), snapshot.parentIdentity.owner == getuid(),
                  snapshot.identity.isRegular || snapshot.identity.isDirectory,
                  snapshot.sourceName != snapshot.destinationName,
                  snapshot.digest == "empty_directory" || (snapshot.digest.count == 64 && snapshot.digest.allSatisfy(\.isHexDigit)),
                  snapshot.identity.isDirectory || SafeFilenameExtension.suffix(for: snapshot.sourceName) == SafeFilenameExtension.suffix(for: snapshot.destinationName),
                  sources.insert(snapshot.sourceURL.path).inserted, targets.insert(SafeFS.folded(snapshot.destinationURL.path)).inserted else {
                throw SafeFS.fail("The private journal contains an invalid or ambiguous path record.")
            }
        }
        return journal
    }
}

private enum SafeJournalPhase: String, Codable { case planned, attempting, completed, undoAttempting, undone }
private struct SafeJournalRecord: Codable { let snapshot: SafeFileSnapshot; var phase: SafeJournalPhase }
private struct SafeJournal: Codable {
    let schema: Int
    let id: UUID
    let createdAt: Date
    var records: [SafeJournalRecord]
    var failures: [String]

    init(id: UUID, records: [SafeJournalRecord]) {
        self.schema = 1
        self.id = id
        self.createdAt = Date()
        self.records = records
        self.failures = []
    }
}
