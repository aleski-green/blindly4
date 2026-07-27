import ApplicationServices

let sessionCommands = CommandGroup(title: "Session", commands: [
    Command("shell", requiresAccessibility: false) { _, _ in
        runInteractiveShell()
    },

    Command("request-permission", requiresAccessibility: false) { _, context in
        printJSON(requestAccessibilityPermission(), to: context)
    },

    Command("snapshot", "--name NAME --path INDEX[.INDEX...] [--pid PID] [--depth N] [--max-nodes N]") { invocation, context in
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

    Command("changes", "--since NAME --path INDEX[.INDEX...] [--pid PID] [--depth N] [--max-nodes N]") { invocation, context in
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
        let added = signaturesAdded(current: current.map { observableSignature(of: $0.element, profile: context.profile) }, since: previous)
        let changes = current.filter { added.contains(observableSignature(of: $0.element, profile: context.profile)) }
        printJSON(["since": name, "changes": changes.map { detail(of: $0.element, path: $0.path, profile: context.profile) }], to: context)
    }
])
