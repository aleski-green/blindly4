import Darwin
import Foundation

private struct ServiceRequest: Codable {
    let arguments: [String]
}

private func socketPath() -> String {
    "\(NSTemporaryDirectory())blindly4-\(getuid()).sock"
}

private func withUnixAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T? {
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
        bytes.withUnsafeBytes { source in destination.copyBytes(from: source) }
    }
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

private func readAll(_ descriptor: Int32) -> Data? {
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 8_192)
    let capacity = buffer.count
    while true {
        let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, capacity) }
        if count == 0 { return result }
        guard count > 0 else { return nil }
        result.append(buffer, count: Int(count))
    }
}

private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
    data.withUnsafeBytes { rawBuffer in
        guard var current = rawBuffer.baseAddress else { return false }
        var remaining = rawBuffer.count
        while remaining > 0 {
            let count = Darwin.write(descriptor, current, remaining)
            guard count > 0 else { return false }
            current = current.advanced(by: count)
            remaining -= count
        }
        return true
    }
}

enum LocalServiceClient {
    static func execute(_ arguments: [String]) -> ExecutionResponse? {
        let path = socketPath()
        if let response = exchange(arguments, socket: path) { return response }
        guard start(socket: path) else { return nil }
        for _ in 0..<30 {
            if let response = exchange(arguments, socket: path) { return response }
            usleep(50_000)
        }
        return nil
    }

    private static func exchange(_ arguments: [String], socket path: String) -> ExecutionResponse? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard let connected: Int32 = withUnixAddress(path, { address, length in
            Darwin.connect(descriptor, address, length)
        }), connected == 0 else { return nil }
        guard let data = try? JSONEncoder().encode(ServiceRequest(arguments: arguments)),
              writeAll(data, to: descriptor) else { return nil }
        _ = shutdown(descriptor, SHUT_WR)
        guard let responseData = readAll(descriptor) else { return nil }
        return try? JSONDecoder().decode(ExecutionResponse.self, from: responseData)
    }

    private static func start(socket path: String) -> Bool {
        guard let executable = executableURL() else { return false }
        // `exchange` has already failed, so this can only be a stale endpoint from
        // an interrupted service. The path is fixed to this user's temp directory.
        if FileManager.default.fileExists(atPath: path) { _ = unlink(path) }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve", "--socket", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func executableURL() -> URL? {
        let invokedAs = CommandLine.arguments[0]
        if invokedAs.contains("/") { return URL(fileURLWithPath: invokedAs).standardizedFileURL }
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(invokedAs)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}

enum LocalServiceServer {
    static func run(socket path: String) -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return 1 }
        defer { close(descriptor) }
        guard let bound: Int32 = withUnixAddress(path, { address, length in
            Darwin.bind(descriptor, address, length)
        }), bound == 0 else { return 0 }
        _ = chmod(path, S_IRUSR | S_IWUSR)
        guard listen(descriptor, 8) == 0 else { unlink(path); return 1 }
        defer { unlink(path) }

        let session = AccessibilitySession()
        let workflowLock = WorkflowLock()
        let logger = SessionLogger()
        defer { logger.finish(reason: "idle_timeout") }
        var lastActivity = Date()
        while workflowLock.isHeld || Date().timeIntervalSince(lastActivity) < 60 {
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&pollDescriptor, 1, 1_000) > 0 else { continue }
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { continue }
            defer { close(client) }
            guard let requestData = readAll(client),
                  let request = try? JSONDecoder().decode(ServiceRequest.self, from: requestData) else {
                continue
            }
            lastActivity = Date()
            let response = CommandRegistry.execute(
                request.arguments,
                session: session,
                logger: logger,
                workflowLock: workflowLock
            )
            guard let responseData = try? JSONEncoder().encode(response) else { continue }
            _ = writeAll(responseData, to: client)
        }
        return 0
    }
}
