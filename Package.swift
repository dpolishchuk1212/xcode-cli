// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "xcode-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "XcodeCLICore"
        ),
        .executableTarget(
            name: "xcode-cli",
            dependencies: [
                "XcodeCLICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "XcodeCLICoreTests",
            dependencies: ["XcodeCLICore"]
        ),
    ]
)
