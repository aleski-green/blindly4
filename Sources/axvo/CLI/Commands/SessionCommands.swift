let sessionCommands = CommandGroup(title: "Session", commands: [
    Command("shell", requiresAccessibility: false) { _, _ in
        runInteractiveShell()
    },

    Command("request-permission", requiresAccessibility: false) { _, context in
        printJSON(requestAccessibilityPermission(), to: context)
    }
])
