import ClaudeUsageCore
import CommonCrypto
import CryptoKit
import Foundation
import SQLite3
import XCTest

@testable import CodexResetWatcher

final class ClaudeDesktopTests: XCTestCase {
    private let organization = "11111111-2222-3333-4444-555555555555"
    private let body = Data(
        #"{"five_hour":{"utilization":27.5,"resets_at":"2026-09-07T01:00:00.123Z"},"seven_day":{"utilization":61,"resets_at":"2026-09-10T12:00:00Z"},"ignored":"synthetic-private-field"}"#
            .utf8)

    private func database(session: String = "synthetic-session", extra: String = "") throws -> ClaudeDesktopCredentials {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("desktop tests \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Cookies")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE meta(key TEXT, value TEXT); INSERT INTO meta VALUES('version','24');
            CREATE TABLE cookies(name TEXT, host_key TEXT, encrypted_value BLOB, value TEXT,
            expires_utc INTEGER, is_persistent INTEGER, path TEXT, top_frame_site_key TEXT);
            INSERT INTO cookies VALUES('sessionKey','.claude.ai',X'','\(session)',0,0,'/','');
            INSERT INTO cookies VALUES('lastActiveOrg','.claude.ai',X'','\(organization)',0,0,'/','');
            \(extra)
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        return ClaudeDesktopCredentials(
            database: url,
            password: { _ in
                XCTFail("Plaintext fixture must not access Keychain")
                return Data()
            })
    }

