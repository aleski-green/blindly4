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

    static func command(named name: String) -> Command? {
        all.first { $0.name == name }
    }

    /// Parses and runs one argument list, such as `["press", "--path", "0.2"]`.
    static func run(_ arguments: [String], context: ExecutionContext) throws {
        guard let name = arguments.first, !isHelpFlag(name) else {
            context.writeStdout(usage() + "\n")
            return
        }
        guard let command = command(named: name) else {
            throw CLIError.usage("Unknown command: \(name)")
        }
        let commandArguments = Array(arguments.dropFirst())
        if commandArguments.contains(where: isHelpFlag) {
            context.writeStdout(commandHelp(command) + "\n")
            return
        }
        let invocation = try Invocation(
            command: name,
            arguments: commandArguments,
            allowedOptions: command.optionNames
        )
        if command.requiresAccessibility { try requireAccessibility() }
        try command.handler(invocation, context)
    }

    /// Executes a command without allowing an error to escape the process boundary.
    static func execute(_ rawArguments: [String], session: AccessibilitySession = AccessibilitySession()) -> ExecutionResponse {
        let profileEnabled = rawArguments.contains("--profile")
        let arguments = rawArguments.filter { $0 != "--profile" }
        let context = ExecutionContext(session: session, profileEnabled: profileEnabled)
        let status: Int32
        do {
            try run(arguments, context: context)
            status = 0
        } catch {
            status = report(error, showUsage: true, to: context)
        }
        if profileEnabled { context.writeStderr(context.profile.render()) }
        return context.response(status: status)
    }

    private static func isHelpFlag(_ token: String) -> Bool {
        ["--help", "-h", "help"].contains(token)
    }

    private static func commandHelp(_ command: Command) -> String {
        [
            command.usageLine,
            command.summary,
            "Risk: \(command.risk.rawValue)",
            "Requires Accessibility permission: \(command.requiresAccessibility ? "yes" : "no")"
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
