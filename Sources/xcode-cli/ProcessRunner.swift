import Foundation

struct ProcessResult: Sendable {
    let output: String
    let exitCode: Int32
}

enum ProcessRunner {
    static func exec(_ executable: String, arguments: [String]) -> ProcessResult {
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
