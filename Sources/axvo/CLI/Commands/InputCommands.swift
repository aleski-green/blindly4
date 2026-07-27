let inputCommands = CommandGroup(title: "Desktop input", commands: [
    Command("click", "--x X --y Y [--pid PID]") { invocation, context in
        let x = try invocation.number("x")
        let y = try invocation.number("y")
        let pid = try requireInputTarget(pidText: invocation.optional("pid"))
        try postMouseClick(x: x, y: y)
        var result: JSON = ["x": x, "y": y, "ok": true]
        if let pid { result["pid"] = pid }
        printJSON(result, to: context)
    },

    Command("type", "--text TEXT [--pid PID]") { invocation, context in
        let text = try invocation.value("text")
        let pid = try requireInputTarget(pidText: invocation.optional("pid"))
        try postText(text)
        var result: JSON = ["characters": text.count, "ok": true]
        if let pid { result["pid"] = pid }
        printJSON(result, to: context)
    },

    Command("paste", "--text TEXT [--pid PID]") { invocation, context in
        let text = try invocation.value("text")
        let pid = try requireInputTarget(pidText: invocation.optional("pid"))
        try pasteText(text, profile: context.profile)
        var result: JSON = ["characters": text.count, "ok": true]
        if let pid { result["pid"] = pid }
        printJSON(result, to: context)
    },

    Command("key", "--key return|tab|escape|space|delete|up|down|left|right|command+k [--pid PID]") { invocation, context in
        let key = try invocation.value("key")
        let pid = try requireInputTarget(pidText: invocation.optional("pid"))
        try postKey(key)
        var result: JSON = ["key": key, "ok": true]
        if let pid { result["pid"] = pid }
        printJSON(result, to: context)
    }
])
