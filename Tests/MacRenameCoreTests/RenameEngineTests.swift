import XCTest
@testable import MacRenameCore

final class RenameEngineTests: XCTestCase {

    func testBasicLiteralPreview() async {
        let engine = RenameEngine()
        engine.searchTerm = "old"
        engine.replaceTerm = "new"
        engine.flags = []

        let url = URL(fileURLWithPath: "/tmp/test_old_file.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertEqual(item.newName, "test_new_file.txt")
        XCTAssertEqual(item.status, .shouldRename)
    }

    func testNameOnlyScoping() async {
        let engine = RenameEngine()
        engine.searchTerm = "test"
        engine.replaceTerm = "demo"
        engine.flags = .nameOnly

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertEqual(item.newName, "demo.txt")
    }

    func testExtensionOnlyScoping() async {
        let engine = RenameEngine()
        engine.searchTerm = "txt"
        engine.replaceTerm = "md"
        engine.flags = .extensionOnly

        let url = URL(fileURLWithPath: "/tmp/readme.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertEqual(item.newName, "readme.md")
    }

    func testExcludeFolders() async {
        let engine = RenameEngine()
        engine.searchTerm = "test"
        engine.replaceTerm = "demo"
        engine.flags = .excludeFolders

        let folder = RenameItem(url: URL(fileURLWithPath: "/tmp/test_folder"), isFolder: true, depth: 0)
        let file = RenameItem(url: URL(fileURLWithPath: "/tmp/test_file.txt"), isFolder: false, depth: 0)
        engine.items = [folder, file]

        await engine.computePreview()

        XCTAssertEqual(folder.status, .excluded)
        XCTAssertEqual(file.status, .shouldRename)
    }

    func testUppercaseTransform() async {
        let engine = RenameEngine()
        engine.searchTerm = "hello"
        engine.replaceTerm = "hello"
        engine.flags = [.uppercase]

        let url = URL(fileURLWithPath: "/tmp/hello.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertEqual(item.newName, "HELLO.TXT")
    }

    func testNoMatch() async {
        let engine = RenameEngine()
        engine.searchTerm = "xyz"
        engine.replaceTerm = "abc"
        engine.flags = []

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertNil(item.newName)
        XCTAssertEqual(item.status, .unchanged)
    }

    func testSameNameUnchanged() async {
        let engine = RenameEngine()
        engine.searchTerm = "test"
        engine.replaceTerm = "test"
        engine.flags = []

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        let item = RenameItem(url: url, isFolder: false, depth: 0)
        engine.items = [item]

        await engine.computePreview()

        XCTAssertEqual(item.status, .unchanged)
    }
}
