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
    let logger = SessionLogger()
    let response = CommandRegistry.execute(Array(arguments.dropFirst()), logger: logger)
    logger.finish(reason: "process_exit")
    emit(response)
    exit(response.status)
}
if arguments.first == "serve" {
    guard let socketIndex = arguments.firstIndex(of: "--socket"), arguments.indices.contains(socketIndex + 1) else {
        exit(64)
    }
    exit(LocalServiceServer.run(socket: arguments[socketIndex + 1]))
}

let response: ExecutionResponse
if let serviceResponse = LocalServiceClient.execute(arguments) {
    response = serviceResponse
} else {
    let logger = SessionLogger()
    response = CommandRegistry.execute(arguments, logger: logger)
    logger.finish(reason: "process_exit")
}
emit(response)
exit(response.status)
