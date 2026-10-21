import XCTest
@testable import MacRenameCore

final class RandomizerTokenTests: XCTestCase {

    func testParseAlnum() {
        let tokens = RandomizerToken.parse("${rstringalnum=8}")
        XCTAssertEqual(tokens.count, 1)
        if case .alphanumeric(let len) = tokens[0].kind {
            XCTAssertEqual(len, 8)
        } else {
            XCTFail("Expected alphanumeric kind")
        }
    }

    func testParseAlpha() {
        let tokens = RandomizerToken.parse("${rstringalpha=5}")
        XCTAssertEqual(tokens.count, 1)
        if case .alpha(let len) = tokens[0].kind {
            XCTAssertEqual(len, 5)
        } else {
            XCTFail("Expected alpha kind")
        }
    }

    func testParseDigit() {
        let tokens = RandomizerToken.parse("${rstringdigit=4}")
        XCTAssertEqual(tokens.count, 1)
        if case .digit(let len) = tokens[0].kind {
            XCTAssertEqual(len, 4)
        } else {
            XCTFail("Expected digit kind")
        }
    }

    func testParseUUID() {
        let tokens = RandomizerToken.parse("${ruuidv4}")
        XCTAssertEqual(tokens.count, 1)
        if case .uuid = tokens[0].kind {
            // OK
        } else {
            XCTFail("Expected uuid kind")
        }
    }

    func testGenerateAlnumLength() {
        let token = RandomizerToken(kind: .alphanumeric(length: 12), span: 0..<10)
        let result = token.generate()
        XCTAssertEqual(result.count, 12)
        XCTAssertTrue(result.allSatisfy { $0.isLetter || $0.isNumber })
    }

    func testGenerateUUIDFormat() {
        let token = RandomizerToken(kind: .uuid, span: 0..<10)
        let result = token.generate()
        XCTAssertEqual(result.count, 36)
        XCTAssertTrue(result.contains("-"))
    }

    func testGenerateDigitOnly() {
        let token = RandomizerToken(kind: .digit(length: 10), span: 0..<10)
        let result = token.generate()
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(result.allSatisfy { $0.isNumber })
    }
}
