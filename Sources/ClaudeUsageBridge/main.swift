import ClaudeUsageCore
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// The parent's status-line command may intentionally ignore stdin.
signal(SIGPIPE, SIG_IGN)
let arguments = CommandLine.arguments
guard arguments.count == 3, arguments[1] == "--directory" else { exit(2) }
let manager = ClaudeConnectionManager(directory: URL(fileURLWithPath: arguments[2]))
let input = FileHandle.standardInput.readDataToEndOfFile()
let receivedAt = Date()
// Feed errors must never break a pre-existing status line or disclose its input.
try? manager.record(statusLine: input, now: receivedAt)
if let command = try? manager.connection()?.previousCommand {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardInput = pipe
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        try? pipe.fileHandleForWriting.write(contentsOf: input)
        try? pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        exit(process.terminationStatus)
    } catch { exit(1) }
} else {
    let report = try? ClaudeUsageReport.fromStatusLine(input, now: receivedAt)
    let parts = [("5h", report?.fiveHour), ("Week", report?.sevenDay)].compactMap { title, window -> String? in
        guard let window, !window.hasExpired(at: receivedAt), let remaining = window.remainingPercentage else { return nil }
        return "\(title): \(Int(remaining.rounded(.down)))% remaining"
    }
    print(parts.isEmpty ? "Claude usage unavailable" : parts.joined(separator: " | "))
}
