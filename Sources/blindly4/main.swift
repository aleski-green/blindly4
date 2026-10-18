import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
// Each invocation observes the live desktop and retains no state after exit.
let response = CommandRegistry.execute(arguments)
emit(response)
exit(response.status)
