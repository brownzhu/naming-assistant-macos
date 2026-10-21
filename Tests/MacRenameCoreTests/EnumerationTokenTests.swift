import XCTest
@testable import MacRenameCore

final class EnumerationTokenTests: XCTestCase {

    func testParseBasic() {
        let tokens = EnumerationToken.parse("Photo_${start=1,increment=1,padding=3}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].start, 1)
        XCTAssertEqual(tokens[0].increment, 1)
        XCTAssertEqual(tokens[0].padding, 3)
    }

    func testParseDefaults() {
        let tokens = EnumerationToken.parse("file_${}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].start, 0)
        XCTAssertEqual(tokens[0].increment, 1)
        XCTAssertEqual(tokens[0].padding, 0)
    }

    func testParseNegative() {
        let tokens = EnumerationToken.parse("${start=-5,increment=-2}")
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].start, -5)
        XCTAssertEqual(tokens[0].increment, -2)
    }

    func testSkipRandomizer() {
        let tokens = EnumerationToken.parse("${rstringalnum=8}")
        XCTAssertEqual(tokens.count, 0)
    }

    func testFormatPadded() {
        let token = EnumerationToken(start: 1, increment: 1, padding: 4, span: 0..<10)
        XCTAssertEqual(token.formatted(at: 0), "0001")
        XCTAssertEqual(token.formatted(at: 9), "0010")
        XCTAssertEqual(token.formatted(at: 999), "1000")
        XCTAssertEqual(token.formatted(at: 9999), "10000")
    }

    func testFormatNoPadding() {
        let token = EnumerationToken(start: 0, increment: 1, padding: 0, span: 0..<10)
        XCTAssertEqual(token.formatted(at: 0), "0")
        XCTAssertEqual(token.formatted(at: 42), "42")
    }

    func testExpandInString() {
        let input = "Photo_${start=1,increment=1,padding=3}_done"
        let tokens = EnumerationToken.parse(input)
        let result = EnumerationToken.expand(input, tokens: tokens, index: 4)
        XCTAssertEqual(result, "Photo_005_done")
    }
}
