import Foundation

/// Manages a persistent LLDB debug session running inside a tmux session.
///
/// Architecture:
/// - `debug start` → tmux session with LLDB attached to the app
/// - `debug exec` → `tmux send-keys` + `capture-pane` for clean text output
/// - Unique markers after each command signal completion
/// - User can `tmux attach -t xcode-debug` for interactive LLDB access
public enum DebugSession {
    public static let sessionName = "xcode-debug"
    public static let sessionFile = "/tmp/xcode-cli-debug.json"

    // MARK: - Session Info

    public struct Info: Codable {
        public var appPid: Int32
        public var sessionName: String

        public init(appPid: Int32, sessionName: String) {
            self.appPid = appPid
            self.sessionName = sessionName
        }
    }

    /// Load session info, verifying tmux session is still alive.
    public static func loadSession() -> Info? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: sessionFile)),
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        let result = ProcessRunner.exec("/usr/bin/env", arguments: ["tmux", "has-session", "-t", info.sessionName])
        guard result.exitCode == 0 else {
            cleanupFiles()
            return nil
        }
        return info
    }

    public static func saveSession(_ info: Info) throws {
        let data = try JSONEncoder().encode(info)
        try data.write(to: URL(fileURLWithPath: sessionFile))
    }

    // MARK: - Session Lifecycle

    /// Start a tmux session with LLDB attached to the given PID.
    public static func start(pid: Int32) throws -> Info {
        cleanup()

        // Create tmux session with LLDB (no status bar, large scrollback)
        let tmuxResult = ProcessRunner.exec("/usr/bin/env", arguments: [
            "tmux", "new-session", "-d", "-s", sessionName, "-x", "220", "-y", "50",
            "--", "xcrun", "lldb", "--no-use-colors", "-p", String(pid)
        ])
        guard tmuxResult.exitCode == 0 else {
            throw DebugError.startFailed("Failed to create tmux session: \(tmuxResult.output)")
        }

        // Configure: no status bar, large scrollback, dumb terminal
        _ = ProcessRunner.exec("/usr/bin/env", arguments: [
            "tmux", "set-option", "-t", sessionName, "status", "off"
        ])
        _ = ProcessRunner.exec("/usr/bin/env", arguments: [
            "tmux", "set-option", "-t", sessionName, "history-limit", "50000"
        ])

        // Wait for LLDB prompt
        guard waitForText("(lldb)", timeout: 10.0) else {
            killSession()
            throw DebugError.startFailed("LLDB failed to attach (no prompt within 10s)")
        }

        // Continue the process so the app keeps running
        let _ = try? execSingle("process continue")

        let info = Info(appPid: pid, sessionName: sessionName)
        try saveSession(info)
        return info
    }

    /// Send LLDB commands and return their output.
    public static func exec(commands: [String]) throws -> [CommandResult] {
        guard loadSession() != nil else { throw DebugError.noSession }
        return try commands.map { try execSingle($0) }
    }

    /// Stop the debug session — detach LLDB and kill tmux.
    public static func cleanup() {
        if loadSession() != nil {
            sendKeys("detach")
            usleep(300_000)
            sendKeys("quit")
            usleep(200_000)
        }
        killSession()
        cleanupFiles()
    }

    // MARK: - Command Execution

    public struct CommandResult {
        public var command: String
        public var output: String
        public var success: Bool
    }

    private static func execSingle(_ command: String) throws -> CommandResult {
        // Unique marker for this command
        let marker = "__XCDONE_\(Int.random(in: 100000...999999))__"

        // Send the command + marker
        sendKeys(command)
        sendKeys("script print(\"\(marker)\")")

        // Wait for marker in capture-pane output
        var capturedOutput: String?
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let pane = capturePane()
            if pane.contains(marker) {
                capturedOutput = pane
                break
            }
            Thread.sleep(forTimeInterval: 0.15)
        }

        guard let captured = capturedOutput else {
            return CommandResult(command: command, output: "[timed out waiting for command to complete]", success: false)
        }

        let output = parseOutput(captured, command: command, marker: marker)
        let hasError = output.contains("error:") && !output.contains("error: refcount")
        return CommandResult(command: command, output: output, success: !hasError)
    }

    /// Get the process state from LLDB.
    public static func getProcessState() throws -> String {
        guard loadSession() != nil else { throw DebugError.noSession }
        let result = try execSingle("process status")
        let output = result.output.lowercased()
        if output.contains("exited") { return "exited" }
        if output.contains("crashed") { return "crashed" }
        if output.contains("stopped") { return "stopped" }
        if output.contains("running") { return "running" }
        return "unknown"
    }

    // MARK: - tmux Helpers

    private static func sendKeys(_ text: String) {
        _ = ProcessRunner.exec("/usr/bin/env", arguments: [
            "tmux", "send-keys", "-t", sessionName, text, "Enter"
        ])
    }

    /// Capture the pane content as plain text (no escape codes).
    private static func capturePane() -> String {
        let result = ProcessRunner.exec("/usr/bin/env", arguments: [
            "tmux", "capture-pane", "-t", sessionName, "-p", "-S", "-"
        ])
        return result.output
    }

    private static func waitForText(_ text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if capturePane().contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Extract command output from captured pane text.
    private static func parseOutput(_ captured: String, command: String, marker: String) -> String {
        var lines = captured.components(separatedBy: "\n")

        // Find the LAST occurrence of the command echo (in case of duplicates from history)
        let cmdEcho = "(lldb) \(command)"
        var startIdx = 0
        for (i, line) in lines.enumerated().reversed() {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(cmdEcho) ||
               line.trimmingCharacters(in: .whitespaces) == command {
                startIdx = i + 1
                break
            }
        }

        // Find the marker line
        var endIdx = lines.count
        for (i, line) in lines.enumerated() where i >= startIdx {
            if line.contains(marker) {
                endIdx = i
                break
            }
        }

        guard startIdx < endIdx else { return "" }
        lines = Array(lines[startIdx..<endIdx])

        // Remove "script print(...)" echo and (lldb) prompts
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("(lldb) script print(") { return false }
            if trimmed == "(lldb)" { return false }
            return true
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func killSession() {
        _ = ProcessRunner.exec("/usr/bin/env", arguments: ["tmux", "kill-session", "-t", sessionName])
    }

    static func cleanupFiles() {
        try? FileManager.default.removeItem(atPath: sessionFile)
    }

    // MARK: - Errors

    public enum DebugError: LocalizedError {
        case startFailed(String)
        case noSession
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .startFailed(let msg): return msg
            case .noSession: return "No active debug session. Start one with: xcode-cli debug start --pid <PID>"
            case .commandFailed(let msg): return msg
            }
        }
    }
}
