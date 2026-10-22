import Darwin
import Foundation
import MacRenameCore

private struct MonitorFailure: Error, CustomStringConvertible {
    let description: String
}

/// Every filesystem operation stays inside this randomly named private fixture.
/// The test never selects a user's directory and never opens file contents.
@MainActor
private final class MonitorFixture {
    let base: URL
    let root: URL
    let outside: URL
    let coordinator: SafeRenameCoordinator
    let monitor: FolderAssistMonitor
    var proposals: [FolderAssistObservation] = []
    var proposalTimes: [TimeInterval] = []
    var statuses: [String] = []

    init() throws {
        // Foundation deliberately preserves some macOS system aliases (for
        // example /var). Resolve this trusted system temp path physically so
        // the production no-symlink traversal rule stays enabled in tests.
        guard let physicalTemp = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            throw MonitorFailure(description: "Cannot locate the physical temporary directory")
        }
        defer { free(physicalTemp) }
        let temporary = URL(fileURLWithPath: String(cString: physicalTemp), isDirectory: true)
        base = temporary.appendingPathComponent("NamingAssistantMonitorTests_" + UUID().uuidString, isDirectory: true)
        root = base.appendingPathComponent("watched", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for directory in [root, outside] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
        } catch {
            try? FileManager.default.removeItem(at: base)
            throw error
        }
        coordinator = SafeRenameCoordinator(journalDirectory: base.appendingPathComponent("journal", isDirectory: true))
        monitor = FolderAssistMonitor(coordinator: coordinator)
        monitor.onCandidate = { [weak self] observation in
            self?.proposals.append(observation)
            self?.proposalTimes.append(ProcessInfo.processInfo.systemUptime)
        }
        monitor.onStatus = { [weak self] in self?.statuses.append($0) }
    }

    @discardableResult
    func mkdir(_ name: String, under parent: URL? = nil) throws -> URL {
        let url = (parent ?? root).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }

    func rename(_ from: String, _ to: String) throws {
        try FileManager.default.moveItem(at: root.appendingPathComponent(from), to: root.appendingPathComponent(to))
    }

    func cleanUp() {
        monitor.stop()
        try? FileManager.default.removeItem(at: base)
    }
}

