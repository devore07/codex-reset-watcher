import ClaudeUsageCore
import SwiftUI

/// Intrinsically sized menu content: remaining capacity and Codex reset expirations.
struct CompactUsageSummary: View {
    let detail: AccountDetailState
    @ObservedObject var claudeStore: ClaudeUsageStore
    var onShowAllResets: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.stack) {
            HStack(alignment: .top, spacing: CodexStyle.Spacing.stack) {
                provider("Codex", image: ProviderMark.codex) {
                    if detail.usageWindows.isEmpty {
                        Text(detail.liveState == .loading ? "Checking usage…" : "Usage unavailable")
                            .font(CodexStyle.Typography.caption)
                            .foregroundStyle(CodexPalette.secondaryText)
                    }
                    ForEach(detail.usageWindows) { window in
                        codexRow(window)
                    }
                    Text(DateFormatting.usageUpdated(detail.usageCapturedAt, old: codexOld))
                        .font(CodexStyle.Typography.caption)
                        .foregroundStyle(CodexPalette.secondaryText)
                    if detail.liveState != .live {
                        Text(detail.statusDetail)
                            .font(CodexStyle.Typography.caption)
                            .foregroundStyle(CodexPalette.secondaryText)
                            .help(detail.errorMessages.joined(separator: "\n"))
                    }
                }
                provider("Claude", image: ProviderMark.claude) {
                    if let report = claudeStore.report {
                        claudeRow("5-hour limit", window: report.fiveHour)
                        claudeRow("Weekly limit", window: report.sevenDay)
                        ForEach(report.fableWeekly) { fable in
                            claudeRow("\(fable.model.rawValue) weekly", window: fable.window)
                        }
                        Text(DateFormatting.usageUpdated(report.receiptDate, old: claudeOld))
                            .font(CodexStyle.Typography.caption)
                            .foregroundStyle(CodexPalette.secondaryText)
                            .help(
                                [claudeStore.receiptLabel, claudeStore.errorMessage, claudeStore.statusTitle].compactMap { $0 }.joined(
                                    separator: "\n"))
                    } else {
                        Text(claudeStore.statusTitle)
                            .font(CodexStyle.Typography.caption)
                            .foregroundStyle(CodexPalette.secondaryText)
                    }
                }
            }
            resets
        }
    }

    private var codexOld: Bool {
        UsageFreshness.isOld(capturedAt: detail.usageCapturedAt, hasError: detail.usageHasError, now: claudeStore.now)
    }

    private var claudeOld: Bool {
        claudeStore.report?.isOld(at: claudeStore.now) == true
            || claudeStore.errorMessage != nil || claudeStore.configurationChanged
    }

    private func codexRow(_ display: UsageLimitDisplay) -> some View {
        let expired = display.window.hasExpired(at: claudeStore.now)
        let remaining = expired ? nil : display.remainingPercent
        return CompactRemainingRow(
            title: display.title, remaining: remaining,
            status: expired ? "Awaiting updated usage" : (display.limitReached ? "Limit reached" : nil),
            resetText: DateFormatting.usageReset(
                display.window.resetDate, seconds: display.window.resetAfterSeconds, now: claudeStore.now),
            tone: display.limitReached && !expired ? .danger : (codexOld ? .muted : .usage(remainingPercent: remaining)))
    }

    private func provider<Content: View>(_ name: String, image: NSImage, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.stack) {
            HStack(spacing: CodexStyle.Spacing.tight) {
                Image(nsImage: image).renderingMode(.template).accessibilityHidden(true)
                Text(name).font(CodexStyle.Typography.cardTitle)
                Spacer()
                Text("Remaining").font(CodexStyle.Typography.eyebrow).foregroundStyle(CodexPalette.secondaryText)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(CodexStyle.Spacing.compactPanel)
        .codexPanel(background: CodexPalette.cardBackground, border: CodexPalette.softBorder, shadow: false)
    }

    private func claudeRow(_ title: String, window: ClaudeUsageWindow?) -> some View {
        let expired = window?.hasExpired(at: claudeStore.now) == true
        let remaining = expired ? nil : window?.remainingPercentage.map { Int($0.rounded(.down)) }
        return CompactRemainingRow(
            title: title, remaining: remaining,
            status: expired ? "Awaiting updated usage" : (remaining == nil ? "Not reported" : nil),
            resetText: DateFormatting.usageReset(window?.resetDate, now: claudeStore.now),
            tone: claudeOld ? .muted : .usage(remainingPercent: remaining))
    }

    private var resets: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.desktopStack) {
            HStack {
                Label("Banked Codex resets", systemImage: "arrow.counterclockwise.circle")
                    .font(CodexStyle.Typography.bodyStrong)
                Spacer()
                Text(resetCountLabel).font(CodexStyle.Typography.caption)
                    .foregroundStyle(CodexPalette.secondaryText)
            }
            ForEach(Array(detail.credits.prefix(4).enumerated()), id: \.element.id) { index, credit in
                expiryRow(index + 1, date: credit.expiresAt)
            }
            ForEach(0..<max(0, min(4, detail.resetCountState.count ?? 0) - detail.credits.prefix(4).count), id: \.self) { offset in
                expiryRow(detail.credits.count + offset + 1, date: nil)
            }
            if max(detail.credits.count, detail.resetCountState.count ?? 0) > 4 {
                Button("Show all reset expirations", action: onShowAllResets)
                    .font(CodexStyle.Typography.caption)
            }
        }
        .padding(CodexStyle.Spacing.compactPanel)
        .codexPanel(background: CodexPalette.cardBackground, border: CodexPalette.softBorder, shadow: false)
    }

    private var resetCountLabel: String {
        switch detail.resetCountState {
        case .loading: "Checking…"
        case .unavailable: "Count unavailable"
        case .known(let count): "\(count) available"
        }
    }

    private func expiryRow(_ ordinal: Int, date: Date?) -> some View {
        let expired = date.map { $0 <= claudeStore.now } == true
        return HStack {
            Text("Reset \(ordinal) \(expired ? "expired" : "expires")")
                .foregroundStyle(expired ? CodexPalette.warningText : CodexPalette.secondaryText)
            Spacer(minLength: CodexStyle.Spacing.stack)
            Text(date.map { DateFormatting.weekdayCompact($0) } ?? "Expiry unavailable")
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(CodexStyle.Typography.caption)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct CompactRemainingRow: View {
    let title: String
    let remaining: Int?
    let status: String?
    let resetText: String
    let tone: CodexTone

    var body: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.tight) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(CodexStyle.Typography.caption).foregroundStyle(CodexPalette.secondaryText)
                Spacer(minLength: CodexStyle.Spacing.tight)
                Text(remaining.map { "\($0)%" } ?? "—")
                    .font(CodexStyle.Typography.summaryMetric).monospacedDigit()
            }
            LimitMeterView(label: "\(title) remaining", remainingPercent: remaining, tone: tone)
            if let status {
                Text(status).font(CodexStyle.Typography.caption).foregroundStyle(tone.foreground)
            }
            if status != resetText {
                Text(resetText).font(CodexStyle.Typography.caption).foregroundStyle(CodexPalette.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
