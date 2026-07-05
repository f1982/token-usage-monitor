import XCTest

final class UsageDisplayFormattingTests: XCTestCase {
    // MARK: - Clamping

    func testClampsNegativePercentToZero() {
        XCTAssertEqual(UsageDisplayFormatting.clampedPercent(-12), 0)
    }

    func testClampsPercentAboveHundred() {
        XCTAssertEqual(UsageDisplayFormatting.clampedPercent(140), 100)
    }

    func testClampsNaNToZero() {
        XCTAssertEqual(UsageDisplayFormatting.clampedPercent(.nan), 0)
    }

    func testClampsNilToZero() {
        XCTAssertEqual(UsageDisplayFormatting.clampedPercent(nil), 0)
    }

    func testKeepsInRangePercent() {
        XCTAssertEqual(UsageDisplayFormatting.clampedPercent(31.4), 31.4)
    }

    // MARK: - Percent text

    func testPercentTextRoundsToNearestInteger() {
        XCTAssertEqual(UsageDisplayFormatting.percentText(30.6), "31% used")
        XCTAssertEqual(UsageDisplayFormatting.percentText(30.4), "30% used")
    }

    func testPercentTextForMissingValueShowsDash() {
        XCTAssertEqual(UsageDisplayFormatting.percentText(nil), "—")
        XCTAssertEqual(UsageDisplayFormatting.percentText(.nan), "—")
    }

    func testPercentTextClampsOutOfRangeValues() {
        XCTAssertEqual(UsageDisplayFormatting.percentText(250), "100% used")
        XCTAssertEqual(UsageDisplayFormatting.percentText(-5), "0% used")
    }

    func testShortPercentText() {
        XCTAssertEqual(UsageDisplayFormatting.shortPercentText(31.2), "31%")
        XCTAssertEqual(UsageDisplayFormatting.shortPercentText(nil), "—")
    }

    // MARK: - Reset text

    func testResetTextIsNilWhenResetTimeMissing() {
        XCTAssertNil(UsageDisplayFormatting.resetText(for: nil))
    }

    func testResetTextSameDayIsRelative() {
        let calendar = Calendar.current
        // Use noon so a +2h reset stays on the same day.
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let resetsAt = now.addingTimeInterval(2 * 3600)
        XCTAssertEqual(
            UsageDisplayFormatting.resetText(for: resetsAt, now: now, calendar: calendar),
            "resets in 2h"
        )
    }

    func testResetTextSameDayMinutes() {
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let resetsAt = now.addingTimeInterval(45 * 60)
        XCTAssertEqual(
            UsageDisplayFormatting.resetText(for: resetsAt, now: now, calendar: calendar),
            "resets in 45m"
        )
    }

    func testResetTextLaterDayUsesShortDate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3 * 86_400)
        let text = UsageDisplayFormatting.resetText(for: resetsAt, now: now)
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.hasPrefix("resets "))
        XCTAssertFalse(text!.contains(" in "))
    }

    func testResetTextInPast() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-60)
        XCTAssertEqual(UsageDisplayFormatting.resetText(for: resetsAt, now: now), "resets soon")
    }

    // MARK: - Cache age

    func testCacheAgeText() {
        let now = Date()
        XCTAssertEqual(UsageDisplayFormatting.cacheAgeText(fetchedAt: now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(UsageDisplayFormatting.cacheAgeText(fetchedAt: now.addingTimeInterval(-12 * 60), now: now), "12m ago")
        XCTAssertEqual(UsageDisplayFormatting.cacheAgeText(fetchedAt: now.addingTimeInterval(-3 * 3600), now: now), "3h ago")
        XCTAssertEqual(UsageDisplayFormatting.cacheAgeText(fetchedAt: now.addingTimeInterval(-2 * 86_400), now: now), "2d ago")
    }
}
