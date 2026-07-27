import Foundation

/// A single CLI verb. `arguments` is the usage fragment shown in help and is also the
/// source of the option names offered by shell tab completion, so a new command only
/// has to be declared once, here, to be fully wired up.
struct Command: Sendable {
    let name: String
    let arguments: String
    let requiresAccessibility: Bool
    let handler: @Sendable (Invocation, ExecutionContext) throws -> Void

    init(
        _ name: String,
        _ arguments: String = "",
        requiresAccessibility: Bool = true,
        handler: @escaping @Sendable (Invocation, ExecutionContext) throws -> Void
    ) {
        self.name = name
        self.arguments = arguments
        self.requiresAccessibility = requiresAccessibility
        self.handler = handler
    }

    var usageLine: String {
        arguments.isEmpty ? "blindy \(name)" : "blindy \(name) \(arguments)"
    }

    var optionNames: [String] {
        arguments
            .split(whereSeparator: { " []|".contains($0) })
            .map(String.init)
            .filter { $0.hasPrefix("--") }
    }
}

struct CommandGroup: Sendable {
    let title: String
    let commands: [Command]
}
