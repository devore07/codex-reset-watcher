import Foundation

public struct ClaudeUsageWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Double?
    public let resetsAt: TimeInterval?

    public init(usedPercentage: Double?, resetsAt: TimeInterval?) {
        self.usedPercentage = usedPercentage.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        self.resetsAt = resetsAt.flatMap { Self.validEpoch($0) ? $0 : nil }
    }

    enum CodingKeys: String, CodingKey { case usedPercentage, resetsAt }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usedPercentage: try? values.decode(Double.self, forKey: .usedPercentage),
            resetsAt: try? values.decode(Double.self, forKey: .resetsAt)
        )
    }

    public static func validEpoch(_ value: TimeInterval) -> Bool {
        value.isFinite && (1_577_836_800...4_102_444_800).contains(value)
    }

    public var remainingPercentage: Double? { usedPercentage.map { 100 - $0 } }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    public func hasExpired(at now: Date) -> Bool { resetDate.map { $0 <= now } ?? false }
}

public struct ClaudeUsageReport: Codable, Equatable, Sendable {
    public let version: Int
    public let receivedAt: TimeInterval
    public let fiveHour: ClaudeUsageWindow?
    public let sevenDay: ClaudeUsageWindow?
    public let waitingForUsage: Bool

    public init(receivedAt: Date, fiveHour: ClaudeUsageWindow?, sevenDay: ClaudeUsageWindow?, waitingForUsage: Bool = false) {
        version = 1
        self.receivedAt = receivedAt.timeIntervalSince1970
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.waitingForUsage = waitingForUsage
    }

    private enum CodingKeys: String, CodingKey { case version, receivedAt, fiveHour, sevenDay, waitingForUsage }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        receivedAt = try values.decode(Double.self, forKey: .receivedAt)
        fiveHour = try? values.decode(ClaudeUsageWindow.self, forKey: .fiveHour)
        sevenDay = try? values.decode(ClaudeUsageWindow.self, forKey: .sevenDay)
        waitingForUsage = try values.decodeIfPresent(Bool.self, forKey: .waitingForUsage) ?? false
    }

    public var receiptDate: Date { Date(timeIntervalSince1970: receivedAt) }
    public var hasUsage: Bool { fiveHour?.usedPercentage != nil || sevenDay?.usedPercentage != nil }
    public var isPartial: Bool { fiveHour?.usedPercentage == nil || sevenDay?.usedPercentage == nil }
    public func isOld(at now: Date) -> Bool { now.timeIntervalSince1970 >= receivedAt + 300 }

    public static func decode(_ data: Data, now: Date = Date()) throws -> Self {
        let report = try JSONDecoder().decode(Self.self, from: data)
        guard report.version == 1, ClaudeUsageWindow.validEpoch(report.receivedAt),
            report.receivedAt <= now.timeIntervalSince1970 + 60
        else {
            throw ClaudeConnectionError.invalidReport
        }
        return report
    }

    /// Only these fields cross the persistence boundary; the rest of stdin is discarded.
    public static func fromStatusLine(_ data: Data, now: Date = Date()) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(Envelope.self, from: data)
        return Self(
            receivedAt: now, fiveHour: envelope.rateLimits?.fiveHour, sevenDay: envelope.rateLimits?.sevenDay,
            waitingForUsage: envelope.rateLimits?.hasWindowFields != true
        )
    }

    private struct Envelope: Decodable {
        let rateLimits: Windows?
        enum CodingKeys: String, CodingKey { case rateLimits }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            rateLimits = try values.decodeIfPresent(Windows.self, forKey: .rateLimits)
        }
    }

    private struct Windows: Decodable {
        let fiveHour: ClaudeUsageWindow?
        let sevenDay: ClaudeUsageWindow?
        let hasWindowFields: Bool
        enum CodingKeys: String, CodingKey { case fiveHour, sevenDay }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            hasWindowFields = values.contains(.fiveHour) || values.contains(.sevenDay)
            fiveHour = try? values.decode(ClaudeUsageWindow.self, forKey: .fiveHour)
            sevenDay = try? values.decode(ClaudeUsageWindow.self, forKey: .sevenDay)
        }
    }
}

public enum ClaudeConnectionError: LocalizedError {
    case invalidReport, invalidSettings, configurationChanged, anotherConnection, missingHelper, unsupportedVersion

    public var errorDescription: String? {
        switch self {
        case .invalidReport: "Claude usage is unavailable. Waiting for a valid report from Claude Code."
        case .invalidSettings: "Claude settings could not be read safely. Fix settings.json before connecting."
        case .configurationChanged:
            "Claude status-line settings changed. Your edits were preserved. Restore the watcher command before retrying, or remove it manually."
        case .anotherConnection: "Disconnect the current Claude configuration before choosing another directory."
        case .missingHelper: "The Claude helper is missing from this app. Reinstall the packaged app."
        case .unsupportedVersion: "Choose a Claude Code executable at version 2.1.251 or later, then connect again."
        }
    }
}
