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
// Useful for diagnostics and service-parity checks; ordinary invocations use the
// local service automatically.
if arguments.first == "--no-service" {
    let response = CommandRegistry.execute(Array(arguments.dropFirst()))
    emit(response)
    exit(response.status)
}
if arguments.first == "serve" {
    guard let socketIndex = arguments.firstIndex(of: "--socket"), arguments.indices.contains(socketIndex + 1) else {
        exit(64)
    }
    exit(LocalServiceServer.run(socket: arguments[socketIndex + 1]))
}

// A terminal shell must retain its own stdin/stdout instead of being proxied.
if arguments.first == "shell" {
    runInteractiveShell()
    exit(0)
}

let response = LocalServiceClient.execute(arguments) ?? CommandRegistry.execute(arguments)
emit(response)
exit(response.status)
