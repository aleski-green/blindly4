/// Help text is generated from the registry so a new command documents itself.
func usage() -> String {
    let sections = CommandRegistry.groups.map { group in
        ([group.title + ":"] + group.commands.map {
            "  \($0.usageLine)\($0.summary.isEmpty ? "" : "\n      \($0.summary)")"
        }).joined(separator: "\n")
    }
    return """
    blindy — macOS Accessibility tree CLI

    \(sections.joined(separator: "\n\n"))

    The default target is the frontmost application. Paths index AXChildren, starting at 0.
    Use `show` to see readable paths, `find` to locate an element by name, and `press`
    to activate a button or tab. `activate`, `click`, `type`, and `key` directly
    control the desktop UI, including app composers that expose no writable AX field.
    Pass `--pid` to click, type, paste, or key to verify that exact app is frontmost
    before Blindly injects a system-wide input event.

    Add `--profile` to any command for timing, AX-read, and cache counters.
    WARNING: full plaintext session logs are written to `.logs/` at the package root by default.
    If you do not want logging, add `--no-log` to a command or set `BLINDY_NO_LOG=1`
    before starting Blindly to disable service logging.
    Add `--no-service` before a command to bypass the local service for diagnostics.
    Use `blindy COMMAND --help` for command-specific safety and permission metadata.
    Use `blindy schema` for machine-readable command metadata.
    """
}
