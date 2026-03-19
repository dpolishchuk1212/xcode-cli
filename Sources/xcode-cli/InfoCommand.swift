import ArgumentParser
import Foundation
import XcodeCLICore

struct InfoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Show discovered project information as JSON"
    )

    @Option(name: .long, help: "Path to .xcworkspace")
    var workspace: String?

    @Option(name: .long, help: "Path to .xcodeproj")
    var project: String?

    @Option(name: .shortAndLong, help: "Build scheme")
    var scheme: String?

    mutating func run() throws {
        let info = try ProjectFinder.discover(
            workspace: workspace,
            project: project,
            scheme: scheme
        )

        let label = info.scheme
            ?? info.workspace?.replacingOccurrences(of: ".xcworkspace", with: "")
            ?? info.project?.replacingOccurrences(of: ".xcodeproj", with: "")
            ?? "project"

        var dict: [String: Any] = ["label": label]
        if let ws = info.workspace { dict["workspace"] = ws }
        if let proj = info.project { dict["project"] = proj }
        if let s = info.scheme { dict["scheme"] = s }
        if let commit = GitInfo.commitHash() { dict["commit"] = commit }
        dict["uncommitted"] = GitInfo.uncommittedCount()

        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}
