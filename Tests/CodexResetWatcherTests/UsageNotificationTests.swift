import XCTest

@testable import CodexResetWatcher

final class UsageNotificationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func low(remaining: Int? = 20, age: Double = 0, error: Bool = false, reset: Date? = nil, scope: String = "fixture")
        -> UsageAlert?
    {
        UsageAlert.lowUsage(
            scope: scope, provider: "Codex", window: "Weekly limit", remaining: remaining, reset: reset,
            capturedAt: now.addingTimeInterval(-age), hasError: error, threshold: 20, now: now)
    }

    func testOnlyFreshKnownLowReadingsAndUpcomingExpiriesCanAlert() throws {
        XCTAssertNotNil(low())
        XCTAssertNotNil(low(remaining: 0))
        XCTAssertNil(low(remaining: nil))
        XCTAssertNil(low(remaining: 21))
        XCTAssertNil(low(remaining: -1))
        XCTAssertNil(low(age: 300))
        XCTAssertNil(low(error: true))
        XCTAssertNil(low(reset: now))
        XCTAssertNil(low(reset: now.addingTimeInterval(-1)))
        for (seconds, eligible) in [(-1.0, false), (0, false), (1, true), (86_400, true), (86_401, false)] {
            let alert = UsageAlert.expiringReset(
                scope: "fixture", expiry: now.addingTimeInterval(seconds), capturedAt: now, hasError: false, now: now)
            XCTAssertEqual(alert != nil, eligible)
        }
        XCTAssertNil(UsageAlert.expiringReset(scope: "fixture", expiry: nil, capturedAt: now, hasError: false, now: now))
        XCTAssertNil(
            UsageAlert.expiringReset(scope: "fixture", expiry: now.addingTimeInterval(10), capturedAt: nil, hasError: false, now: now))
        XCTAssertNil(
            UsageAlert.expiringReset(scope: "fixture", expiry: now.addingTimeInterval(10), capturedAt: now, hasError: true, now: now))
        XCTAssertNotEqual(try XCTUnwrap(low()).id, try XCTUnwrap(low(scope: "second-fixture")).id)
    }

    @MainActor
    func testOptInAuthorizationDeduplicationAndRestart() async throws {
        let name = "watcher-notification-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var delivered: [String] = []
        let alert = try XCTUnwrap(low())
        let disabled = UsageNotifications(
            defaults: defaults,
            authorized: {
                XCTFail("Must not query permission while off")
                return true
            }, deliver: { delivered.append($0.id) })
        XCTAssertFalse(disabled.enabled)
        await disabled.send([alert], now: now)
        XCTAssertTrue(delivered.isEmpty)

        defaults.set(true, forKey: "notificationsEnabled")
        let denied = UsageNotifications(defaults: defaults, authorized: { false }, deliver: { delivered.append($0.id) })
        await denied.send([alert], now: now)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertNotNil(denied.message)

        let first = UsageNotifications(defaults: defaults, authorized: { true }, deliver: { delivered.append($0.id) })
        await first.send([alert, alert], now: now)
        await first.send([alert], now: now.addingTimeInterval(15))
        XCTAssertEqual(delivered.count, 1)
        let restarted = UsageNotifications(defaults: defaults, authorized: { true }, deliver: { delivered.append($0.id) })
        await restarted.send([alert], now: now.addingTimeInterval(30))
        XCTAssertEqual(delivered.count, 1)
        let nextPeriod = try XCTUnwrap(low(reset: now.addingTimeInterval(604_800)))
        await restarted.send([nextPeriod], now: now)
        XCTAssertEqual(delivered.count, 2)
        let saved = try XCTUnwrap(defaults.dictionary(forKey: "sentUsageAlerts"))
        XCTAssertTrue(saved.keys.allSatisfy { $0.count == 64 && !$0.contains("fixture") })
    }

    @MainActor
    func testDeliveryFailureRetriesAndUnknownResetRearmsAfter24Hours() async throws {
        let name = "watcher-notification-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "notificationsEnabled")
        var attempts = 0
        let notifications = UsageNotifications(
            defaults: defaults, authorized: { true },
            deliver: { _ in
                attempts += 1
                if attempts == 1 { throw NSError(domain: "synthetic", code: 1) }
            })
        let alert = try XCTUnwrap(low())
        await notifications.send([alert], now: now)
        XCTAssertNotNil(notifications.message)
        await notifications.send([alert], now: now)
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(notifications.message)
        await notifications.send([alert], now: now.addingTimeInterval(86_400))
        XCTAssertEqual(attempts, 2, "Expired candidates must not be delivered")
        let tomorrow = now.addingTimeInterval(86_400)
        let fresh = try XCTUnwrap(
            UsageAlert.lowUsage(
                scope: "fixture", provider: "Codex", window: "Weekly limit", remaining: 10, reset: nil,
                capturedAt: tomorrow, hasError: false, threshold: 20, now: tomorrow))
        await notifications.send([fresh], now: tomorrow)
        XCTAssertEqual(attempts, 3)
    }
}
