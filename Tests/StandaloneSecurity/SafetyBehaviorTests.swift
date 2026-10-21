import Foundation
import Darwin

struct SecurityFixture {
    let root: URL
    var files: URL { root.appendingPathComponent("files", isDirectory: true) }
    var journal: URL { root.appendingPathComponent("history", isDirectory: true) }
    init() throws {
        guard let physicalTemp = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw ReviewFailure(description: "Cannot locate physical temp directory") }
        defer { free(physicalTemp) }
        root = URL(fileURLWithPath: String(cString: physicalTemp), isDirectory: true).appendingPathComponent("naming_safety_" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
    func file(_ name: String = "source.pdf", contents: String = "original") throws -> URL {
        let url = files.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
    func content(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    func coordinator() -> SafeRenameCoordinator { SafeRenameCoordinator(journalDirectory: journal) }
}

extension SecurityRegression {
    static func testAsync(_ name: String, _ body: () async throws -> Void) async {
        do { try await body(); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func mustThrowAsync(_ body: () async throws -> Void) async throws {
        do { try await body() } catch { return }
        throw ReviewFailure(description: "Expected rejection")
    }
    static func preview(_ c: SafeRenameCoordinator, _ source: URL, _ destination: String = "2026_10_21_research_report.pdf") async throws -> SafeRenamePlan {
        try await c.preview([SafeRenameRequest(sourceURL: source, proposedName: destination)])
    }
    static func ready(_ c: SafeRenameCoordinator, _ source: URL, _ destination: String = "2026_10_21_research_report.pdf") async throws -> SafeRenamePlan {
        let plan = try await preview(c, source, destination)
        try check(plan.canExecute, plan.entries.flatMap(\.issues).joined(separator: "; "))
        return plan
    }
    static func rewritePhase(_ journalURL: URL, _ phase: String) throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as! [String: Any]
        var records = json["records"] as! [[String: Any]]
        records[0]["phase"] = phase
        json["records"] = records
        try JSONSerialization.data(withJSONObject: json).write(to: journalURL)
    }
    static func safetyTests() async {
        await testAsync("safety: preview is read-only, confirmation required") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator()
            let plan = try await ready(c, source)
            try check(f.exists(source) && !f.exists(f.journal), "Preview mutated filesystem")
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: false) }
            try check(f.exists(source), "Unconfirmed rename moved source")
        }
        await testAsync("safety: successful execute persists history and restart undo") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator()
            let plan = try await ready(c, source)
            let receipt = try await c.execute(plan, confirmedByUser: true)
            try check(receipt.completed.count == 1 && receipt.failures.isEmpty, "Rename not completed: \(receipt.failures)")
            let dest = f.files.appendingPathComponent(plan.entries[0].proposedName)
            try check(!f.exists(source) && f.exists(dest), "Wrong final locations")
            try check(try f.content(dest) == "original", "Content changed")
            let restarted = f.coordinator()
            let history = try await restarted.history()
            try check(history.count == 1 && history[0].completed.count == 1, "Restart lost receipt")
            let undone = try await restarted.undo(history[0], confirmedByUser: true)
            try check(undone.completed.isEmpty && undone.failures.isEmpty && f.exists(source) && !f.exists(dest), "Undo did not restore source: \(undone.failures)")
        }
        await testAsync("safety: source content modified after preview rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            try Data("modified".utf8).write(to: source)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source) && !f.exists(f.files.appendingPathComponent(plan.entries[0].proposedName)), "Changed file was moved")
        }
        await testAsync("safety: same-size modification with restored mtime rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
            let c = f.coordinator(); let plan = try await ready(c, source)
            let handle = try FileHandle(forWritingTo: source); try handle.write(contentsOf: Data("tampered".utf8)); try handle.close()
            try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate]!], ofItemAtPath: source.path)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source), "Modified file was moved")
        }
        await testAsync("safety: source replaced after preview rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            try FileManager.default.moveItem(at: source, to: f.files.appendingPathComponent("saved.pdf"))
            _ = try f.file(contents: "original")
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source), "Replacement was moved")
        }
        await testAsync("safety: occupied destination at preview rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); _ = try f.file("occupied.pdf", contents: "target")
            let plan = try await preview(f.coordinator(), source, "occupied.pdf")
            try check(!plan.canExecute && f.exists(source), "Target conflict allowed")
        }
        await testAsync("safety: target created after preview never overwritten") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let dest = try f.file(plan.entries[0].proposedName, contents: "do not overwrite")
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(try f.content(dest) == "do not overwrite", "Existing target was overwritten")
            try check(f.exists(source), "Conflict moved source")
        }
        await testAsync("safety: case-insensitive destination conflict rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); _ = try f.file("TARGET.PDF")
            try check(!(try await preview(f.coordinator(), source, "target.PDF")).canExecute, "Case-fold target conflict allowed")
        }
        await testAsync("safety: duplicate target batch rejected without mutation") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let a = try f.file("a.pdf"), b = try f.file("b.pdf")
            let c = f.coordinator()
            let plan = try await c.preview([SafeRenameRequest(sourceURL: a, proposedName: "same.pdf"), SafeRenameRequest(sourceURL: b, proposedName: "same.pdf")])
            try check(!plan.canExecute && f.exists(a) && f.exists(b), "Duplicate batch target allowed")
        }
        await testAsync("safety: source symlink rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let original = try f.file("original.pdf"), link = f.files.appendingPathComponent("link.pdf")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
            try check(!(try await preview(f.coordinator(), link)).canExecute, "Symlink allowed")
        }
        await testAsync("safety: symlink parent rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            _ = try f.file(); let link = f.root.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.files)
            try check(!(try await preview(f.coordinator(), link.appendingPathComponent("source.pdf"))).canExecute, "Symlink parent allowed")
        }
        await testAsync("safety: parent replaced after preview rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            try FileManager.default.moveItem(at: f.files, to: f.root.appendingPathComponent("saved_files"))
            try FileManager.default.createDirectory(at: f.files, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]); _ = try f.file()
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source), "Replacement parent source moved")
        }
        await testAsync("safety: hard-linked source rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); try FileManager.default.linkItem(at: source, to: f.files.appendingPathComponent("other.pdf"))
            try check(!(try await preview(f.coordinator(), source)).canExecute, "Hard link allowed")
        }
        await testAsync("safety: remote file host rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let remote = URL(string: "file://evil.invalid" + source.path)!
            try check(!(try await preview(f.coordinator(), remote)).canExecute, "Remote file URL accepted as local")
        }
        await testAsync("safety: path traversal proposed basename rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file()
            for name in ["../outside.pdf", ".", "..", "a/b.pdf", "a\u{0}.pdf", "a\u{202E}.pdf", "a\n.pdf", String(repeating: "a", count: 256) + ".pdf"] {
                try check(!(try await preview(f.coordinator(), source, name)).canExecute, "Invalid name accepted: \(String(reflecting: name))")
            }
        }
        await testAsync("safety: Git ancestor protects nested export document") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            try FileManager.default.createDirectory(at: f.files.appendingPathComponent(".git"), withIntermediateDirectories: false)
            let sub = f.files.appendingPathComponent("exports"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let source = sub.appendingPathComponent("source.pdf"); try Data("x".utf8).write(to: source)
            try check(!(try await preview(f.coordinator(), source)).canExecute, "Git ancestor protection bypassed")
        }
        await testAsync("safety: fixed name and TeX source protected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            for filename in ["AGENTS.md", "SKILL.md", "package.json", "chapter.tex", "dependency.bib", "script.py"] {
                let source = try f.file(filename)
                try check(!(try await preview(f.coordinator(), source, "renamed" + SafeFilenameExtension.suffix(for: filename))).canExecute, "Protected file allowed: \(filename)")
            }
        }
        await testAsync("safety: compound extension must remain complete and exact") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file("source.nii.gz")
            try check(!(try await preview(f.coordinator(), source, "renamed.gz")).canExecute, "Compound suffix truncated")
            try check((try await preview(f.coordinator(), source, "renamed.nii.gz")).canExecute, "Valid compound suffix refused")
        }
        await testAsync("safety: non-empty folder blocked and never traversed") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let folder = f.files.appendingPathComponent("folder"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            let child = folder.appendingPathComponent("child.pdf"); try Data("x".utf8).write(to: child)
            try check(!(try await preview(f.coordinator(), folder, "renamed_folder")).canExecute && f.exists(child), "Non-empty folder renamed")
        }
        await testAsync("safety: empty folder execute and undo") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let folder = f.files.appendingPathComponent("folder"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let c = f.coordinator(); let plan = try await ready(c, folder, "renamed_folder")
            let receipt = try await c.execute(plan, confirmedByUser: true)
            try check(receipt.completed.count == 1, "Empty folder did not rename")
            let undone = try await c.undo(receipt, confirmedByUser: true)
            try check(undone.completed.isEmpty && f.exists(folder), "Empty folder undo failed: \(undone.failures)")
        }
        await testAsync("safety: modified renamed file is never undone") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let receipt = try await c.execute(plan, confirmedByUser: true); let dest = receipt.completed[0].destinationURL
            try Data("modified".utf8).write(to: dest)
            let result = try await c.undo(receipt, confirmedByUser: true)
            try check(result.completed.count == 1 && !result.failures.isEmpty && f.exists(dest) && !f.exists(source), "Modified file was undone")
        }
        await testAsync("safety: occupied original prevents undo overwrite") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let receipt = try await c.execute(plan, confirmedByUser: true); _ = try f.file(contents: "new original")
            let result = try await c.undo(receipt, confirmedByUser: true)
            try check(!result.failures.isEmpty && result.completed.count == 1, "Undo conflict not surfaced")
            try check(try f.content(source) == "new original", "Undo overwrote new original")
        }
        await testAsync("safety: journal-directory symlink blocks execution before mutation") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let outside = f.root.appendingPathComponent("outside"); try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createSymbolicLink(at: f.journal, withDestinationURL: outside)
            let c = f.coordinator(); let plan = try await ready(c, source)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source) && (try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty, "Journal symlink was followed")
        }
        await testAsync("safety: journal-file symlink never followed on history read") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let receipt = try await c.execute(plan, confirmedByUser: true)
            let stored = f.root.appendingPathComponent("original_journal.json"); try FileManager.default.moveItem(at: receipt.journalURL, to: stored)
            try FileManager.default.createSymbolicLink(at: receipt.journalURL, withDestinationURL: stored)
            try await mustThrowAsync { _ = try await f.coordinator().history() }
            try check(f.exists(receipt.completed[0].destinationURL), "History changed renamed file")
        }
        await testAsync("safety: over-permissive journal directory blocks mutation") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); try FileManager.default.createDirectory(at: f.journal, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
            let c = f.coordinator(); let plan = try await ready(c, source)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source), "Unsafe history permissions allowed mutation")
        }
        await testAsync("safety: journal path traversal rejected on restart") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt.journalURL)) as! [String: Any]
            var records = json["records"] as! [[String: Any]]; var snapshot = records[0]["snapshot"] as! [String: Any]
            snapshot["sourceName"] = "../outside.pdf"; records[0]["snapshot"] = snapshot; json["records"] = records
            try JSONSerialization.data(withJSONObject: json).write(to: receipt.journalURL)
            try await mustThrowAsync { _ = try await f.coordinator().history() }
        }
        await testAsync("safety: unsupported journal schema rejected on restart") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt.journalURL)) as! [String: Any]
            json["schema"] = 999
            try JSONSerialization.data(withJSONObject: json).write(to: receipt.journalURL)
            try await mustThrowAsync { _ = try await f.coordinator().history() }
        }
        await testAsync("safety: execute plan is single-use") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            _ = try await c.execute(plan, confirmedByUser: true)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
        }
        await testAsync("safety: batch preflight mutation blocks all objects") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let a = try f.file("a.pdf"), b = try f.file("b.pdf"); let c = f.coordinator()
            let plan = try await c.preview([SafeRenameRequest(sourceURL: a, proposedName: "renamed_a.pdf"), SafeRenameRequest(sourceURL: b, proposedName: "renamed_b.pdf")])
            try check(plan.canExecute, "Batch preview unexpectedly blocked")
            try Data("changed".utf8).write(to: b)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(a) && f.exists(b) && !f.exists(f.files.appendingPathComponent("renamed_a.pdf")), "Batch moved item before preflight finished")
        }
        await testAsync("safety: leaf switched to symlink after preview blocked") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let saved = f.files.appendingPathComponent("saved.pdf")
            try FileManager.default.moveItem(at: source, to: saved)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: saved)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(try f.content(saved) == "original", "Symlink target was changed")
        }
        await testAsync("safety: replaced renamed file is not undone") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let plan = try await ready(c, source)
            let receipt = try await c.execute(plan, confirmedByUser: true); let dest = receipt.completed[0].destinationURL
            try FileManager.default.moveItem(at: dest, to: f.files.appendingPathComponent("saved.pdf"))
            try Data("original".utf8).write(to: dest)
            let result = try await c.undo(receipt, confirmedByUser: true)
            try check(!result.failures.isEmpty && f.exists(dest) && !f.exists(source), "Replacement was incorrectly restored")
        }
        await testAsync("safety: restart recovers crash after rename without moving file") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            let destination = receipt.completed[0].destinationURL
            try rewritePhase(receipt.journalURL, "attempting")
            let restarted = f.coordinator(); let history = try await restarted.history()
            try check(history.count == 1 && history[0].completed.count == 1 && f.exists(destination) && !f.exists(source), "Recovery moved file or lost rename")
            let undone = try await restarted.undo(history[0], confirmedByUser: true)
            try check(undone.completed.isEmpty && f.exists(source), "Recovered operation cannot be undone")
        }
        await testAsync("safety: restart recovers crash before rename without moving file") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            let destination = receipt.completed[0].destinationURL
            try FileManager.default.moveItem(at: destination, to: source)
            try rewritePhase(receipt.journalURL, "attempting")
            let history = try await f.coordinator().history()
            try check(history.count == 1 && history[0].completed.isEmpty && f.exists(source) && !f.exists(destination), "Recovery unexpectedly moved source")
        }
        await testAsync("safety: restart recovers crash after undo without moving file") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            let destination = receipt.completed[0].destinationURL
            _ = try await c.undo(receipt, confirmedByUser: true)
            try rewritePhase(receipt.journalURL, "undoAttempting")
            let history = try await f.coordinator().history()
            try check(history.count == 1 && history[0].completed.isEmpty && f.exists(source) && !f.exists(destination), "Recovery did not recognize restored file")
        }
        await testAsync("safety: ambiguous interrupted operation requests manual review") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            let destination = receipt.completed[0].destinationURL
            try Data("tampered".utf8).write(to: destination)
            try rewritePhase(receipt.journalURL, "attempting")
            let restarted = f.coordinator(); let history = try await restarted.history()
            try check(history.count == 1 && !history[0].failures.isEmpty && f.exists(destination) && !f.exists(source), "Ambiguous recovery moved something")
            try await mustThrowAsync { _ = try await restarted.undo(history[0], confirmedByUser: true) }
        }
        await testAsync("safety: first launch creates private app and history directories") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let app = f.root.appendingPathComponent("NewApp", isDirectory: true)
            let journal = app.appendingPathComponent("History", isDirectory: true)
            let c = SafeRenameCoordinator(journalDirectory: journal)
            let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            try check(receipt.completed.count == 1 && receipt.failures.isEmpty, "First launch rename failed")
            for directory in [app, journal] {
                let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
                let permissions = (attrs[.posixPermissions] as! NSNumber).intValue
                try check(permissions & 0o077 == 0, "New history directory not private")
            }
            _ = try await c.undo(receipt, confirmedByUser: true)
            try check(f.exists(source), "First launch cannot undo")
        }
        await testAsync("safety: symlink app-history parent never followed") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let outside = f.root.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let app = f.root.appendingPathComponent("LinkedApp", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: app, withDestinationURL: outside)
            let c = SafeRenameCoordinator(journalDirectory: app.appendingPathComponent("History", isDirectory: true))
            let plan = try await ready(c, source)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source) && (try FileManager.default.contentsOfDirectory(atPath: outside.path)).isEmpty, "Application folder symlink was followed")
        }
        await testAsync("safety: oversized sparse file is rejected before content hashing") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file()
            let handle = try FileHandle(forWritingTo: source)
            try handle.truncate(atOffset: UInt64(512 * 1024 * 1024 + 1)); try handle.close()
            let plan = try await preview(f.coordinator(), source)
            try check(!plan.canExecute && f.exists(source), "Oversized file allowed")
        }
        await testAsync("safety: destination exceeding full path limit rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            var parent = f.files
            while parent.path.utf8.count < 850 {
                parent = parent.appendingPathComponent(String(repeating: "d", count: 90), isDirectory: true)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
            let source = parent.appendingPathComponent("source.pdf")
            try Data("x".utf8).write(to: source)
            let name = String(repeating: "a", count: 240) + ".pdf"
            try check(source.path.utf8.count < 1024 && parent.appendingPathComponent(name).path.utf8.count >= 1024, "Fixture does not cross path boundary")
            let plan = try await preview(f.coordinator(), source, name)
            try check(!plan.canExecute, "Oversized complete destination path accepted")
        }
        await testAsync("safety: ancestor search access suffices without directory listing") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let ancestor = f.files.appendingPathComponent("search_only", isDirectory: true)
            let parent = ancestor.appendingPathComponent("selected", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let source = parent.appendingPathComponent("source.pdf"); try Data("x".utf8).write(to: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: ancestor.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ancestor.path) }
            let plan = try await preview(f.coordinator(), source)
            try check(plan.canExecute, "Ancestor unnecessarily requires list access: \(plan.entries.flatMap(\.issues))")
        }
        await testAsync("safety: search-only ancestor still reveals fixed project marker") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let ancestor = f.files.appendingPathComponent("search_only", isDirectory: true)
            let parent = ancestor.appendingPathComponent("selected", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.createDirectory(at: ancestor.appendingPathComponent(".git"), withIntermediateDirectories: false)
            let source = parent.appendingPathComponent("source.pdf"); try Data("x".utf8).write(to: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: ancestor.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ancestor.path) }
            let plan = try await preview(f.coordinator(), source)
            try check(!plan.canExecute && plan.entries[0].issues.contains { $0.contains("protected engineering") }, "Project marker missed without list access")
        }
        await testAsync("safety: deferred history reads no selected parent before authorization") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let source = try f.file(); let c = f.coordinator(); let receipt = try await c.execute(ready(c, source), confirmedByUser: true)
            try rewritePhase(receipt.journalURL, "attempting")
            let journalBefore = try Data(contentsOf: receipt.journalURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: f.files.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.files.path) }
            let restarted = f.coordinator(); let history = try await restarted.history(recoverInterrupted: false)
            try check(history.count == 1 && history[0].requiresRecovery && history[0].failures.isEmpty && history[0].recoveryParentURLs == [f.files], "Deferred history accessed or reconciled unapproved paths")
            try check(try Data(contentsOf: receipt.journalURL) == journalBefore, "Deferred history rewrote operation")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.files.path)
            let recovered = try await restarted.recover(history[0])
            try check(!recovered.requiresRecovery && recovered.completed.count == 1, "Authorized target recovery failed")
        }
        await testAsync("safety: targeted recovery leaves other operations pending") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let a = try f.file("a.pdf"), b = try f.file("b.pdf"); let c = f.coordinator()
            let first = try await c.execute(ready(c, a, "renamed_a.pdf"), confirmedByUser: true)
            let second = try await c.execute(ready(c, b, "renamed_b.pdf"), confirmedByUser: true)
            try rewritePhase(first.journalURL, "attempting"); try rewritePhase(second.journalURL, "attempting")
            let secondBefore = try Data(contentsOf: second.journalURL)
            let restarted = f.coordinator(); let history = try await restarted.history(recoverInterrupted: false)
            let pendingFirst = history.first { $0.id == first.id }!
            let recovered = try await restarted.recover(pendingFirst)
            let remaining = try await restarted.history(recoverInterrupted: false)
            try check(!recovered.requiresRecovery && remaining.first { $0.id == second.id }!.requiresRecovery, "Recovery touched a different operation")
            try check(try Data(contentsOf: second.journalURL) == secondBefore, "Unapproved history was rewritten")
        }
        await testAsync("safety: recognized Assets ancestor protects nested files without Git") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            try FileManager.default.createDirectory(at: f.files.appendingPathComponent("Example.xcodeproj"), withIntermediateDirectories: false)
            let assets = f.files.appendingPathComponent("Assets", isDirectory: true)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let source = assets.appendingPathComponent("figure.png"); try Data("x".utf8).write(to: source)
            let plan = try await preview(f.coordinator(), source, "renamed_figure.png")
            try check(!plan.canExecute, "Recognized dependency folder did not block nested asset")
        }
    }
}
