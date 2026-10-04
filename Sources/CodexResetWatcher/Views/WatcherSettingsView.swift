import ServiceManagement
import SwiftUI

struct WatcherSettingsView: View {
    @ObservedObject var notifications: UsageNotifications
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                        set: { value in setLaunchAtLogin(value) }))
                if loginStatus == .requiresApproval {
                    Text("Approval required in macOS Login Items.")
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).foregroundStyle(CodexPalette.warningText) }
            }
            Section("Notifications") {
                Toggle(
                    "Enable notifications",
                    isOn: Binding(
                        get: { notifications.enabled },
                        set: { value in Task { await notifications.setEnabled(value) } })
                )
                .disabled(notifications.requestingPermission)
                Toggle("Warn when usage capacity is low", isOn: $notifications.lowUsageEnabled)
                    .disabled(!notifications.enabled)
                Picker("Remaining capacity", selection: $notifications.threshold) {
                    ForEach([10, 20, 25], id: \.self) { value in Text("\(value)% or less").tag(value) }
                }
                .disabled(!notifications.enabled || !notifications.lowUsageEnabled)
                Toggle("Warn when a Codex reset expires within 24 hours", isOn: $notifications.expiryEnabled)
                    .disabled(!notifications.enabled)
                Text(
                    "Quiet alerts while the watcher is running. Uses fresh readings only. Low-capacity warnings cover Codex and Claude overall limits, once per window; without a reset time, at most once per 24 hours."
                )
                .font(CodexStyle.Typography.caption)
                .foregroundStyle(CodexPalette.secondaryText)
                if let message = notifications.message {
                    Text(message).foregroundStyle(CodexPalette.warningText)
                    Button("Open Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .codexWindowSurface()
        .codexButtonStyle()
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onChange(of: scenePhase) {
            if scenePhase == .active { loginStatus = SMAppService.mainApp.status }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change launch at login. Keep the app in a stable location and check macOS Login Items."
        }
        loginStatus = SMAppService.mainApp.status
    }
}
