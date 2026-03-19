import Foundation

/// Filters console log lines by a search pattern.
public struct LogFilter: Sendable {
    public let pattern: String?

    public init(pattern: String?) {
        self.pattern = pattern
    }

    /// Returns true if the line should be shown.
    public func matches(_ line: String) -> Bool {
        guard let pattern, !pattern.isEmpty else { return true }
        return line.localizedCaseInsensitiveContains(pattern)
    }

    /// Build `log stream --predicate` for an app's bundle identifier.
    /// Matches the app's subsystem plus its own process output with no subsystem set.
    public static func logStreamPredicate(bundleId: String) -> String {
        let appName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        return "subsystem == '\(bundleId)' OR (processImagePath ENDSWITH '/\(appName)' AND senderImagePath ENDSWITH '/\(appName)' AND subsystem == '')"
    }
}
