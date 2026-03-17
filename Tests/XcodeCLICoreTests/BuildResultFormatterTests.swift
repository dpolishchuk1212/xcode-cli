import Testing
@testable import XcodeCLICore

@Suite("BuildResultFormatter")
struct BuildResultFormatterTests {

    // MARK: - Test data

    static let sampleErrors: [BuildIssue] = [
        BuildIssue(kind: .error, file: "/src/A.swift", line: 10, column: 5, message: "type mismatch"),
        BuildIssue(kind: .error, file: "/src/B.swift", line: 20, column: 3, message: "undefined symbol"),
    ]

    static let sampleWarnings: [BuildIssue] = [
        BuildIssue(kind: .warning, file: "/src/C.swift", line: 5, column: 8, message: "unused variable"),
        BuildIssue(kind: .warning, file: "/src/D.swift", line: 1, column: 10, message: "deprecated API"),
    ]

    static let mixedIssues: [BuildIssue] = sampleErrors + sampleWarnings

    // MARK: - Summary line: success

    @Test func successNoWarnings() {
        let f = BuildResultFormatter(issues: [], exitCode: 0, elapsed: "1.2s", filter: .errors)
        #expect(f.summaryLine == "✓ Build Succeeded [1.2s]")
    }

    @Test func successWithOneWarning() {
        let f = BuildResultFormatter(
            issues: [BuildIssue(kind: .warning, file: nil, line: nil, column: nil, message: "w")],
            exitCode: 0, elapsed: "2.0s", filter: .errors
        )
        #expect(f.summaryLine == "✓ Build Succeeded (1 warning) [2.0s]")
    }

    @Test func successWithMultipleWarnings() {
        let f = BuildResultFormatter(issues: Self.sampleWarnings, exitCode: 0, elapsed: "3.5s", filter: .errors)
        #expect(f.summaryLine == "✓ Build Succeeded (2 warnings) [3.5s]")
    }

    // MARK: - Summary line: failure

    @Test func failureOneErrorNoWarnings() {
        let f = BuildResultFormatter(
            issues: [Self.sampleErrors[0]],
            exitCode: 65, elapsed: "1.0s", filter: .errors
        )
        #expect(f.summaryLine == "✗ Build Failed (1 error, 0 warnings) [1.0s]")
    }

    @Test func failureMultipleErrorsAndWarnings() {
        let f = BuildResultFormatter(issues: Self.mixedIssues, exitCode: 65, elapsed: "4.2s", filter: .errors)
        #expect(f.summaryLine == "✗ Build Failed (2 errors, 2 warnings) [4.2s]")
    }

    @Test func failureOneErrorOneWarning() {
        let issues = [Self.sampleErrors[0], Self.sampleWarnings[0]]
        let f = BuildResultFormatter(issues: issues, exitCode: 65, elapsed: "1.5s", filter: .errors)
        #expect(f.summaryLine == "✗ Build Failed (1 error, 1 warning) [1.5s]")
    }

    // MARK: - Filter: errors (default)

    @Test func errorsFilterShowsOnlyErrors() {
        let f = BuildResultFormatter(issues: Self.mixedIssues, exitCode: 65, elapsed: "2.0s", filter: .errors)
        let output = f.formatted

        #expect(output.contains("Errors:"))
        #expect(output.contains("type mismatch"))
        #expect(output.contains("undefined symbol"))
        #expect(!output.contains("Warnings:"))
        #expect(!output.contains("unused variable"))
        #expect(!output.contains("deprecated API"))
    }

    @Test func errorsFilterStillCountsWarningsInSummary() {
        let f = BuildResultFormatter(issues: Self.mixedIssues, exitCode: 65, elapsed: "2.0s", filter: .errors)
        #expect(f.summaryLine.contains("2 warnings"))
    }

    @Test func errorsFilterSuccessStillMentionsWarnings() {
        let f = BuildResultFormatter(issues: Self.sampleWarnings, exitCode: 0, elapsed: "1.0s", filter: .errors)
        #expect(f.summaryLine.contains("2 warnings"))
        #expect(!f.formatted.contains("Warnings:"))
    }

    // MARK: - Filter: issues

    @Test func issuesFilterShowsErrorsAndWarnings() {
        let f = BuildResultFormatter(issues: Self.mixedIssues, exitCode: 65, elapsed: "2.0s", filter: .issues)
        let output = f.formatted

        #expect(output.contains("Errors:"))
        #expect(output.contains("type mismatch"))
        #expect(output.contains("Warnings:"))
        #expect(output.contains("unused variable"))
        #expect(output.contains("deprecated API"))
    }

    @Test func issuesFilterNoRawOutput() {
        let f = BuildResultFormatter(
            issues: Self.mixedIssues, exitCode: 65, elapsed: "2.0s",
            filter: .issues, rawOutput: "FULL BUILD LOG HERE"
        )
        #expect(!f.formatted.contains("FULL BUILD LOG HERE"))
    }

    // MARK: - Filter: all

    @Test func allFilterIncludesRawOutput() {
        let f = BuildResultFormatter(
            issues: Self.mixedIssues, exitCode: 65, elapsed: "2.0s",
            filter: .all, rawOutput: "CompileSwift normal arm64\n** BUILD FAILED **"
        )
        let output = f.formatted

        #expect(output.contains("CompileSwift normal arm64"))
        #expect(output.contains("** BUILD FAILED **"))
        #expect(output.contains("Errors:"))
        #expect(output.contains("Warnings:"))
    }

    @Test func allFilterShowsWarnings() {
        let f = BuildResultFormatter(
            issues: Self.sampleWarnings, exitCode: 0, elapsed: "1.0s",
            filter: .all, rawOutput: "raw"
        )
        #expect(f.formatted.contains("Warnings:"))
    }

    @Test func allFilterEmptyRawOutputOmitted() {
        let f = BuildResultFormatter(issues: [], exitCode: 0, elapsed: "1.0s", filter: .all, rawOutput: "")
        #expect(!f.formatted.hasPrefix("\n"))
    }

    // MARK: - Edge cases

    @Test func noIssuesCleanSuccess() {
        let f = BuildResultFormatter(issues: [], exitCode: 0, elapsed: "0.5s", filter: .issues)
        #expect(f.formatted == "✓ Build Succeeded [0.5s]")
    }

    @Test func noIssuesButBuildFailed() {
        let f = BuildResultFormatter(issues: [], exitCode: 1, elapsed: "0.3s", filter: .errors)
        #expect(f.formatted == "✗ Build Failed (0 errors, 0 warnings) [0.3s]")
    }

    @Test func succeededProperty() {
        #expect(BuildResultFormatter(issues: [], exitCode: 0, elapsed: "1s", filter: .errors).succeeded)
        #expect(!BuildResultFormatter(issues: [], exitCode: 1, elapsed: "1s", filter: .errors).succeeded)
        #expect(!BuildResultFormatter(issues: [], exitCode: 65, elapsed: "1s", filter: .errors).succeeded)
    }

    @Test func errorsAndWarningsProperties() {
        let f = BuildResultFormatter(issues: Self.mixedIssues, exitCode: 65, elapsed: "1s", filter: .errors)
        #expect(f.errors.count == 2)
        #expect(f.warnings.count == 2)
        #expect(f.errors.allSatisfy { $0.kind == .error })
        #expect(f.warnings.allSatisfy { $0.kind == .warning })
    }
}
