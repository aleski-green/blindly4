# blindy

`blindy` is a real macOS Accessibility API wrapper for inspecting and acting on the UI accessibility tree. It does **not** control VoiceOver or use `say`; it reads the same AX tree that assistive technologies use.

## Build

```sh
cd axvo
swift build -c release
./.build/release/blindy request-permission
```

Enable the terminal application you used to run the command in **System Settings → Privacy & Security → Accessibility**. The command deliberately exits rather than silently producing partial data when permission is unavailable.

## Examples

```sh
# List regular GUI apps and their PIDs
blindy apps

# See a readable outline of the frontmost app. The first column is the path.
blindy show --depth 5

# Search the tree by accessible name (partial, case-insensitive) and role.
# A tab may appear as AXRadioButton, AXButton, or AXTabGroup depending on the app.
blindy find --title 'Settings' --depth 8
blindy find --title 'Privacy' --role RadioButton

# Use a path from `show` or `find`. Focus text controls; activate tabs/buttons.
blindy focus --path 0.2.1
blindy press --path 0.2.1

# Read the frontmost app's complete nested tree as JSON (best for programs)
blindy tree --depth 4

# Read a particular app without bringing it forward
blindy tree --pid 12345 --depth 2

# Inspect the system-wide keyboard focus
blindy focused

# A path indexes AXChildren below the application root
blindy inspect --path 0.2
blindy actions --path 0.2
blindy press --path 0.2
blindy set-value --path 0.2 --value 'new text'
```

## Sending through the desktop app

Some web-based desktop apps (including Slack) expose their composer only as a web area. In that case, control the focused desktop application directly:

```sh
# Bring Slack forward, then click its message composer coordinates.
blindy activate --pid 14476
blindy open --url 'https://your-workspace.slack.com/archives/C123/p123?thread_ts=123&cid=C123'
blindy click --x 600 --y 900
blindy type --text 'Hello from Blindly'
blindy key --key return
```

`key --key return` activates the focused control. In a Slack composer, that sends the message, so use it only when the final message is correct.

If a web-based composer filters direct Unicode input, use `blindy paste --text 'Hello from Blindly'`. It pastes via Command-V and restores the previous text clipboard after the target app receives the paste.

## Interactive shell

Use this when you want to explore without repeatedly typing the executable path:

```sh
blindy shell
```

```text
blindy> apps
blindy> show --pid 1317 --depth 4
blindy> find --pid 1317 --title "Settings"
blindy> press --pid 1317 --path 0.2.1
blindy> exit
```

## Navigation workflow

1. Put the application you want to inspect in front.
2. Run `blindy show --depth 5` to see its accessible controls and paths, or search directly with `blindy find --title 'text you can see'`.
3. Copy the returned `path` and use `blindy inspect --path PATH` to check its role and supported actions.
4. For text fields, use `blindy focus --path PATH`, then `blindy set-value --path PATH --value 'text'`. For tabs and buttons, use `blindy press --path PATH`.

`press`, `focus`, and `set-value` can change the target application's UI. All other commands are read-only. Use `blindy --help` for the complete command reference.

## Project layout

```text
Sources/axvo/
  main.swift              entry point: run the registry, map errors to exit codes
  CLI/                    Command type, registry, generated help
  CLI/Commands/           one file per group of commands
  Accessibility/          AX element reading, tree walking, path resolution
  Input/                  synthetic mouse/keyboard events, NSWorkspace actions
  Shell/                  interactive prompt, line editor, tokenizer
  Support/                JSON output, errors, argument parsing
```

## Adding a command

Declare it in the matching group in `CLI/Commands/`:

```swift
Command("windows", "[--pid PID]") { invocation in
    let app = try invocation.application()
    printJSON(["windows": children(of: app).map { summary(of: $0) }])
}
```

The registry supplies the accessibility check and argument parsing, and the help text
and shell tab completion are derived from the declared name and arguments, so no other
file needs to change. Pass `requiresAccessibility: false` for commands that do not read
the accessibility tree.
