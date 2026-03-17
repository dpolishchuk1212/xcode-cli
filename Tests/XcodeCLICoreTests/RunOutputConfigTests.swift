import Testing
@testable import XcodeCLICore

@Suite("RunOutputConfig")
struct RunOutputConfigTests {

    // MARK: - Default (both on)

    @Test func defaultShowsEverything() {
        let config = RunOutputConfig(debug: true, console: true)
        #expect(config.showStatusMessages == true)
        #expect(config.streamConsoleLogs == true)
        #expect(config.attachDebugger == true)
    }

    // MARK: - Console only

    @Test func consoleOnlyShowsStatusAndLogs() {
        let config = RunOutputConfig(debug: false, console: true)
        #expect(config.showStatusMessages == true)
        #expect(config.streamConsoleLogs == true)
        #expect(config.attachDebugger == false)
    }

    // MARK: - Debug only

    @Test func debugOnlyShowsStatusAndDebugger() {
        let config = RunOutputConfig(debug: true, console: false)
        #expect(config.showStatusMessages == true)
        #expect(config.streamConsoleLogs == false)
        #expect(config.attachDebugger == true)
    }

    // MARK: - Fire and forget (both off)

    @Test func noDebugNoConsoleSilent() {
        let config = RunOutputConfig(debug: false, console: false)
        #expect(config.showStatusMessages == false)
        #expect(config.streamConsoleLogs == false)
        #expect(config.attachDebugger == false)
    }
}