    func testResponseConversionAndMinimization() throws {
        let report = try ClaudeDesktopClient.decode(body)
        XCTAssertEqual(report.fiveHour?.remainingPercentage, 72.5)
        XCTAssertEqual(report.sevenDay?.remainingPercentage, 39)
        XCTAssertNotNil(report.fiveHour?.resetDate)
        XCTAssertNotNil(report.sevenDay?.resetDate)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(report), as: UTF8.self).contains("synthetic-private-field"))
        let partial = try ClaudeDesktopClient.decode(
            Data(#"{"five_hour":{"utilization":false},"seven_day":{"utilization":20,"resets_at":"9999-01-01T00:00:00Z"}}"#.utf8))
        XCTAssertNil(partial.fiveHour?.usedPercentage)
        XCTAssertEqual(partial.sevenDay?.remainingPercentage, 80)
        XCTAssertNil(partial.sevenDay?.resetDate)
        for invalid in ["{}", "[]", "null", "", #"{"five_hour":{"utilization":101}}"#, #"{"seven_day":{"utilization":-1}}"#] {
            XCTAssertThrowsError(try ClaudeDesktopClient.decode(Data(invalid.utf8)))
        }
    }

    func testCookieScopeExpiryAndHeaderValidation() throws {
        let auth = try database(extra: "INSERT INTO cookies VALUES('sessionKey','.unrelated.test',X'','ignored',0,0,'/','');").load()
        XCTAssertEqual(auth.sessionKey, "synthetic-session")
        XCTAssertEqual(auth.organization, UUID(uuidString: organization))
        XCTAssertThrowsError(try database(session: "bad;header").load())
        XCTAssertThrowsError(try database(extra: "UPDATE cookies SET expires_utc=1,is_persistent=1 WHERE name='sessionKey';").load())
        XCTAssertThrowsError(try database(extra: "INSERT INTO cookies SELECT * FROM cookies WHERE name='sessionKey';").load())
        XCTAssertThrowsError(try database(extra: "UPDATE meta SET value='25';").load())
    }

    func testEncryptedCookieChecksHostAndVersion() throws {
        let key = try ClaudeDesktopCredentials.deriveKey(Data("test-password".utf8))
        let plain = Data(SHA256.hash(data: Data(".claude.ai".utf8))) + Data("synthetic-session".utf8)
        var encrypted = Data(count: plain.count + 16)
        let capacity = encrypted.count
        var count = 0
        let status = encrypted.withUnsafeMutableBytes { output in
            plain.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, key.count, [UInt8](repeating: 32, count: 16), input.baseAddress,
                        plain.count, output.baseAddress, capacity, &count)
                }
            }
        }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        encrypted.count = count
        let payload = Data("v10".utf8) + encrypted
        XCTAssertEqual(try ClaudeDesktopCredentials.decrypt(payload, key: key, host: ".claude.ai", version: 24), "synthetic-session")
        XCTAssertThrowsError(try ClaudeDesktopCredentials.decrypt(payload, key: key, host: "claude.ai", version: 24))
        XCTAssertThrowsError(try ClaudeDesktopCredentials.decrypt(Data("v20".utf8) + encrypted, key: key, host: ".claude.ai", version: 24))
        XCTAssertThrowsError(try ClaudeDesktopCredentials.decrypt(Data("v10broken".utf8), key: key, host: ".claude.ai", version: 24))
        let hex = payload.map { String(format: "%02x", $0) }.joined()
        var credentials = try database(extra: "UPDATE cookies SET encrypted_value=X'\(hex)',value='' WHERE name='sessionKey';")
        credentials.password = { _ in Data("test-password".utf8) }
        XCTAssertEqual(try credentials.load().sessionKey, "synthetic-session")
    }

    func testRequestsAreReadOnlyScopedAndRejectFailures() async throws {
        let credentials = try database()
        let body = body
        let expected = ClaudeDesktopClient.endpoint(organization: UUID(uuidString: organization)!)
        let client = ClaudeDesktopClient(
            credentials: credentials,
            perform: { request in
                XCTAssertEqual(request.url, expected)
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=synthetic-session")
                XCTAssertNil(request.httpBody)
                return (
                    body,
                    HTTPURLResponse(url: expected, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                )
            })
        let result = try await client.fetch()
        XCTAssertEqual(result.report.sevenDay?.remainingPercentage, 39)
        for status in [302, 401, 403, 429, 500] {
            let failing = ClaudeDesktopClient(
                credentials: credentials,
                perform: { _ in
                    (
                        body,
                        HTTPURLResponse(
                            url: expected, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                    )
                })
            do {
                _ = try await failing.fetch()
                XCTFail("Accepted failure")
            } catch { XCTAssertTrue(error is ClaudeDesktopError) }
        }
        let redirected = ClaudeDesktopClient(
            credentials: credentials,
            perform: { _ in
                (
                    body,
                    HTTPURLResponse(
                        url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        do {
            _ = try await redirected.fetch()
            XCTFail("Accepted changed destination")
        } catch {}
    }

    func testAccountChangeDuringRequestIsRejected() async throws {
        let credentials = try database()
        let body = body
        let client = ClaudeDesktopClient(
            credentials: credentials,
            perform: { request in
                var db: OpaquePointer?
                guard sqlite3_open(credentials.database.path, &db) == SQLITE_OK else { throw ClaudeDesktopError.loginUnavailable }
                defer { sqlite3_close(db) }
                sqlite3_exec(db, "UPDATE cookies SET value='switched-session' WHERE name='sessionKey'", nil, nil, nil)
                return (
                    body,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        do {
            _ = try await client.fetch()
            XCTFail("Accepted an earlier login's response")
        } catch { XCTAssertEqual(error as? ClaudeDesktopError, .accountChanged) }
    }

    @MainActor
    func testRateLimitBackoffAndInflightDisconnect() async throws {
        let credentials = try database()
        let manager = ClaudeConnectionManager(directory: credentials.database.deletingLastPathComponent().appendingPathComponent("watcher"))
        let store = ClaudeUsageStore(manager: manager)
        let body = body
        store.desktopClient = ClaudeDesktopClient(
            credentials: credentials,
            perform: { request in
                (
                    body,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            })
        await store.connectDesktop()
        store.desktopClient.perform = { _ in throw ClaudeDesktopError.rateLimited }
        await store.refreshDesktop(force: true)
        store.desktopClient.perform = { _ in
            XCTFail("Backoff must apply to manual refresh")
            throw ClaudeDesktopError.rateLimited
        }
        await store.refreshDesktop(force: true)
        store.disconnect()
        store.desktopClient.perform = { request in
            (
                body,
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!
            )
        }
        await store.connectDesktop()
        let gate = DesktopRequestGate()
        store.desktopClient.perform = { request in
            await gate.wait()
            return (
                body,
                HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!
            )
        }
        let refresh = Task { await store.refreshDesktop(force: true) }
        while !(await gate.started) { await Task.yield() }
        store.disconnect()
        await gate.release()
        await refresh.value
        XCTAssertFalse(store.connected)
        XCTAssertNil(store.report)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.directory.appendingPathComponent("desktop-enabled").path))
    }

    @MainActor
    func testDesktopConnectionRestartFailureAndDisconnect() async throws {
        let credentials = try database()
        let directory = credentials.database.deletingLastPathComponent().appendingPathComponent("watcher")
        let manager = ClaudeConnectionManager(directory: directory)
        let store = ClaudeUsageStore(manager: manager)
        let body = body
        store.desktopClient = ClaudeDesktopClient(
            credentials: credentials,
            perform: { request in
                (
                    body,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                )
            })
        await store.connectDesktop()
        XCTAssertTrue(store.desktopEnabled)
        XCTAssertEqual(store.report?.fiveHour?.remainingPercentage, 72.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.reportURL.path))
        let restarted = ClaudeUsageStore(manager: manager)
        XCTAssertTrue(restarted.desktopEnabled)
        XCTAssertNil(restarted.report)
        let original = store.report?.receivedAt
        store.desktopClient.perform = { _ in throw ClaudeDesktopError.serverUnavailable }
        await store.refreshDesktop(force: true)
        XCTAssertEqual(store.report?.receivedAt, original)
        XCTAssertNotNil(store.errorMessage)
        store.desktopClient.credentials = try database(session: "different-session")
        await store.refreshDesktop(force: true)
        XCTAssertNil(store.report, "Do not show another login's old report after a failed refresh")
        store.disconnect()
        XCTAssertFalse(store.desktopEnabled)
        XCTAssertFalse(store.connected)
        XCTAssertFalse(ClaudeUsageStore(manager: manager).desktopEnabled)
    }
}

private actor DesktopRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var started: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
