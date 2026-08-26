import ApplicationServices

let sessionCommands = CommandGroup(title: "Session", commands: [
    Command("workflow", "<acquire|release>", summary: "Acquire or release the five-minute service workflow lock.", risk: .localState, requiresAccessibility: false) { invocation, context in
        guard let lock = context.workflowLock, invocation.positionals.count == 1 else {
            throw CLIError.usage("workflow requires the local service and one action: acquire or release")
        }
        switch invocation.positionals[0] {
        case "acquire":
            guard let token = lock.acquire() else { throw CLIError.workflowBusy }
            printJSON(["token": token], to: context)
        case "release":
            guard let token = context.workflowToken else { throw CLIError.workflowLeaseInvalid }
            switch lock.release(token: token) {
            case .allowed:
                printJSON(["released": true], to: context)
            case .busy:
                throw CLIError.workflowBusy
            case .invalid:
                throw CLIError.workflowLeaseInvalid
            }
        default:
            throw CLIError.usage("workflow action must be acquire or release")
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
