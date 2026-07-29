# blindy

`blindy` is a real macOS Accessibility API wrapper for inspecting and acting on the UI accessibility tree. It does **not** control VoiceOver or use `say`; it reads the same AX tree that assistive technologies use.

## Build

```sh
git clone https://github.com/aleski-green/blindly4.git
cd blindly4
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
blindy show-menu --path 0.2
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

For a message that will be sent externally, use the verified form. It requires the intended PID, clears the current AX draft, and refuses success unless the composer's own AX subtree exposes exactly the requested text. It focuses the live AX composer and retains the clipboard until the paste is observed (up to one second), so a delayed web view cannot paste a restored clipboard value. Bind Send to the same exact draft immediately before the action:

```sh
blindy paste --pid 14476 --target-path 0.2.4 --text 'Hello from Blindly'
blindy press --pid 14476 --path 0.2.5 --expect-description Send \
  --require-value-path 0.2.4 --require-value 'Hello from Blindly'
```

If the composer cannot expose the exact draft through its own AX value, title, description, or descendants, Blindly fails closed. This prevents a pre-existing draft or text from another control from being sent accidentally.

## Watching for UI changes

Use a memory-only snapshot to report new accessible elements in any region. This is
universal: it does not assume an app's message labels or wording.

```sh
# Before an operation, record the chat/message region.
blindy snapshot --pid 12345 --name before --path 0.2.1.0 --depth 7

# After waiting, return only AX elements that were not present in that region.
blindy changes --pid 12345 --since before --path 0.2.1.0 --depth 7
```

Snapshots live only in the local service process and disappear when it exits.

## Navigation workflow

1. Put the application you want to inspect in front.
2. Run `blindy show --depth 5` to see its accessible controls and paths, or search directly with `blindy find --title 'text you can see'`.
3. Copy the returned `path` and use `blindy inspect --path PATH` to check its role and supported actions. Use `show-menu` when the element exposes `AXShowMenu`.
4. For text fields, use `blindy focus --path PATH`, then `blindy set-value --path PATH --value 'text'`. For tabs and buttons, use `blindy press --path PATH`.

`tree`, `show`, `find`, `focused`, `inspect`, `actions`, `apps`, and `changes` are
read-only. `snapshot` changes only memory-local service state. Other commands can
change the desktop UI; `press` and `key` can submit or commit an external action.
Use `blindy --help` for the command reference, `blindy COMMAND --help` for a
command's risk classification, and `blindy schema` for machine-readable metadata.

AX paths are indexes into a live tree and may change whenever the target UI updates.
Rediscover the target immediately before performing a mutation.

## Project layout

```text
Sources/axvo/
  main.swift              entry point: run the registry, map errors to exit codes
  CLI/                    Command type, registry, generated help
  CLI/Commands/           one file per group of commands
  Accessibility/          AX element reading, tree walking, path resolution
  Input/                  synthetic mouse/keyboard events, NSWorkspace actions
  Service/                memory-only local service and Unix socket transport
  Support/                JSON output, errors, argument parsing
```

## Adding a command

Declare it in the matching group in `CLI/Commands/`:

```swift
Command(
    "windows",
    "[--pid PID]",
    summary: "List application windows."
) { invocation, context in
    let app = try invocation.application()
    printJSON(["windows": children(of: app).map { summary(of: $0) }], to: context)
}
```

The registry supplies the accessibility check and argument parsing, and the help text
is derived from the declared name and arguments, so no other file needs to change.
Pass `requiresAccessibility: false` for commands that do not read the accessibility
tree.

## Development

Run the permission-free validation suite from the repository root:

```sh
swift build
swift run blindy --self-test
swift run blindy schema
```

`--self-test` needs no test framework and no Accessibility permission, so it runs
anywhere the executable builds. CI runs the same commands on every pull request.

Commands that access a live application's AX tree require macOS Accessibility
permission and are intentionally excluded from automated CI. Exit status `64`
indicates invalid CLI usage, `77` indicates an Accessibility failure, and `1`
indicates an unexpected error. `AGENTS.md` documents the architecture, output
contracts, and safety invariants for coding agents and contributors.

## Performance

One-shot commands automatically share a per-user local service while it is active. The
service keeps only in-memory, validated `find --limit 1` path hints; it never writes UI
metadata or search text to disk, and falls back to a normal accessibility-tree search if
the app, window, or target has changed. Add `--profile` to a command to inspect elapsed
time, accessibility reads, visited nodes, cache hits, and paste wait time. Prefix a
command with `--no-service` to bypass the service for diagnostics.

For system-wide input commands (`click`, `type`, `paste`, and `key`), pass `--pid` to
make Blindly activate and verify the intended foreground application before it emits the
event. For external messages, also pass `paste --target-path` and use `press` with
`--require-value-path` / `--require-value`; a PID guard alone cannot prove that a global
keyboard event reached the intended composer.
