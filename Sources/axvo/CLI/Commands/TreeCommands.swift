import ApplicationServices

let treeCommands = CommandGroup(title: "Accessibility tree", commands: [
    Command("tree", "[--pid PID] [--depth N] [--max-nodes N]") { invocation in
        let depth = try invocation.integer("depth", default: 4, minimum: 0)
        var remaining = try invocation.integer("max-nodes", default: 250, minimum: 1)
        let root = try invocation.application()
        printJSON([
            "tree": tree(of: root, depth: depth, remaining: &remaining),
            "truncated": remaining == 0
        ])
    },

    Command("show", "[--pid PID] [--depth N]") { invocation in
        let depth = try invocation.integer("depth", default: 4, minimum: 0)
        for match in descendants(of: try invocation.application(), depth: depth) {
            print(outlineLine(path: match.path, element: match.element))
        }
    },

    Command("find", "--title TEXT [--role ROLE] [--value TEXT] [--pid PID] [--depth N] [--limit N]") { invocation in
        let title = invocation.optional("title")
        let role = invocation.optional("role")
        let value = invocation.optional("value")
        guard title != nil || role != nil || value != nil else {
            throw CLIError.usage("find requires at least one of --title, --role, or --value")
        }
        let depth = try invocation.integer("depth", default: 8, minimum: 0)
        let limit = try invocation.integer("limit", default: 25, minimum: 1)
        let found = descendants(of: try invocation.application(), depth: depth)
            .filter { matches($0.element, title: title, role: role, value: value) }
            .prefix(limit)
        printJSON(["matches": found.map { detail(of: $0.element, path: $0.path) }])
    },

    Command("focused") { _ in
        guard let focused = copyElementAttribute(AXUIElementCreateSystemWide(), "AXFocusedUIElement") else {
            throw CLIError.accessibility("No focused accessibility element is available")
        }
        printJSON(detail(of: focused))
    }
])
