import ClaudeUsageCore
import Foundation

@MainActor
struct WeeklyMenuBarPresentation {
    let title: String
    let help: String

    static func claude(report: ClaudeUsageReport?, hasError: Bool, now: Date) -> Self {
        guard let window = report?.sevenDay, let remaining = window.remainingPercentage else {
            return Self(
                title: "Claude --% | week",
                help: "Claude weekly usage is unavailable. Open the dashboard for connection and report details.")
        }
        if window.hasExpired(at: now) {
            return Self(
                title: "Claude --% | updating",
                help: "Claude weekly reset time has passed. Awaiting updated usage from the selected source.")
        }
        let old = hasError || report?.isOld(at: now) == true
        let percent = Int(remaining.rounded(.down))
        let reset = window.resetDate.map { DateFormatting.weekdayName($0) } ?? "week"
        let timing = window.resetDate.map { "Resets \(DateFormatting.weekdayCompact($0))." } ?? "Reset time unavailable."
        let receipt = report.map { "Received \(DateFormatting.weekdayCompact($0.receiptDate))." } ?? ""
        return Self(
            title: "Claude \(percent)%\(old ? "*" : "") | \(reset)",
            help:
                "Claude weekly: \(percent)% remaining. \(timing) \(receipt)\(old ? " * Last reported; this reading is old or the latest check failed." : "")"
        )
    }
}
