import Foundation
import XCTest

@testable import ClaudeUsageCore

final class ClaudeUsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSubscriptionFieldsAndFractionalRemaining() throws {
        let report = try decode(
            #"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800000100},"seven_day":{"used_percentage":100,"resets_at":1800600000}}}"#
        )
        XCTAssertEqual(report.fiveHour?.remainingPercentage, 76.5)
        XCTAssertEqual(report.sevenDay?.remainingPercentage, 0)
        XCTAssertFalse(report.isPartial)
        XCTAssertEqual(report.receiptDate, now)
        XCTAssertFalse(report.isOld(at: now.addingTimeInterval(299)))
        XCTAssertTrue(report.isOld(at: now.addingTimeInterval(300)))
        XCTAssertFalse(report.fiveHour!.hasExpired(at: now))
        XCTAssertTrue(report.fiveHour!.hasExpired(at: now.addingTimeInterval(100)))
    }

    func testMissingInvalidAndIndependentWindows() throws {
        for bad in [
            "null", "[]", "42", #"{"used_percentage":-1}"#, #"{"used_percentage":101}"#, #"{"used_percentage":true}"#,
            #"{"used_percentage":"50"}"#
        ] {
            let report = try decode("{\"rate_limits\":{\"five_hour\":\(bad),\"seven_day\":{\"used_percentage\":0}}}")
            XCTAssertNil(report.fiveHour?.usedPercentage)
            XCTAssertEqual(report.sevenDay?.remainingPercentage, 100)
            XCTAssertTrue(report.isPartial)
        }
        XCTAssertFalse(try decode("{}").hasUsage)
        XCTAssertFalse(try decode(#"{"rate_limits":null}"#).hasUsage)
        XCTAssertThrowsError(try decode("not json"))
    }

    func testInvalidTimingDoesNotDiscardUsage() throws {
        let report = try decode(#"{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":1e100}}}"#)
        XCTAssertEqual(report.fiveHour?.remainingPercentage, 50)
        XCTAssertNil(report.fiveHour?.resetDate)
        XCTAssertNil(ClaudeUsageWindow(usedPercentage: .infinity, resetsAt: .infinity).usedPercentage)
    }

    func testOnlyDerivedFieldsPersistAndVersionAndReceiptAreValidated() throws {
        let report = try decode(
            #"{"session_id":"private-session","transcript_path":"private-path","credentials":"private-secret","rate_limits":{"five_hour":{"used_percentage":40},"extra_usage":{"cost":900}}}"#
        )
        let data = try JSONEncoder().encode(report)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("private"))
        XCTAssertFalse(text.contains("extra_usage"))
        XCTAssertEqual(try ClaudeUsageReport.decode(data, now: now), report)
        XCTAssertThrowsError(
            try ClaudeUsageReport.decode(Data(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2").utf8), now: now))
        XCTAssertThrowsError(try ClaudeUsageReport.decode(data, now: now.addingTimeInterval(-100)))
    }

    func testCompatibilityCheck() {
        XCTAssertTrue(ClaudeConnectionManager.supports(version: "2.1.251 (Claude Code)\n"))
        XCTAssertTrue(ClaudeConnectionManager.supports(version: "3.0.0"))
        XCTAssertFalse(ClaudeConnectionManager.supports(version: "2.1.250"))
        XCTAssertFalse(ClaudeConnectionManager.supports(version: "unknown"))
        XCTAssertFalse(ClaudeConnectionManager.supports(version: "2.1.251.beta"))
    }

    func testStartupReportIsDistinctFromMalformedUsage() throws {
        XCTAssertTrue(try decode("{}").waitingForUsage)
        XCTAssertTrue(try decode(#"{"rate_limits":{}}"#).waitingForUsage)
        XCTAssertThrowsError(try decode(#"{"rate_limits":42}"#))
        XCTAssertFalse(try decode(#"{"rate_limits":{"five_hour":{"used_percentage":-1}}}"#).waitingForUsage)
        let data = try JSONEncoder().encode(decode("{}"))
        XCTAssertTrue(try ClaudeUsageReport.decode(data, now: now).waitingForUsage)
    }

    private func decode(_ string: String) throws -> ClaudeUsageReport {
        try ClaudeUsageReport.fromStatusLine(Data(string.utf8), now: now)
    }
}

final class ClaudeConnectionTests: XCTestCase {
    private func fixture() throws -> (ClaudeConnectionManager, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-test spaces 'quoted' \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("bundled-helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        return (
            ClaudeConnectionManager(directory: root.appendingPathComponent("bridge")), root.appendingPathComponent("configuration"), helper
        )
    }

    private func settings(_ directory: URL, _ object: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent("settings.json"))
    }

    private func readSettings(_ directory: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("settings.json"))) as! [String: Any]
    }

    func testAbsentSettingsRepeatedConnectAndDisconnect() throws {
        let (manager, configuration, helper) = try fixture()
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        XCTAssertTrue(manager.isConfigured(try XCTUnwrap(manager.connection())))
        XCTAssertNil(try manager.connection()?.previousCommand)
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        XCTAssertNil(try manager.connection()?.previousCommand)
        try manager.disconnect()
        XCTAssertNil(try readSettings(configuration)["statusLine"])
        XCTAssertFalse(try XCTUnwrap(manager.connection()).enabled)
        try manager.disconnect()
    }

    func testPreservesCommandSettingsAndUserChangesOnDisconnect() throws {
        let (manager, configuration, helper) = try fixture()
        let command = "cat | /usr/bin/wc -c"
        try settings(configuration, ["theme": "dark", "statusLine": ["type": "command", "command": command, "padding": 2]])
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        XCTAssertEqual(try manager.connection()?.previousCommand, command)
        var object = try readSettings(configuration)
        var line = object["statusLine"] as! [String: Any]
        line["padding"] = 4
        object["statusLine"] = line
        object["newSetting"] = true
        try settings(configuration, object)
        try manager.disconnect()
        let restored = try readSettings(configuration)
        let restoredLine = restored["statusLine"] as! [String: Any]
        XCTAssertEqual(restoredLine["command"] as? String, command)
        XCTAssertEqual(restoredLine["padding"] as? Int, 4)
        XCTAssertEqual(restored["theme"] as? String, "dark")
        XCTAssertEqual(restored["newSetting"] as? Bool, true)
    }

    func testReplacementCommandIsNeverOverwritten() throws {
        let (manager, configuration, helper) = try fixture()
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        try settings(configuration, ["statusLine": ["type": "command", "command": "printf replacement"]])
        XCTAssertFalse(manager.isConfigured(try XCTUnwrap(manager.connection())))
        XCTAssertThrowsError(try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251"))
        try manager.disconnect()
        XCTAssertEqual((try readSettings(configuration)["statusLine"] as? [String: Any])?["command"] as? String, "printf replacement")
    }

    func testMalformedSettingsAndOldVersionRemainUntouched() throws {
        let (manager, configuration, helper) = try fixture()
        try FileManager.default.createDirectory(at: configuration, withIntermediateDirectories: true)
        let url = configuration.appendingPathComponent("settings.json")
        let original = Data("{broken".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251"))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertThrowsError(try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.1"))
        XCTAssertNil(try manager.connection())
    }

    func testDifferentConfigurationRequiresDisconnectAndSymlinkIsRejected() throws {
        let (manager, configuration, helper) = try fixture()
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        XCTAssertThrowsError(
            try manager.connect(
                configurationDirectory: configuration.appendingPathComponent("other"), bundledHelper: helper, version: "2.1.251"))
        try manager.disconnect()
        let settingsURL = configuration.appendingPathComponent("settings.json")
        try FileManager.default.removeItem(at: settingsURL)
        try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: helper)
        XCTAssertThrowsError(try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251"))
    }

    func testRecordingPrivateConcurrentReportsAndDisconnect() throws {
        let (manager, configuration, helper) = try fixture()
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        let base = Date()
        DispatchQueue.concurrentPerform(iterations: 25) { index in
            let data = Data("{\"private\":\"do-not-store\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(index)}}}".utf8)
            try! manager.record(statusLine: data, now: base.addingTimeInterval(Double(index)))
        }
        let report = try manager.readReport(now: base.addingTimeInterval(25))
        XCTAssertEqual(report.fiveHour?.usedPercentage, 24)
        XCTAssertEqual(report.receivedAt, base.addingTimeInterval(24).timeIntervalSince1970)
        XCTAssertFalse(try String(contentsOf: manager.reportURL, encoding: .utf8).contains("do-not-store"))
        for url in [manager.reportURL, manager.directory.appendingPathComponent("connection.json")] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
            XCTAssertEqual(mode, 0o600)
        }
        try manager.disconnect()
        try manager.record(statusLine: Data("{}".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.reportURL.path))
    }

    func testMalformedReportIsUnavailableAndDoesNotLeakRawInput() throws {
        let (manager, configuration, helper) = try fixture()
        try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: "2.1.251")
        try manager.record(statusLine: Data("private broken payload".utf8))
        XCTAssertFalse(try manager.readReport().hasUsage)
        XCTAssertFalse(try String(contentsOf: manager.reportURL, encoding: .utf8).contains("private"))
    }
}
