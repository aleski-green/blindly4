let inputCommands = CommandGroup(title: "Desktop input", commands: [
    Command("click", "--x X --y Y") { invocation in
        let x = try invocation.number("x")
        let y = try invocation.number("y")
        try postMouseClick(x: x, y: y)
        printJSON(["x": x, "y": y, "ok": true])
    },

    Command("type", "--text TEXT") { invocation in
        let text = try invocation.value("text")
        try postText(text)
        printJSON(["characters": text.count, "ok": true])
    },

    Command("paste", "--text TEXT") { invocation in
        let text = try invocation.value("text")
        try pasteText(text)
        printJSON(["characters": text.count, "ok": true])
    },

    Command("key", "--key return|tab|escape|space|delete|up|down|left|right|command+k") { invocation in
        let key = try invocation.value("key")
        try postKey(key)
        printJSON(["key": key, "ok": true])
    }
])
