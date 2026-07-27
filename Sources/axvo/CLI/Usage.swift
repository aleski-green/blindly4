/// Help text is generated from the registry so a new command documents itself.
func usage() -> String {
    let sections = CommandRegistry.groups.map { group in
        ([group.title + ":"] + group.commands.map { "  " + $0.usageLine }).joined(separator: "\n")
    }
    return """
    blindy — macOS Accessibility tree CLI

    \(sections.joined(separator: "\n\n"))

    The default target is the frontmost application. Paths index AXChildren, starting at 0.
    Use `show` to see readable paths, `find` to locate an element by name, and `press`
    to activate a button or tab. `activate`, `click`, `type`, and `key` directly
    control the desktop UI, including app composers that expose no writable AX field.

    Run `blindy shell` for an interactive prompt. Type `help` or `exit` there.
    """
}
