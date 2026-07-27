import AppKit
import ApplicationServices
import Darwin
import Foundation

typealias JSON = [String: Any]

enum CLIError: Error {
    case usage(String)
    case accessibility(String)
}

func printJSON(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"error\":\"could not encode JSON\"}\n", stderr)
        return
    }
    print(text)
}

func usage() -> String {
    """
    blindy — macOS Accessibility tree CLI

    Usage:
      blindy apps
      blindy shell
      blindy activate --pid PID
      blindy open --url URL
      blindy tree [--pid PID] [--depth N] [--max-nodes N]
      blindy show [--pid PID] [--depth N]
      blindy find --title TEXT [--role ROLE] [--pid PID] [--depth N]
      blindy focused
      blindy inspect --path INDEX[.INDEX...] [--pid PID]
      blindy actions --path INDEX[.INDEX...] [--pid PID]
      blindy focus --path INDEX[.INDEX...] [--pid PID]
      blindy press --path INDEX[.INDEX...] [--pid PID]
      blindy set-value --path INDEX[.INDEX...] --value TEXT [--pid PID]
      blindy set-selected-text --path INDEX[.INDEX...] --value TEXT [--pid PID]
      blindy click --x X --y Y
      blindy type --text TEXT
      blindy paste --text TEXT
      blindy key --key return|tab|escape|space|delete|up|down|left|right|command+k
      blindy request-permission

    The default target is the frontmost application. Paths index AXChildren, starting at 0.
    Use `show` to see readable paths, `find` to locate an element by name, and `press`
    to activate a button or tab. `activate`, `click`, `type`, and `key` directly
    control the desktop UI, including app composers that expose no writable AX field.

    Run `blindy shell` for an interactive prompt. Type `help` or `exit` there.
    """
}

