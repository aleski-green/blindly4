/// Help text is generated from the registry so a new command documents itself.
func usage() -> String {
    let sections = CommandRegistry.groups.map { group in
        ([group.title + ":"] + group.commands.map {
            "  \($0.usageLine)\($0.summary.isEmpty ? "" : "\n      \($0.summary)")"
        }).joined(separator: "\n")
    }
    return """
    blindly4 — macOS Accessibility tree CLI

    \(sections.joined(separator: "\n\n"))

    The default target is the frontmost application. Paths index AXChildren, starting at 0.
    Use `show` to see readable paths, `find` to locate an element by name, and `press`
    to activate a button or tab. `activate`, `click`, `type`, and `key` directly
    control the desktop UI, including app composers that expose no writable AX field.
    Pass `--pid` to click, type, paste, or key to verify that exact app is frontmost
    before blindly4 injects a system-wide input event.

    Add `--profile` to any command for timing, AX-read, and cache counters.
    Session logs use compact AX snapshots plus path references by default. Discovery snapshots
    can contain visible private text. Set BLINDLY4_LOG_MODE=full for legacy full plaintext logs.
    Add `--no-log` to a command or set `BLINDLY4_NO_LOG=1` before starting blindly4 to disable logging.
    Add `--no-service` before a command to bypass the local service for diagnostics.
    Use `blindly4 COMMAND --help` for command-specific safety and permission metadata.
    Use `blindly4 schema` for machine-readable command metadata.
    """
}
