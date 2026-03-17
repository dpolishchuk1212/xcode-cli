import Foundation

public struct BuildIssue: Sendable, Equatable {
    public enum Kind: String, Sendable { case error, warning }

    public let kind: Kind
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let message: String

    public init(kind: Kind, file: String?, line: Int?, column: Int?, message: String) {
        self.kind = kind
        self.file = file
        self.line = line
        self.column = column
        self.message = message
    }
}

extension BuildIssue: CustomStringConvertible {
    public var description: String {
        guard let file, let line, let column else { return message }
        return "\(relativePath(file)):\(line):\(column): \(message)"
    }

    private func relativePath(_ path: String) -> String {
        let cwd = FileManager.default.currentDirectoryPath + "/"
        return path.hasPrefix(cwd) ? String(path.dropFirst(cwd.count)) : path
    }
}

public enum BuildLogParser {
    public static func parse(_ output: String) -> [BuildIssue] {
        var issues: [BuildIssue] = []
        var seen = Set<String>()

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let issue = parseLine(String(line)) else { continue }
            let key = "\(issue.file ?? ""):\(issue.line ?? 0):\(issue.column ?? 0):\(issue.kind.rawValue):\(issue.message)"
            if seen.insert(key).inserted {
                issues.append(issue)
            }
        }

        return issues
    }

    // MARK: - Private

    private static func parseLine(_ line: String) -> BuildIssue? {
        // file:line:col: error|warning: message
        if let m = line.wholeMatch(of: /^(.+?):(\d+):(\d+): (error|warning): (.+)$/) {
            return BuildIssue(
                kind: m.4 == "error" ? .error : .warning,
                file: String(m.1),
                line: Int(m.2),
                column: Int(m.3),
                message: String(m.5)
            )
        }

        // xcodebuild: error: message
        if let m = line.wholeMatch(of: /^xcodebuild: error: (.+)$/) {
            return BuildIssue(kind: .error, file: nil, line: nil, column: nil, message: String(m.1))
        }

        // ld: error/warning (linker)
        if let m = line.wholeMatch(of: /^ld: (error|warning): (.+)$/) {
            return BuildIssue(
                kind: m.1 == "error" ? .error : .warning,
                file: nil, line: nil, column: nil,
                message: "linker: \(m.2)"
            )
        }

        // clang: error: message
        if let m = line.wholeMatch(of: /^clang: error: (.+)$/) {
            return BuildIssue(kind: .error, file: nil, line: nil, column: nil, message: "clang: \(m.1)")
        }

        return nil
    }
}