func shellTokens(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false
    for character in line {
        if escaping {
            current.append(character)
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if let activeQuote = quote {
            if character == activeQuote { quote = nil }
            else { current.append(character) }
        } else if character == "\"" || character == "'" {
            quote = character
        } else if character.isWhitespace {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}

final class TerminalEditor {
    private var history: [String] = []
    private var historyIndex: Int?

    private let commands = ["actions", "apps", "exit", "find", "focus", "focused", "help", "inspect", "press", "quit", "request-permission", "set-value", "shell", "show", "tree"]
    private let options = ["--depth", "--limit", "--max-nodes", "--path", "--pid", "--role", "--title", "--value"]

    private func write(_ text: String) {
        FileHandle.standardOutput.write(text.data(using: .utf8)!)
    }

    private func render(prompt: String, buffer: [Character], cursor: Int) {
        write("\r\(prompt)\(String(buffer))\u{001B}[K")
        let charactersAfterCursor = buffer.count - cursor
        if charactersAfterCursor > 0 { write("\u{001B}[\(charactersAfterCursor)D") }
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = withUnsafeMutableBytes(of: &byte) {
            Darwin.read(STDIN_FILENO, $0.baseAddress, 1)
        }
        return count == 1 ? byte : nil
    }

    private func completionCandidates(buffer: [Character], cursor: Int) -> (start: Int, choices: [String], addSpace: Bool) {
        var start = cursor
        while start > 0 && !buffer[start - 1].isWhitespace { start -= 1 }
        let partial = String(buffer[start..<cursor])
        let isFirstToken = !buffer[..<start].contains { $0.isWhitespace }
        let source = isFirstToken ? commands : options
        // Every command option currently expects a value, so a trailing space is useful
        // after completing either a command or an option.
        return (start, source.filter { $0.hasPrefix(partial) }, true)
    }

    func readLine(prompt: String) -> String? {
        // Piped input remains useful for scripts and automated tests.
        guard isatty(STDIN_FILENO) != 0 else { return Swift.readLine() }

        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return Swift.readLine() }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { return Swift.readLine() }
        defer { tcsetattr(STDIN_FILENO, TCSAFLUSH, &original) }

        var buffer: [Character] = []
        var cursor = 0
        historyIndex = nil
        write(prompt)

        while let byte = readByte() {
            switch byte {
            case 3: // Ctrl-C
                write("^C\r\n")
                return ""
            case 4: // Ctrl-D
                if buffer.isEmpty { write("\r\n"); return nil }
            case 10, 13:
                let result = String(buffer)
                write("\r\n")
                if !result.isEmpty, history.last != result { history.append(result) }
                return result
            case 8, 127: // Backspace
                if cursor > 0 { buffer.remove(at: cursor - 1); cursor -= 1; render(prompt: prompt, buffer: buffer, cursor: cursor) }
            case 9: // Tab
                let completion = completionCandidates(buffer: buffer, cursor: cursor)
                if completion.choices.count == 1, let choice = completion.choices.first {
                    let replacement = Array(choice + (completion.addSpace ? " " : ""))
                    buffer.replaceSubrange(completion.start..<cursor, with: replacement)
                    cursor = completion.start + replacement.count
                    render(prompt: prompt, buffer: buffer, cursor: cursor)
                } else if !completion.choices.isEmpty {
                    write("\r\n\(completion.choices.joined(separator: "  "))\r\n")
                    render(prompt: prompt, buffer: buffer, cursor: cursor)
                }
            case 27: // Escape sequences for arrow keys
                guard readByte() == 91, let direction = readByte() else { continue }
                switch direction {
                case 65: // Up
                    if historyIndex == nil, !history.isEmpty { historyIndex = history.count - 1 }
                    else if let index = historyIndex, index > 0 { historyIndex = index - 1 }
                    if let index = historyIndex { buffer = Array(history[index]); cursor = buffer.count; render(prompt: prompt, buffer: buffer, cursor: cursor) }
                case 66: // Down
                    if let index = historyIndex, index < history.count - 1 {
                        historyIndex = index + 1
                        buffer = Array(history[index + 1])
                    } else {
                        historyIndex = nil
                        buffer = []
                    }
                    cursor = buffer.count
                    render(prompt: prompt, buffer: buffer, cursor: cursor)
                case 67: // Right
                    if cursor < buffer.count { cursor += 1; render(prompt: prompt, buffer: buffer, cursor: cursor) }
                case 68: // Left
                    if cursor > 0 { cursor -= 1; render(prompt: prompt, buffer: buffer, cursor: cursor) }
                default: continue
                }
            case 32...126:
                buffer.insert(Character(UnicodeScalar(byte)), at: cursor)
                cursor += 1
                render(prompt: prompt, buffer: buffer, cursor: cursor)
            default:
                continue
            }
        }
        return nil
    }
}

func interactiveShell() {
    let editor = TerminalEditor()
    print("blindy interactive shell — type `help` for commands, `exit` to close.")
    while true {
        guard let line = editor.readLine(prompt: "blindy> ") else { return }
        let tokens = shellTokens(line)
        guard let command = tokens.first else { continue }
        if command == "exit" || command == "quit" { return }
        if command == "help" { print(usage()); continue }
        if command == "shell" { print("Already in the blindy shell."); continue }

        let process = Process()
        process.executableURL = currentExecutableURL()
        process.arguments = tokens
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            printJSON(["error": "Could not run \(command): \(error.localizedDescription)"])
        }
    }
}

func currentExecutableURL() -> URL {
    let invokedAs = CommandLine.arguments[0]
    if invokedAs.contains("/") { return URL(fileURLWithPath: invokedAs).standardizedFileURL }

    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for directory in path.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(invokedAs)
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    // This fallback retains the original error message if the executable has disappeared.
    return URL(fileURLWithPath: invokedAs)
}

func activateApplication(pidText: String) throws {
    guard let pid = pid_t(pidText), let app = NSRunningApplication(processIdentifier: pid) else {
        throw CLIError.usage("--pid must identify a running application")
    }
    app.unhide()
    guard app.activate(options: [.activateIgnoringOtherApps]) else {
        throw CLIError.accessibility("Could not activate process \(pid)")
    }
}

func openURL(_ urlText: String) throws {
    guard let url = URL(string: urlText), let scheme = url.scheme, ["https", "http", "slack"].contains(scheme.lowercased()) else {
        throw CLIError.usage("open requires an http, https, or slack URL")
    }
    guard NSWorkspace.shared.open(url) else { throw CLIError.accessibility("Could not open \(urlText)") }
}

func postMouseClick(x: Double, y: Double) throws {
    let point = CGPoint(x: x, y: y)
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        throw CLIError.accessibility("Could not create mouse events")
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func postText(_ text: String) throws {
    let characters = Array(text.utf16)
    guard !characters.isEmpty else { return }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
        throw CLIError.accessibility("Could not create keyboard events")
    }
    characters.withUnsafeBufferPointer { buffer in
        down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
        up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func pasteText(_ text: String) throws {
    let pasteboard = NSPasteboard.general
    let previousText = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
        throw CLIError.accessibility("Could not place text on the macOS pasteboard")
    }
    try postKey("command+v")
    // Give the focused application time to consume the paste, then restore the text
    // clipboard so Blindly does not leave the user's copied text replaced.
    usleep(1_000_000)
    if let previousText {
        pasteboard.clearContents()
        pasteboard.setString(previousText, forType: .string)
    }
}

func postKey(_ keyName: String) throws {
    let keys: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "delete": 51,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
        "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
        "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
        "v": 9, "w": 13, "x": 7, "y": 16, "z": 6
    ]
    let parts = keyName.lowercased().split(separator: "+").map(String.init)
    guard let key = parts.last, let keyCode = keys[key] else {
        throw CLIError.usage("Unsupported --key \(keyName). Use return, tab, arrows, letters, or modifiers such as command+k.")
    }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        switch modifier {
        case "command", "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "option", "alt": flags.insert(.maskAlternate)
        case "control", "ctrl": flags.insert(.maskControl)
        default: throw CLIError.usage("Unsupported modifier \(modifier) in --key \(keyName)")
        }
    }
    guard let source = CGEventSource(stateID: .hidSystemState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw CLIError.accessibility("Could not create keyboard events")
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func parsedOptions(_ args: [String]) throws -> (positionals: [String], options: [String: String]) {
    var positionals: [String] = []
    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
        let token = args[index]
        if token.hasPrefix("--") {
            guard index + 1 < args.count, !args[index + 1].hasPrefix("--") else {
                throw CLIError.usage("Missing value for \(token)")
            }
            options[String(token.dropFirst(2))] = args[index + 1]
            index += 2
        } else {
            positionals.append(token)
            index += 1
        }
    }
    return (positionals, options)
}

func copyAttribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func copyElementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func attributes(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let array = names as? [String] else { return [] }
    return array
}

func actions(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let array = names as? [String] else { return [] }
    return array
}

func textValue(_ value: Any) -> Any {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number }
    if let url = value as? URL { return url.absoluteString }
    let cfValue = value as CFTypeRef
    if CFGetTypeID(cfValue) == AXValueGetTypeID() {
        let range = unsafeDowncast(cfValue, to: AXValue.self)
        var point = CGPoint.zero
        if AXValueGetValue(range, .cgPoint, &point) { return ["x": point.x, "y": point.y] }
        var size = CGSize.zero
        if AXValueGetValue(range, .cgSize, &size) { return ["width": size.width, "height": size.height] }
        var rect = CGRect.zero
        if AXValueGetValue(range, .cgRect, &rect) {
            return ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
        }
    }
    return String(describing: value)
}

