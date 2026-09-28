import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    if let failure = SelfTest.run() {
        FileHandle.standardError.write(Data("self-test failed: \(failure)\n".utf8))
        exit(1)
    }
    print("self-test passed")
    exit(0)
}
// Each invocation observes the live desktop and retains no state after exit.
let response = CommandRegistry.execute(arguments)
emit(response)
exit(response.status)
