import Foundation

/// Every command the CLI understands. Adding a command means adding it to one group.
enum CommandRegistry {
    static let groups: [CommandGroup] = [
        applicationCommands,
        treeCommands,
        elementCommands,
        inputCommands,
        sessionCommands
    ]

    static let all: [Command] = groups.flatMap(\.commands)

    static let names: [String] = all.map(\.name).sorted()

    static let optionFlags: [String] = Array(Set(all.flatMap(\.optionNames))).sorted()

    static func command(named name: String) -> Command? {
        all.first { $0.name == name }
    }

    /// Parses and runs one argument list, such as `["press", "--path", "0.2"]`.
    static func run(_ arguments: [String]) throws {
        guard let name = arguments.first, !isHelpFlag(name) else {
            print(usage())
            return
        }
        guard let command = command(named: name) else {
            throw CLIError.usage("Unknown command: \(name)")
        }
        let invocation = try Invocation(command: name, arguments: Array(arguments.dropFirst()))
        if command.requiresAccessibility { try requireAccessibility() }
        try command.handler(invocation)
    }

    private static func isHelpFlag(_ token: String) -> Bool {
        ["--help", "-h", "help"].contains(token)
    }
}
