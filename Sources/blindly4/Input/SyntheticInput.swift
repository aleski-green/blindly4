import AppKit
import Foundation

private let keyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "delete": 51,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5,
    "h": 4, "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45,
    "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32,
    "v": 9, "w": 13, "x": 7, "y": 16, "z": 6
]

private let modifierFlags: [String: CGEventFlags] = [
    "command": .maskCommand, "cmd": .maskCommand,
    "shift": .maskShift,
    "option": .maskAlternate, "alt": .maskAlternate,
    "control": .maskControl, "ctrl": .maskControl
]

enum ScrollDirection: String, CaseIterable {
    case up, down, left, right

    init(cliValue: String) throws {
        guard let direction = Self(rawValue: cliValue.lowercased()) else {
            throw CLIError.usage("Unsupported --direction \(cliValue). Use up, down, left, or right.")
        }
        self = direction
    }
}

private func eventSource() throws -> CGEventSource {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw CLIError.accessibility("Could not create a HID event source")
    }
    return source
}

func postMouseClick(x: Double, y: Double) throws {
    let point = CGPoint(x: x, y: y)
    let source = try eventSource()
    guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        throw CLIError.accessibility("Could not create mouse events")
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

/// Posts a line-based scroll-wheel event to the current foreground application.
/// Positive wheel deltas follow Core Graphics' up/left convention.
func postScroll(direction: ScrollDirection, amount: Int) throws {
    guard amount <= Int(Int32.max) else {
        throw CLIError.usage("--amount is too large")
    }
    let delta = Int32(amount)
    let vertical: Int32
    let horizontal: Int32
    switch direction {
    case .up:
        vertical = delta
        horizontal = 0
    case .down:
        vertical = -delta
        horizontal = 0
    case .left:
        vertical = 0
        horizontal = delta
    case .right:
        vertical = 0
        horizontal = -delta
    }
    let source = try eventSource()
    guard let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .line,
        wheelCount: 2,
        wheel1: vertical,
        wheel2: horizontal,
        wheel3: 0
    ) else {
        throw CLIError.accessibility("Could not create a scroll event")
    }
    event.post(tap: .cghidEventTap)
}

func postText(_ text: String) throws {
    let characters = Array(text.utf16)
    guard !characters.isEmpty else { return }
    let source = try eventSource()
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
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

func postKey(_ keyName: String) throws {
    let parts = keyName.lowercased().split(separator: "+").map(String.init)
    guard let key = parts.last, let keyCode = keyCodes[key] else {
        throw CLIError.usage("Unsupported --key \(keyName). Use return, tab, arrows, letters, or modifiers such as command+k.")
    }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
        guard let flag = modifierFlags[modifier] else {
            throw CLIError.usage("Unsupported modifier \(modifier) in --key \(keyName)")
        }
        flags.insert(flag)
    }
    let source = try eventSource()
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw CLIError.accessibility("Could not create keyboard events")
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

/// Returns whether an optional observer confirmed that the pasted text reached its
/// intended control before the clipboard was restored.
func pasteText(_ text: String, profile: Profile? = nil, until observed: (() -> Bool)? = nil) throws -> Bool {
    let pasteboard = NSPasteboard.general
    let previousText = pasteboard.string(forType: .string)
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
        throw CLIError.accessibility("Could not place text on the macOS pasteboard")
    }
    try postKey("command+v")
    // The event is normally consumed on the next run-loop turn.  A normal paste keeps
    // the old short bounded wait; a verified paste retains the clipboard long enough
    // to observe the target's AX value, but never indefinitely.
    let waitStarted = ContinuousClock.now
    let attempts = observed == nil ? 12 : 100
    var didObserve = observed == nil
    for _ in 0..<attempts {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        if observed?() == true {
            didObserve = true
            break
        }
    }
    let wait = waitStarted.duration(to: .now)
    profile?.pasteWaitMilliseconds += Int(Double(wait.components.seconds) * 1_000 + Double(wait.components.attoseconds) / 1e15)
    if let previousText {
        pasteboard.clearContents()
        pasteboard.setString(previousText, forType: .string)
    }
    return didObserve
}
