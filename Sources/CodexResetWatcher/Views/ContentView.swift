import SwiftUI

struct ContentView: View {
    @ObservedObject var store: ResetCreditsStore
    @ObservedObject var claudeStore: ClaudeUsageStore
    @Binding var appearanceModeRawValue: String

    @Binding var dashboardViewModeRawValue: String

    private var mode: DashboardViewMode {
        DashboardViewMode(rawValue: dashboardViewModeRawValue) ?? .detailed
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mode == .compact ? "Usage at a glance" : "Dashboard")
                    .font(CodexStyle.Typography.bodyStrong)
                Spacer()
                CodexSegmentedPicker("Dashboard size", selection: $dashboardViewModeRawValue) {
                    ForEach(DashboardViewMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .frame(width: 190)
            }
            .padding(.horizontal, CodexStyle.Spacing.desktopPage)
            .padding(.vertical, CodexStyle.Spacing.desktopStack)
            Divider()
            if mode == .compact {
                CompactDashboardView(
                    detail: store.detail(for: .active), claudeStore: claudeStore,
                    appearanceModeRawValue: $appearanceModeRawValue, onRefresh: refresh)
            } else {
                detailedView
            }
        }
        .background(CodexPalette.appBackground)
        .onChange(of: dashboardViewModeRawValue) {
            if mode == .compact {
                store.select(.active)
                claudeStore.showingClaude = false
            }
        }
        .onChange(of: claudeStore.showingClaude) {
            if claudeStore.showingClaude { dashboardViewModeRawValue = DashboardViewMode.detailed.rawValue }
        }
        .onChange(of: store.selectedAccount) {
            if store.selectedAccount != .active { dashboardViewModeRawValue = DashboardViewMode.detailed.rawValue }
        }
    }

    private func refresh() {
        claudeStore.requestRefresh()
        Task { await store.refresh() }
    }

    private var detailedView: some View {
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
                        claudeStore: claudeStore,
                        cachedAccountCount: store.cachedSnapshots.count,
                        appearanceModeRawValue: $appearanceModeRawValue,
                        onRefresh: {
                            claudeStore.reload()
                            Task {
                                claudeStore.requestRefresh()
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
