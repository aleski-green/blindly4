import ApplicationServices

let sessionCommands = CommandGroup(title: "Session", commands: [
    Command("lease", "<acquire|renew|release|status> [--owner OWNER] [--token TOKEN] [--ttl SECONDS]", summary: "Coordinate an exclusive, service-wide workflow lease.", risk: .localState, requiresAccessibility: false) { invocation, context in
        guard let leases = context.workflowLeases else {
            throw CLIError.usage("lease requires the local Blindly service; remove --no-service")
        }
        guard invocation.positionals.count == 1 else {
            throw CLIError.usage("lease requires one action: acquire, renew, release, or status")
        }
        switch invocation.positionals[0] {
        case "acquire":
            let owner = try invocation.value("owner")
            guard !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("--owner must not be empty")
            }
            let ttl = try invocation.integer("ttl", default: 60, minimum: 1)
            guard ttl <= 3_600 else { throw CLIError.usage("--ttl must be <= 3600") }
            switch leases.acquire(owner: owner, ttlSeconds: ttl) {
            case .success(let lease):
                printJSON([
                    "expiresInSeconds": ttl,
                    "owner": lease.owner,
                    "token": lease.token,
                    "workflowId": lease.id
                ], to: context)
            case .failure(.busy(let retryAfterMilliseconds)):
                throw CLIError.workflowBusy(retryAfterMilliseconds: retryAfterMilliseconds)
            case .failure(.granted), .failure(.invalidToken):
                throw CLIError.workflowLeaseInvalid
            }
        case "renew":
            let token = try invocation.value("token")
            let ttl = try invocation.integer("ttl", default: 60, minimum: 1)
            guard ttl <= 3_600 else { throw CLIError.usage("--ttl must be <= 3600") }
            switch leases.renew(token: token, ttlSeconds: ttl) {
            case .success(let lease):
                printJSON([
                    "expiresInSeconds": ttl,
                    "owner": lease.owner,
                    "workflowId": lease.id
                ], to: context)
            case .failure(.busy(let retryAfterMilliseconds)):
                throw CLIError.workflowBusy(retryAfterMilliseconds: retryAfterMilliseconds)
            case .failure(.granted), .failure(.invalidToken):
                throw CLIError.workflowLeaseInvalid
            }
        case "release":
            let token = try invocation.value("token")
            switch leases.release(token: token) {
            case .granted(let lease?):
                printJSON(["owner": lease.owner, "released": true, "workflowId": lease.id], to: context)
            case .busy(let retryAfterMilliseconds):
                throw CLIError.workflowBusy(retryAfterMilliseconds: retryAfterMilliseconds)
            case .granted(nil), .invalidToken:
                throw CLIError.workflowLeaseInvalid
            }
        case "status":
            if let lease = leases.status() {
                let seconds = max(0, Int(lease.expiresAt.timeIntervalSinceNow.rounded(.up)))
                printJSON([
                    "expiresInSeconds": seconds,
                    "held": true,
                    "owner": lease.owner,
                    "workflowId": lease.id
                ], to: context)
            } else {
                printJSON(["held": false], to: context)
            }
        default:
            throw CLIError.usage("Unknown lease action: \(invocation.positionals[0])")
        }
    },

    Command("request-permission", summary: "Request macOS Accessibility permission.", risk: .uiMutation, requiresAccessibility: false) { _, context in
        printJSON(requestAccessibilityPermission(), to: context)
    },

    Command("snapshot", "--name NAME --path INDEX[.INDEX...] [--pid PID] [--depth N] [--max-nodes N]", summary: "Store an in-memory snapshot of an AX subtree.", risk: .localState) { invocation, context in
        let name = try invocation.value("name")
        let path = try invocation.value("path")
        let depth = try invocation.integer("depth", default: 8, minimum: 0)
        let limit = try invocation.integer("max-nodes", default: 500, minimum: 1)
        let app = try invocation.application()
        let root = try elementAtPath(path, from: app, profile: context.profile)
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        let signatures = Set(findDescendants(of: root, depth: depth, limit: limit, profile: context.profile) { _ in true }
            .map { observableSignature(of: $0.element, profile: context.profile) })
        context.session.storeSnapshot(signatures, name: name, pid: Int(pid), path: path)
        printJSON(["name": name, "path": path, "elements": signatures.count, "ok": true], to: context)
    },

    Command("changes", "--since NAME --path INDEX[.INDEX...] [--pid PID] [--depth N] [--max-nodes N]", summary: "Report elements added since an in-memory snapshot.") { invocation, context in
        let name = try invocation.value("since")
        let path = try invocation.value("path")
        let depth = try invocation.integer("depth", default: 8, minimum: 0)
        let limit = try invocation.integer("max-nodes", default: 500, minimum: 1)
        let app = try invocation.application()
        var pid: pid_t = 0
        AXUIElementGetPid(app, &pid)
        guard let previous = context.session.snapshot(name: name, pid: Int(pid), path: path) else {
            throw CLIError.usage("No in-memory snapshot named \(name) for this app and path")
        }
        let root = try elementAtPath(path, from: app, profile: context.profile)
        let current = findDescendants(of: root, depth: depth, limit: limit, profile: context.profile) { _ in true }
        let added = Set(current.map { observableSignature(of: $0.element, profile: context.profile) }).subtracting(previous)
        let changes = current.filter { added.contains(observableSignature(of: $0.element, profile: context.profile)) }
        printJSON(["since": name, "changes": changes.map { detail(of: $0.element, path: $0.path, profile: context.profile) }], to: context)
    }
])
