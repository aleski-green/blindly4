import Foundation

/// A short-lived, in-memory lock for one multi-command desktop workflow.
/// Access is serialized by the local service's single-threaded accept loop.
final class WorkflowLock {
    enum Authorization {
        case allowed
        case busy
        case invalid
    }

    private var lease: (token: String, expiresAt: Date)?

    func acquire(now: Date = Date()) -> String? {
        expire(now: now)
        guard lease == nil else { return nil }
        let token = "wf_\(UUID().uuidString.lowercased())"
        lease = (token, now.addingTimeInterval(300))
        return token
    }

    func release(token: String, now: Date = Date()) -> Authorization {
        let authorization = authorize(token: token, now: now)
        guard case .allowed = authorization else { return authorization }
        lease = nil
        return .allowed
    }

    func authorize(token: String?, now: Date = Date()) -> Authorization {
        expire(now: now)
        guard let lease else { return token == nil ? .allowed : .invalid }
        guard lease.token == token else { return .busy }
        self.lease = (lease.token, now.addingTimeInterval(300))
        return .allowed
    }

    var isHeld: Bool {
        expire(now: Date())
        return lease != nil
    }

    private func expire(now: Date) {
        if let lease, lease.expiresAt <= now { self.lease = nil }
    }
}

func workflowArguments(_ arguments: [String]) throws -> (command: [String], token: String?) {
    guard let index = arguments.firstIndex(of: "--lease") else { return (arguments, nil) }
    guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
        throw CLIError.usage("--lease requires a token")
    }
    guard !arguments.dropFirst(index + 2).contains("--lease") else {
        throw CLIError.usage("--lease may be passed only once")
    }
    var command = arguments
    let token = command.remove(at: index + 1)
    command.remove(at: index)
    return (command, token)
}
