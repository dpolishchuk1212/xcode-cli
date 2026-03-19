import ArgumentParser
import Foundation
import XcodeCLICore

struct DebugCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug",
        abstract: "Manage LLDB debug sessions for Simulator apps",
        discussion: """
        Runs LLDB in a tmux session for persistent debugging.
        You can also attach interactively: tmux attach -t xcode-debug
        """,
        subcommands: [DebugStartCommand.self, DebugExecCommand.self, DebugStopCommand.self, DebugStatusCommand.self]
    )
}

// MARK: - debug start

struct DebugStartCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Attach LLDB to a running process"
    )

    @Option(name: .long, help: "Process ID to attach to")
    var pid: Int32?

    @Option(name: .long, help: "App name to find via pgrep (e.g., 'TestApp')")
    var appName: String?

    func run() throws {
        // Check tmux is available
        let tmuxCheck = ProcessRunner.exec("/usr/bin/env", arguments: ["tmux", "-V"])
        guard tmuxCheck.exitCode == 0 else {
            throw ValidationError("tmux is required for debugging. Install with: brew install tmux")
        }

        // Resolve target PID
        let targetPid: Int32
        if let pid {
            targetPid = pid
        } else if let appName {
            let result = ProcessRunner.exec("/usr/bin/pgrep", arguments: ["-x", appName])
            guard let pid = result.output
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .compactMap({ Int32($0) })
                .max() else {
                throw ValidationError("No process found with name '\(appName)'")
            }
            targetPid = pid
        } else {
            throw ValidationError("Either --pid or --app-name is required")
        }

        // Verify process exists
        guard kill(targetPid, 0) == 0 else {
            throw ValidationError("Process \(targetPid) not found")
        }

        let info = try DebugSession.start(pid: targetPid)
        print("Debug session started (App PID: \(info.appPid))")
        print("Run commands:  xcode-cli debug exec \"bt\" \"frame variable\"")
        print("Interactive:   tmux attach -t \(info.sessionName)")
    }
}

// MARK: - debug exec

struct DebugExecCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Run LLDB commands in the active debug session"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Argument(help: "LLDB commands to execute")
    var commands: [String]

    func run() throws {
        let results = try DebugSession.exec(commands: commands)

        if json {
            let jsonResults = results.map { r -> [String: Any] in
                ["command": r.command, "output": r.output, "success": r.success]
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["results": jsonResults], options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            for r in results {
                print("(lldb) \(r.command)")
                if !r.output.isEmpty {
                    print(r.output, terminator: r.output.hasSuffix("\n") ? "" : "\n")
                }
            }
        }
    }
}

// MARK: - debug stop

struct DebugStopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Detach LLDB and stop the debug session"
    )

    func run() throws {
        guard DebugSession.loadSession() != nil else {
            print("No active debug session.")
            return
        }
        DebugSession.cleanup()
        print("Debug session stopped.")
    }
}

// MARK: - debug status

struct DebugStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the current debug session status"
    )

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    func run() throws {
        guard let session = DebugSession.loadSession() else {
            if json {
                print(#"{"active":false}"#)
            } else {
                print("No active debug session.")
            }
            return
        }

        let state: String
        do {
            state = try DebugSession.getProcessState()
        } catch {
            state = "unknown"
        }

        if json {
            let result: [String: Any] = [
                "active": true,
                "state": state,
                "appPid": Int(session.appPid),
                "tmuxSession": session.sessionName
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) {
                print(str)
            }
        } else {
            print("Debug session active")
            print("  App PID:      \(session.appPid)")
            print("  State:        \(state)")
            print("  tmux session: \(session.sessionName)")
            print("  Interactive:  tmux attach -t \(session.sessionName)")
        }
    }
}
