import AppKit
import SwiftUI

@main
struct CodexResetWatcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearanceMode") private var appearanceModeRawValue = CodexAppearanceMode.auto.rawValue
    @AppStorage("dashboardViewMode") private var dashboardViewModeRawValue = DashboardViewMode.detailed.rawValue
    @StateObject private var store = ResetCreditsStore()
    @StateObject private var claudeStore = ClaudeUsageStore()
    @StateObject private var mainWindowController = MainWindowController()

    private var appearanceMode: CodexAppearanceMode {
        CodexAppearanceMode(rawValue: appearanceModeRawValue) ?? .auto
    }

    private var dashboardViewMode: DashboardViewMode {
        DashboardViewMode(rawValue: dashboardViewModeRawValue) ?? .detailed
    }

    var body: some Scene {
        WindowGroup("Codex Reset Watcher", id: "main") {
            ContentView(
                store: store, claudeStore: claudeStore, appearanceModeRawValue: $appearanceModeRawValue,
                dashboardViewModeRawValue: $dashboardViewModeRawValue
            )
            .preferredColorScheme(appearanceMode.colorScheme)
            .onAppear {
                applyAppearanceMode()
            }
            .onChange(of: appearanceModeRawValue) {
                applyAppearanceMode()
            }
            .background {
                MainWindowReader { window in
                    mainWindowController.register(window, mode: dashboardViewMode)
                }
            }
            .frame(
                minWidth: dashboardViewMode.minimumSize.width,
                idealWidth: dashboardViewMode.defaultSize.width,
                minHeight: dashboardViewMode.minimumSize.height,
                idealHeight: dashboardViewMode.defaultSize.height
            )
            .task {
                store.start()
                claudeStore.start()
            }
        }
        .defaultSize(
            width: dashboardViewMode.defaultSize.width,
            height: dashboardViewMode.defaultSize.height
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Codex Reset Watcher") {
                Button("Refresh") {
                    claudeStore.requestRefresh()
                    Task {
                        await store.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarStatusView(
                store: store,
                claudeStore: claudeStore,
                mainWindowController: mainWindowController,
                appearanceModeRawValue: $appearanceModeRawValue
            )
            .preferredColorScheme(appearanceMode.colorScheme)
            .onAppear {
                applyAppearanceMode()
                claudeStore.reload()
            }
            .onChange(of: appearanceModeRawValue) {
                applyAppearanceMode()
            }
            .task {
                store.start()
                claudeStore.start()
                claudeStore.reload()
            }
        } label: {
            WeeklyMenuBarLabel(store: store, claudeStore: claudeStore)
        }
        .menuBarExtraStyle(.window)
    }

    private func applyAppearanceMode() {
        NSApp.appearance = appearanceMode.nsAppearance
    }
}
