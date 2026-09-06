import AppKit
import ClaudeUsageCore
import SwiftUI
import XCTest

@testable import CodexResetWatcher

final class ClaudeLayoutTests: XCTestCase {
    @MainActor
    func testMenuWithBothProvidersAndFourResetsHasBoundedIntrinsicHeight() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"tokens":{"access_token":"synthetic-test-value","account_id":"fixture"}}"#.utf8).write(
            to: root.appendingPathComponent("auth.json"))
        let now = Date()
        let reset = now.addingTimeInterval(3600).timeIntervalSince1970
        let expiry = ISO8601DateFormatter().string(from: now.addingTimeInterval(86_400))
        let client = CodexAPIClient(
            codexHome: root,
            perform: { request in
                let object: [String: Any]
                if request.url!.path.hasSuffix("/usage") {
                    object = [
                        "rate_limit": [
                            "allowed": true, "primary_window": ["used_percent": 40, "limit_window_seconds": 604_800, "reset_at": reset]
                        ]
                    ]
                } else {
                    object = [
                        "available_count": 4,
                        "credits": (1...4).map { ["id": "fixture-\($0)", "status": "available", "expires_at": expiry] }
                    ]
                }
                return (
                    try JSONSerialization.data(withJSONObject: object),
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                )
            })
        let codex = ResetCreditsStore(
            client: client,
            snapshotPersistence: AccountSnapshotPersistence(fileURL: root.appendingPathComponent("snapshots.json"), salt: "test"))
        await codex.refresh()
        XCTAssertEqual(codex.availableCount, 4)
        let manager = ClaudeConnectionManager(directory: root.appendingPathComponent("bridge"))
        let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        try manager.connect(configurationDirectory: root.appendingPathComponent("config"), bundledHelper: helper, version: "2.1.251")
        let input: [String: Any] = [
            "rate_limits": [
                "five_hour": ["used_percentage": 25, "resets_at": reset], "seven_day": ["used_percentage": 80, "resets_at": reset + 86_400]
            ]
        ]
        try manager.record(statusLine: JSONSerialization.data(withJSONObject: input), now: now)
        let original = try manager.readReport(now: now)
        let withFable = ClaudeUsageReport(
            receivedAt: now, fiveHour: original.fiveHour, sevenDay: original.sevenDay,
            fableWeekly: [ClaudeFableWindow(model: .fable, window: ClaudeUsageWindow(usedPercentage: 40, resetsAt: reset + 172_800))])
        try JSONEncoder().encode(withFable).write(to: manager.reportURL, options: .atomic)
        let claude = ClaudeUsageStore(manager: manager)
        claude.reload(at: now)
        XCTAssertEqual(claude.report?.fableWeekly.count, 1)
        for mode in CodexAppearanceMode.allCases {
            let view = MenuBarStatusView(
                store: codex, claudeStore: claude, mainWindowController: MainWindowController(),
                appearanceModeRawValue: .constant(mode.rawValue)
            )
            .preferredColorScheme(mode.colorScheme)
            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            XCTAssertEqual(size.width, CodexStyle.Size.multiProviderMenuWidth, accuracy: 1)
            XCTAssertLessThanOrEqual(size.height, 800, "Combined menu is too tall: \(size)")
            if let output = ProcessInfo.processInfo.environment["CODEX_UI_TEST_OUTPUT"] {
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                    let data = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
                {
                    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent("claude-menu-\(mode.rawValue).png"))
                }
            }
        }
    }
}
