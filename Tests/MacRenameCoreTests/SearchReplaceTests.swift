import XCTest
@testable import MacRenameCore

final class SearchReplaceTests: XCTestCase {

    func testLiteralReplaceFirst() {
        let result = SearchReplace.replace(in: "foo bar foo", searchTerm: "foo", replaceTerm: "baz", flags: [])
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "baz bar foo")
    }

    func testLiteralReplaceAll() {
        let result = SearchReplace.replace(in: "foo bar foo", searchTerm: "foo", replaceTerm: "baz", flags: .matchAll)
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "baz bar baz")
    }

    func testLiteralCaseInsensitive() {
        let result = SearchReplace.replace(in: "Hello World", searchTerm: "hello", replaceTerm: "hi", flags: [])
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "hi World")
    }

    func testLiteralCaseSensitiveNoMatch() {
        let result = SearchReplace.replace(in: "Hello World", searchTerm: "hello", replaceTerm: "hi", flags: .caseSensitive)
        XCTAssertFalse(result.matched)
        XCTAssertNil(result.output)
    }

    func testEmptySearchTerm() {
        let result = SearchReplace.replace(in: "test", searchTerm: "", replaceTerm: "x", flags: [])
        XCTAssertFalse(result.matched)
    }

    func testRegexCaptureGroup() {
        let result = SearchReplace.replace(
            in: "IMG_20240315_143045.jpg",
            searchTerm: "IMG_(\\d{4})(\\d{2})(\\d{2})",
            replaceTerm: "Photo_$1-$2-$3",
            flags: .useRegex
        )
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "Photo_2024-03-15_143045.jpg")
    }

    func testRegexReplaceAll() {
        let result = SearchReplace.replace(in: "a1b2c3", searchTerm: "\\d", replaceTerm: "X", flags: [.useRegex, .matchAll])
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "aXbXcX")
    }

    func testRegexReplaceFirst() {
        let result = SearchReplace.replace(in: "a1b2c3", searchTerm: "\\d", replaceTerm: "X", flags: .useRegex)
        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.output, "aXb2c3")
    }

    func testInvalidRegex() {
        let result = SearchReplace.replace(in: "test", searchTerm: "[invalid", replaceTerm: "x", flags: .useRegex)
        XCTAssertFalse(result.matched)
    }
}
