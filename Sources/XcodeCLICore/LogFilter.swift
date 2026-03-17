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
}
