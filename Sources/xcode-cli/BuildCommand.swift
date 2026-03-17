import ArgumentParser
import Foundation

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

    @Flag(name: .shortAndLong, help: "Show full xcodebuild output")
    var verbose: Bool = false

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

        print("Building \(label) (\(configuration))...")

        let start = Date()
        let result = ProcessRunner.exec(
            "/usr/bin/xcrun",
            arguments: ["xcodebuild"] + args
        )
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))

        if verbose {
            print(result.output)
        }

        let issues = BuildLogParser.parse(result.output)
        let errors = issues.filter { $0.kind == .error }
        let warnings = issues.filter { $0.kind == .warning }

        // Summary line
        if result.exitCode == 0 {
            let suffix = warnings.isEmpty ? "" : " (\(warnings.count) warning\(warnings.count == 1 ? "" : "s"))"
            print("✓ Build Succeeded\(suffix) [\(elapsed)]")
        } else {
            print("✗ Build Failed (\(errors.count) error\(errors.count == 1 ? "" : "s"), \(warnings.count) warning\(warnings.count == 1 ? "" : "s")) [\(elapsed)]")
        }

        if !errors.isEmpty {
            print("\nErrors:")
            for e in errors { print("  \(e)") }
        }

        if !warnings.isEmpty {
            print("\nWarnings:")
            for w in warnings { print("  \(w)") }
        }

        if result.exitCode != 0 {
            throw ExitCode.failure
        }
    }
}
