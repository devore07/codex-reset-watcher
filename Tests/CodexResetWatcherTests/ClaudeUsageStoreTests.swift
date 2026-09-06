import ClaudeUsageCore
import Foundation
import XCTest

@testable import CodexResetWatcher

final class ClaudeUsageStoreTests: XCTestCase {
    private func fixture() throws -> (ClaudeConnectionManager, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        return (ClaudeConnectionManager(directory: root.appendingPathComponent("bridge")), root.appendingPathComponent("config"), helper)
    }

    @MainActor
    func testConnectionWaitingPartialOldAndMissingReports() async throws {
        let (manager, config, helper) = try fixture()
        let store = ClaudeUsageStore(manager: manager)
        store.reload()
        XCTAssertEqual(store.statusTitle, "Connect Claude")
        try manager.connect(configurationDirectory: config, bundledHelper: helper, version: "2.1.251")
        store.reload()
        XCTAssertEqual(store.statusTitle, "Waiting for Claude Code")
        let now = Date()
        try manager.record(statusLine: Data(#"{"rate_limits":{"five_hour":{"used_percentage":42}}}"#.utf8), now: now)
        store.reload(at: now)
        XCTAssertEqual(store.statusTitle, "Partial usage report")
        XCTAssertEqual(store.report?.fiveHour?.remainingPercentage, 58)
        store.reload(at: now.addingTimeInterval(300))
        XCTAssertEqual(store.statusTitle, "Last reported")
        XCTAssertEqual(store.report?.receivedAt, now.timeIntervalSince1970)
        try Data("malformed".utf8).write(to: manager.reportURL)
        store.reload(at: now.addingTimeInterval(301))
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.report?.receivedAt, now.timeIntervalSince1970)
        XCTAssertEqual(store.report?.fiveHour?.remainingPercentage, 58)
        try FileManager.default.removeItem(at: manager.reportURL)
        store.reload()
        XCTAssertNotNil(store.errorMessage)
        store.disconnect()
        XCTAssertNil(store.report)
        XCTAssertFalse(store.connected)
    }

    @MainActor
    func testIncomingMissingWindowDoesNotReusePriorWindowAndCodexIsIndependent() async throws {
        let (manager, config, helper) = try fixture()
        try manager.connect(configurationDirectory: config, bundledHelper: helper, version: "2.1.251")
        let now = Date()
        try manager.record(
            statusLine: Data(#"{"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":40}}}"#.utf8), now: now)
        let store = ClaudeUsageStore(manager: manager)
        store.reload(at: now)
        XCTAssertEqual(store.statusTitle, "Reported by Claude Code")
        try manager.record(statusLine: Data(#"{"rate_limits":{"seven_day":{"used_percentage":45}}}"#.utf8), now: now.addingTimeInterval(1))
        store.reload(at: now.addingTimeInterval(1))
        XCTAssertNil(store.report?.fiveHour)
        XCTAssertEqual(store.report?.sevenDay?.remainingPercentage, 55)
        let codex = ResetCreditsStore(
            client: CodexAPIClient(codexHome: config.appendingPathComponent("missing-codex")),
            snapshotPersistence: AccountSnapshotPersistence(fileURL: config.appendingPathComponent("snapshots.json"), salt: "test")
        )
        await codex.refresh()
        XCTAssertEqual(codex.menuBarTitle, "--% | week")
        XCTAssertEqual(store.report?.sevenDay?.remainingPercentage, 55)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor
    func testDirectoryObservationSeesAtomicReportReplacement() async throws {
        let (manager, config, helper) = try fixture()
        try manager.connect(configurationDirectory: config, bundledHelper: helper, version: "2.1.251")
        let store = ClaudeUsageStore(manager: manager)
        store.start()
        try manager.record(statusLine: Data(#"{"rate_limits":{"five_hour":{"used_percentage":20}}}"#.utf8))
        // The periodic fallback is 15 seconds; this proves directory events handle atomic rename.
        for _ in 0..<20 where store.report == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.report?.fiveHour?.remainingPercentage, 80)
        try manager.record(statusLine: Data(#"{"rate_limits":{"five_hour":{"used_percentage":70}}}"#.utf8))
        for _ in 0..<20 where store.report?.fiveHour?.usedPercentage != 70 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.report?.fiveHour?.remainingPercentage, 30)
    }
}
