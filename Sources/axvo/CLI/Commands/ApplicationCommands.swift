let applicationCommands = CommandGroup(title: "Applications", commands: [
    // Listing running applications comes from NSWorkspace, not the Accessibility API.
    Command("apps", requiresAccessibility: false) { _, context in
        printJSON(["apps": runningApplications()], to: context)
    },

    Command("activate", "--pid PID") { invocation, context in
        let pid = try invocation.value("pid")
        try activateApplication(pidText: pid)
        printJSON(["pid": pid, "ok": true], to: context)
    },

    Command("open", "--url URL") { invocation, context in
        let url = try invocation.value("url")
        try openURL(url)
        printJSON(["url": url, "ok": true], to: context)
    }
])
