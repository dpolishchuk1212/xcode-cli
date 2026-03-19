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

    @Option(name: .long, help: "App PID — exits when the app terminates")
    var appPid: Int32?

    func run() throws {
        let filter = LogFilter(pattern: grep)

        // Clear/create log file
        nonisolated(unsafe) var logHandle: FileHandle?
        if let logFile {
            FileManager.default.createFile(atPath: logFile, contents: nil, attributes: nil)
            logHandle = FileHandle(forWritingAtPath: logFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "simctl", "spawn", deviceUdid, "log", "stream",
            "--level", "debug",
            "--predicate", LogFilter.logStreamPredicate(bundleId: bundleId),
            "--style", "compact"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let str = String(line)
                if filter.matches(str) {
                    let lineData = Data((str + "\n").utf8)
                    FileHandle.standardOutput.write(lineData)
                    logHandle?.write(lineData)
                }
            }
        }

        // Monitor app PID — terminate log stream when app dies
        let pidToMonitor = appPid
        if let pidToMonitor {
            DispatchQueue.global().async {
                while kill(pidToMonitor, 0) == 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                }
                process.terminate()
            }
        }

        // Clean exit on signals
        signal(SIGINT) { _ in _exit(0) }
        signal(SIGTERM) { _ in _exit(0) }

        try process.run()
        process.waitUntilExit()
    }
}
