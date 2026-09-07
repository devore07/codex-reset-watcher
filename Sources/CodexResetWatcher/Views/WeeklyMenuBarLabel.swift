import SwiftUI

struct WeeklyMenuBarLabel: View {
    @ObservedObject var store: ResetCreditsStore
    @ObservedObject var claudeStore: ClaudeUsageStore
    @State private var claudeTurn = false

    private var showingClaude: Bool { claudeTurn && claudeStore.connected }
    private var claude: WeeklyMenuBarPresentation {
        .claude(report: claudeStore.report, hasError: claudeStore.errorMessage != nil, now: claudeStore.now)
    }
    private var title: String { showingClaude ? claude.title : "Codex \(store.menuBarTitle)" }
    private var help: String {
        let reset = store.usageWindows.first(where: { $0.kind == .weekly })?.window.resetDate
        let codexTiming = reset.map { "Resets \(DateFormatting.weekdayCompact($0))." } ?? "Reset time unavailable."
        let reading = showingClaude ? claude.help : "Codex weekly remaining: \(store.menuBarTitle). \(codexTiming)"
        return reading + (claudeStore.connected ? " Alternates providers every 10 seconds." : "")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: showingClaude ? "asterisk" : "terminal.fill")
            if !showingClaude, store.statusSymbolName.hasPrefix("exclamationmark") {
                Image(systemName: store.statusSymbolName)
            }
            Text(title).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showingClaude ? "Claude weekly usage" : "Codex weekly usage")
        .accessibilityValue(help)
        .help(help)
        .onChange(of: claudeStore.connected) { claudeTurn = false }
        .task {
            store.start()
            claudeStore.start()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                claudeTurn = claudeStore.connected ? !claudeTurn : false
            }
        }
    }
}
