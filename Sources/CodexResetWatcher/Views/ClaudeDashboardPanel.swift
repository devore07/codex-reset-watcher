import SwiftUI

/// A live Claude summary beside the active Codex account, independent of its refresh state.
struct ClaudeDashboardPanel: View {
    @ObservedObject var store: ClaudeUsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: CodexStyle.Spacing.desktopStack) {
            HStack {
                Label("Claude", systemImage: "chart.bar")
                    .font(CodexStyle.Typography.sectionTitle)
                Spacer()
                Button(store.connected ? "Connection settings" : "Connect Claude") {
                    store.showingClaude = true
                }
                .controlSize(.small)
            }
            Text(store.connected ? "Source: \(store.sourceLabel)" : "Optional subscription connection")
                .font(CodexStyle.Typography.caption)
                .foregroundStyle(CodexPalette.secondaryText)

            ClaudeUsageRows(store: store, heading: "Current limits")

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(CodexStyle.Typography.body)
                    .foregroundStyle(CodexPalette.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.connected {
                Text(
                    store.desktopEnabled
                        ? "Desktop and web subscription usage. Checks every five minutes; Refresh requests a new reading."
                        : "Updates when terminal Claude Code reports usage. Refresh rereads the local report; the CLI feed does not supply Fable usage."
                )
                .font(CodexStyle.Typography.caption)
                .foregroundStyle(CodexPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { store.reload() }
    }
}
