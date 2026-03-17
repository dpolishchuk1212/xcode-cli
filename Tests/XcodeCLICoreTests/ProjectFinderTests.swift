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
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Create a fake .xcodeproj directory
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("Foo.xcodeproj"),
            withIntermediateDirectories: true
        )

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "Foo")
        #expect(info.project == "Foo.xcodeproj")
        #expect(info.scheme == "Foo")
    }

    @Test func prefersWorkspaceOverProject() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("App.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("App.xcworkspace"),
            withIntermediateDirectories: true
        )

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "App")
        #expect(info.workspace == "App.xcworkspace")
        #expect(info.project == nil)
    }

    @Test func discoversPackageSwift() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        FileManager.default.createFile(
            atPath: tmp.appendingPathComponent("Package.swift").path,
            contents: nil
        )

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "MyPkg")
        #expect(info.workspace == nil)
        #expect(info.project == nil)
        #expect(info.scheme == "MyPkg")
    }

    @Test func throwsWhenNothingFound() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        #expect(throws: ProjectNotFoundError.self) {
            try ProjectFinder.discover(workspace: nil, project: nil, scheme: nil)
        }
    }

    @Test func skipsInternalXcworkspace() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcode-cli-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Internal workspace inside .xcodeproj — should be skipped
        let projDir = tmp.appendingPathComponent("App.xcodeproj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: projDir.appendingPathComponent("project.xcworkspace"),
            withIntermediateDirectories: true
        )

        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(tmp.path)
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }

        let info = try ProjectFinder.discover(workspace: nil, project: nil, scheme: "App")
        // Should find the .xcodeproj, NOT the internal .xcworkspace
        #expect(info.project == "App.xcodeproj")
        #expect(info.workspace == nil)
    }
}
