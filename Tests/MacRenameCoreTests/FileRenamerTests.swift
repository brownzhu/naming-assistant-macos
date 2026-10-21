import XCTest
@testable import MacRenameCore

final class FileRenamerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macrename-renamer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Atomic rename must refuse to clobber an existing destination — the
    /// regression we'd reintroduce if the old `fileExists`+`moveItem` pair
    /// came back.
    func testAtomicRenameRefusesExistingDestination() throws {
        let source = tmpDir.appendingPathComponent("source.txt")
        let dest = tmpDir.appendingPathComponent("dest.txt")
        try "src".data(using: .utf8)!.write(to: source)
        try "dst".data(using: .utf8)!.write(to: dest)

        let item = RenameItem(url: source, isFolder: false, depth: 0)
        item.newName = "dest.txt"
        item.status = .shouldRename

        XCTAssertThrowsError(try FileRenamer.execute(items: [item])) { error in
            guard case RenameError.destinationExists = error else {
                XCTFail("Expected destinationExists, got \(error)")
                return
            }
        }

        // Both files must still exist with their original contents.
        XCTAssertEqual(try Data(contentsOf: source), "src".data(using: .utf8))
        XCTAssertEqual(try Data(contentsOf: dest), "dst".data(using: .utf8))
    }

    /// When the second rename in a batch fails, the first must be rolled
    /// back. Verifies the rollback path of the `partialRollback`/`rollback`
    /// machinery on the success-path side: rollback succeeds → caller sees
    /// only the primary error, not `partialRollback`.
    func testFailedBatchRollsBackEarlierRenames() throws {
        let a = tmpDir.appendingPathComponent("a.txt")
        let b = tmpDir.appendingPathComponent("b.txt")
        let blocker = tmpDir.appendingPathComponent("blocker.txt")
        try Data().write(to: a)
        try Data().write(to: b)
        try "blk".data(using: .utf8)!.write(to: blocker)

        // First rename succeeds (a → a-renamed.txt).
        // Second rename fails (b → blocker.txt because blocker exists).
        let item1 = RenameItem(url: a, isFolder: false, depth: 0)
        item1.newName = "a-renamed.txt"
        item1.status = .shouldRename

        let item2 = RenameItem(url: b, isFolder: false, depth: 0)
        item2.newName = "blocker.txt"
        item2.status = .shouldRename

        XCTAssertThrowsError(try FileRenamer.execute(items: [item1, item2])) { error in
            // Rollback of item1 should succeed cleanly, so the caller gets
            // the primary error — not a partialRollback.
            guard case RenameError.destinationExists = error else {
                XCTFail("Expected primary destinationExists, got \(error)")
                return
            }
        }

        // a must be back at its original path; blocker must be untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "rollback should have restored a.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("a-renamed.txt").path))
        XCTAssertEqual(try Data(contentsOf: blocker), "blk".data(using: .utf8))
    }

    /// The error message for `partialRollback` must name the unrecovered
    /// files so the user knows what to repair manually.
    func testPartialRollbackErrorMentionsUnrecoveredFiles() {
        let primary = RenameError.renameFailed(
            source: "b.txt",
            destination: "blocker.txt",
            underlying: NSError(domain: "test", code: 1)
        )
        let stranded = RenamePair(
            source: URL(fileURLWithPath: "/tmp/a.txt"),
            destination: URL(fileURLWithPath: "/tmp/a-renamed.txt")
        )
        let err = RenameError.partialRollback(primary: primary, unrecovered: [stranded])

        let description = err.errorDescription ?? ""
        XCTAssertTrue(description.contains("a-renamed.txt"),
                      "user-facing message must name the file left at its new name")
        XCTAssertTrue(description.contains("1 file"),
                      "user-facing message must say how many files are unrecovered")
    }

    /// Case-only renames go through the two-step temp-file dance, not
    /// renamex_np. Verify that path still works on a case-insensitive volume.
    func testCaseOnlyRenameSucceeds() throws {
        let lower = tmpDir.appendingPathComponent("photo.jpg")
        try Data().write(to: lower)

        let item = RenameItem(url: lower, isFolder: false, depth: 0)
        item.newName = "Photo.jpg"
        item.status = .shouldRename

        let pairs = try FileRenamer.execute(items: [item])
        XCTAssertEqual(pairs.count, 1)

        // On case-insensitive volumes the new file resolves at the same path
        // string under either casing — assert via a directory listing instead.
        let names = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(names.contains("Photo.jpg"), "expected case-renamed file; got \(names)")
    }
}
