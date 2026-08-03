import Foundation

enum CommandRisk: String, Sendable {
    case readOnly = "read-only"
    case localState = "local-state"
    case uiMutation = "ui-mutation"
    case externalCommit = "external-commit"
}

/// A single CLI verb. `arguments` is the usage fragment shown in help, so a new
/// command only has to be declared once, here, to be fully wired up.
struct Command: Sendable {
    let name: String
    let arguments: String
    let summary: String
    let risk: CommandRisk
    let requiresAccessibility: Bool
    let handler: @Sendable (Invocation, ExecutionContext) throws -> Void

    init(
        _ name: String,
        _ arguments: String = "",
        summary: String = "",
        risk: CommandRisk = .readOnly,
        requiresAccessibility: Bool = true,
        handler: @escaping @Sendable (Invocation, ExecutionContext) throws -> Void
    ) {
        self.name = name
        self.arguments = arguments
        self.summary = summary
        self.risk = risk
        self.requiresAccessibility = requiresAccessibility
        self.handler = handler
    }

    var optionNames: Set<String> {
        Set(arguments.split(whereSeparator: \.isWhitespace).compactMap { token in
            guard token.contains("--"), let range = token.range(of: "--") else { return nil }
            let suffix = token[range.upperBound...]
            let name = suffix.prefix { $0.isLetter || $0.isNumber || $0 == "-" }
            return name.isEmpty ? nil : String(name)
        })
    }

    var usageLine: String {
        arguments.isEmpty ? "blindly4 \(name)" : "blindly4 \(name) \(arguments)"
    }

    var metadata: JSON {
        [
            "name": name,
            "usage": usageLine,
            "summary": summary,
            "risk": risk.rawValue,
            "requiresAccessibility": requiresAccessibility,
            "options": optionNames.sorted()
        ]
    }
}

struct CommandGroup: Sendable {
    let title: String
    let commands: [Command]
}
