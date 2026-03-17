import Testing
@testable import XcodeCLICore

@Suite("BuildLogParser")
struct BuildLogParserTests {

    // MARK: - Swift compiler issues

    @Test func parsesSwiftError() {
        let output = "/path/to/File.swift:15:10: error: use of unresolved identifier 'foo'"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .error)
        #expect(issues[0].file == "/path/to/File.swift")
        #expect(issues[0].line == 15)
        #expect(issues[0].column == 10)
        #expect(issues[0].message == "use of unresolved identifier 'foo'")
    }

    @Test func parsesSwiftWarning() {
        let output = "/path/to/File.swift:3:10: warning: consider using a struct"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .warning)
        #expect(issues[0].file == "/path/to/File.swift")
        #expect(issues[0].line == 3)
        #expect(issues[0].column == 10)
        #expect(issues[0].message == "consider using a struct")
    }

    @Test func parsesMultipleIssues() {
        let output = """
        /src/A.swift:1:5: error: type mismatch
        /src/B.swift:10:3: warning: unused variable
        /src/C.swift:20:8: error: missing return
        """
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 3)
        #expect(issues.filter { $0.kind == .error }.count == 2)
        #expect(issues.filter { $0.kind == .warning }.count == 1)
    }

    // MARK: - xcodebuild errors

    @Test func parsesXcodebuildError() {
        let output = "xcodebuild: error: The directory does not contain an Xcode project."
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .error)
        #expect(issues[0].file == nil)
        #expect(issues[0].message == "The directory does not contain an Xcode project.")
    }

    // MARK: - Linker issues

    @Test func parsesLinkerError() {
        let output = "ld: error: framework not found SomeFramework"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .error)
        #expect(issues[0].message == "linker: framework not found SomeFramework")
    }

    @Test func parsesLinkerWarning() {
        let output = "ld: warning: directory not found for option '-L/some/path'"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .warning)
        #expect(issues[0].message == "linker: directory not found for option '-L/some/path'")
    }

    // MARK: - Clang errors

    @Test func parsesClangError() {
        let output = "clang: error: no such file or directory: 'missing.c'"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .error)
        #expect(issues[0].message == "clang: no such file or directory: 'missing.c'")
    }

    // MARK: - Deduplication

    @Test func deduplicatesIdenticalIssues() {
        let line = "/src/File.swift:5:3: error: something went wrong"
        let output = "\(line)\n\(line)\n\(line)"
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
    }

    @Test func keepsDifferentIssuesOnSameLine() {
        let output = """
        /src/File.swift:5:3: error: first error
        /src/File.swift:5:3: warning: also a warning here
        """
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 2)
    }

    // MARK: - Edge cases

    @Test func returnsEmptyForCleanBuild() {
        let output = """
        CompileSwift normal arm64 /src/File.swift
        Linking MyApp
        ** BUILD SUCCEEDED **
        """
        let issues = BuildLogParser.parse(output)

        #expect(issues.isEmpty)
    }

    @Test func returnsEmptyForEmptyOutput() {
        #expect(BuildLogParser.parse("").isEmpty)
    }

    @Test func ignoresNonIssueLinesInNoisyOutput() {
        let output = """
        note: Using new build system
        CompileSwift normal arm64 /src/A.swift (in target 'MyApp')
        /src/A.swift:10:5: error: cannot find 'x' in scope
            x.doSomething()
            ^
        ** BUILD FAILED **
        """
        let issues = BuildLogParser.parse(output)

        #expect(issues.count == 1)
        #expect(issues[0].kind == .error)
        #expect(issues[0].message == "cannot find 'x' in scope")
    }
}
