import ApplicationServices
import Foundation

private let pathArguments = "--path INDEX[.INDEX...] [--pid PID]"

/// Commands that write a string attribute share everything but the attribute name.
private func textAttributeCommand(_ name: String, attribute: String) -> Command {
    Command(name, "--path INDEX[.INDEX...] --value TEXT [--pid PID]", summary: "Write \(attribute) on an accessibility element.", risk: .uiMutation) { invocation, context in
        let target = try invocation.element(profile: context.profile)
        let value = try invocation.value("value")
        try setAttribute(target.element, attribute, value as CFTypeRef)
        printJSON(["path": target.path, "attribute": attribute, "ok": true], to: context)
    }
}

let elementCommands = CommandGroup(title: "Elements", commands: [
    Command("inspect", pathArguments, summary: "Inspect one accessibility element.") { invocation, context in
        printJSON(detail(of: try invocation.element(profile: context.profile).element, profile: context.profile), to: context)
    },

    Command("actions", pathArguments, summary: "List actions supported by one element.") { invocation, context in
        let target = try invocation.element(profile: context.profile)
        printJSON(["path": target.path, "actions": actions(of: target.element, profile: context.profile).sorted()], to: context)
    },

    Command("focus", pathArguments, summary: "Move keyboard focus to an element.", risk: .uiMutation) { invocation, context in
        let target = try invocation.element(profile: context.profile)
        try setAttribute(
            target.element,
            kAXFocusedAttribute,
            true as CFTypeRef,
            hint: "This element may not accept keyboard focus; use `press` for a tab or button."
        )
        printJSON(["path": target.path, "attribute": kAXFocusedAttribute, "ok": true], to: context)
    },

    Command("show-menu", pathArguments, summary: "Open an element's accessibility context menu.", risk: .uiMutation) { invocation, context in
        let target = try invocation.element(profile: context.profile)
        guard actions(of: target.element, profile: context.profile).contains(kAXShowMenuAction) else {
            throw CLIError.usage("show-menu target does not support \(kAXShowMenuAction)")
        }
        try performAction(target.element, kAXShowMenuAction)
        printJSON(["path": target.path, "action": kAXShowMenuAction, "ok": true], to: context)
    },

    Command("press", "\(pathArguments) [--expect-description TEXT] [--require-selected] [--require-value-path PATH --require-value TEXT]", summary: "Perform AXPress; this may trigger an irreversible external action.", risk: .externalCommit) { invocation, context in
        let target = try invocation.element(profile: context.profile)
        if let expected = invocation.optional("expect-description"),
           !textAttribute(target.element, "AXDescription", profile: context.profile).localizedCaseInsensitiveContains(expected) {
            throw CLIError.usage("press target does not match --expect-description \(expected)")
        }
        let requiredValuePath = invocation.optional("require-value-path")
        let requiredValue = invocation.optional("require-value")
        guard (requiredValuePath == nil) == (requiredValue == nil) else {
            throw CLIError.usage("press requires both --require-value-path and --require-value")
        }
        if let requiredValuePath, let requiredValue {
            let draft = try elementAtPath(requiredValuePath, from: try invocation.application(), profile: context.profile)
            guard hasExactVisibleText(in: draft, expected: requiredValue, profile: context.profile) else {
                throw CLIError.accessibility("Press blocked: the required draft does not exactly match --require-value")
            }
        }
        try performAction(target.element, kAXPressAction)
        var selected = false
        if invocation.hasFlag("require-selected") {
            for _ in 0..<20 {
                let value = copyAttribute(target.element, "AXSelected", profile: context.profile) as? NSNumber
                if value?.boolValue == true { selected = true; break }
                usleep(50_000)
            }
            guard selected else {
                throw CLIError.accessibility("Press completed but the target was not selected; no follow-up action should be taken")
            }
        }
        var result: JSON = ["path": target.path, "action": kAXPressAction, "ok": true]
        if invocation.hasFlag("require-selected") { result["selected"] = selected }
        printJSON(result, to: context)
    },

    textAttributeCommand("set-value", attribute: kAXValueAttribute),
    textAttributeCommand("set-selected-text", attribute: kAXSelectedTextAttribute)
])
