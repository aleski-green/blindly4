import Foundation

enum CLIError: Error {
    case usage(String)
    case accessibility(String)
    case workflowBusy(retryAfterMilliseconds: Int)
    case workflowLeaseInvalid
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
    case CLIError.workflowBusy(let retryAfterMilliseconds):
        printJSON([
            "code": "workflow_busy",
            "error": "Another workflow currently owns the Blindly service",
            "retryAfterMilliseconds": retryAfterMilliseconds
        ], to: context)
        return 75
    case CLIError.workflowLeaseInvalid:
        printJSON([
            "code": "workflow_lease_invalid",
            "error": "The workflow lease token is invalid or has expired"
        ], to: context)
        return 75
    default:
        printJSON(["error": String(describing: error)], to: context)
        return 1
    }
}
