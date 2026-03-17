import Testing
import Foundation
@testable import XcodeCLICore

@Suite("ProjectFinder")
struct ProjectFinderTests {

    // MARK: - Explicit paths

    @Test func usesExplicitWorkspace() throws {
        let info = try ProjectFinder.discover(
            workspace: "MyApp.xcworkspace",
            project: nil,
            scheme: "MyApp"
        )
        #expect(info.workspace == "MyApp.xcworkspace")
        #expect(info.project == nil)
        #expect(info.scheme == "MyApp")
    }

    @Test func usesExplicitProject() throws {
        let info = try ProjectFinder.discover(
            workspace: nil,
            project: "MyApp.xcodeproj",
            scheme: "MyApp"
        )
        #expect(info.workspace == nil)
        #expect(info.project == "MyApp.xcodeproj")
        #expect(info.scheme == "MyApp")
    }

    // MARK: - Auto-discovery

    @Test func discoversXcodeproj() throws {
        let tmp = makeTmpDir()
        defer { cleanup(tmp) }

        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("Foo.xcodeproj"),
            withIntermediateDirectories: true
        )

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "Foo", in: tmp.path)
        #expect(info.project == "Foo.xcodeproj")
        #expect(info.scheme == "Foo")
    }

    @Test func prefersWorkspaceOverProject() throws {
        let tmp = makeTmpDir()
        defer { cleanup(tmp) }

        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("App.xcworkspace"),
            withIntermediateDirectories: true
        )

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "App", in: tmp.path)
        #expect(info.workspace == "App.xcworkspace")
        #expect(info.project == nil)
    }

    @Test func discoversPackageSwift() throws {
        let tmp = makeTmpDir()
        defer { cleanup(tmp) }

        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("Package.swift").path,
            contents: nil
        )

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "MyPkg", in: tmp.path)
        #expect(info.workspace == nil)
        #expect(info.project == nil)
        #expect(info.scheme == "MyPkg")
    }

    @Test func throwsWhenNothingFound() throws {
        let tmp = makeTmpDir()
        defer { cleanup(tmp) }

        #expect(throws: ProjectNotFoundError.self) {
            try ProjectFinder.discover(workspace: nil, project: nil, scheme: nil, in: tmp.path)
        }
    }

    @Test func skipsInternalXcworkspace() throws {
        let tmp = makeTmpDir()
        defer { cleanup(tmp) }

        let projDir = tmp.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: projDir.appendingPathComponent("project.xcworkspace"),
            withIntermediateDirectories: true
        )

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "App", in: tmp.path)
        #expect(info.project == "App.xcodeproj")
        #expect(info.workspace == nil)
    }

    // MARK: - Helpers

    private func makeTmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