@main
@MainActor
private struct MonitorRegression {
    private static var passed = 0
    private static var failed = 0

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw MonitorFailure(description: message) }
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func waitUntil(_ message: String, timeout: TimeInterval = 6,
                                  _ condition: @MainActor () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return }
            try await sleep(0.05)
        }
        throw MonitorFailure(description: message)
    }

    private static func stayQuiet(_ fixture: MonitorFixture, count: Int,
                                 duration: TimeInterval = 1.8) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + duration
        while ProcessInfo.processInfo.systemUptime < deadline {
            try check(fixture.proposals.count == count, "An excluded or stale folder produced a proposal")
            try await sleep(0.05)
        }
        try check(fixture.proposals.count == count, "An excluded or stale folder produced a proposal")
    }

    private static func test(_ name: String,
                             _ body: @MainActor (MonitorFixture) async throws -> Void) async {
        do {
            let fixture = try MonitorFixture()
            defer { fixture.cleanUp() }
            try await body(fixture)
            passed += 1
            print("PASS \(name)")
        } catch {
            failed += 1
            print("FAIL \(name): \(error)")
        }
    }

    static func main() async {
        await test("Finder placeholder waits for a committed user name") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            try fixture.mkdir("untitled folder")
            // Model interactive Finder typing. A create+rename coalesced into
            // the first ambiguous event is deliberately not a positive case.
            try await stayQuiet(fixture, count: 0, duration: 1.6)
            try fixture.rename("untitled folder", "test")
            try await waitUntil("The renamed new folder was not proposed") { fixture.proposals.count == 1 }
            try check(fixture.proposals[0].sourceURL.lastPathComponent == "test", "The placeholder itself was proposed")
            try await stayQuiet(fixture, count: 1, duration: 0.4)
        }

        await test("Only eligible new empty direct children are proposed") { fixture in
            try fixture.mkdir("existing")
            let nested = try fixture.mkdir("nested_parent")
            let moved = try fixture.mkdir("moved_in", under: fixture.outside)
            try await fixture.monitor.start(rootURL: fixture.root)
            try fixture.rename("existing", "existing_renamed")
            try FileManager.default.moveItem(at: moved, to: fixture.root.appendingPathComponent("moved_in"))
            try fixture.mkdir("outside_new", under: fixture.outside)
            try fixture.mkdir("nested_new", under: nested)
            try fixture.mkdir("2026_10_research_standard")
            try fixture.mkdir(".hidden")
            let filled = try fixture.mkdir("nonempty")
            try Data([1]).write(to: filled.appendingPathComponent("fixture.bin"))
            try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("linked"), withDestinationURL: fixture.outside)
            try fixture.mkdir("eligible")
            try await waitUntil("The eligible direct child was not proposed") { !fixture.proposals.isEmpty }
            try await stayQuiet(fixture, count: 1)
            try check(fixture.proposals[0].sourceURL.lastPathComponent == "eligible", "An existing, moved, nested, hidden, standard, linked or nonempty folder was proposed")
            try check(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("eligible").path), "The monitor changed a folder name")
        }

        await test("Configured category tokens preserve existing standard names") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root, categoryTokens: ["client_work"])
            let standard = try fixture.mkdir("2026_10_client_work_contract")
            try await stayQuiet(fixture, count: 0)
            try fixture.mkdir("eligiblecustom")
            try await waitUntil("A new eligible child after a custom standard name was not proposed") {
                fixture.proposals.count == 1
            }
            try await stayQuiet(fixture, count: 1)
            try check(fixture.proposals[0].sourceURL.lastPathComponent == "eligiblecustom",
                      "An already standard custom-category folder was proposed")
            try check(FileManager.default.fileExists(atPath: standard.path), "The custom standard name was changed")
        }

        await test("Dismissal, guarded rename and undo do not prompt again") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            try fixture.mkdir("one_proposal")
            try await waitUntil("The fresh folder was not proposed") { fixture.proposals.count == 1 }
            let observation = fixture.proposals[0]
            fixture.monitor.dismiss(identity: observation.identity)
            let plan = try await fixture.coordinator.preview([observation.renameRequest(proposedName: "2026_10_research_one_proposal")])
            try check(plan.canExecute, "The isolated confirmed rename could not be prepared")
            let receipt = try await fixture.coordinator.execute(plan, confirmedByUser: true)
            _ = try await fixture.coordinator.undo(receipt, confirmedByUser: true)
            try await stayQuiet(fixture, count: 1)
        }

        await test("Stop cancels pending delivery and restart excludes its baseline") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            try fixture.mkdir("pending_at_stop")
            try await sleep(0.2)
            fixture.monitor.stop()
            try fixture.mkdir("created_while_stopped")
            try await stayQuiet(fixture, count: 0)
            try await fixture.monitor.start(rootURL: fixture.root)
            try fixture.mkdir("after_restart")
            try await waitUntil("A new folder after restart was not proposed") { fixture.proposals.count == 1 }
            try check(fixture.proposals[0].sourceURL.lastPathComponent == "after_restart", "A stopped-session or baseline folder was proposed")
        }

        await test("Moving the watched root pauses observation") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            try FileManager.default.moveItem(at: fixture.root, to: fixture.base.appendingPathComponent("moved_root"))
            try await waitUntil("A root mutation did not pause observation", timeout: 4) { !fixture.monitor.isRunning }
            try check(fixture.proposals.isEmpty && fixture.statuses.contains(where: { $0.contains("暂停") }), "The root mutation did not fail closed with a status")
        }

        await test("Unrelated activity does not postpone a settled candidate") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            let started = ProcessInfo.processInfo.systemUptime
            try fixture.mkdir("settled")
            for index in 0..<75 {
                try Data([UInt8(index)]).write(to: fixture.root.appendingPathComponent(".noise"))
                try await sleep(0.04)
            }
            try check(fixture.proposals.count == 1 && fixture.proposals[0].sourceURL.lastPathComponent == "settled", "A settled folder was postponed by unrelated events")
            try check((fixture.proposalTimes.first ?? .infinity) - started < 2.6, "Unrelated events reset the settling deadline")
        }

        await test("More than 128 simultaneous candidates pause before delivery") { fixture in
            try await fixture.monitor.start(rootURL: fixture.root)
            for index in 0..<129 { try fixture.mkdir("fresh_\(index)") }
            try await waitUntil("The candidate limit did not pause observation", timeout: 4) { !fixture.monitor.isRunning }
            try check(fixture.proposals.isEmpty, "A candidate-limit burst leaked a proposal")
            try check(fixture.statuses.contains(where: { $0.contains("同时新建") }), "The candidate limit had no clear status")
        }

        print("RESULT \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
