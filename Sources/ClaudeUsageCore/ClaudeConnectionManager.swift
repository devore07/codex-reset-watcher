import Foundation

public struct ClaudeConnectionManager: Sendable {
    public let directory: URL
    public var reportURL: URL { directory.appendingPathComponent("usage.json") }
    public var helperURL: URL { directory.appendingPathComponent("ClaudeUsageBridge") }
    private var stateURL: URL { directory.appendingPathComponent("connection.json") }

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Reset Watcher/Claude")
    }

    public init(directory: URL = Self.defaultDirectory) { self.directory = directory }

    public struct Connection: Codable, Sendable {
        public var enabled: Bool
        public let configurationPath: String
        public let wrapperCommand: String
        // Configuration recovery only. This is never included in usage reports.
        public let previousStatusLine: Data?

        public var previousCommand: String? {
            guard let previousStatusLine,
                let settings = try? JSONSerialization.jsonObject(with: previousStatusLine) as? [String: Any]
            else { return nil }
            return settings["command"] as? String
        }
    }

    public func connection() throws -> Connection? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return nil }
        return try JSONDecoder().decode(Connection.self, from: Data(contentsOf: stateURL))
    }

    public func isConfigured(_ connection: Connection) -> Bool {
        guard connection.enabled,
            let settings = try? readSettings(at: URL(fileURLWithPath: connection.configurationPath)).object,
            let line = settings["statusLine"] as? [String: Any]
        else { return false }
        return line["type"] as? String == "command" && line["command"] as? String == connection.wrapperCommand
    }

    public func connect(configurationDirectory: URL, bundledHelper: URL, version: String) throws {
        guard Self.supports(version: version) else { throw ClaudeConnectionError.unsupportedVersion }
        guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else { throw ClaudeConnectionError.missingHelper }
        let settingsURL = configurationDirectory.standardizedFileURL.appendingPathComponent("settings.json")
        try ClaudePrivateFiles.withLock(in: directory) {
            let existing = try connection()
            if let existing, existing.enabled && existing.configurationPath != settingsURL.path {
                throw ClaudeConnectionError.anotherConnection
            }
            let original = try readSettings(at: settingsURL)
            let previous = original.object["statusLine"]
            let previousObject = previous as? [String: Any]
            if previous != nil {
                guard let previousObject, previousObject["type"] as? String == "command",
                    let command = previousObject["command"] as? String, !command.isEmpty
                else {
                    throw ClaudeConnectionError.invalidSettings
                }
            }
            let wrapper = "\(Self.shellQuote(helperURL.path)) --directory \(Self.shellQuote(directory.path))"
            let alreadyWrapped = previousObject?["command"] as? String == wrapper
            if let existing, existing.enabled && !alreadyWrapped {
                throw ClaudeConnectionError.configurationChanged
            }
            if alreadyWrapped && existing == nil { throw ClaudeConnectionError.configurationChanged }
            let backup =
                alreadyWrapped
                ? existing?.previousStatusLine
                : try previous.map {
                    try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys])
                }
            var state = Connection(enabled: false, configurationPath: settingsURL.path, wrapperCommand: wrapper, previousStatusLine: backup)
            // Save recovery metadata before changing settings; retry can recover an interrupted install.
            try ClaudePrivateFiles.atomicWrite(try JSONEncoder().encode(state), to: stateURL)
            try ClaudePrivateFiles.atomicWrite(Data(contentsOf: bundledHelper), to: helperURL, mode: 0o700)
            try FileManager.default.createDirectory(
                at: configurationDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var updated = original.object
            var line = previousObject ?? [:]
            line["type"] = "command"
            line["command"] = wrapper
            updated["statusLine"] = line
            guard try readSettings(at: settingsURL).data == original.data else { throw ClaudeConnectionError.configurationChanged }
            try ClaudePrivateFiles.atomicWrite(
                try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]), to: settingsURL)
            if !alreadyWrapped { try? FileManager.default.removeItem(at: reportURL) }
            state.enabled = true
            try ClaudePrivateFiles.atomicWrite(try JSONEncoder().encode(state), to: stateURL)
        }
    }

    public func disconnect() throws {
        try ClaudePrivateFiles.withLock(in: directory) {
            guard var state = try connection() else { return }
            let settingsURL = URL(fileURLWithPath: state.configurationPath)
            let original = try readSettings(at: settingsURL)
            var updated = original.object
            if var current = updated["statusLine"] as? [String: Any],
                current["command"] as? String == state.wrapperCommand
            {
                let previous = try state.previousStatusLine.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
                if let previous {
                    // Restore only our command; preserve edits to padding and other options.
                    current["command"] = previous["command"]
                    current["type"] = previous["type"]
                    updated["statusLine"] = current
                } else {
                    current.removeValue(forKey: "command")
                    current.removeValue(forKey: "type")
                    if current.isEmpty {
                        updated.removeValue(forKey: "statusLine")
                    } else {
                        current["type"] = "command"
                        current["command"] = "printf ''"
                        updated["statusLine"] = current
                    }
                }
                guard try readSettings(at: settingsURL).data == original.data else { throw ClaudeConnectionError.configurationChanged }
                try ClaudePrivateFiles.atomicWrite(
                    try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .sortedKeys]), to: settingsURL)
            }
            // Keep an inert forwarding helper for already-running sessions. Never restore over a user's replacement command.
            state.enabled = false
            try ClaudePrivateFiles.atomicWrite(try JSONEncoder().encode(state), to: stateURL)
            try? FileManager.default.removeItem(at: reportURL)
        }
    }

    public func record(statusLine data: Data, now: Date = Date()) throws {
        try ClaudePrivateFiles.withLock(in: directory) {
            guard let state = try connection(), isConfigured(state) else { return }
            let report =
                (try? ClaudeUsageReport.fromStatusLine(data, now: now))
                ?? ClaudeUsageReport(receivedAt: now, fiveHour: nil, sevenDay: nil)
            if let prior = try? readReport(now: now), prior.receivedAt > report.receivedAt { return }
            try ClaudePrivateFiles.atomicWrite(try JSONEncoder().encode(report), to: reportURL)
        }
    }

    public func readReport(now: Date = Date()) throws -> ClaudeUsageReport {
        let size = try FileManager.default.attributesOfItem(atPath: reportURL.path)[.size] as? NSNumber
        guard let size, size.intValue <= 16_384 else { throw ClaudeConnectionError.invalidReport }
        return try ClaudeUsageReport.decode(Data(contentsOf: reportURL), now: now)
    }

    public static func supports(version: String) -> Bool {
        let token = version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first ?? ""
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        let parts = components.compactMap { Int($0) }
        guard components.count == 3, parts.count == 3 else { return false }
        return !parts.lexicographicallyPrecedes([2, 1, 251])
    }

    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }

    private func readSettings(at url: URL) throws -> (data: Data?, object: [String: Any]) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, [:]) }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ClaudeConnectionError.invalidSettings }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeConnectionError.invalidSettings
            }
            return (data, object)
        } catch { throw ClaudeConnectionError.invalidSettings }
    }
}
