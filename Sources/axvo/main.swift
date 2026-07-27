import Foundation

do {
    try CommandRegistry.run(Array(CommandLine.arguments.dropFirst()))
} catch {
    exit(report(error, showUsage: true))
}
