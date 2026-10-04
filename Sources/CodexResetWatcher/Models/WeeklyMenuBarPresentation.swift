import ClaudeUsageCore
import Foundation

@MainActor
struct WeeklyMenuBarPresentation {
    let title: String
    let help: String

    static func codex(windows: [UsageLimitDisplay], capturedAt: Date?, hasError: Bool, now: Date) -> Self {
        guard let weekly = windows.first(where: { $0.kind == .weekly }),
            let remaining = weekly.remainingPercent
        else {
            return Self(title: "--% | week", help: "Codex weekly usage is unavailable.")
        }
        if weekly.window.hasExpired(at: now) {
            return Self(title: "--% | updating", help: "Codex weekly reset time has passed. Awaiting updated usage.")
        }
        let old = UsageFreshness.isOld(capturedAt: capturedAt, hasError: hasError, now: now)
        let reset =
            weekly.window.resetDate
            ?? weekly.window.resetAfterSeconds.map { now.addingTimeInterval(TimeInterval($0)) }
        let cue = reset.map { DateFormatting.weekdayName($0) } ?? "week"
        let timing = reset.map { "Resets \(DateFormatting.weekdayCompact($0))." } ?? "Reset time unavailable."
        return Self(
            title: "\(remaining)%\(old ? "*" : "") | \(cue)",
            help: "Codex weekly: \(remaining)% remaining. \(timing) \(DateFormatting.usageUpdated(capturedAt, old: old))"
                + (old ? " * Last reported; this reading is old or the latest check failed." : ""))
    }

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

enum UsageFreshness {
    static func isOld(capturedAt: Date?, hasError: Bool, now: Date) -> Bool {
        guard let capturedAt else { return true }
        return hasError || now.timeIntervalSince(capturedAt) >= 300
    }
}
