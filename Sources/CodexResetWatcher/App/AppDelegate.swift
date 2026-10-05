import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let showDockIconKey = "showDockIcon"

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.applyDockIconPreference()
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    static func applyDockIconPreference(defaults: UserDefaults = .standard) {
        setDockIconVisible(defaults.object(forKey: showDockIconKey) as? Bool ?? true)
    }

    @MainActor
    static func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
