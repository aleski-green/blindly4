import ApplicationServices
import Foundation

private let pathArguments = "--path INDEX[.INDEX...] [--pid PID]"

/// Commands that write a string attribute share everything but the attribute name.
private func textAttributeCommand(_ name: String, attribute: String) -> Command {
    Command(name, "--path INDEX[.INDEX...] --value TEXT [--pid PID]") { invocation in
        let target = try invocation.element()
        let value = try invocation.value("value")
        try setAttribute(target.element, attribute, value as CFTypeRef)
        printJSON(["path": target.path, "attribute": attribute, "ok": true])
    }
}

let elementCommands = CommandGroup(title: "Elements", commands: [
    Command("inspect", pathArguments) { invocation in
        printJSON(detail(of: try invocation.element().element))
    },

    Command("actions", pathArguments) { invocation in
        let target = try invocation.element()
        printJSON(["path": target.path, "actions": actions(of: target.element).sorted()])
    },

    Command("focus", pathArguments) { invocation in
        let target = try invocation.element()
        try setAttribute(
            target.element,
            kAXFocusedAttribute,
            true as CFTypeRef,
            hint: "This element may not accept keyboard focus; use `press` for a tab or button."
        )
        printJSON(["path": target.path, "attribute": kAXFocusedAttribute, "ok": true])
    },

    Command("press", pathArguments) { invocation in
        let target = try invocation.element()
        try performAction(target.element, kAXPressAction)
        printJSON(["path": target.path, "action": kAXPressAction, "ok": true])
    },

    textAttributeCommand("set-value", attribute: kAXValueAttribute),
    textAttributeCommand("set-selected-text", attribute: kAXSelectedTextAttribute)
])
