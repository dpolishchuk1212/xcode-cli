import ArgumentParser
import Foundation
import XcodeCLICore

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

    mutating func run() throws {
        // 1. Build (unless --skip-build)
        if !skipBuild {
            let info = try ProjectFinder.discover(workspace: workspace, project: project, scheme: scheme)
            var buildArgs = ["build"]
            if let ws = info.workspace { buildArgs += ["-workspace", ws] }
            else if let proj = info.project { buildArgs += ["-project", proj] }
            if let s = info.scheme { buildArgs += ["-scheme", s] }
            buildArgs += ["-configuration", configuration,
                          "-destination", "generic/platform=iOS Simulator"]

            let label = info.scheme
                ?? info.workspace?.replacingOccurrences(of: ".xcworkspace", with: "")
                ?? info.project?.replacingOccurrences(of: ".xcodeproj", with: "")
                ?? "project"
            print("Building \(label) (\(configuration))...")

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
            print(formatter.formatted)

            if result.exitCode != 0 { throw ExitCode.failure }
        }

        // 2. Resolve scheme (needed for bundle ID and app path)
        let info = try ProjectFinder.discover(workspace: workspace, project: project, scheme: scheme)
        guard let schemeName = info.scheme else {
            print("Error: Could not determine scheme. Use --scheme to specify.")
            throw ExitCode.failure
        }

        // 3. Find simulator
        let simListResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "-j"])
        let allDevices = SimulatorFinder.parseDevices(from: simListResult.output)
        guard let device = SimulatorFinder.findBest(from: allDevices, matching: simulator) else {
            print("Error: No suitable iOS Simulator found.\(simulator.map { " No match for '\($0)'." } ?? "")")
            throw ExitCode.failure
        }

        // 4. Boot simulator if needed
        if !device.isBooted {
            print("Booting \(device.name)...")
            let bootResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "boot", device.udid])
            if bootResult.exitCode != 0 {
                print("Error: Failed to boot simulator: \(bootResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                throw ExitCode.failure
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

        guard let bundleId else {
            print("Error: Could not determine bundle identifier from build settings.")
            throw ExitCode.failure
        }

        // 6. Install app
        if let buildDir, let productName {
            let appPath = "\(buildDir)/\(productName)"
            print("Installing \(productName) on \(device.name)...")
            let installResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "install", device.udid, appPath])
            if installResult.exitCode != 0 {
                print("Error: Install failed: \(installResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                throw ExitCode.failure
            }
        }

        // 7. Launch + attach
        let shouldLaunch = !wait

        // Start console log streaming in background
        var logProcess: Process?
        if console {
            logProcess = startLogStream(deviceUDID: device.udid, bundleId: bundleId)
        }

        if debug {
            // LLDB interactive session
            if shouldLaunch {
                print("Launching \(schemeName) with debugger on \(device.name)...")
                // Launch the app first, then attach LLDB
                let launchResult = ProcessRunner.exec(
                    "/usr/bin/xcrun",
                    arguments: ["simctl", "launch", "--wait-for-debugger", device.udid, bundleId]
                )
                if launchResult.exitCode != 0 {
                    logProcess?.terminate()
                    print("Error: Launch failed: \(launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                    throw ExitCode.failure
                }
                // Extract PID from launch output (format: "com.app.bundle: 12345")
                let pid = launchResult.output.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)
                runLLDB(bundleId: bundleId, deviceUDID: device.udid, pid: pid)
            } else {
                print("Waiting for \(schemeName) to launch on \(device.name)...")
                print("Launch the app manually in the Simulator, then LLDB will attach.")
                runLLDB(bundleId: bundleId, deviceUDID: device.udid, pid: nil)
            }
            logProcess?.terminate()
        } else if shouldLaunch {
            // No debugger — just launch and stream logs
            print("Launching \(schemeName) on \(device.name)...")
            let launchResult = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["simctl", "launch", device.udid, bundleId])
            if launchResult.exitCode != 0 {
                logProcess?.terminate()
                print("Error: Launch failed: \(launchResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
                throw ExitCode.failure
            }

            if console {
                print("Streaming console (Ctrl+C to stop)...\n")
                logProcess?.waitUntilExit()
            }
        } else {
            // --wait --no-debug: just install and wait
            print("App installed. Launch it manually in the Simulator.")
            if console {
                print("Streaming console (Ctrl+C to stop)...\n")
                logProcess?.waitUntilExit()
            }
        }
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

    private func startLogStream(deviceUDID: String, bundleId: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "spawn", deviceUDID, "log", "stream",
                             "--predicate", "subsystem == '\(bundleId)' OR processImagePath CONTAINS '\(bundleId.split(separator: ".").last ?? "")'",
                             "--style", "compact"]
        process.standardOutput = FileHandle.standardError  // logs go to stderr so they don't interfere with LLDB
        process.standardError = FileHandle.standardError
        try? process.run()
        return process
    }

    private func runLLDB(bundleId: String, deviceUDID: String, pid: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        if let pid {
            process.arguments = ["lldb", "--attach-pid", pid]
        } else {
            process.arguments = ["lldb", "--wait-for", bundleId]
        }

        // Hand off stdin/stdout to the user for interactive LLDB
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try? process.run()
        process.waitUntilExit()
    }
}
