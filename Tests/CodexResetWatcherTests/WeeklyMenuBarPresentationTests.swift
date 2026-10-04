import ClaudeUsageCore
import XCTest

@testable import CodexResetWatcher

final class WeeklyMenuBarPresentationTests: XCTestCase {
    @MainActor
    func testCodexFreshFailedOldAndExpiredReadings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func presentation(age: Double = 0, error: Bool = false, reset: Double? = nil) -> WeeklyMenuBarPresentation {
            let window = UsageLimitDisplay(
                id: "weekly", kind: .weekly, title: "Weekly limit",
                window: UsageLimitWindow(usedPercent: 25, limitWindowSeconds: 604_800, resetAfterSeconds: nil, resetAt: reset),
                limitReached: false)
            return .codex(windows: [window], capturedAt: now.addingTimeInterval(-age), hasError: error, now: now)
        }
        XCTAssertEqual(presentation().title, "75% | week")
        XCTAssertEqual(presentation(age: 299).title, "75% | week")
        for value in [presentation(age: 300), presentation(error: true)] {
            XCTAssertEqual(value.title, "75%* | week")
            XCTAssertTrue(value.help.contains("Last updated"))
            XCTAssertTrue(value.help.contains("Last reported"))
        }
        XCTAssertEqual(presentation(reset: now.timeIntervalSince1970).title, "--% | updating")
        XCTAssertEqual(presentation(error: true, reset: now.timeIntervalSince1970 - 1).title, "--% | updating")
        XCTAssertTrue(presentation(reset: now.timeIntervalSince1970 + 3600).title.hasPrefix("75% | "))
        XCTAssertEqual(WeeklyMenuBarPresentation.codex(windows: [], capturedAt: now, hasError: false, now: now).title, "--% | week")
    }

    @MainActor
    func testCompactResetTimingCountsDownAndPreservesMissingAndPassedStates() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = UsageLimitWindow(usedPercent: 20, limitWindowSeconds: 18_000, resetAfterSeconds: 8100, resetAt: nil)
        let later = now.addingTimeInterval(3600)
        let anchored = window.anchored(capturedAt: now, now: later)
        XCTAssertEqual(DateFormatting.usageReset(nil, seconds: anchored.resetAfterSeconds, now: later), "Resets in 1h 15m")
        XCTAssertEqual(DateFormatting.usageReset(now.addingTimeInterval(8100), now: now), "Resets in 2h 15m")
        XCTAssertEqual(DateFormatting.usageReset(nil, now: now), "Reset time unavailable")
        XCTAssertEqual(DateFormatting.usageReset(now, now: now), "Awaiting updated usage")
        XCTAssertTrue(window.anchored(capturedAt: now, now: now.addingTimeInterval(8100)).hasExpired(at: now.addingTimeInterval(8100)))
        XCTAssertFalse(anchored.hasExpired(at: later))
    }

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
        // Fractional reference time loses precision when round-tripped through Unix time.
        let now = Date(timeIntervalSinceReferenceDate: 810_000_000.000_000_3)
        let report = ClaudeUsageReport(
            receivedAt: now, fiveHour: nil,
            sevenDay: ClaudeUsageWindow(usedPercentage: 0, resetsAt: now.timeIntervalSince1970))
        let value = WeeklyMenuBarPresentation.claude(report: report, hasError: false, now: now)
        XCTAssertEqual(value.title, "Claude --% | updating")
        XCTAssertTrue(value.help.contains("Awaiting updated usage"))
    }
}
