import CryptoKit
import Foundation
import UserNotifications

struct UsageAlert: Sendable {
    let id: String
    let title: String
    let body: String
    let expiresAt: Date

    private init(key: String, title: String, body: String, expiresAt: Date) {
        id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        self.title = title
        self.body = body
        self.expiresAt = expiresAt
    }

    static func lowUsage(
        scope: String, provider: String, window: String, remaining: Int?, reset: Date?,
        capturedAt: Date?, hasError: Bool, threshold: Int, now: Date
    ) -> Self? {
        guard !UsageFreshness.isOld(capturedAt: capturedAt, hasError: hasError, now: now),
            let remaining, (0...100).contains(remaining), remaining <= threshold,
            reset.map({ $0 > now }) ?? true
        else { return nil }
        // Without a reset time, cap repeat warnings at one per 24 hours.
        let period = reset.map { String($0.timeIntervalSince1970) } ?? "unknown"
        return Self(
            key: "low|\(scope)|\(window)|\(period)", title: "\(provider) capacity is low",
            body: "\(window): \(remaining)% remaining. Open the watcher for current usage.",
            expiresAt: reset ?? now.addingTimeInterval(86_400))
    }

    static func expiringReset(scope: String, expiry: Date?, capturedAt: Date?, hasError: Bool, now: Date) -> Self? {
        guard !UsageFreshness.isOld(capturedAt: capturedAt, hasError: hasError, now: now),
            let expiry, expiry > now, expiry.timeIntervalSince(now) <= 86_400
        else { return nil }
        return Self(
            key: "expiry|\(scope)|\(expiry.timeIntervalSince1970)", title: "Codex reset expires soon",
            body: "A banked reset expires within 24 hours. Open the watcher to check its expiration.", expiresAt: expiry)
    }
}

@MainActor
final class UsageNotifications: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published var lowUsageEnabled: Bool { didSet { defaults.set(lowUsageEnabled, forKey: "notifyLowUsage") } }
    @Published var expiryEnabled: Bool { didSet { defaults.set(expiryEnabled, forKey: "notifyResetExpiry") } }
    @Published var threshold: Int { didSet { defaults.set(threshold, forKey: "notificationThreshold") } }
    @Published private(set) var message: String?
    @Published private(set) var requestingPermission = false
    private let defaults: UserDefaults
    private let authorized: () async -> Bool
    private let deliver: (UsageAlert) async throws -> Void
    private var checking = false
    private var sent: [String: Double]

    init(
        defaults: UserDefaults = .standard,
        authorized: @escaping () async -> Bool = {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        },
        deliver: @escaping (UsageAlert) async throws -> Void = { alert in
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            // Quiet local alerts: no sound, badge, account label, or credential data.
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: alert.id, content: content, trigger: nil))
        }
    ) {
        self.defaults = defaults
        self.authorized = authorized
        self.deliver = deliver
        enabled = defaults.bool(forKey: "notificationsEnabled")
        lowUsageEnabled = defaults.object(forKey: "notifyLowUsage") as? Bool ?? true
        expiryEnabled = defaults.object(forKey: "notifyResetExpiry") as? Bool ?? true
        let savedThreshold = defaults.integer(forKey: "notificationThreshold")
        threshold = [10, 20, 25].contains(savedThreshold) ? savedThreshold : 20
        sent = defaults.dictionary(forKey: "sentUsageAlerts") as? [String: Double] ?? [:]
    }

    func setEnabled(_ value: Bool) async {
        guard !requestingPermission else { return }
        if !value {
            enabled = false
            defaults.set(false, forKey: "notificationsEnabled")
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            message = nil
            return
        }
        requestingPermission = true
        defer { requestingPermission = false }
        do {
            enabled = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
            defaults.set(enabled, forKey: "notificationsEnabled")
            message = enabled ? nil : "Notifications are disabled in macOS. Allow them in System Settings to enable alerts."
        } catch {
            message = "Could not request notification permission. Try again from the packaged app."
        }
    }

    func check(codex: ResetCreditsStore, claude: ClaudeUsageStore, now: Date) async {
        guard enabled else { return }
        var alerts: [UsageAlert] = []
        let scope = codex.activeSnapshotID?.rawValue ?? "active"
        if lowUsageEnabled {
            for window in codex.usageWindows where window.kind != .generic && !window.window.hasExpired(at: now) {
                if let alert = UsageAlert.lowUsage(
                    scope: "codex|\(scope)", provider: "Codex", window: window.title,
                    remaining: window.remainingPercent, reset: window.window.resetDate,
                    capturedAt: codex.usageCapturedAt, hasError: codex.usageErrorMessage != nil,
                    threshold: threshold, now: now)
                {
                    alerts.append(alert)
                }
            }
            if claude.connected, let report = claude.report {
                for (title, window) in [("5-hour limit", report.fiveHour), ("Weekly limit", report.sevenDay)] {
                    if let alert = UsageAlert.lowUsage(
                        scope: "claude|\(claude.sourceLabel)", provider: "Claude", window: title,
                        remaining: window?.remainingPercentage.map { Int($0.rounded(.down)) }, reset: window?.resetDate,
                        capturedAt: report.receiptDate, hasError: claude.errorMessage != nil || claude.configurationChanged,
                        threshold: threshold, now: now)
                    {
                        alerts.append(alert)
                    }
                }
            }
        }
        if expiryEnabled {
            for credit in codex.availableCreditDisplays {
                if let alert = UsageAlert.expiringReset(
                    scope: scope, expiry: credit.expiresAt, capturedAt: codex.lastChecked,
                    hasError: codex.creditsErrorMessage != nil, now: now)
                {
                    alerts.append(alert)
                }
            }
        }
        await send(alerts, now: now)
    }

    func send(_ alerts: [UsageAlert], now: Date) async {
        guard enabled, !checking else { return }
        checking = true
        defer { checking = false }
        sent = sent.filter { $0.value > now.timeIntervalSince1970 }
        defaults.set(sent, forKey: "sentUsageAlerts")
        guard await authorized() else {
            message = "Notifications are disabled in macOS. Allow them in System Settings to receive alerts."
            return
        }
        for alert in alerts where alert.expiresAt > now && sent[alert.id] == nil {
            guard enabled else { return }
            do {
                try await deliver(alert)
                sent[alert.id] = alert.expiresAt.timeIntervalSince1970
                defaults.set(sent, forKey: "sentUsageAlerts")
                message = nil
            } catch {
                message = "Could not deliver a notification. The watcher will retry while the reading is fresh."
                return
            }
        }
    }
}