func summary(of element: AXUIElement, includeAttributes: Bool = false) -> JSON {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    var result: JSON = ["pid": Int(pid)]
    for name in ["AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue", "AXIdentifier", "AXEnabled", "AXFocused", "AXPosition", "AXSize"] {
        if let value = copyAttribute(element, name) { result[String(name.dropFirst(2)).lowercased()] = textValue(value) }
    }
    if includeAttributes { result["attributes"] = attributes(of: element).sorted() }
    return result
}

func children(of element: AXUIElement) -> [AXUIElement] {
    let standardChildren = (copyAttribute(element, "AXChildren") as? [AXUIElement]) ?? []
    // Electron and some native apps expose their content windows through AXWindows
    // rather than AXChildren on the application element. Treat those windows as
    // navigable children unless a window is already present in AXChildren.
    let role = textAttribute(element, "AXRole")
    let alreadyContainsWindow = standardChildren.contains { textAttribute($0, "AXRole") == "AXWindow" }
    guard role == "AXApplication", !alreadyContainsWindow,
          let windows = copyAttribute(element, "AXWindows") as? [AXUIElement] else {
        return standardChildren
    }
    return standardChildren + windows
}

func tree(of element: AXUIElement, depth: Int, remaining: inout Int) -> JSON {
    remaining -= 1
    var node = summary(of: element)
    guard depth > 0, remaining > 0 else { return node }
    var listedChildren: [JSON] = []
    for child in children(of: element) {
        guard remaining > 0 else { break }
        listedChildren.append(tree(of: child, depth: depth - 1, remaining: &remaining))
    }
    if !listedChildren.isEmpty { node["children"] = listedChildren }
    return node
}

struct Match {
    let path: String
    let element: AXUIElement
}

