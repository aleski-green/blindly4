import Foundation

/// A per-service, in-memory lease that gives one caller exclusive ownership of the
/// desktop workflow. The local service is single-threaded, so this needs no locking
/// of its own; every check and state change happens on the service loop.
final class WorkflowLeaseCoordinator {
    struct Lease {
        let id: String
        let owner: String
        let token: String
        let expiresAt: Date

        func metadata() -> JSON {
            ["workflowId": id, "workflowOwner": owner]
        }
    }

    enum Authorization: Error {
        case granted(Lease?)
        case busy(retryAfterMilliseconds: Int)
        case invalidToken
    }

    private var activeLease: Lease?

    func acquire(owner: String, ttlSeconds: Int, now: Date = Date()) -> Result<Lease, Authorization> {
        expireIfNeeded(now: now)
        guard activeLease == nil else {
            return .failure(.busy(retryAfterMilliseconds: retryAfterMilliseconds(now: now)))
        }
        let lease = Lease(
            id: "wf_\(UUID().uuidString.lowercased())",
            owner: owner,
            token: "wl_\(UUID().uuidString.lowercased())",
            expiresAt: now.addingTimeInterval(TimeInterval(ttlSeconds))
        )
        activeLease = lease
        return .success(lease)
    }

    func renew(token: String, ttlSeconds: Int, now: Date = Date()) -> Result<Lease, Authorization> {
        switch authorize(token: token, now: now) {
        case .granted(let active?):
            let renewed = Lease(
                id: active.id,
                owner: active.owner,
                token: active.token,
                expiresAt: now.addingTimeInterval(TimeInterval(ttlSeconds))
            )
            activeLease = renewed
            return .success(renewed)
        case .granted(nil), .invalidToken:
            return .failure(.invalidToken)
        case .busy(let retryAfterMilliseconds):
            return .failure(.busy(retryAfterMilliseconds: retryAfterMilliseconds))
        }
    }

    func release(token: String, now: Date = Date()) -> Authorization {
        switch authorize(token: token, now: now) {
        case .granted(let active?):
            activeLease = nil
            return .granted(active)
        case .granted(nil), .invalidToken:
            return .invalidToken
        case .busy(let retryAfterMilliseconds):
            return .busy(retryAfterMilliseconds: retryAfterMilliseconds)
        }
    }

    /// A missing token is permitted only when no workflow owns the service. Once a
    /// lease exists, every regular command—including reads—must present its token.
    func authorize(token: String?, now: Date = Date()) -> Authorization {
        expireIfNeeded(now: now)
        guard let active = activeLease else {
            return token == nil ? .granted(nil) : .invalidToken
        }
        guard token == active.token else {
            return .busy(retryAfterMilliseconds: retryAfterMilliseconds(now: now))
        }
        return .granted(active)
    }

    func status(now: Date = Date()) -> Lease? {
        expireIfNeeded(now: now)
        return activeLease
    }

    var hasActiveLease: Bool {
        status() != nil
    }

    private func expireIfNeeded(now: Date) {
        if let activeLease, activeLease.expiresAt <= now {
            self.activeLease = nil
        }
    }

    private func retryAfterMilliseconds(now: Date) -> Int {
        guard let activeLease else { return 0 }
        return max(0, Int((activeLease.expiresAt.timeIntervalSince(now) * 1_000).rounded(.up)))
    }
}

struct WorkflowLeaseArguments {
    let commandArguments: [String]
    let token: String?
    let loggingArguments: [String]

    init(_ arguments: [String]) throws {
        var commandArguments: [String] = []
        var loggingArguments: [String] = []
        var token: String?
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument == "--lease" else {
                commandArguments.append(argument)
                loggingArguments.append(argument)
                index += 1
                continue
            }
            guard token == nil else {
                throw CLIError.usage("--lease may be passed only once")
            }
            guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
                throw CLIError.usage("--lease requires a token")
            }
            token = arguments[index + 1]
            loggingArguments.append("--lease")
            loggingArguments.append("<redacted>")
            index += 2
        }
        self.commandArguments = commandArguments
        self.token = token
        self.loggingArguments = loggingArguments
    }
}
