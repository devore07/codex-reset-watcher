import AppKit
import ClaudeUsageCore
import Foundation

@MainActor
final class ClaudeUsageStore: ObservableObject {
    @Published private(set) var report: ClaudeUsageReport?
    @Published private(set) var connected = false
    @Published private(set) var configurationChanged = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var setupMessage: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var now = Date()
    @Published var showingClaude = false
    @Published var configurationPath: String
    @Published var executablePath: String

    let manager: ClaudeConnectionManager
    private var observation: ClaudeDirectoryObservation?
    private var clockTask: Task<Void, Never>?

    init(manager: ClaudeConnectionManager = ClaudeConnectionManager()) {
        self.manager = manager
        let home = FileManager.default.homeDirectoryForCurrentUser
        configurationPath =
            (try? manager.connection()?.configurationPath).map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            } ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? home.appendingPathComponent(".claude").path
        let desktopEngines = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
        let versions = (try? FileManager.default.contentsOfDirectory(at: desktopEngines, includingPropertiesForKeys: nil)) ?? []
        let bundled = versions.filter { ClaudeConnectionManager.supports(version: $0.lastPathComponent) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("claude.app/Contents/MacOS/claude").path }
        let candidates =
            [home.appendingPathComponent(".local/bin/claude").path, "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] + bundled
        executablePath = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? candidates[0]
    }

    var statusTitle: String {
        if configurationChanged { return "Claude connection changed" }
        if !connected { return "Connect Claude" }
        if errorMessage != nil { return "Claude usage unavailable" }
        guard let report else { return "Waiting for Claude Code" }
        if report.isOld(at: now) { return "Last reported" }
        if report.isPartial { return "Partial usage report" }
        return "Reported by Claude Code"
    }

    var receiptLabel: String? {
        report.map { "Received \(DateFormatting.weekdayCompact($0.receiptDate))" }
    }

    func start() {
        guard clockTask == nil else { return }
        reload()
        observeDirectory()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self else { return }
                self.reload()
                if self.observation == nil { self.observeDirectory() }
            }
        }
    }

    private func observeDirectory() {
        observation = ClaudeDirectoryObservation(directory: manager.directory) { [weak self] in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    func reload(at date: Date = Date()) {
        now = date
        do {
            let connection = try manager.connection()
            connected = connection?.enabled == true
            configurationChanged = connection.map { $0.enabled && !manager.isConfigured($0) } ?? false
            guard connected else {
                report = nil
                errorMessage = nil
                return
            }
            guard !configurationChanged else {
                errorMessage = ClaudeConnectionError.configurationChanged.localizedDescription
                return
            }
            if !FileManager.default.fileExists(atPath: manager.reportURL.path), report == nil {
                errorMessage = nil
                return
            }
            let incoming = try manager.readReport(now: date)
            if incoming.waitingForUsage, !incoming.hasUsage, report == nil {
                errorMessage = nil
                return
            }
            guard incoming.hasUsage else { throw ClaudeConnectionError.invalidReport }
            report = incoming
            errorMessage = nil
        } catch {
            errorMessage =
                report == nil
                ? "Usage could not be read. Waiting for a valid Claude Code report."
                : "Usage could not be read. Showing the last valid report with its original receipt time."
        }
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        setupMessage = nil
        defer { isConnecting = false }
        let executable = URL(fileURLWithPath: NSString(string: executablePath).expandingTildeInPath)
        let configuration = URL(fileURLWithPath: NSString(string: configurationPath).expandingTildeInPath)
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ClaudeUsageBridge")
        let manager = manager
        do {
            try await Task.detached {
                let version = try ClaudeExecutableVersion.read(executable)
                try manager.connect(configurationDirectory: configuration, bundledHelper: helper, version: version)
            }.value
            setupMessage = "Connected. Use Claude Code to receive usage. Project settings can override the user status line."
            observeDirectory()
        } catch {
            setupMessage =
                (error as? ClaudeConnectionError)?.localizedDescription
                ?? "Could not connect Claude. Check the selected paths and their permissions."
        }
        reload()
    }

    func disconnect() {
        do {
            try manager.disconnect()
            setupMessage = "Disconnected. Any replacement status-line command was preserved."
        } catch {
            setupMessage =
                (error as? ClaudeConnectionError)?.localizedDescription
                ?? "Could not disconnect. Check Claude settings and file permissions."
        }
        reload()
    }

    func choosePath(directory: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        panel.message =
            directory ? "Choose the Claude configuration directory containing settings.json." : "Choose the Claude Code executable."
        if panel.runModal() == .OK, let url = panel.url {
            if directory { configurationPath = url.path } else { executablePath = url.path }
        }
    }
}

private final class ClaudeDirectoryObservation: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    init?(directory: URL, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .global(qos: .utility))
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit { source.cancel() }
}

private enum ClaudeExecutableVersion {
    static func read(_ executable: URL) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ClaudeConnectionError.unsupportedVersion }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            throw ClaudeConnectionError.unsupportedVersion
        }
        guard process.terminationStatus == 0 else { throw ClaudeConnectionError.unsupportedVersion }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
