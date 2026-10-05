import AppKit
import XCTest

@testable import CodexResetWatcher

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testDockIconPreferenceDefaultsVisibleAndRestoresBothModes() throws {
        let suite = "dock-icon-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let app = NSApplication.shared
        let originalPolicy = app.activationPolicy()
        defer {
            defaults.removePersistentDomain(forName: suite)
            app.setActivationPolicy(originalPolicy)
        }

        AppDelegate.applyDockIconPreference(defaults: defaults)
        XCTAssertEqual(app.activationPolicy(), .regular)

        AppDelegate.setDockIconVisible(false)
        XCTAssertEqual(app.activationPolicy(), .accessory, "A live toggle must use its value before preferences are saved")

        for visible in [false, true] {
            defaults.set(visible, forKey: AppDelegate.showDockIconKey)
            AppDelegate.applyDockIconPreference(defaults: defaults)
            XCTAssertEqual(app.activationPolicy(), visible ? .regular : .accessory)

            let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            AppDelegate.applyDockIconPreference(defaults: reloadedDefaults)
            XCTAssertEqual(app.activationPolicy(), visible ? .regular : .accessory)
        }
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(app))
    }
}
