import CoreServices
import Foundation
import MacRenameCore

private struct FolderAssistEvent: Sendable {
    let path: String
    let flags: FSEventStreamEventFlags
}

/// FSEvents owns this immutable bridge through its retain/release callbacks.
/// Copy paths and flags before returning from the C callback; none of its
/// borrowed buffers escape into an asynchronous task.
private final class FolderAssistEventContext: Sendable {
    let deliver: @Sendable ([FolderAssistEvent], Bool) -> Void

    init(deliver: @escaping @Sendable ([FolderAssistEvent], Bool) -> Void) {
        self.deliver = deliver
    }
}

/// The only unchecked state is the CF stream, protected by the lock. This
/// permits teardown from deinit without assuming an actor executor there.
private final class FolderAssistStream: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: FSEventStreamRef?

    init(_ stream: FSEventStreamRef) { self.stream = stream }

    func invalidate() {
        lock.lock()
        let old = stream
        stream = nil
        lock.unlock()
        if let old {
            FSEventStreamStop(old)
            FSEventStreamInvalidate(old)
            FSEventStreamRelease(old)
        }
    }

    deinit { invalidate() }
}

/// Watches one explicitly selected root. It only proposes newly created,
/// empty, direct-child folders; the UI must separately confirm and execute a
/// guarded rename. No file contents, preferences or UI are accessed here.
@MainActor
final class FolderAssistMonitor {
    var onCandidate: ((FolderAssistObservation) -> Void)?
    var onStatus: ((String) -> Void)?
    private(set) var isRunning = false
    var rootURL: URL? { root?.url }

    private struct Candidate {
        var name: String
        var revision = UUID()
        var stableAt: TimeInterval
        let expiresAt: TimeInterval
    }

