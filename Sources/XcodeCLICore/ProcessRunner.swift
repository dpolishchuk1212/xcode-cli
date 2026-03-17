import Foundation

public struct ProcessResult: Sendable {
    public let output: String
    public let exitCode: Int32

    public init(output: String, exitCode: Int32) {
        self.output = output
        self.exitCode = exitCode
    }
}

public enum ProcessRunner {
    public static func exec(_ executable: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return ProcessResult(output: "Failed to launch \(executable): \(error)", exitCode: 1)
        }

        // Read all data before waiting (avoids pipe-buffer deadlock)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return ProcessResult(output: output, exitCode: process.terminationStatus)
    }
}
