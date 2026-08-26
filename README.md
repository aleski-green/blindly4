# blindly4

`blindly4` is a real macOS Accessibility API wrapper for inspecting and acting on the UI accessibility tree. It does **not** control VoiceOver or use `say`; it reads the same AX tree that assistive technologies use.

## Build

```sh
git clone https://github.com/aleski-green/blindly4.git
cd blindly4
swift build -c release
./.build/release/blindly4 request-permission
```

Enable the terminal application you used to run the command in **System Settings → Privacy & Security → Accessibility**. The command deliberately exits rather than silently producing partial data when permission is unavailable.

## Examples

```sh
# List regular GUI apps and their PIDs
blindly4 apps

# See a readable outline of the frontmost app. The first column is the path.
blindly4 show --depth 5

# Search the tree by accessible name (partial, case-insensitive) and role.
# A tab may appear as AXRadioButton, AXButton, or AXTabGroup depending on the app.
blindly4 find --title 'Settings' --depth 8
blindly4 find --title 'Privacy' --role RadioButton

# Use a path from `show` or `find`. Focus text controls; activate tabs/buttons.
blindly4 focus --path 0.2.1
blindly4 press --path 0.2.1

# Read the frontmost app's complete nested tree as JSON (best for programs)
blindly4 tree --depth 4

# Read a particular app without bringing it forward
blindly4 tree --pid 12345 --depth 2

# Inspect the system-wide keyboard focus
blindly4 focused

# A path indexes AXChildren below the application root
blindly4 inspect --path 0.2
blindly4 actions --path 0.2
blindly4 show-menu --path 0.2
blindly4 scroll-to --path 0.2
blindly4 press --path 0.2
blindly4 set-value --path 0.2 --value 'new text'
```

## Session logs

blindly4 writes compact NDJSON audit logs by default. A service process uses one log
for its lifetime; `--no-service` creates one log for that direct invocation.
Logs live in `.logs/` at the package root and are named with their UTC start time,
for example `session_s_20260731T175601123Z.ndjson`.

Discovery commands (`show`, `tree`, `find`, `inspect`, `actions`, and `focused`) write
unredacted AX snapshots with a snapshot ID. Later commands record only their app/PID,
AX path, status, duration, and the latest snapshot ID for that PID. They do not record
arguments, stdout, or stderr. Snapshots can still contain private visible text.

Set `BLINDLY4_LOG_MODE=full` to use the legacy full-fidelity format, which records
arguments, stdout, and stderr. If you do not want any logging, add `--no-log` to an
individual command or start blindly4 with `BLINDLY4_NO_LOG=1`.

Add `--no-log` to omit one command from a service log. Set `BLINDLY4_NO_LOG=1` before
starting Blindly to disable logging for the whole service process. Set
`BLINDLY4_LOG_DIR` to override the log directory.

## Coordinating workflows

Use `workflow acquire` to obtain a 60-second local-service lock, pass the returned token
as `--lease TOKEN` to every command in that workflow, then release it with
`workflow release --lease TOKEN`. While held, other commands return `workflow_busy`.

## Sending through the desktop app

Some web-based desktop apps (including Slack) expose their composer only as a web area. In that case, control the focused desktop application directly:

```sh
# Bring Slack forward, then click its message composer coordinates.
blindly4 activate --pid 14476
blindly4 open --url 'https://your-workspace.slack.com/archives/C123/p123?thread_ts=123&cid=C123'
blindly4 click --x 600 --y 900
blindly4 type --text 'Hello from blindly4'
blindly4 key --key return
```

When a web view does not expose scrollable elements in its AX tree, send a bounded
line-based scroll event to the verified foreground app instead:

```sh
blindly4 scroll --pid 14476 --direction down --amount 5
```

Use `scroll-to --path PATH` when the target element advertises the `AXScrollToVisible`
action; it brings that exact accessible element into view without relying on coordinates.

`key --key return` activates the focused control. In a Slack composer, that sends the message, so use it only when the final message is correct.

If a web-based composer filters direct Unicode input, use `blindly4 paste --text 'Hello from blindly4'`. It pastes via Command-V and restores the previous text clipboard after the target app receives the paste.

For a message that will be sent externally, use the verified form. It requires the intended PID, clears the current AX draft, and refuses success unless the composer's own AX subtree exposes exactly the requested text. It focuses the live AX composer and retains the clipboard until the paste is observed (up to one second), so a delayed web view cannot paste a restored clipboard value. Bind Send to the same exact draft immediately before the action:

```sh
blindly4 paste --pid 14476 --target-path 0.2.4 --text 'Hello from blindly4'
blindly4 press --pid 14476 --path 0.2.5 --expect-description Send \
  --require-value-path 0.2.4 --require-value 'Hello from blindly4'
```

If the composer cannot expose the exact draft through its own AX value, title, description, or descendants, blindly4 fails closed. This prevents a pre-existing draft or text from another control from being sent accidentally.

