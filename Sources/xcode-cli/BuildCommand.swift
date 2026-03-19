import ArgumentParser
import Foundation
import XcodeCLICore

extension OutputFilter: ExpressibleByArgument {}

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build an Xcode project or workspace"
    )

    @Option(name: .long, help: "Path to .xcworkspace")
    var workspace: String?

    @Option(name: .long, help: "Path to .xcodeproj")
    var project: String?

    @Option(name: .shortAndLong, help: "Build scheme")
    var scheme: String?

    @Option(name: .shortAndLong, help: "Build configuration (Debug/Release)")
    var configuration: String = "Debug"

    @Option(name: .shortAndLong, help: "Build destination (e.g. 'platform=iOS Simulator,name=iPhone 16')")
    var destination: String?

    @Option(name: .shortAndLong, help: "Filter output: all (full log), issues (errors+warnings), errors (errors only)")
    var filter: OutputFilter = .errors

    @Flag(name: .long, help: "Output results as JSON (for tool integrations)")
    var json: Bool = false

    mutating func run() throws {
        let info = try ProjectFinder.discover(
            workspace: workspace,
            project: project,
            scheme: scheme
        )

        var args = ["build"]

        if let ws = info.workspace {
            args += ["-workspace", ws]
        } else if let proj = info.project {
            args += ["-project", proj]
        }

        if let s = info.scheme {
            args += ["-scheme", s]
        }

        args += ["-configuration", configuration]

        if let dest = destination {
            args += ["-destination", dest]
        } else if info.workspace == nil && info.project == nil {
            // SPM packages require an explicit destination
            args += ["-destination", "platform=macOS"]
        }

        let label = info.scheme
            ?? info.workspace?.replacingOccurrences(of: ".xcworkspace", with: "")
            ?? info.project?.replacingOccurrences(of: ".xcodeproj", with: "")
            ?? "project"

        if !json {
            print("Building \(label) (\(configuration))...")
        }

        let start = Date()
        let result = ProcessRunner.exec(
            "/usr/bin/xcrun",
            arguments: ["xcodebuild"] + args
        )
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))

        let formatter = BuildResultFormatter(
            issues: BuildLogParser.parse(result.output),
            exitCode: result.exitCode,
            elapsed: elapsed,
            filter: filter,
            rawOutput: result.output
        )

        if json {
            let dict: [String: Any] = [
                "success": result.exitCode == 0,
                "elapsed": elapsed,
                "errorCount": formatter.errors.count,
                "warningCount": formatter.warnings.count,
                "output": formatter.formatted,
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print(formatter.formatted)
        }

        if result.exitCode != 0 {
            throw ExitCode.failure
        }
    }
}
