import Darwin
import Foundation

extension SecurityRegression {
    static func folderAssistTests() async {
        func folder(_ name: String, in parent: URL) throws -> URL {
            let url = parent.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            return url
        }
        await testAsync("folder assist: direct baseline records identities without following links") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let directory = try folder("existing", in: f.files)
            try Data("sentinel".utf8).write(to: directory.appendingPathComponent("keep.txt"))
            _ = try f.file("ordinary.txt")
            let link = f.files.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let entries = try await c.folderAssistEntries(in: root)
            try check(entries.count == 3, "Baseline expanded a child or lost an entry")
            try check(entries.first(where: { $0.name == "existing" })?.isDirectory == true, "Directory type missing")
            try check(entries.first(where: { $0.name == "alias" })?.isDirectory == false, "Symlink target was followed")
            try check(try f.content(directory.appendingPathComponent("keep.txt")) == "sentinel", "Baseline altered descendant")
            try check(!f.exists(f.journal), "Observation created a journal")
        }
        await testAsync("folder assist: freshly created empty child produces an identity-bound observation") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            try check(observed.sourceURL == source && observed.root == root && observed.createdAt >= cutoff, "Wrong observation")
            let request = observed.renameRequest(proposedName: "2026_10_research_test")
            try check(request.expectedSourceIdentity == observed.identity && request.expectedParentIdentity == root.identity, "Identity preconditions lost")
            try check(f.exists(source) && !f.exists(f.journal), "Observation mutated a source")
        }
        await testAsync("folder assist: old child cannot qualify from appearing in a new snapshot") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            _ = try folder("old", in: f.files)
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            try await mustThrowAsync {
                _ = try await c.observeNewEmptyFolder(named: "old", in: root, createdNotBefore: Date().addingTimeInterval(1))
            }
        }
        await testAsync("folder assist: traversal and invalid cutoff rejected before child access") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            for name in ["../outside", ".", "..", "a/b", "hidden\nname", ".hidden"] {
                try await mustThrowAsync { _ = try await c.observeNewEmptyFolder(named: name, in: root, createdNotBefore: Date()) }
            }
            try await mustThrowAsync {
                _ = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: Date(timeIntervalSince1970: .nan))
            }
        }
        await testAsync("folder assist: regular files links and nonempty folders never qualify") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date()
            _ = try f.file("regular")
            let child = try folder("occupied", in: f.files)
            try Data("keep".utf8).write(to: child.appendingPathComponent("keep.txt"))
            try FileManager.default.createSymbolicLink(at: f.files.appendingPathComponent("link"), withDestinationURL: child)
            for name in ["regular", "occupied", "link"] {
                try await mustThrowAsync { _ = try await c.observeNewEmptyFolder(named: name, in: root, createdNotBefore: cutoff) }
            }
            try check(try f.content(child.appendingPathComponent("keep.txt")) == "keep", "Nonempty child changed")
        }
        await testAsync("folder assist: fixed names packages and project children remain protected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date()
            for name in ["AGENTS.md", "Demo.app", "Sources"] {
                _ = try folder(name, in: f.files)
                try await mustThrowAsync { _ = try await c.observeNewEmptyFolder(named: name, in: root, createdNotBefore: cutoff) }
            }
        }
        await testAsync("folder assist: engineering root cannot be enabled") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            _ = try folder(".git", in: f.files)
            try await mustThrowAsync { _ = try await f.coordinator().folderAssistRoot(at: f.files) }
            try check(!f.exists(f.journal), "Rejected root created history")
        }
        await testAsync("folder assist: symlink and writable roots are rejected") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator()
            let link = f.root.appendingPathComponent("linked-root")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.files)
            try await mustThrowAsync { _ = try await c.folderAssistRoot(at: link) }
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.files.path)
            try await mustThrowAsync { _ = try await c.folderAssistRoot(at: f.files) }
        }
        await testAsync("folder assist: replaced root invalidates baseline and observation") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            try FileManager.default.moveItem(at: f.files, to: f.root.appendingPathComponent("retired"))
            _ = try folder("files", in: f.root); _ = try folder("test", in: f.files)
            try await mustThrowAsync { _ = try await c.folderAssistEntries(in: root) }
            try await mustThrowAsync { _ = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: Date.distantPast) }
        }
        await testAsync("folder assist: source replacement before preview cannot become a new plan") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            try FileManager.default.moveItem(at: source, to: f.root.appendingPathComponent("retired"))
            _ = try folder("test", in: f.files)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try check(!plan.canExecute && f.exists(source) && !f.exists(f.journal), "A different object acquired the candidate plan")
        }
        await testAsync("folder assist: parent replacement before preview cannot acquire the grant") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); _ = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            try FileManager.default.moveItem(at: f.files, to: f.root.appendingPathComponent("retired-root"))
            _ = try folder("files", in: f.root); _ = try folder("test", in: f.files)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try check(!plan.canExecute && !f.exists(f.journal), "Replacement root was authorized by stale identity")
        }
        await testAsync("folder assist: birthtime precondition rejects otherwise identical inode metadata") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let source = try folder("test", in: f.files)
            let fd = try SafeFS.openDirectory(f.files); defer { close(fd) }
            var value = try SafeFS.folderAssistStat(at: "test", parentFD: fd)
            value.st_birthtimespec.tv_sec += 1
            let request = SafeRenameRequest(sourceURL: source, proposedName: "2026_10_research_test",
                expectedSourceIdentity: FolderAssistIdentity(value), expectedParentIdentity: root.identity)
            let plan = try await c.preview([request])
            try check(!plan.canExecute && !f.exists(f.journal), "Birthtime mismatch was ignored")
        }
        await testAsync("folder assist: observed rename uses existing journal and restart undo") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try check(plan.canExecute, "Legitimate observation did not preview")
            let receipt = try await c.execute(plan, confirmedByUser: true)
            try check(receipt.completed.count == 1 && !f.exists(source), "Observed folder was not renamed")
            let restored = try await f.coordinator().undo(receipt, confirmedByUser: true)
            try check(restored.completed.isEmpty && f.exists(source), "Restart undo did not restore folder")
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: receipt.journalURL)) as! [String: Any]
            try check(json["schema"] as? Int == 1, "Journal schema unexpectedly changed")
        }
        await testAsync("folder assist: child gaining contents after preview blocks execution") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try Data("keep".utf8).write(to: source.appendingPathComponent("keep.txt"))
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source) && !f.exists(f.journal), "Nonempty source was moved")
        }
        await testAsync("folder assist: child permission change after observation blocks preview") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: source.path)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try check(!plan.canExecute && f.exists(source) && !f.exists(f.journal),
                      "An observed child became writable by others but still acquired a plan")
        }
        await testAsync("folder assist: root permission change after preview blocks execution") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator(); let root = try await c.folderAssistRoot(at: f.files)
            let cutoff = Date(); let source = try folder("test", in: f.files)
            let observed = try await c.observeNewEmptyFolder(named: "test", in: root, createdNotBefore: cutoff)
            let plan = try await c.preview([observed.renameRequest(proposedName: "2026_10_research_test")])
            try check(plan.canExecute, "Private root did not preview")
            try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.files.path)
            try await mustThrowAsync { _ = try await c.execute(plan, confirmedByUser: true) }
            try check(f.exists(source) && !f.exists(f.journal), "A root writable by others permitted a rename")
        }
        await testAsync("folder assist: pending operation blocks a retained preview without recovery") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            let c = f.coordinator()
            let first = try f.file("first.pdf")
            let firstPlan = try await ready(c, first, "2026_10_22_research_first_v01.pdf")
            let firstReceipt = try await c.execute(firstPlan, confirmedByUser: true)
            let second = try f.file("second.pdf")
            let secondPlan = try await ready(c, second, "2026_10_22_research_second_v01.pdf")
            try rewritePhase(firstReceipt.journalURL, "attempting")
            let pendingBytes = try Data(contentsOf: firstReceipt.journalURL)
            try await mustThrowAsync { _ = try await c.execute(secondPlan, confirmedByUser: true) }
            try check(f.exists(second) && !f.exists(f.files.appendingPathComponent("2026_10_22_research_second_v01.pdf")),
                      "Retained preview ran despite a pending operation")
            try check(try Data(contentsOf: firstReceipt.journalURL) == pendingBytes,
                      "Fresh execution recovered or modified another entry's journal")
            try check(try FileManager.default.contentsOfDirectory(atPath: f.journal.path).count == 1,
                      "Blocked execution wrote a new journal")
            let pending = try await c.history(recoverInterrupted: false)
            try check(pending.count == 1 && pending[0].requiresRecovery, "Pending state was silently recovered")
        }
        await testAsync("folder assist: bounded direct enumeration refuses excess entries") {
            let f = try SecurityFixture(); defer { f.cleanup() }
            _ = try f.file("a"); _ = try f.file("b")
            let fd = try SafeFS.openDirectory(f.files); defer { close(fd) }
            try mustThrow { _ = try SafeFS.names(in: fd, maximumCount: 1) }
        }
    }
}
