import Darwin
import Foundation

extension SafeRenameCoordinator {
    /// The UI must obtain a user-selected exact root grant before this call.
    /// It validates the root and recognized project boundaries without reading
    /// descendants. Do not interpret this as permission to watch an ancestor.
    public func folderAssistRoot(at url: URL) throws -> FolderAssistRoot {
        guard SafeFS.validAbsoluteURL(url) else { throw SafeFS.fail("Select an absolute local folder without traversal components.") }
        let fd = try SafeFS.openDirectory(url)
        defer { close(fd) }
        let value = try SafeFS.folderAssistStat(fd: fd)
        try Self.validateFolderAssistRoot(value)
        try Self.protectionCheck(source: url.appendingPathComponent("folder_assist_candidate"),
                                 destinationName: "folder_assist_candidate", isDirectory: false,
                                 maximumDirectoryEntries: 10_000)
        return FolderAssistRoot(url: url, identity: FolderAssistIdentity(value))
    }

    /// A bounded direct-child baseline. Existing identities must be excluded by
    /// the monitor. Appearance and birth time alone cannot prove a Finder mkdir
    /// rather than a move; the monitor must separately gate event provenance.
    public func folderAssistEntries(in root: FolderAssistRoot) throws -> [FolderAssistEntry] {
        let fd = try Self.openFolderAssistRoot(root)
        defer { close(fd) }
        let names = try SafeFS.names(in: fd, maximumCount: 10_000)
        var entries: [FolderAssistEntry] = []
        for name in names {
            var value = stat()
            let result = name.withCString { fstatat(fd, $0, &value, AT_SYMLINK_NOFOLLOW) }
            if result != 0 {
                if errno == ENOENT { continue } // A concurrent deletion is not a new candidate.
                throw SafeFS.posix("Read watched folder entry without following links")
            }
            entries.append(FolderAssistEntry(name: name, identity: FolderAssistIdentity(value),
                                            isDirectory: value.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR)))
        }
        try Self.verifyFolderAssistRootPath(root, openFD: fd)
        return entries
    }

    /// Requires an event-gated candidate that was not in the baseline. The
    /// cutoff is strict: coarse or missing birth timestamps are not rounded
    /// backwards to qualify an older folder. This can intentionally miss an
    /// otherwise new folder on a low-resolution filesystem.
    public func observeNewEmptyFolder(named name: String, in root: FolderAssistRoot,
                                      createdNotBefore cutoff: Date) throws -> FolderAssistObservation {
        guard SafeFS.validBasename(name), cutoff.timeIntervalSince1970.isFinite else {
            throw SafeFS.fail("The new folder name or observation cutoff is invalid.")
        }
        let fd = try Self.openFolderAssistRoot(root)
        defer { close(fd) }
        let value = try SafeFS.folderAssistStat(at: name, parentFD: fd)
        let identity = FolderAssistIdentity(value)
        guard value.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR), value.st_uid == getuid(),
              value.st_mode & 0o022 == 0 else {
            throw SafeFS.fail("Folder assistance only accepts your ordinary, private empty folders; links are protected.")
        }
        guard let createdAt = identity.createdAt, createdAt >= cutoff else {
            throw SafeFS.fail("The folder predates this watch session or has no usable creation time.")
        }
        let source = root.url.appendingPathComponent(name, isDirectory: true)
        try Self.protectionCheck(source: source, destinationName: name, isDirectory: true,
                                 maximumDirectoryEntries: 10_000)
        let child = name.withCString { openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard child >= 0 else { throw SafeFS.posix("Open observed folder without following links") }
        defer { close(child) }
        guard FolderAssistIdentity(try SafeFS.folderAssistStat(fd: child)) == identity,
              try SafeFS.names(in: child, maximumCount: 1).isEmpty,
              FolderAssistIdentity(try SafeFS.folderAssistStat(at: name, parentFD: fd)) == identity else {
            throw SafeFS.fail("The observed folder changed or is not empty.")
        }
        try Self.verifyFolderAssistRootPath(root, openFD: fd)
        return FolderAssistObservation(root: root, sourceURL: source, identity: identity, createdAt: createdAt)
    }

    private static func validateFolderAssistRoot(_ value: stat) throws {
        guard value.st_mode & UInt16(S_IFMT) == UInt16(S_IFDIR), value.st_uid == getuid(), value.st_mode & 0o022 == 0 else {
            throw SafeFS.fail("The watched root must be your ordinary folder and must not be writable by other users.")
        }
    }

    private static func openFolderAssistRoot(_ root: FolderAssistRoot) throws -> Int32 {
        let fd = try SafeFS.openDirectory(root.url)
        do {
            let value = try SafeFS.folderAssistStat(fd: fd)
            try validateFolderAssistRoot(value)
            guard FolderAssistIdentity(value) == root.identity else {
                throw SafeFS.fail("The watched root was moved or replaced; select it again.")
            }
            return fd
        } catch { close(fd); throw error }
    }

    private static func verifyFolderAssistRootPath(_ root: FolderAssistRoot, openFD: Int32) throws {
        let current = try openFolderAssistRoot(root)
        defer { close(current) }
        guard FolderAssistIdentity(try SafeFS.folderAssistStat(fd: current)) == FolderAssistIdentity(try SafeFS.folderAssistStat(fd: openFD)) else {
            throw SafeFS.fail("The watched root path changed during observation.")
        }
    }
}

extension SafeFS {
    static func folderAssistStat(fd: Int32) throws -> stat {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw posix("Read watched folder identity") }
        return value
    }

    static func folderAssistStat(at name: String, parentFD: Int32) throws -> stat {
        var value = stat()
        let result = name.withCString { fstatat(parentFD, $0, &value, AT_SYMLINK_NOFOLLOW) }
        guard result == 0 else { throw posix("Read observed folder identity") }
        return value
    }
}
