import ArgumentParser
import Foundation
import XcodeCLICore

/// PID of the log stream process, used by signal handler to clean up orphans.
nonisolated(unsafe) var _logStreamPID: pid_t = 0

private func _cleanupLogStream(_: Int32) {
    if _logStreamPID > 0 { kill(_logStreamPID, SIGTERM) }
    _exit(0)
}

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Build, install, and run an app on the iOS Simulator"
    )

    // MARK: - Project options

    @Option(name: .long, help: "Path to .xcworkspace")
    var workspace: String?

    @Option(name: .long, help: "Path to .xcodeproj")
    var project: String?

    @Option(name: .shortAndLong, help: "Build scheme")
    var scheme: String?

    @Option(name: .shortAndLong, help: "Build configuration (Debug/Release)")
    var configuration: String = "Debug"

    // MARK: - Run options

    @Option(name: .long, help: "Simulator name or UDID (default: latest iPhone)")
    var simulator: String?

    @Flag(name: .long, help: "Skip the build step")
    var skipBuild: Bool = false

    @Flag(name: .long, help: "Install and attach debugger but don't launch (you launch manually)")
    var wait: Bool = false

    @Flag(name: .long, inversion: .prefixedNo, help: "Attach LLDB debugger")
    var debug: Bool = true

    @Flag(name: .long, inversion: .prefixedNo, help: "Stream console logs")
    var console: Bool = true

    @Option(name: .long, help: "Filter console logs by pattern (case-insensitive substring match)")
    var grep: String?

    @Flag(name: .long, help: "Output results as JSON (for tool integrations)")
    var json: Bool = false

    mutating func run() throws {
        // 1. Resolve project and simulator first (needed for build destination)
        let info = try ProjectFinder.discover(workspace: workspace, project: project, scheme: scheme)
        guard let schemeName = info.scheme else {
            try failWith("Could not determine scheme. Use --scheme to specify.")
        }

        let simListResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        let allDevices = SimulatorFinder.parseDevices(from: simListResult.output)
        guard let device = SimulatorFinder.findBest(from: allDevices, matching: simulator) else {
            try failWith("No suitable iOS Simulator found.\(simulator.map { " No match for '\($0)'." } ?? "")")
        }

        jsonSet("simulator", device.name)

        // 2. Build (unless --skip-build), targeting the selected simulator
        if !skipBuild {
            var buildArgs = ["build"]
            if let ws = info.workspace { buildArgs += ["-workspace", ws] }
            else if let proj = info.project { buildArgs += ["-project", proj] }
            buildArgs += ["-scheme", schemeName,
                          "-configuration", configuration,
                          "-destination", "platform=iOS Simulator,id=\(device.udid)"]

            let label = schemeName
            if !json { print("Building \(label) (\(configuration)) for \(device.name)...") }

            let start = Date()
            let result = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["xcodebuild"] + buildArgs)
            let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))

            let formatter = BuildResultFormatter(
                issues: BuildLogParser.parse(result.output),
                exitCode: result.exitCode,
                elapsed: elapsed,
                filter: .errors,
                rawOutput: result.output
            )

            jsonSet("buildSuccess", result.exitCode == 0)
            jsonSet("buildElapsed", elapsed)
            jsonSet("errorCount", formatter.errors.count)
            jsonSet("warningCount", formatter.warnings.count)
            jsonSet("buildOutput", formatter.formatted)

            if !json { print(formatter.formatted) }

            if result.exitCode != 0 {
                try failWith(nil)
            }
        }

        let output = RunOutputConfig(debug: debug, console: console)

        // 4. Boot simulator if needed
        if !device.isBooted {
            if !json && output.showStatusMessages { print("Booting \(device.name)...") }
            let bootResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "boot", device.udid])
            if bootResult.exitCode != 0 {
                try failWith("Failed to boot simulator: \(bootResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Open Simulator.app so the user can see the device
        _ = ProcessRunner.exec("/usr/bin/open", arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", device.udid])

        // 5. Resolve app bundle ID and .app path from build settings
        var settingsArgs = ["xcodebuild", "-showBuildSettings", "-scheme", schemeName, "-configuration", configuration,
                            "-destination", "id=\(device.udid)"]
        if let ws = info.workspace { settingsArgs += ["-workspace", ws] }
        else if let proj = info.project { settingsArgs += ["-project", proj] }

        let settingsResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: settingsArgs)
        let bundleId = extractSetting("PRODUCT_BUNDLE_IDENTIFIER", from: settingsResult.output)
        let buildDir = extractSetting("BUILT_PRODUCTS_DIR", from: settingsResult.output)
        let productName = extractSetting("FULL_PRODUCT_NAME", from: settingsResult.output)
        let executableName = extractSetting("EXECUTABLE_NAME", from: settingsResult.output)

        guard let bundleId else {
            try failWith("Could not determine bundle identifier from build settings.")
        }

        // Compute app binary path for LLDB symbol loading
        let appBinaryPath: String? = if let buildDir, let productName, let executableName {
            "\(buildDir)/\(productName)/\(executableName)"
        } else {
            nil
        }

        // 6. Install app
        if let buildDir, let productName {
            let appPath = "\(buildDir)/\(productName)"
            if !json && output.showStatusMessages { print("Installing \(productName) on \(device.name)...") }
            let installResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "install", device.udid, appPath])
            if installResult.exitCode != 0 {
                try failWith("Install failed: \(installResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // 7. Launch + attach
        let shouldLaunch = !wait

        // Start console log streaming in background
        var logProcess: Process?
        if console {
            logProcess = startLogStream(deviceUDID: device.udid, bundleId: bundleId, filter: LogFilter(pattern: grep))

            // Ensure log stream is killed on exit (Ctrl+C, SIGTERM, etc.)
            if let lp = logProcess {
                _logStreamPID = lp.processIdentifier
                signal(SIGINT, _cleanupLogStream)
                signal(SIGTERM, _cleanupLogStream)
            }
        }

        if debug {
            // LLDB interactive session
            if shouldLaunch {
                if !json && output.showStatusMessages { print("Launching \(schemeName) with debugger on \(device.name)...") }
                // Launch the app first, then attach LLDB
                let launchResult = ProcessRunner.exec(
                    "/usr/bin/xcrun",
                    arguments: ["simctl", "launch", "--wait-for-debugger", device.udid, bundleId]
                )
                if launchResult.exitCode != 0 {
                    logProcess?.terminate()
                    try failWith("Launch failed: \(launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                // Extract PID from launch output (format: "com.app.bundle: 12345")
                let pid = launchResult.output.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                runLLDB(pid: pid, waitForName: nil, appBinaryPath: appBinaryPath, hasLogProcess: logProcess != nil)
            } else {
                if !json && output.showStatusMessages {
                    print("Waiting for \(schemeName) to launch on \(device.name)...")
                    print("Launch the app manually in the Simulator, then LLDB will attach.")
                }
                runLLDB(pid: nil, waitForName: executableName ?? schemeName, appBinaryPath: appBinaryPath, hasLogProcess: logProcess != nil)
            }
            logProcess?.terminate()
        } else if shouldLaunch {
            // No debugger — just launch and stream logs
            if !json && output.showStatusMessages { print("Launching \(schemeName) on \(device.name)...") }
            let launchResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "launch", device.udid, bundleId])
            if launchResult.exitCode != 0 {
                logProcess?.terminate()
                try failWith("Launch failed: \(launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            if console, let logProc = logProcess {
                let appPid: Int32? = launchResult.output.split(separator: ":")
                    .last.flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                if !json && output.showStatusMessages { print("Streaming console (Ctrl+C or terminate app to stop)...\n") }
                waitForProcessExit(logProcess: logProc, appPid: appPid)
            }
        } else {
            // --wait --no-debug: just install and wait
            if !json && output.showStatusMessages { print("App installed. Launch it manually in the Simulator.") }
            if console, let logProc = logProcess {
                if !json && output.showStatusMessages { print("Streaming console (Ctrl+C to stop)...\n") }
                logProc.waitUntilExit()
            }
        }

        // Success — emit JSON if requested
        if json {
            jsonSet("success", true)
            jsonSet("launched", shouldLaunch)
            emitJSON()
        }
    }

    // MARK: - JSON helpers

    nonisolated(unsafe) private static var _jsonResult: [String: Any] = [:]

    private func jsonSet(_ key: String, _ value: Any) {
        Self._jsonResult[key] = value
    }

    private func emitJSON() {
        guard let data = try? JSONSerialization.data(withJSONObject: Self._jsonResult, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8) else { return }
        print(str)
        Self._jsonResult = [:]
    }

    private func failWith(_ message: String?) throws -> Never {
        if json {
            jsonSet("success", false)
            if let message { jsonSet("error", message) }
            emitJSON()
        } else if let message {
            print("Error: \(message)")
        }
        throw ExitCode.failure
    }

    // MARK: - Private

    private func extractSetting(_ key: String, from output: String) -> String? {
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) = ") {
                return String(trimmed.dropFirst(key.count + 3))
            }
        }
        return nil
    }

    private func startLogStream(deviceUDID: String, bundleId: String, filter: LogFilter) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let appName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        process.arguments = ["simctl", "spawn", deviceUDID, "log", "stream",
                             "--level", "debug",
                             "--predicate", "subsystem == '\(bundleId)' OR (processImagePath ENDSWITH '/\(appName)' AND senderImagePath ENDSWITH '/\(appName)' AND subsystem == '')",
                             "--style", "compact"]

        if filter.pattern != nil {
            // Pipe through filter — read lines and only forward matches to stderr
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                    if filter.matches(String(line)) {
                        FileHandle.standardError.write(Data((line + "\n").utf8))
                    }
                }
            }
        } else {
            // No filter — stream directly to stderr
            process.standardOutput = FileHandle.standardError
            process.standardError = FileHandle.standardError
        }

        try? process.run()
        return process
    }

    /// Wait for either the log process to exit or the app process to die.
    /// Simulator apps run as real macOS processes, so `kill(pid, 0)` works.
    private func waitForProcessExit(logProcess: Process, appPid: Int32?) {
        if let appPid {
            // Poll until the app process is gone, then stop log stream
            DispatchQueue.global().async {
                while kill(appPid, 0) == 0 {
                    Thread.sleep(forTimeInterval: 0.5)
                }
                logProcess.terminate()
            }
        }
        logProcess.waitUntilExit()
        if appPid != nil {
            print("\nApp terminated.")
        }
    }

    private func runLLDB(pid: String?, waitForName: String?, appBinaryPath: String?, hasLogProcess: Bool) {
        var args = ["/usr/bin/xcrun", "lldb"]

        if let appBinaryPath { args.append(appBinaryPath) }

        if let pid {
            args += ["--attach-pid", pid]
        } else if let waitForName {
            if appBinaryPath != nil {
                args += ["-o", "process attach --name \(waitForName) --waitfor"]
            } else {
                args += ["--wait-for", waitForName]
            }
        } else {
            return
        }

        if !hasLogProcess {
            // No log stream to manage — exec directly for full terminal control
            let cArgs = args.map { strdup($0) } + [nil]
            execvp(args[0], cArgs)
            // Only reached if exec fails
            perror("execvp")
            return
        }

        // Log stream is running — use posix_spawn with its own process group,
        // give it the terminal, wait, then clean up.
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        var childPid: pid_t = 0
        let rc = posix_spawnp(&childPid, args[0], nil, &attr, cArgs, environ)
        posix_spawnattr_destroy(&attr)
        cArgs.forEach { if let p = $0 { free(p) } }

        guard rc == 0 else { return }

        // Give terminal to LLDB so it can use its interactive line editor
        let originalGroup = tcgetpgrp(STDIN_FILENO)
        tcsetpgrp(STDIN_FILENO, childPid)

        var status: Int32 = 0
        waitpid(childPid, &status, 0)

        // Reclaim terminal
        tcsetpgrp(STDIN_FILENO, originalGroup)
    }
}
