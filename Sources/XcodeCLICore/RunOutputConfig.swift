/// Determines what output the `run` command should produce based on flags.
public struct RunOutputConfig: Sendable, Equatable {
    public let showStatusMessages: Bool
    public let streamConsoleLogs: Bool
    public let attachDebugger: Bool

    public init(debug: Bool, console: Bool) {
        self.attachDebugger = debug
        self.streamConsoleLogs = console
        // Show status messages ("Installing...", "Launching...") only when
        // there's an interactive session (debug or console). When both are off,
        // the user wants fire-and-forget silence.
        self.showStatusMessages = debug || console
    }
}