func walk(_ element: AXUIElement, path: String, depth: Int, matches: inout [Match]) {
    matches.append(Match(path: path, element: element))
    guard depth > 0 else { return }
    for (index, child) in children(of: element).enumerated() {
        let childPath = path.isEmpty ? String(index) : "\(path).\(index)"
        walk(child, path: childPath, depth: depth - 1, matches: &matches)
    }
}

func textAttribute(_ element: AXUIElement, _ name: String) -> String {
    guard let value = copyAttribute(element, name) else { return "" }
    return String(describing: textValue(value))
}

func outlineLine(path: String, element: AXUIElement) -> String {
    let role = textAttribute(element, "AXRole")
    let title = textAttribute(element, "AXTitle")
    let value = textAttribute(element, "AXValue")
    let description = textAttribute(element, "AXDescription")
    let label = [title, value, description].first { !$0.isEmpty } ?? ""
    return "\(path.isEmpty ? "root" : path)  \(role)\(label.isEmpty ? "" : "  \(label)")"
}

func matching(_ element: AXUIElement, title: String?, role: String?, value: String?) -> Bool {
    func contains(_ text: String, _ query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return text.localizedCaseInsensitiveContains(query)
    }
    let actualRole = textAttribute(element, "AXRole")
    let normalizedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX\($0)" }
    return contains(textAttribute(element, "AXTitle"), title)
        && contains(textAttribute(element, "AXValue"), value)
        && (normalizedRole == nil || actualRole == normalizedRole)
}

func targetApp(pidText: String?) throws -> AXUIElement {
    if let pidText {
        guard let pid = pid_t(pidText) else { throw CLIError.usage("--pid must be an integer") }
        return AXUIElementCreateApplication(pid)
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw CLIError.accessibility("No frontmost application found")
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

func element(at pathText: String, from root: AXUIElement) throws -> AXUIElement {
    guard !pathText.isEmpty else { return root }
    let parts = pathText.split(separator: ".")
    var element = root
    for part in parts {
        guard let index = Int(part), index >= 0 else { throw CLIError.usage("Invalid path: \(pathText)") }
        let elementChildren = children(of: element)
        guard index < elementChildren.count else {
            throw CLIError.accessibility("Path \(pathText) does not exist (index \(index) is out of range)")
        }
        element = elementChildren[index]
    }
    return element
}

func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
        throw CLIError.accessibility("Accessibility access is not enabled. Run `blindy request-permission`, then enable your terminal in System Settings > Privacy & Security > Accessibility.")
    }
}

