import ClaudeUsageCore
import SwiftUI

struct ClaudeUsageRows: View {
    @ObservedObject var store: ClaudeUsageStore
    var openDetails: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.tight) {
            HStack {
                Text("Claude")
                    .font(CodexStyle.Typography.menuRowTitle)
                Spacer()
                Text(store.statusTitle)
                    .font(CodexStyle.Typography.menuRowMeta)
                    .foregroundStyle(CodexPalette.secondaryText)
            }
            if let report = store.report {
                windowRow("5-hour limit", window: report.fiveHour, symbol: "clock")
                windowRow("Weekly limit", window: report.sevenDay, symbol: "calendar")
                ForEach(report.fableWeekly) { fable in
                    windowRow("\(fable.model.rawValue) weekly", window: fable.window, symbol: "sparkles")
                }
                if report.fableWeekly.isEmpty {
                    windowRow(
                        "Fable weekly", window: nil, symbol: "sparkles",
                        missingLabel: store.desktopEnabled ? "Not reported by Claude" : "Not supplied by CLI feed")
                }
                if let receipt = store.receiptLabel {
                    HStack {
                        Text(receipt)
                            .font(CodexStyle.Typography.menuRowMeta)
                            .foregroundStyle(CodexPalette.secondaryText)
                        if let openDetails {
                            Spacer()
                            Button("Details", action: openDetails).font(CodexStyle.Typography.menuRowMeta)
                        }
                    }
                }
            } else {
                Text(
                    store.emptyMessage
                )
                .font(CodexStyle.Typography.menuRowMeta)
                .foregroundStyle(CodexPalette.secondaryText)
            }
        }
    }

    private func windowRow(_ title: String, window: ClaudeUsageWindow?, symbol: String, missingLabel: String? = nil) -> some View {
        let expired = window?.hasExpired(at: store.now) == true
        let remaining = expired ? nil : window?.remainingPercentage.map { Int($0.rounded(.down)) }
        let tone: CodexTone =
            store.errorMessage != nil || store.report?.isOld(at: store.now) == true
            ? .muted : .usage(remainingPercent: remaining)
        return HStack(spacing: CodexStyle.Spacing.rowGap) {
            CodexIconBadge(systemName: symbol, tone: tone, size: CodexStyle.Size.smallIconBadge, symbolSize: CodexStyle.Icon.menu)
                .frame(width: CodexStyle.Size.menuIconColumn)
            VStack(alignment: .leading, spacing: CodexStyle.Spacing.tight) {
                Text(title).font(CodexStyle.Typography.menuRowTitle)
                Text(expired ? "Awaiting updated usage" : (window == nil ? missingLabel : nil) ?? resetLabel(window))
                    .font(CodexStyle.Typography.menuRowMeta)
                    .foregroundStyle(CodexPalette.secondaryText)
                LimitMeterView(
                    label: "Claude \(title) remaining", remainingPercent: remaining, tone: tone, height: CodexStyle.Meter.menuHeight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(remaining.map { "\($0)% left" } ?? "--")
                .font(CodexStyle.Typography.menuMetric)
                .monospacedDigit()
                .frame(width: CodexStyle.Size.menuMetricColumn, alignment: .trailing)
        }
        .codexRow(minHeight: CodexStyle.Row.tall)
        .accessibilityElement(children: .combine)
    }

    private func resetLabel(_ window: ClaudeUsageWindow?) -> String {
        guard let date = window?.resetDate else { return "Reset time unavailable" }
        return "Resets: \(DateFormatting.weekdayCompact(date))"
    }
}

struct ClaudeDetailView: View {
    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CodexStyle.Spacing.section) {
                Text("Claude subscription usage").font(CodexStyle.Typography.appTitle)
                Text("Source: \(store.connected ? store.sourceLabel : store.selectedSource.rawValue) · Pro / Max")
                    .font(CodexStyle.Typography.body)
                    .foregroundStyle(CodexPalette.secondaryText)
                ClaudeUsageRows(store: store)
                Text(
                    (store.desktopEnabled || (!store.connected && store.selectedSource == .desktop))
                        ? "Checks the shared desktop and web subscription limits through Claude Desktop’s saved login every five minutes. Refresh requests a new reading. This uses an unofficial interface that may change."
                        : "These are observations from terminal Claude Code, not independent server checks. The Claude desktop Code tab does not supply this feed. Web or desktop usage appears only when a terminal session reports the shared subscription limits. Refresh rereads the local report."
                )
                .font(CodexStyle.Typography.body)
                if store.desktopEnabled {
                    Text(
                        "Fable limits appear when Claude reports a separate weekly allowance. Pro may use paid usage credits instead; an unreported limit is not a zero balance. Paid credit balances are not shown here."
                    )
                    .font(CodexStyle.Typography.caption)
                    .foregroundStyle(CodexPalette.secondaryText)
                }
                if !store.desktopEnabled && store.connected {
                    Text(
                        "The CLI status-line feed does not supply Fable usage. To check Fable, disconnect this feed and select Claude Desktop; you can continue using the CLI normally."
                    )
                    .font(CodexStyle.Typography.caption)
                    .foregroundStyle(CodexPalette.secondaryText)
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(CodexPalette.warningText) }
                Divider()
                connectionControls
            }
            .padding(CodexStyle.Spacing.desktopPage)
        }
        .background(CodexPalette.appBackground)
        .onAppear { store.reload() }
    }

    private var connectionControls: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.stack) {
            Text("Connection").font(CodexStyle.Typography.sectionTitle)
            if !store.connected {
                Picker("Usage source", selection: $store.selectedSource) {
                    ForEach(ClaudeUsageSource.allCases) { source in Text(source.rawValue).tag(source) }
                }
                if store.selectedSource == .desktop {
                    Text(
                        "Connect reads Claude Desktop’s saved login using macOS Keychain and sends its session cookie only to claude.ai for read-only usage checks. Credentials stay in memory. No terminal or browser extension is required. macOS may ask you to allow Keychain access."
                    )
                    .font(CodexStyle.Typography.body)
                } else {
                    Text(
                        "Connect installs a local helper and updates the selected Claude settings. An existing status line is preserved. Terminal Claude Code 2.1.251 or later is required; the desktop app alone is not sufficient."
                    )
                    .font(CodexStyle.Typography.body)
                    pathControl("Claude configuration", value: $store.configurationPath, directory: true)
                    pathControl("Claude Code executable", value: $store.executablePath, directory: false)
                }
            }
            HStack {
                if store.connected {
                    Button("Refresh") { store.requestRefresh() }
                        .disabled(store.isRefreshingDesktop)
                    if store.desktopEnabled, store.errorMessage != nil {
                        Button("Reconnect Desktop") { Task { await store.connectDesktop() } }
                    }
                    Button("Disconnect Claude") { store.disconnect() }
                } else {
                    Button("Connect Claude") { Task { await store.connect() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isConnecting)
                }
                if store.isConnecting { ProgressView().controlSize(.small) }
            }
            if let message = store.setupMessage { Text(message).font(CodexStyle.Typography.body) }
            if store.connected {
                Text(
                    store.desktopEnabled
                        ? "Keep Claude Desktop signed in. Checks can continue while you use the web app. Usage values are held in memory and fetched again after the watcher restarts. Disconnect stops checks without signing you out of Claude."
                        : "If no report arrives after a Claude Code response, check that you are signed into Pro/Max and that project settings do not override the user status line. This view shows one subscription; it does not identify or track multiple Claude accounts."
                )
                .font(CodexStyle.Typography.caption)
                .foregroundStyle(CodexPalette.secondaryText)
            }
        }
        .disabled(store.isConnecting)
    }

    private func pathControl(_ label: String, value: Binding<String>, directory: Bool) -> some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.tight) {
            Text(label).font(CodexStyle.Typography.caption)
            HStack {
                TextField(label, text: value).textFieldStyle(.roundedBorder)
                Button("Choose…") { store.choosePath(directory: directory) }
            }
        }
    }
}
