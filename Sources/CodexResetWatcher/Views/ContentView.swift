import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ResetCreditsStore
    @ObservedObject var claudeStore: ClaudeUsageStore
    @Binding var appearanceModeRawValue: String

    var body: some View {
        HStack(spacing: 0) {
            AccountSidebarView(store: store, claudeStore: claudeStore)
                .frame(width: CodexStyle.Size.sidebarWidth)
                .background(CodexPalette.sidebarBackground)

            Divider()

            Group {
                if claudeStore.showingClaude {
                    ClaudeDetailView(store: claudeStore)
                } else {
                    AccountDetailView(
                        detail: store.detail(),
                        cachedAccountCount: store.cachedSnapshots.count,
                        appearanceModeRawValue: $appearanceModeRawValue,
                        onRefresh: {
                            claudeStore.reload()
                            Task {
                                await store.refresh()
                            }
                        },
                        onForget: { id in
                            store.forgetSnapshot(id: id)
                        },
                        onClearStale: {
                            store.clearStaleSnapshots()
                        },
                        onClearCached: {
                            store.clearCachedSnapshots()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