    private static let settleTime: TimeInterval = 1.2
    private static let lifetime: TimeInterval = 120
    private static let maximumCandidates = 128
    private static let maximumPendingPaths = 2_048
    private static let maximumKnownIdentities = 20_000
    private static let incompleteFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped |
        kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped |
        kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount |
        kFSEventStreamEventFlagUnmount
    )

    private let coordinator: SafeRenameCoordinator
    private var root: FolderAssistRoot?
    private var enabledAt = Date.distantFuture
    private var generation = UUID()
    private var starting = false
    private var stream: FolderAssistStream?
    private var knownIdentities = Set<FolderAssistIdentity>()
    private var candidates: [FolderAssistIdentity: Candidate] = [:]
    private var pending: [String: FSEventStreamEventFlags] = [:]
    private var processingTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var debounceDeadline: TimeInterval?
    private var settlingSession: UUID?

    init(coordinator: SafeRenameCoordinator) { self.coordinator = coordinator }

    /// The caller owns the root's user-selected security-scope lease for the
    /// whole watch session. Starting a second session invalidates the first.
    func start(rootURL: URL) async throws {
        stop()
        let session = generation
        do {
            let validated = try await coordinator.folderAssistRoot(at: rootURL)
            try requireCurrent(session)
            root = validated
            enabledAt = Date()
            starting = true
            stream = try makeStream(path: validated.url.path, session: session)

            // Start the stream before taking the baseline. Events during this
            // bounded snapshot are buffered, but every baseline identity is
            // excluded even if it was just created in that small interval.
            let baseline = try await coordinator.folderAssistEntries(in: validated)
            try requireCurrent(session)
            knownIdentities = Set(baseline.map(\.identity))
            starting = false
            isRunning = true
            onStatus?("正在留意所选目录中新建的空文件夹；输入名称后会显示确认建议。")
            beginProcessingIfNeeded()
        } catch {
            if generation == session {
                stop()
                onStatus?("文件夹助手未启动，请重新选择可访问的普通目录。")
            }
            throw error
        }
    }

    func stop() {
        generation = UUID()
        isRunning = false
        starting = false
        processingTask?.cancel()
        processingTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        debounceDeadline = nil
        settlingSession = nil
        stream?.invalidate()
        stream = nil
        root = nil
        pending.removeAll()
        candidates.removeAll()
        knownIdentities.removeAll()
    }

    /// An emitted or dismissed identity stays excluded until a new session.
    /// The app's own rename and undo events therefore cannot prompt again.
    func dismiss(identity: FolderAssistIdentity) {
        candidates.removeValue(forKey: identity)
        knownIdentities.insert(identity)
        scheduleDebounce()
    }

    deinit {
        processingTask?.cancel()
        debounceTask?.cancel()
        stream?.invalidate()
    }

    private func requireCurrent(_ session: UUID) throws {
        guard session == generation, !Task.isCancelled else { throw CancellationError() }
    }

    private func makeStream(path: String, session: UUID) throws -> FolderAssistStream {
        let bridge = FolderAssistEventContext { [weak self] events, overflow in
            Task { @MainActor [weak self] in
                self?.receive(events, overflow: overflow, session: session)
            }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(bridge).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<FolderAssistEventContext>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<FolderAssistEventContext>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagWatchRoot
        )
        let rawStream = withExtendedLifetime(bridge) { FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let bridge = Unmanaged<FolderAssistEventContext>.fromOpaque(info).takeUnretainedValue()
                guard count <= 4_096 else { bridge.deliver([], true); return }
                let array = unsafeBitCast(paths, to: NSArray.self)
                guard let names = array as? [String], names.count == count else {
                    bridge.deliver([], true)
                    return
                }
                var copied: [FolderAssistEvent] = []
                copied.reserveCapacity(count)
                for index in 0..<count {
                    copied.append(FolderAssistEvent(path: names[index], flags: flags[index]))
                }
                bridge.deliver(copied, false)
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) }
        guard let raw = rawStream else {
            throw NSError(domain: "FolderAssistMonitor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法建立所选目录的观察服务。"])
        }
        let handle = FolderAssistStream(raw)
        FSEventStreamSetDispatchQueue(raw, DispatchQueue.main)
        guard FSEventStreamStart(raw) else {
            handle.invalidate()
            throw NSError(domain: "FolderAssistMonitor", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "无法启动所选目录的观察服务。"])
        }
        return handle
    }

    private func receive(_ events: [FolderAssistEvent], overflow: Bool, session: UUID) {
        guard session == generation, let root, isRunning || starting else { return }
        if overflow || events.contains(where: { $0.flags & Self.incompleteFlags != 0 }) {
            pause("目录事件不完整，文件夹助手已暂停；请重新选择目录。")
            return
        }
        for event in events {
            let path = event.path
            // Never turn traversal components into a valid direct-child path.
            guard path.hasPrefix("/"),
                  !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { continue }
            let url = URL(fileURLWithPath: path)
            if url.path == root.url.path {
                let rootMutation = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed)
                if event.flags & rootMutation != 0 {
                    pause("所选目录已移动或发生变化，文件夹助手已暂停；请重新选择目录。")
                    return
                }
                continue
            }
            guard url.deletingLastPathComponent().path == root.url.path else { continue }
            let name = url.lastPathComponent
            if pending[name] == nil, pending.count >= Self.maximumPendingPaths {
                pause("目录变化过于密集，文件夹助手已暂停；请重新选择目录。")
                return
            }
            pending[name, default: 0] |= event.flags
        }
        if !starting { beginProcessingIfNeeded() }
    }

    private func beginProcessingIfNeeded() {
        guard isRunning, processingTask == nil, !pending.isEmpty else { return }
        let session = generation
        processingTask = Task { [weak self] in
            guard let self else { return }
            while self.generation == session, self.isRunning, !Task.isCancelled, !self.pending.isEmpty {
                let batch = self.pending
                self.pending.removeAll(keepingCapacity: true)
                guard let root = self.root else { break }
                do {
                    let entries = try await self.coordinator.folderAssistEntries(in: root)
                    guard self.generation == session, !Task.isCancelled else { return }
                    self.reconcile(entries: entries, events: batch)
                } catch {
                    guard self.generation == session, !Task.isCancelled else { return }
                    self.pause("无法核实所选目录，文件夹助手已暂停；请重新选择目录。")
                    return
                }
            }
            guard self.generation == session else { return }
            self.processingTask = nil
            self.scheduleDebounce()
        }
    }

    private func reconcile(entries: [FolderAssistEntry], events: [String: FSEventStreamEventFlags]) {
        let now = ProcessInfo.processInfo.systemUptime
        var present = Set<FolderAssistIdentity>()
        for entry in entries {
            present.insert(entry.identity)
            if var candidate = candidates[entry.identity] {
                if !entry.isDirectory || shouldExclude(name: entry.name) {
                    exclude(entry.identity)
                } else if candidate.name != entry.name {
                    candidate.name = entry.name
                    candidate.revision = UUID()
                    candidate.stableAt = now + Self.settleTime
                    candidates[entry.identity] = candidate
                }
                continue
            }
            guard !knownIdentities.contains(entry.identity) else { continue }
            // Another creation can arrive while the snapshot is awaited. If
            // its event belongs to the next batch, leave its identity unseen
            // until that batch supplies the initial provenance flags.
            guard let flags = events[entry.name] else { continue }
            knownIdentities.insert(entry.identity)
            guard entry.isDirectory, !shouldExclude(name: entry.name),
                  let createdAt = entry.createdAt, createdAt >= enabledAt,
                  Self.isInitialCreation(flags) else { continue }
            guard candidates.count < Self.maximumCandidates else {
                pause("同时新建的目录过多，文件夹助手已暂停；请重新选择目录。")
                return
            }
            candidates[entry.identity] = Candidate(name: entry.name, stableAt: now + Self.settleTime,
                                                   expiresAt: now + Self.lifetime)
        }
        for identity in Array(candidates.keys) where !present.contains(identity) { exclude(identity) }
        if knownIdentities.count > Self.maximumKnownIdentities {
            pause("本次目录变化数量已达到保护上限；请重新选择目录以继续。")
        }
        scheduleDebounce()
    }

    private static func isInitialCreation(_ flags: FSEventStreamEventFlags) -> Bool {
        let required = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir)
        let ambiguous = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemCloned |
            kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsSymlink
        )
        return flags & required == required && flags & ambiguous == 0
    }

    private func shouldExclude(name: String) -> Bool {
        name.isEmpty || name.hasPrefix(".") || NamingProfile.matchesStandardStem(name, kind: .projectFolder)
    }

    private static func isPlaceholder(_ name: String) -> Bool {
        let stems = "untitled folder|new folder|未命名文件夹|未命名文件夾|未命名資料夾|新建文件夹|新建文件夾|新建資料夾|neuer ordner"
        let pattern = "^(?:" + stems + ")(?:[ ]+[0-9]+|[ ]*\\([0-9]+\\))?$"
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func exclude(_ identity: FolderAssistIdentity) {
        candidates.removeValue(forKey: identity)
        knownIdentities.insert(identity)
    }

    private func scheduleDebounce() {
        guard isRunning, !candidates.isEmpty else {
            debounceTask?.cancel()
            debounceTask = nil
            debounceDeadline = nil
            return
        }
        guard settlingSession != generation else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = candidates.values.map {
            Self.isPlaceholder($0.name) ? $0.expiresAt : min($0.stableAt, $0.expiresAt)
        }.min()!
        // Preserve an already scheduled earlier wakeup. Unrelated directory
        // activity cannot keep postponing an otherwise settled candidate.
        if debounceTask != nil, let scheduled = debounceDeadline, scheduled <= deadline { return }
        debounceTask?.cancel()
        debounceDeadline = deadline
        let delay = max(0.01, deadline - now)
        let session = generation
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard let self, self.generation == session, !Task.isCancelled else { return }
            self.debounceTask = nil
            self.debounceDeadline = nil
            self.settlingSession = session
            await self.deliverSettledCandidates(session: session)
            guard self.generation == session else { return }
            self.settlingSession = nil
            self.scheduleDebounce()
        }
    }

    private func deliverSettledCandidates(session: UUID) async {
        guard isRunning, generation == session, let root else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for (identity, candidate) in candidates {
            guard generation == session, !Task.isCancelled else { return }
            if now >= candidate.expiresAt { exclude(identity); continue }
            guard now >= candidate.stableAt, !Self.isPlaceholder(candidate.name) else { continue }
            do {
                let observation = try await coordinator.observeNewEmptyFolder(
                    named: candidate.name, in: root, createdNotBefore: enabledAt
                )
                guard generation == session, !Task.isCancelled else { return }
                guard let current = candidates[identity], current.revision == candidate.revision else { continue }
                guard observation.identity == identity else { exclude(identity); continue }
                exclude(identity)
                onCandidate?(observation)
            } catch {
                guard generation == session, !Task.isCancelled else { return }
                guard let current = candidates[identity], current.revision == candidate.revision else { continue }
                exclude(identity)
                onStatus?("已跳过不再符合条件的文件夹；只会建议本次新建、仍为空的普通文件夹。")
            }
        }
    }

    private func pause(_ message: String) {
        stop()
        onStatus?(message)
    }
}
