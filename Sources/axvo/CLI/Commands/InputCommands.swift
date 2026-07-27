import CoreFoundation

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

    Command("paste", "--text TEXT [--pid PID] [--target-path PATH]") { invocation, context in
        let text = try invocation.value("text")
        let targetPath = invocation.optional("target-path")
        if targetPath != nil, invocation.optional("pid") == nil {
            throw CLIError.usage("paste --target-path requires --pid so Blindly can refuse cross-app input")
        }
        let pid = try requireInputTarget(pidText: invocation.optional("pid"))
        var verified = false
        if let targetPath {
            let target = try elementAtPath(targetPath, from: try invocation.application(), profile: context.profile)
            let role = textAttribute(target, "AXRole", profile: context.profile)
            guard ["AXTextArea", "AXTextField", "AXComboBox", "AXSecureTextField"].contains(role) else {
                let foundRole = role.isEmpty ? "an unnamed element" : role
                throw CLIError.usage("Paste blocked: --target-path must resolve to a writable AX text control, not \(foundRole)")
            }
            // Safe external-message mode never emits a global HID keyboard event.
            // macOS does not bind such events to a PID, so a focus race can otherwise
            // write into another app.  Unsupported web views therefore fail closed.
            if (try? setAttribute(target, "AXValue", text as CFTypeRef)) != nil,
               sameVisibleText(textAttribute(target, "AXValue", profile: context.profile), text) {
                verified = true
            }
            guard verified else {
                throw CLIError.accessibility("Paste blocked: the target did not expose exactly the requested text through AXValue; do not press Send")
            }
        } else {
            _ = try pasteText(text, profile: context.profile)
        }
        var result: JSON = ["characters": text.count, "ok": true]
        if let pid { result["pid"] = pid }
        if let targetPath { result["targetPath"] = targetPath; result["verified"] = verified }
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
