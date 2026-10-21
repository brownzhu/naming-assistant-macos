import XCTest
@testable import MacRenameCore

final class FileValidatorTests: XCTestCase {

    func testValidFilename() {
        let status = FileValidator.validate(newName: "photo.jpg", parentPath: "/Users/test", isFolder: false)
        XCTAssertEqual(status, .shouldRename)
    }

    func testSlashInvalid() {
        let status = FileValidator.validate(newName: "path/file.txt", parentPath: "/Users/test", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testColonInvalid() {
        let status = FileValidator.validate(newName: "file:name.txt", parentPath: "/Users/test", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testEmptyInvalid() {
        let status = FileValidator.validate(newName: "", parentPath: "/Users/test", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testFilenameTooLong() {
        let longName = String(repeating: "a", count: 256)
        let status = FileValidator.validate(newName: longName, parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .filenameTooLong)
    }

    func testDotInvalid() {
        let status = FileValidator.validate(newName: ".", parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testDotDotInvalid() {
        let status = FileValidator.validate(newName: "..", parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testPathTraversalRejected() {
        // Already covered by `/` rejection, but pin the behavior so a future
        // refactor that loosens the slash rule can't reopen the hole.
        let status = FileValidator.validate(newName: "../../etc/passwd", parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testNullByteRejected() {
        let status = FileValidator.validate(newName: "evil\u{0}.txt", parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testControlCharRejected() {
        let status = FileValidator.validate(newName: "file\u{1}name", parentPath: "/tmp", isFolder: false)
        XCTAssertEqual(status, .invalidCharacters)
    }

    func testTrimWhitespace() {
        let result = FileValidator.trimFilename("  hello world  ")
        XCTAssertEqual(result, "hello world")
    }

    func testTrimDots() {
        let result = FileValidator.trimFilename("file...")
        XCTAssertEqual(result, "file")
    }

    func testTrimCombined() {
        let result = FileValidator.trimFilename("  hello. . ")
        XCTAssertEqual(result, "hello")
    }
}
