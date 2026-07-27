let sessionCommands = CommandGroup(title: "Session", commands: [
    Command("shell", requiresAccessibility: false) { _ in
        runInteractiveShell()
    },

    Command("request-permission", requiresAccessibility: false) { _ in
        printJSON(requestAccessibilityPermission())
    }
])
