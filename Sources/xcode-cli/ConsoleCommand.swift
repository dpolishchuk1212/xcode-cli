import ArgumentParser
import Foundation
import XcodeCLICore

struct ConsoleCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "console",
        abstract: "Stream console logs from a running iOS Simulator app"
    )

    @Option(name: .long, help: "Simulator device UDID")
    var deviceUdid: String

    @Option(name: .long, help: "App bundle identifier")
    var bundleId: String

    @Option(name: .long, help: "Filter log messages by pattern (case-insensitive)")
    var grep: String?

    @Option(name: .long, help: "Write logs to a file (cleared on start)")
    var logFile: String?

    @Option(name: .long, help: "App PID — exits when the app terminates (ignored when --launch is used)")
    var appPid: Int32?

    @Flag(name: .long, help: "Launch the app and capture stdout/stderr (for print()/NSLog)")
    var launch: Bool = false

    func run() throws {
        let filter = LogFilter(pattern: grep)

        // Clear/create log file
        nonisolated(unsafe) var logHandle: FileHandle?
        if let logFile {
            FileManager.default.createFile(atPath: logFile, contents: nil, attributes: nil)
            logHandle = FileHandle(forWritingAtPath: logFile)
        }

        @Sendable func emit(_ line: String) {
            let lineData = Data((line + "\n").utf8)
            FileHandle.standardOutput.write(lineData)
            logHandle?.write(lineData)
        }

        // Track the app PID for lifecycle monitoring
        nonisolated(unsafe) var monitorPid = appPid

        // If --launch, launch the app with --console to capture stdout (print())
        var launchProcess: Process?
        if launch {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["simctl", "launch", "--console-pty", deviceUdid, bundleId]

            // --console-pty uses a PTY (line-buffered), merges app stdout+stderr into simctl's stdout
            let ptyPipe = Pipe()
            proc.standardOutput = ptyPipe
            proc.standardError = FileHandle.nullDevice

            ptyPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    let str = String(line)
                    // First line is "com.app.bundle: 12345" — extract PID
                    if monitorPid == nil, str.contains(bundleId), str.contains(":") {
                        monitorPid = str.split(separator: ":").last
                            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        continue
                    }
                    if !str.isEmpty, filter.matches(str) { emit("[app] \(str)") }
                }
            }

            try proc.run()
            launchProcess = proc

            // Wait briefly for PID to be captured
            for _ in 0..<20 {
                if monitorPid != nil { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        // Start log stream for os_log / Logger / NSLog messages
        let logStreamProcess = Process()
        logStreamProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        logStreamProcess.arguments = [
            "simctl", "spawn", deviceUdid, "log", "stream",
            "--level", "debug",
            "--predicate", LogFilter.logStreamPredicate(bundleId: bundleId),
            "--style", "compact"
        ]

        let logPipe = Pipe()
        logStreamProcess.standardOutput = logPipe
        logStreamProcess.standardError = FileHandle.nullDevice

        logPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let str = String(line)
                if filter.matches(str) { emit(str) }
            }
        }

        try logStreamProcess.run()

        // Monitor app PID — terminate everything when app dies
        let pidToMonitor = monitorPid
        let launchProc = launchProcess
        if let pidToMonitor {
            DispatchQueue.global().async {
                while kill(pidToMonitor, 0) == 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                }
                logStreamProcess.terminate()
                launchProc?.terminate()
            }
        }

        signal(SIGINT) { _ in _exit(0) }
        signal(SIGTERM) { _ in _exit(0) }

        // Wait for log stream to end (main blocking call)
        logStreamProcess.waitUntilExit()
    }
}
