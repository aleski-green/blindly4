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
            // Prefer process-targeted AX value writing. Some web views do not support
            // it, in which case emulate the assistive-technology focus/paste flow and
            // require a proof that this exact composer now contains the full draft.
            if (try? setAttribute(target, "AXValue", text as CFTypeRef)) != nil,
               hasExactVisibleText(in: target, expected: text, profile: context.profile) {
                verified = true
            }
            if !verified {
                guard let point = center(of: target, profile: context.profile) else {
                    throw CLIError.accessibility("Paste blocked: --target-path has no usable on-screen bounds")
                }
                try postMouseClick(x: point.x, y: point.y)
                _ = try requireInputTarget(pidText: invocation.optional("pid"))
                verified = try pasteText(text, profile: context.profile) {
                    hasExactVisibleText(in: target, expected: text, profile: context.profile)
                }
            }
            guard verified else {
                throw CLIError.accessibility("Paste blocked: the composer did not expose exactly the requested text; do not press Send")
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
