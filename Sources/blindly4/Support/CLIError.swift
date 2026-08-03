import Foundation

enum CLIError: Error {
    case usage(String)
    case accessibility(String)
}

/// Renders a failure and returns the exit code the top level should use.
func report(_ error: Error, showUsage: Bool, to context: ExecutionContext) -> Int32 {
    switch error {
    case CLIError.usage(let message):
        context.writeStderr("Error: \(message)\n")
        if showUsage { context.writeStderr("\n\(usage())\n") }
        return 64
    case CLIError.accessibility(let message):
        printJSON(["error": message], to: context)
        return 77
    default:
        printJSON(["error": String(describing: error)], to: context)
        return 1
    }
}
