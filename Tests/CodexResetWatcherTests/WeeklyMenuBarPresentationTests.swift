import ClaudeUsageCore
import XCTest

@testable import CodexResetWatcher

final class WeeklyMenuBarPresentationTests: XCTestCase {
    @MainActor
    func testWeeklyPercentageAndResetStayIndependentOfOtherWindows() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(86_400)
        let report = ClaudeUsageReport(
            receivedAt: now,
            fiveHour: ClaudeUsageWindow(usedPercentage: 99, resetsAt: reset.timeIntervalSince1970 + 100),
            sevenDay: ClaudeUsageWindow(usedPercentage: 24.2, resetsAt: reset.timeIntervalSince1970))
        let value = WeeklyMenuBarPresentation.claude(report: report, hasError: false, now: now)
        XCTAssertEqual(value.title, "Claude 75% | \(DateFormatting.weekdayName(reset))")
        XCTAssertTrue(value.help.contains(DateFormatting.weekdayCompact(reset)))
    }

    @MainActor
    func testMissingWeeklyDoesNotSubstituteFiveHourOrFable() {
        let now = Date()
        let window = ClaudeUsageWindow(usedPercentage: 20, resetsAt: nil)
        let report = ClaudeUsageReport(
            receivedAt: now, fiveHour: window, sevenDay: nil,
            fableWeekly: [ClaudeFableWindow(model: .fable, window: window)])
        XCTAssertEqual(WeeklyMenuBarPresentation.claude(report: report, hasError: false, now: now).title, "Claude --% | week")
        XCTAssertEqual(WeeklyMenuBarPresentation.claude(report: nil, hasError: true, now: now).title, "Claude --% | week")
    }

    @MainActor
    func testOldAndFailedReadingsHaveVisibleMarkerAndReceipt() {
        let now = Date()
        let report = ClaudeUsageReport(receivedAt: now, fiveHour: nil, sevenDay: ClaudeUsageWindow(usedPercentage: 0, resetsAt: nil))
        for (error, date) in [(true, now), (false, now.addingTimeInterval(300))] {
            let value = WeeklyMenuBarPresentation.claude(report: report, hasError: error, now: date)
            XCTAssertEqual(value.title, "Claude 100%* | week")
            XCTAssertTrue(value.help.contains("Last reported"))
            XCTAssertTrue(value.help.contains(DateFormatting.weekdayCompact(now)))
        }
        XCTAssertEqual(WeeklyMenuBarPresentation.claude(report: report, hasError: false, now: now).title, "Claude 100% | week")
    }

    @MainActor
    func testPassedResetHidesRemainingPercentage() {
        let now = Date()
        let report = ClaudeUsageReport(
            receivedAt: now, fiveHour: nil,
            sevenDay: ClaudeUsageWindow(usedPercentage: 0, resetsAt: now.timeIntervalSince1970))
        let value = WeeklyMenuBarPresentation.claude(report: report, hasError: false, now: now)
        XCTAssertEqual(value.title, "Claude --% | updating")
        XCTAssertTrue(value.help.contains("Awaiting updated usage"))
    }
}
