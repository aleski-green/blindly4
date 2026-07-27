import Foundation

enum CLIError: Error {
    case usage(String)
    case accessibility(String)
}

/// Renders a failure and returns the exit code the top level should use. The
/// interactive shell reports the same text but keeps running, so it ignores the code.
@discardableResult
func report(_ error: Error, showUsage: Bool) -> Int32 {
    switch error {
    case CLIError.usage(let message):
        fputs("Error: \(message)\n", stderr)
        if showUsage { fputs("\n\(usage())\n", stderr) }
        return 64
    case CLIError.accessibility(let message):
        printJSON(["error": message])
        return 77
    default:
        printJSON(["error": String(describing: error)])
        return 1
    }
}
