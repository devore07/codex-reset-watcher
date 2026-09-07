import AppKit
import XCTest

@testable import CodexResetWatcher

final class DashboardWindowTests: XCTestCase {
    @MainActor
    func testModeSwitchShrinksAndExpandsTheSameWindowWithoutRepeatedlyResettingUserSize() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1240, height: 682),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Codex Reset Watcher"
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let controller = MainWindowController()
        controller.register(window, mode: .compact)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 600, accuracy: 1)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, 510, accuracy: 1)
        window.setContentSize(NSSize(width: 640, height: 550))
        controller.register(window, mode: .compact)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 640, accuracy: 1)
        controller.register(window, mode: .detailed)
        XCTAssertGreaterThan(window.contentRect(forFrameRect: window.frame).width, 1000)
        controller.register(window, mode: .compact)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 600, accuracy: 1)
    }
}