func run() throws {
    let input = Array(CommandLine.arguments.dropFirst())
    guard let command = input.first, command != "--help", command != "-h" else {
        print(usage())
        return
    }
    if command == "request-permission" {
        // This is the documented string value of kAXTrustedCheckOptionPrompt. Using the
        // literal avoids Swift 6's shared-mutable-global diagnostic on the C declaration.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        printJSON(["trusted": trusted, "message": trusted ? "Accessibility access is enabled." : "A permission prompt was requested. Enable your terminal in System Settings, then rerun the command."])
        return
    }
    if command == "shell" {
        interactiveShell()
        return
    }
    let parsed = try parsedOptions(Array(input.dropFirst()))
    // Listing running applications comes from NSWorkspace, not the Accessibility API.
    if command != "apps" { try requireAccessibility() }

    switch command {
    case "apps":
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { ["name": $0.localizedName ?? "", "pid": Int($0.processIdentifier), "bundleId": $0.bundleIdentifier ?? ""] as JSON }
        printJSON(["apps": apps])
    case "activate":
        guard let pid = parsed.options["pid"] else { throw CLIError.usage("activate requires --pid") }
        try activateApplication(pidText: pid)
        printJSON(["pid": pid, "ok": true])
    case "open":
        guard let url = parsed.options["url"] else { throw CLIError.usage("open requires --url") }
        try openURL(url)
        printJSON(["url": url, "ok": true])
    case "tree":
        let root = try targetApp(pidText: parsed.options["pid"])
        let depth = Int(parsed.options["depth"] ?? "4") ?? 4
        let maxNodes = Int(parsed.options["max-nodes"] ?? "250") ?? 250
        guard depth >= 0, maxNodes > 0 else { throw CLIError.usage("--depth must be >= 0 and --max-nodes must be > 0") }
        var remaining = maxNodes
        printJSON(["tree": tree(of: root, depth: depth, remaining: &remaining), "truncated": remaining == 0])
    case "show":
        let root = try targetApp(pidText: parsed.options["pid"])
        let depth = Int(parsed.options["depth"] ?? "4") ?? 4
        guard depth >= 0 else { throw CLIError.usage("--depth must be >= 0") }
        var all: [Match] = []
        walk(root, path: "", depth: depth, matches: &all)
        for match in all { print(outlineLine(path: match.path, element: match.element)) }
    case "find":
        let title = parsed.options["title"]
        let role = parsed.options["role"]
        let value = parsed.options["value"]
        guard title != nil || role != nil || value != nil else {
            throw CLIError.usage("find requires at least one of --title, --role, or --value")
        }
        let root = try targetApp(pidText: parsed.options["pid"])
        let depth = Int(parsed.options["depth"] ?? "8") ?? 8
        let limit = Int(parsed.options["limit"] ?? "25") ?? 25
        guard depth >= 0, limit > 0 else { throw CLIError.usage("--depth must be >= 0 and --limit must be > 0") }
        var all: [Match] = []
        walk(root, path: "", depth: depth, matches: &all)
        let found = all.filter { matching($0.element, title: title, role: role, value: value) }.prefix(limit)
        printJSON(["matches": found.map { match in
            var result = summary(of: match.element, includeAttributes: true)
            result["path"] = match.path
            result["actions"] = actions(of: match.element).sorted()
            return result
        }])
    case "focused":
        let system = AXUIElementCreateSystemWide()
        guard let focused = copyElementAttribute(system, "AXFocusedUIElement") else {
            throw CLIError.accessibility("No focused accessibility element is available")
        }
        var result = summary(of: focused, includeAttributes: true)
        result["actions"] = actions(of: focused).sorted()
        printJSON(result)
    case "click":
        guard let x = Double(parsed.options["x"] ?? ""), let y = Double(parsed.options["y"] ?? "") else {
            throw CLIError.usage("click requires numeric --x and --y")
        }
        try postMouseClick(x: x, y: y)
        printJSON(["x": x, "y": y, "ok": true])
    case "type":
        guard let value = parsed.options["text"] else { throw CLIError.usage("type requires --text") }
        try postText(value)
        printJSON(["characters": value.count, "ok": true])
    case "paste":
        guard let value = parsed.options["text"] else { throw CLIError.usage("paste requires --text") }
        try pasteText(value)
        printJSON(["characters": value.count, "ok": true])
    case "key":
        guard let key = parsed.options["key"] else { throw CLIError.usage("key requires --key") }
        try postKey(key)
        printJSON(["key": key, "ok": true])
    case "inspect", "actions", "focus", "press", "set-value", "set-selected-text":
        guard let path = parsed.options["path"] else { throw CLIError.usage("\(command) requires --path") }
        let element = try element(at: path, from: targetApp(pidText: parsed.options["pid"]))
        if command == "inspect" {
            var result = summary(of: element, includeAttributes: true)
            result["actions"] = actions(of: element).sorted()
            printJSON(result)
        } else if command == "actions" {
            printJSON(["path": path, "actions": actions(of: element).sorted()])
        } else if command == "focus" {
            let error = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            guard error == .success else {
                throw CLIError.accessibility("Setting AXFocused failed: \(error.rawValue). This element may not accept keyboard focus; use `press` for a tab or button.")
            }
            printJSON(["path": path, "attribute": "AXFocused", "ok": true])
        } else if command == "press" {
            let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
            guard error == .success else { throw CLIError.accessibility("AXPress failed: \(error.rawValue)") }
            printJSON(["path": path, "action": "AXPress", "ok": true])
        } else if command == "set-selected-text" {
            guard let value = parsed.options["value"] else { throw CLIError.usage("set-selected-text requires --value") }
            let error = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, value as CFTypeRef)
            guard error == .success else { throw CLIError.accessibility("Setting AXSelectedText failed: \(error.rawValue)") }
            printJSON(["path": path, "attribute": "AXSelectedText", "ok": true])
        } else {
            guard let value = parsed.options["value"] else { throw CLIError.usage("set-value requires --value") }
            let error = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef)
            guard error == .success else { throw CLIError.accessibility("Setting AXValue failed: \(error.rawValue)") }
            printJSON(["path": path, "attribute": "AXValue", "ok": true])
        }
    default:
        throw CLIError.usage("Unknown command: \(command)")
    }
}

do {
    try run()
} catch CLIError.usage(let message) {
    fputs("Error: \(message)\n\n\(usage())\n", stderr)
    exit(64)
} catch CLIError.accessibility(let message) {
    printJSON(["error": message])
    exit(77)
} catch {
    printJSON(["error": String(describing: error)])
    exit(1)
}
