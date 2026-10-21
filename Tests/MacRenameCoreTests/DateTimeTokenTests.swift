import XCTest
import Foundation
@testable import MacRenameCore

final class DateTimeTokenTests: XCTestCase {

    func testContainsTokens() {
        XCTAssertTrue(DateTimeToken.containsTokens(in: "file_$YYYY"))
        XCTAssertTrue(DateTimeToken.containsTokens(in: "file_$MM"))
        XCTAssertFalse(DateTimeToken.containsTokens(in: "no tokens here"))
    }

    func testExpandYear() {
        let date = makeDate(year: 2024, month: 3, day: 15, hour: 14, minute: 30, second: 45)
        let result = DateTimeToken.expand("$YYYY-$YY-$Y", date: date)
        XCTAssertEqual(result, "2024-24-2024")
    }

    func testExpandMonth() {
        let date = makeDate(year: 2024, month: 3, day: 15, hour: 0, minute: 0, second: 0)
        let result = DateTimeToken.expand("$MM-$M", date: date)
        XCTAssertEqual(result, "03-3")
    }

    func testExpandDay() {
        let date = makeDate(year: 2024, month: 3, day: 5, hour: 0, minute: 0, second: 0)
        let result = DateTimeToken.expand("$DD-$D", date: date)
        XCTAssertEqual(result, "05-5")
    }

    func testExpandHour() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 14, minute: 0, second: 0)
        let result = DateTimeToken.expand("$HH-$H-$hh-$h", date: date)
        XCTAssertEqual(result, "14-14-02-2")
    }

    func testExpandAMPM() {
        let morning = makeDate(year: 2024, month: 1, day: 1, hour: 9, minute: 0, second: 0)
        let afternoon = makeDate(year: 2024, month: 1, day: 1, hour: 14, minute: 0, second: 0)
        XCTAssertEqual(DateTimeToken.expand("$TT", date: morning), "AM")
        XCTAssertEqual(DateTimeToken.expand("$tt", date: afternoon), "pm")
    }

    func testExpandMinuteSecond() {
        let date = makeDate(year: 2024, month: 1, day: 1, hour: 0, minute: 5, second: 9)
        let result = DateTimeToken.expand("$mm:$ss", date: date)
        XCTAssertEqual(result, "05:09")
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone.current
        return Calendar.current.date(from: components)!
    }
}