## Watching for UI changes

Use a memory-only snapshot to report new accessible elements in any region. This is
universal: it does not assume an app's message labels or wording.

```sh
# Before an operation, record the chat/message region.
blindly4 snapshot --pid 12345 --name before --path 0.2.1.0 --depth 7

# After waiting, return only AX elements that were not present in that region.
blindly4 changes --pid 12345 --since before --path 0.2.1.0 --depth 7
```

Snapshots live only in the local service process and disappear when it exits.

## Navigation workflow

1. Put the application you want to inspect in front.
2. Run `blindly4 show --depth 5` to see its accessible controls and paths, or search directly with `blindly4 find --title 'text you can see'`.
3. Copy the returned `path` and use `blindly4 inspect --path PATH` to check its role and supported actions. Use `show-menu` when the element exposes `AXShowMenu`.
4. For text fields, use `blindly4 focus --path PATH`, then `blindly4 set-value --path PATH --value 'text'`. For tabs and buttons, use `blindly4 press --path PATH`.

`tree`, `show`, `find`, `focused`, `inspect`, `actions`, `apps`, and `changes` are
read-only. `snapshot` changes only memory-local service state. Other commands can
change the desktop UI; `press` and `key` can submit or commit an external action.
Use `blindly4 --help` for the command reference, `blindly4 COMMAND --help` for a
command's risk classification, and `blindly4 schema` for machine-readable metadata.

AX paths are indexes into a live tree and may change whenever the target UI updates.
Rediscover the target immediately before performing a mutation.

## Using blindly4 inside Codex

blindly4 is a plain CLI that prints JSON to stdout, so a coding agent drives it by
running shell commands and reading the result. Nothing else has to be wired up.

Install it once and grant permission:

```sh
swift build -c release
cp .build/release/blindly4 /usr/local/bin/
blindly4 request-permission
```

Accessibility permission belongs to the process that runs the agent's shell, not to
`blindly4` itself. Grant it to Codex, or to the terminal hosting it, in **System
Settings → Privacy & Security → Accessibility**. Without it every AX command exits
`77`.

Have the agent run `blindly4 schema` at the start of a session. It returns every
command with its options and a `risk` field: `read-only` inspects without changing
anything, `local-state` writes only in-memory service state, `ui-mutation` moves
focus or injects input, and `external-commit` may send, submit, buy, or delete and
must never be run speculatively.

### Example: read a conversation and reply

Each step depends on the previous one. The paths below are illustrative — take real
ones from the `show` and `find` output.

```sh
# 1. Find the app and its PID.
blindly4 apps

# 2. Bring it forward and read a readable outline with paths.
blindly4 activate --pid 14476
blindly4 show --pid 14476 --depth 6

# 3. Open the conversation by its visible name.
blindly4 find --pid 14476 --title 'Jane Doe' --depth 10
blindly4 press --pid 14476 --path 0.2.1.3

# 4. Record the message region, wait, then read only what is new.
blindly4 snapshot --pid 14476 --name before --path 0.2.4 --depth 7
blindly4 changes --pid 14476 --since before --path 0.2.4 --depth 7

# 5. Rediscover the composer, write the draft, and verify it.
blindly4 find --pid 14476 --role AXTextArea --depth 10
blindly4 paste --pid 14476 --target-path 0.2.6 --text 'Reply text'

# 6. Send only after step 5 reported the exact draft.
blindly4 press --pid 14476 --path 0.2.7 --expect-description Send \
  --require-value-path 0.2.6 --require-value 'Reply text'
```

Steps 1 through 4 are safe to run unattended. Step 6 is `external-commit` and
actually sends the message.

### Rules for the agent

- Re-run `find` immediately before any mutation. A path read thirty seconds ago may
  now address a different element.
- Pass `--pid` on input commands. It makes Blindly verify the foreground application
  before emitting a system-wide event, so a window that steals focus cannot receive
  the keystrokes.
- Never send with bare `type` followed by `key --key return`. Use
  `paste --target-path` with `press --require-value`, which fails closed unless the
  composer exposes exactly the intended text.
- There is no unread state in the accessibility tree. Use `snapshot` before and
  `changes` after; this works regardless of how an app labels its messages.
- Add `--require-selected` to `press` when the target exposes `AXSelected`, so a
  follow-up step cannot act on a selection that never happened.
- Check the exit code. `64` is invalid usage, `77` is a permission or accessibility
  failure, `1` is unexpected. Do not continue a mutation sequence after a non-zero
  exit.

## Project layout

```text
Sources/blindly4/
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
swift run blindly4 --self-test
swift run blindly4 schema
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

For system-wide input commands (`click`, `type`, `paste`, `scroll`, and `key`), pass `--pid` to
make Blindly activate and verify the intended foreground application before it emits the
event. For external messages, also pass `paste --target-path` and use `press` with
`--require-value-path` / `--require-value`; a PID guard alone cannot prove that a global
keyboard event reached the intended composer.
