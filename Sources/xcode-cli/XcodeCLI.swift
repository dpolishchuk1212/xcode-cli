import ArgumentParser

@main
struct XcodeCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-cli",
        abstract: "Token-efficient Xcode CLI for coding agents",
        version: "0.1.2",
        subcommands: [BuildCommand.self, RunCommand.self]
    )
}
