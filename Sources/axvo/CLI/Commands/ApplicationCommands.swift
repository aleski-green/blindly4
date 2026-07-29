let applicationCommands = CommandGroup(title: "Applications", commands: [
    // Listing running applications comes from NSWorkspace, not the Accessibility API.
    Command("apps", summary: "List regular GUI applications and process IDs.", requiresAccessibility: false) { _, context in
        printJSON(["apps": runningApplications()], to: context)
    },

    Command("activate", "--pid PID", summary: "Bring a running application to the foreground.", risk: .uiMutation) { invocation, context in
        let pid = try invocation.value("pid")
        try activateApplication(pidText: pid)
        printJSON(["pid": pid, "ok": true], to: context)
    },

    Command("open", "--url URL", summary: "Open an HTTP, HTTPS, or Slack URL.", risk: .uiMutation) { invocation, context in
        let url = try invocation.value("url")
        try openURL(url)
        printJSON(["url": url, "ok": true], to: context)
    },

    Command("schema", summary: "Print machine-readable command and safety metadata.", requiresAccessibility: false) { _, context in
        printJSON([
            "schemaVersion": 1,
            "commands": CommandRegistry.all.map(\.metadata)
        ], to: context)
    }
])
