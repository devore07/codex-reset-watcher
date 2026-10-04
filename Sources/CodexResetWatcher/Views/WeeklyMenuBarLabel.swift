import SwiftUI

struct WeeklyMenuBarLabel: View {
    @ObservedObject var store: ResetCreditsStore
    @ObservedObject var claudeStore: ClaudeUsageStore
    @State private var claudeTurn = false

    private var showingClaude: Bool { claudeTurn && claudeStore.connected }
    private var claude: WeeklyMenuBarPresentation {
        .claude(
            report: claudeStore.report, hasError: claudeStore.errorMessage != nil || claudeStore.configurationChanged,
            now: claudeStore.now)
    }
    private var codex: WeeklyMenuBarPresentation { store.menuBarPresentation(at: claudeStore.now) }
    private var title: String { showingClaude ? claude.title : "Codex \(codex.title)" }
    private var help: String {
        let reading = showingClaude ? claude.help : codex.help
        return reading + (claudeStore.connected ? " Alternates providers every 10 seconds." : "")
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: showingClaude ? ProviderMark.claude : ProviderMark.codex)
                .renderingMode(.template)
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
