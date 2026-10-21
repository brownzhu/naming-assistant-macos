import XCTest
@testable import MacRenameCore

final class TokenExpanderTests: XCTestCase {

    func testExpandEnumerationOnly() {
        let result = TokenExpander.expandInlineTokens(
            "Photo_${start=1,increment=1,padding=3}",
            flags: .enumerate,
            enumIndex: 0
        )
        XCTAssertEqual(result, "Photo_001")
    }

    func testExpandEnumerationIndex5() {
        let result = TokenExpander.expandInlineTokens(
            "file_${start=0,increment=2,padding=2}",
            flags: .enumerate,
            enumIndex: 5
        )
        XCTAssertEqual(result, "file_10")
    }

    func testExpandRandomizerLength() {
        let result = TokenExpander.expandInlineTokens(
            "prefix_${rstringdigit=6}_suffix",
            flags: .randomize,
            enumIndex: 0
        )
        // Should have replaced the token, check structure
        XCTAssertTrue(result.hasPrefix("prefix_"))
        XCTAssertTrue(result.hasSuffix("_suffix"))
        // The random part should be 6 digits
        let middle = result.dropFirst(7).dropLast(7)
        XCTAssertEqual(middle.count, 6)
        XCTAssertTrue(middle.allSatisfy { $0.isNumber })
    }

    func testExpandUUID() {
        let result = TokenExpander.expandInlineTokens(
            "${ruuidv4}",
            flags: .randomize,
            enumIndex: 0
        )
        XCTAssertEqual(result.count, 36)
        XCTAssertTrue(result.contains("-"))
    }

    func testNoExpansionWhenFlagsMissing() {
        let input = "Photo_${start=1,increment=1,padding=3}"
        let result = TokenExpander.expandInlineTokens(input, flags: [], enumIndex: 0)
        XCTAssertEqual(result, input, "Should not expand when enumerate flag is not set")
    }

    func testMultipleEnumerationTokens() {
        let result = TokenExpander.expandInlineTokens(
            "${start=1,increment=1,padding=2}_${start=100,increment=10}",
            flags: .enumerate,
            enumIndex: 3
        )
        XCTAssertEqual(result, "04_130")
    }

    func testDateTimeExpansion() {
        var components = DateComponents()
        components.year = 2024
        components.month = 12
        components.day = 25
        components.hour = 15
        components.minute = 30
        components.second = 45
        components.timeZone = TimeZone.current
        let date = Calendar.current.date(from: components)!

        let result = TokenExpander.expandDateTimeTokens(
            "photo_$YYYY$MM$DD_$HH$mm$ss",
            date: date
        )
        XCTAssertEqual(result, "photo_20241225_153045")
    }

    func testMetadataExpansion() {
        let patterns: [String: String] = [
            "CAMERA_MAKE": "Canon",
            "ISO": "400",
        ]
        let result = TokenExpander.expandMetadataTokens(
            "$CAMERA_MAKE_ISO$ISO",
            patterns: patterns
        )
        XCTAssertEqual(result, "Canon_ISO400")
    }

    func testMetadataUnknownPatternLeftAsIs() {
        let result = TokenExpander.expandMetadataTokens(
            "$UNKNOWN_PATTERN",
            patterns: [:]
        )
        XCTAssertEqual(result, "$UNKNOWN_PATTERN")
    }
}
