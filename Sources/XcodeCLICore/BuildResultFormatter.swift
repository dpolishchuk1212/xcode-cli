public enum OutputFilter: String, Sendable, CaseIterable {
    case all       // full xcodebuild output + parsed issues
    case issues    // errors + warnings
    case errors    // errors only
}

public struct BuildResultFormatter: Sendable {
    public let issues: [BuildIssue]
    public let exitCode: Int32
    public let elapsed: String
    public let filter: OutputFilter
    public let rawOutput: String

    public init(
        issues: [BuildIssue],
        exitCode: Int32,
        elapsed: String,
        filter: OutputFilter,
        rawOutput: String = ""
    ) {
        self.issues = issues
        self.exitCode = exitCode
        self.elapsed = elapsed
        self.filter = filter
        self.rawOutput = rawOutput
    }

    public var errors: [BuildIssue] { issues.filter { $0.kind == .error } }
    public var warnings: [BuildIssue] { issues.filter { $0.kind == .warning } }
    public var succeeded: Bool { exitCode == 0 }

    public var summaryLine: String {
        let errs = errors
        let warns = warnings
        if succeeded {
            let suffix = warns.isEmpty
                ? ""
                : " (\(warns.count) warning\(warns.count == 1 ? "" : "s"))"
            return "✓ Build Succeeded\(suffix) [\(elapsed)]"
        } else {
            return "✗ Build Failed (\(errs.count) error\(errs.count == 1 ? "" : "s"), \(warns.count) warning\(warns.count == 1 ? "" : "s")) [\(elapsed)]"
        }
    }

    public var formatted: String {
        var parts: [String] = []

        if filter == .all && !rawOutput.isEmpty {
            parts.append(rawOutput)
        }

        parts.append(summaryLine)

        let errs = errors
        if !errs.isEmpty {
            parts.append("\nErrors:\n" + errs.map { "  \($0)" }.joined(separator: "\n"))
        }

        let warns = warnings
        if filter != .errors && !warns.isEmpty {
            parts.append("\nWarnings:\n" + warns.map { "  \($0)" }.joined(separator: "\n"))
        }

        return parts.joined(separator: "\n")
    }
}
