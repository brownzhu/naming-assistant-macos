import XCTest
@testable import MacRenameCore

final class CaseTransformTests: XCTestCase {

    func testUppercaseFull() {
        let result = CaseTransform.apply(.uppercase, to: "hello world.txt", flags: [])
        XCTAssertEqual(result, "HELLO WORLD.TXT")
    }

    func testLowercaseFull() {
        let result = CaseTransform.apply(.lowercase, to: "HELLO WORLD.TXT", flags: [])
        XCTAssertEqual(result, "hello world.txt")
    }

    func testUppercaseNameOnly() {
        let result = CaseTransform.apply(.uppercase, to: "hello world.txt", flags: .nameOnly)
        XCTAssertEqual(result, "HELLO WORLD.txt")
    }

    func testLowercaseExtensionOnly() {
        let result = CaseTransform.apply(.lowercase, to: "Hello.TXT", flags: .extensionOnly)
        XCTAssertEqual(result, "Hello.txt")
    }

    func testTitleCaseExceptions() {
        let result = CaseTransform.apply(.titlecase, to: "the quick brown fox and the lazy dog", flags: [])
        XCTAssertEqual(result, "The Quick Brown Fox and the Lazy Dog")
    }

    func testCapitalizedEachWord() {
        let result = CaseTransform.apply(.capitalized, to: "hello WORLD foo", flags: [])
        XCTAssertEqual(result, "Hello World Foo")
    }

    func testTitleCaseFirstLast() {
        let result = CaseTransform.apply(.titlecase, to: "a tale of two cities", flags: [])
        XCTAssertEqual(result, "A Tale of Two Cities")
    }
}
