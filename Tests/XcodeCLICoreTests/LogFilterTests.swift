import Testing
@testable import XcodeCLICore

@Suite("LogFilter")
struct LogFilterTests {

    @Test func nilPatternMatchesEverything() {
        let filter = LogFilter(pattern: nil)
        #expect(filter.matches("anything"))
        #expect(filter.matches(""))
    }

    @Test func emptyPatternMatchesEverything() {
        let filter = LogFilter(pattern: "")
        #expect(filter.matches("some log line"))
        #expect(filter.matches(""))
    }

    @Test func matchesSubstring() {
        let filter = LogFilter(pattern: "Button")
        #expect(filter.matches("TestApp[123] [UI] Button tapped: count = 1"))
        #expect(!filter.matches("TestApp[123] [UI] ContentView appeared"))
    }

    @Test func caseInsensitive() {
        let filter = LogFilter(pattern: "button")
        #expect(filter.matches("Button tapped"))
        #expect(filter.matches("BUTTON PRESSED"))
        #expect(filter.matches("button clicked"))
    }

    @Test func noMatchReturnsFalse() {
        let filter = LogFilter(pattern: "network")
        #expect(!filter.matches("TestApp[123] [UI] Button tapped"))
        #expect(!filter.matches("ContentView appeared"))
    }

    @Test func matchesLogLevel() {
        let filter = LogFilter(pattern: "error")
        #expect(filter.matches("Error: connection refused"))
        #expect(filter.matches("2026-03-17 10:00:00 TestApp[123] Network error occurred"))
        #expect(!filter.matches("2026-03-17 10:00:00 TestApp[123] All good"))
    }

    @Test func matchesSubsystem() {
        let filter = LogFilter(pattern: "com.xcode-cli")
        #expect(filter.matches("[com.xcode-cli.TestApp:UI] Button tapped"))
        #expect(!filter.matches("[com.apple.UIKit:Layout] frame changed"))
    }
}
