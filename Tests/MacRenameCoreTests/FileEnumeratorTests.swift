import XCTest
@testable import MacRenameCore

final class FileEnumeratorTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macrename-enum-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testTopLevelSymlinkSkipped() throws {
        let real = tmpDir.appendingPathComponent("real.txt")
        try Data().write(to: real)
        let link = tmpDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let items = FileEnumerator.enumerate(urls: [link], recursive: false)
        XCTAssertTrue(items.isEmpty, "Symlink dropped at top level should be skipped")
    }

    func testSymlinkInsideDirectorySkipped() throws {
        let real = tmpDir.appendingPathComponent("real.txt")
        try Data().write(to: real)
        let link = tmpDir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let items = FileEnumerator.enumerate(urls: [tmpDir], recursive: true)
        let names = items.map { $0.url.lastPathComponent }
        XCTAssertTrue(names.contains("real.txt"))
        XCTAssertFalse(names.contains("link.txt"), "Symlink inside enumerated dir must be skipped")
    }

    func testSymlinkToOutsideDirectoryNotFollowed() throws {
        // Set up a separate "secret" dir outside the enumerated tree.
        let secretDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macrename-secret-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: secretDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: secretDir) }
        let secretFile = secretDir.appendingPathComponent("victim.txt")
        try Data().write(to: secretFile)

        // Symlink inside tmpDir pointing to the secret dir.
        let link = tmpDir.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secretDir)

        let items = FileEnumerator.enumerate(urls: [tmpDir], recursive: true)
        let paths = items.map { $0.url.path }
        XCTAssertFalse(paths.contains(where: { $0.contains("victim.txt") }),
                       "Enumerator must not traverse a symlink into another directory")
    }
}
