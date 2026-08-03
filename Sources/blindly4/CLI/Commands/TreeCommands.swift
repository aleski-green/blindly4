import ApplicationServices

let treeCommands = CommandGroup(title: "Accessibility tree", commands: [
    Command("tree", "[--pid PID] [--depth N] [--max-nodes N]", summary: "Print a bounded accessibility tree as JSON.") { invocation, context in
        let depth = try invocation.integer("depth", default: 4, minimum: 0)
        var remaining = try invocation.integer("max-nodes", default: 250, minimum: 1)
        let root = try invocation.application()
        printJSON([
            "tree": tree(of: root, depth: depth, remaining: &remaining, profile: context.profile),
            "truncated": remaining == 0
        ], to: context)
    },

    Command("show", "[--pid PID] [--depth N]", summary: "Print a human-readable accessibility outline.") { invocation, context in
        let depth = try invocation.integer("depth", default: 4, minimum: 0)
        for match in descendants(of: try invocation.application(), depth: depth, profile: context.profile) {
            context.writeStdout(outlineLine(path: match.path, element: match.element, profile: context.profile) + "\n")
        }
    },

    Command("find", "[--title TEXT] [--role ROLE] [--value TEXT] [--description TEXT] [--pid PID] [--depth N] [--limit N]", summary: "Search the accessibility tree using stable attributes.") { invocation, context in
        let title = invocation.optional("title")
        let role = invocation.optional("role")
        let value = invocation.optional("value")
        let description = invocation.optional("description")
        guard title != nil || role != nil || value != nil || description != nil else {
            throw CLIError.usage("find requires at least one of --title, --role, --value, or --description")
        }
        let depth = try invocation.integer("depth", default: 8, minimum: 0)
        let limit = try invocation.integer("limit", default: 25, minimum: 1)
        let found = findCachedOrDescendants(
            root: try invocation.application(), invocation: invocation, title: title, role: role, value: value, description: description,
            depth: depth, limit: limit, context: context
        )
        printJSON(["matches": found.map { detail(of: $0.element, path: $0.path, profile: context.profile) }], to: context)
    },

    Command("focused", summary: "Inspect the system-wide focused accessibility element.") { _, context in
        guard let focused = copyElementAttribute(AXUIElementCreateSystemWide(), "AXFocusedUIElement", profile: context.profile) else {
            throw CLIError.accessibility("No focused accessibility element is available")
        }
        printJSON(detail(of: focused, profile: context.profile), to: context)
    }
])
