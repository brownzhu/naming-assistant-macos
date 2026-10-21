import XCTest
@testable import MacRenameCore

final class MetadataExtractorTests: XCTestCase {

    func testSanitizeStripsPathSeparators() {
        XCTAssertEqual(MetadataExtractor.sanitize("../../etc/passwd"), "....etcpasswd")
        XCTAssertEqual(MetadataExtractor.sanitize("foo/bar"), "foobar")
        XCTAssertEqual(MetadataExtractor.sanitize("a:b"), "ab")
    }

    func testSanitizeStripsControlAndNullBytes() {
        XCTAssertEqual(MetadataExtractor.sanitize("evil\u{0}name"), "evilname")
        XCTAssertEqual(MetadataExtractor.sanitize("a\u{1}b\u{7F}c"), "abc")
    }

    func testSanitizeTrimsWhitespace() {
        XCTAssertEqual(MetadataExtractor.sanitize("  Canon  "), "Canon")
    }

    func testSanitizeRejectsPureDots() {
        // ".." or "." would be path-traversal components if used as a filename.
        XCTAssertNil(MetadataExtractor.sanitize(".."))
        XCTAssertNil(MetadataExtractor.sanitize("."))
        XCTAssertNil(MetadataExtractor.sanitize("..."))
    }

    func testSanitizeRejectsEmptyAfterCleaning() {
        XCTAssertNil(MetadataExtractor.sanitize(""))
        XCTAssertNil(MetadataExtractor.sanitize("///"))
        XCTAssertNil(MetadataExtractor.sanitize("\u{0}\u{1}"))
    }

    func testSanitizePreservesNormalText() {
        XCTAssertEqual(MetadataExtractor.sanitize("Canon EOS R5"), "Canon EOS R5")
        XCTAssertEqual(MetadataExtractor.sanitize("RF 24-70mm F2.8"), "RF 24-70mm F2.8")
    }
}
