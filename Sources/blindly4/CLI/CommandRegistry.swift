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
        if requestsCommandHelp(commandArguments) {
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
    static func execute(
        _ rawArguments: [String],
        session: AccessibilitySession = AccessibilitySession(),
        logger: SessionLogger? = nil,
        workflowLeases: WorkflowLeaseCoordinator? = nil
    ) -> ExecutionResponse {
        let startedAt = Date()
        let profileEnabled = rawArguments.contains("--profile")
        let context = ExecutionContext(
            session: session,
            profileEnabled: profileEnabled,
            workflowLeases: workflowLeases
        )
        var loggingArguments = rawArguments
        var workflowMetadata: JSON?
        let status: Int32
        do {
            let leaseArguments = try WorkflowLeaseArguments(rawArguments)
            loggingArguments = leaseArguments.loggingArguments
            if let workflowLeases, leaseArguments.commandArguments.first != "lease" {
                switch workflowLeases.authorize(token: leaseArguments.token) {
                case .granted(let lease):
                    workflowMetadata = lease?.metadata()
                case .busy(let retryAfterMilliseconds):
                    throw CLIError.workflowBusy(retryAfterMilliseconds: retryAfterMilliseconds)
                case .invalidToken:
                    throw CLIError.workflowLeaseInvalid
                }
            } else if workflowLeases == nil, leaseArguments.token != nil {
                throw CLIError.usage("--lease requires the local Blindly service; remove --no-service")
            }
            let arguments = leaseArguments.commandArguments.filter { $0 != "--profile" && $0 != "--no-log" }
            try run(arguments, context: context)
            status = 0
        } catch {
            status = report(error, showUsage: true, to: context)
        }
        if profileEnabled { context.writeStderr(context.profile.render()) }
        let response = context.response(status: status)
        logger?.log(
            arguments: redactLeaseCommandToken(in: loggingArguments),
            response: redactLeaseResponse(response, command: loggingArguments.first),
            elapsedMilliseconds: Date().timeIntervalSince(startedAt) * 1_000,
            workflow: workflowMetadata
        )
        return response
    }

    private static func redactLeaseCommandToken(in arguments: [String]) -> [String] {
        guard arguments.first == "lease" else { return arguments }
        var redacted = arguments
        if let tokenIndex = redacted.firstIndex(of: "--token"), redacted.indices.contains(tokenIndex + 1) {
            redacted[tokenIndex + 1] = "<redacted>"
        }
        return redacted
    }

    private static func redactLeaseResponse(_ response: ExecutionResponse, command: String?) -> ExecutionResponse {
        guard command == "lease",
              let data = response.stdout.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? JSON else {
            return response
        }
        object.removeValue(forKey: "token")
        guard let redactedData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let stdout = String(data: redactedData, encoding: .utf8) else {
            return response
        }
        return ExecutionResponse(stdout: stdout + "\n", stderr: response.stderr, status: response.status)
    }

    /// `help` and `-h` are ordinary text that a caller may legitimately pass as an
    /// option value, so they only request help in the leading position. Treating them
    /// as help anywhere turns `type --text help` into a no-op that still exits 0, which
    /// reads as success to a calling agent. `--help` is unambiguous in any position
    /// because a value may never start with `--`.
    static func requestsCommandHelp(_ commandArguments: [String]) -> Bool {
        (commandArguments.first.map(isHelpFlag) ?? false) || commandArguments.contains("--help")
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
