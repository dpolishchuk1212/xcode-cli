import Foundation

public enum GitInfo {
    public static func commitHash() -> String? {
        let result = ProcessRunner.exec("/usr/bin/git", arguments: ["rev-parse", "--short", "HEAD"])
        guard result.exitCode == 0 else { return nil }
        let hash = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    public static func uncommittedCount() -> Int {
        let result = ProcessRunner.exec("/usr/bin/git", arguments: ["status", "--porcelain"])
        guard result.exitCode == 0 else { return 0 }
        return result.output
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}
