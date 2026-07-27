let applicationCommands = CommandGroup(title: "Applications", commands: [
    // Listing running applications comes from NSWorkspace, not the Accessibility API.
    Command("apps", requiresAccessibility: false) { _ in
        printJSON(["apps": runningApplications()])
    },

    Command("activate", "--pid PID") { invocation in
        let pid = try invocation.value("pid")
        try activateApplication(pidText: pid)
        printJSON(["pid": pid, "ok": true])
    },

    Command("open", "--url URL") { invocation in
        let url = try invocation.value("url")
        try openURL(url)
        printJSON(["url": url, "ok": true])
    }
])
