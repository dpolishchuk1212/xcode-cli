import Foundation

public struct ProjectInfo: Sendable {
    public let workspace: String?
    public let project: String?
    public let scheme: String?

    public init(workspace: String?, project: String?, scheme: String?) {
        self.workspace = workspace
        self.project = project
        self.scheme = scheme
    }
}

public struct ProjectNotFoundError: Error, CustomStringConvertible {
    public let directory: String
    public var description: String {
        "No .xcworkspace, .xcodeproj, or Package.swift found in \(directory)"
    }
}

public enum ProjectFinder {
    public static func discover(workspace: String?, project: String?, scheme: String?) throws -> ProjectInfo {
        // Explicit paths — use as-is
        if workspace != nil || project != nil {
            let resolved = scheme ?? resolveScheme(workspace: workspace, project: project)
            return ProjectInfo(workspace: workspace, project: project, scheme: resolved)
        }

        let cwd = FileManager.default.currentDirectoryPath
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: cwd)) ?? []

        // Prefer .xcworkspace (skip internal ones inside .xcodeproj)
        if let ws = contents.first(where: {
            $0.hasSuffix(".xcworkspace") && !$0.contains(".xcodeproj")
        }) {
            let resolved = scheme ?? resolveScheme(workspace: ws, project: nil)
            return ProjectInfo(workspace: ws, project: nil, scheme: resolved)
        }

        // Fall back to .xcodeproj
        if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
            let resolved = scheme ?? resolveScheme(workspace: nil, project: proj)
            return ProjectInfo(workspace: nil, project: proj, scheme: resolved)
        }

        // SPM project — xcodebuild can handle Package.swift
        if contents.contains("Package.swift") {
            let resolved = scheme ?? resolveScheme(workspace: nil, project: nil)
            return ProjectInfo(workspace: nil, project: nil, scheme: resolved)
        }

        throw ProjectNotFoundError(directory: cwd)
    }

    // MARK: - Private

    private static func resolveScheme(workspace: String?, project: String?) -> String? {
        var args = ["-list", "-json"]
        if let ws = workspace { args += ["-workspace", ws] }
        else if let proj = project { args += ["-project", proj] }

        let result = ProcessRunner.exec("/usr/bin/xcrun", arguments: ["xcodebuild"] + args)
        guard result.exitCode == 0 else { return nil }

        // Extract JSON from output (xcodebuild may print warnings before JSON)
        let output = result.output
        guard let jsonStart = output.firstIndex(of: "{"),
              let jsonEnd = output.lastIndex(of: "}") else { return nil }
        let jsonString = String(output[jsonStart...jsonEnd])

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let schemes: [String]? =
            (json["workspace"] as? [String: Any])?["schemes"] as? [String]
            ?? (json["project"] as? [String: Any])?["schemes"] as? [String]

        guard let schemes, !schemes.isEmpty else { return nil }

        // Prefer scheme matching workspace/project name
        let baseName = (workspace ?? project)?
            .replacingOccurrences(of: ".xcworkspace", with: "")
            .replacingOccurrences(of: ".xcodeproj", with: "")

        if let base = baseName, schemes.contains(base) {
            return base
        }

        return schemes.first
    }
}
