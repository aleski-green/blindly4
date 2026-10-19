# blindly4

Blindly4 supports **macOS 13+ and Windows 10/11** with a shared, stateless CLI and native accessibility backends. CI builds and tests macOS, Windows x64 and Windows ARM64.

This fork tracks [aleski-green/blindly4](https://github.com/aleski-green/blindly4) and implements both native backends in Rust.

| Operating system | Backend | Build requirements |
| --- | --- | --- |
| macOS 13+ | Rust / Apple Accessibility | Stable Rust and Xcode Command Line Tools; Accessibility permission for desktop access |
| Windows 10/11, ARM64 and x64 | Rust / Microsoft UI Automation | Stable Rust and MSVC C++ Build Tools with the Windows SDK; native packages need no language runtime |

Windows support was contributed through the [fatmahalqaisi-code/blindly4 fork](https://github.com/fatmahalqaisi-code/blindly4).

`blindly4` inspects and operates the real desktop accessibility tree: Apple Accessibility on macOS and Microsoft UI Automation on Windows. It does **not** control VoiceOver or use `say`.

**Windows 10/11:** see [native Windows builds, commands and tests](windows/README.md). Both ARM64 and x64 are supported. The examples below use the shared CLI; the macOS build and permission instructions apply only to macOS.

## Build on macOS

```sh
git clone https://github.com/fatmahalqaisi-code/blindly4.git
cd blindly4
./macos/build.sh
./.build/release/blindly4 request-permission
```

Enable the terminal application you used to run the command in **System Settings → Privacy & Security → Accessibility**. The command deliberately exits rather than silently producing partial data when permission is unavailable.

## Build on Windows

From PowerShell with Git, stable Rust, and Visual Studio C++ Build Tools (including the Windows SDK) installed:

```powershell
git clone https://github.com/fatmahalqaisi-code/blindly4.git
cd blindly4
.\windows\build.ps1
.\.build\windows\blindly4.exe apps
```

The build selects the host architecture; pass `-Runtime win-x64` or `-Runtime win-arm64` to choose explicitly. Run desktop commands in the logged-in interactive session. See [Windows commands, safety limits and tests](windows/README.md).

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

## Stateless execution (schema version 2)

Every invocation runs one command directly against the live desktop, prints its
result, and exits. Blindly keeps no cross-command state: no background service,
search cache, named snapshots, workflow leases, or log files. Optional `--profile`
diagnostics go only to stderr. The desktop itself remains stateful, and input still
changes applications and may temporarily use the clipboard.

Callers own before/after comparisons, any audit trail, and exclusive desktop access
for the entire workflow. Serialize even commands targeting different apps: keyboard,
mouse, focus, and clipboard are shared. A full AX path does not prevent concurrent
input or guarantee that child indexes still identify the same control. Sapiens4
already provides a single computer owner for its managed callers; standalone
callers must supply equivalent coordination. Blindly does not enforce it.

This intentionally removes `serve`, `workflow`, `snapshot`, `changes`, `--lease`,
`--no-service`, and `--no-log`; obsolete commands/options fail with exit 64.
The `BLINDLY4_LOG_*` and `BLINDLY4_NO_LOG` environment settings are no longer used.
Existing log files are left untouched and remain gitignored. Retained UI commands
keep their JSON results, permission checks, and input/draft guards.

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

If a web-based composer filters direct Unicode input, use `blindly4 paste --text 'Hello from blindly4'`. It pastes via Command-V on macOS or Ctrl-V on Windows and restores the previous clipboard after the target app receives the paste.

For a message that will be sent externally, use the verified form. It requires the intended PID, clears the current AX draft, and refuses success unless the composer's own AX subtree exposes exactly the requested text. It focuses the live AX composer and retains the clipboard until the paste is observed (up to one second), so a delayed web view cannot paste a restored clipboard value. Bind Send to the same exact draft immediately before the action:

```sh
blindly4 paste --pid 14476 --target-path 0.2.4 --text 'Hello from blindly4'
blindly4 press --pid 14476 --path 0.2.5 --expect-description Send \
  --require-value-path 0.2.4 --require-value 'Hello from blindly4'
```

If the composer cannot expose the exact draft through its own AX value (or, if unavailable, its own bounded AX subtree), blindly4 fails closed. This prevents a pre-existing draft or text from another control from being sent accidentally.

If no identifiable Send button is exposed and the app uses Enter to send, verify
the recipient, rediscover and focus the composer, then use a guarded key:

```sh
blindly4 focus --pid 14476 --path 0.2.4
blindly4 key --pid 14476 --key return --target-path 0.2.4 --require-value 'Hello from blindly4'
```

Both guard options and a PID are required together. The command refuses input
unless the target is the focused text control, its draft matches exactly, and the
app is still frontmost. `verified` reports these preconditions, not delivery;
inspect the outgoing conversation before reporting success or retrying.
Keyboard names include `return`/`enter`, `tab`, and `delete`/`backspace` (backward delete).

## Watching for UI changes

Accessibility errors retain exit code 77 and include a JSON `code`:
`accessibility_permission_denied` requires permission repair; `focus_unavailable`
means no focused element was exposed; other AX or draft-guard failures use
`accessibility_error`. Use `focused --pid PID` for app-scoped focus observation.
A missing focus can be retried once after rediscovering and focusing the intended
control. Never use focus recovery to bypass an exact-draft or send guard failure.

For before/after comparison, capture `tree`, `show`, or targeted `find` results in
the caller and compare fresh observations there. Blindly does not retain a baseline
or infer unread messages. Read again after navigation and before mutations.

## Navigation workflow

1. Put the application you want to inspect in front.
2. Run `blindly4 show --depth 5` to see its accessible controls and paths, or search directly with `blindly4 find --title 'text you can see'`.
3. Copy the returned `path` and use `blindly4 inspect --path PATH` to check its role and supported actions. Use `show-menu` when the element exposes `AXShowMenu`.
4. For text fields, use `blindly4 focus --path PATH`, then `blindly4 set-value --path PATH --value 'text'`. For tabs and buttons, use `blindly4 press --path PATH`.

`tree`, `show`, `find`, `focused`, `inspect`, `actions`, and `apps` are
read-only. Other commands can
change the desktop UI; `press` and `key` can submit or commit an external action.
Use `blindly4 --help` for the command reference, `blindly4 COMMAND --help` for a
command's risk classification, and `blindly4 schema` for machine-readable metadata.

AX paths are indexes into a live tree and may change whenever the target UI updates.
Rediscover the target immediately before performing a mutation.

Before entering text, inspect the actual editable control. An `AXGroup` can contain
a focused `AXTextArea` without being writable itself. If the candidate is a
container, discover its children at sufficient depth and inspect the intended
editable child. Verify the app and destination, not just its role. Do not infer
editability from focus, invent child indexes, or reuse historical numeric paths.

A `paste --target-path` rejection saying the target is not a writable AX text
control happens before input. Allow one bounded rediscovery and inspection of the
intended editable child, then one guarded paste retry. This exception does not
apply to exact-draft, focus, or submission guard failures. Never classify an error
as pre-input rejection from its exit code alone. If input or submission may have
occurred, inspect the draft and outcome before considering a retry.

Reuse successful guarded-paste verification when sufficient; retain fresh
submission guards and the required post-action checks. Avoid redundant identical
inspections. Verify the requested result: tool success, an injected key, or an
empty composer alone does not prove delivery.


## Using blindly4 inside Codex

blindly4 is a plain CLI that prints JSON to stdout, so a coding agent drives it by
running shell commands and reading the result. Nothing else has to be wired up.

On macOS, install it once and grant permission:

```sh
./macos/build.sh
cp .build/release/blindly4 /usr/local/bin/
blindly4 request-permission
```

On Windows, use the self-contained executable from `.build/windows/` or add its directory to `PATH`; no macOS Accessibility permission setup applies.

On macOS, Accessibility permission belongs to the process that runs the agent's shell, not to
`blindly4` itself. Grant it to Codex, or to the terminal hosting it, in **System
Settings → Privacy & Security → Accessibility**. Without it every AX command exits
`77`.

Have the agent run `blindly4 schema` at the start of a session. It returns every
command with its options and a `risk` field: `read-only` inspects without changing
anything, `ui-mutation` moves
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

# 4. Read the conversation; keep any comparison baseline in the caller.
blindly4 tree --pid 14476 --depth 7 --max-nodes 500

# 5. Rediscover the composer, write the draft, and verify it.
blindly4 find --pid 14476 --role AXTextArea --depth 10
blindly4 paste --pid 14476 --target-path 0.2.6 --text 'Reply text'

# 6. Send only after step 5 reported the exact draft.
blindly4 press --pid 14476 --path 0.2.7 --expect-description Send \
  --require-value-path 0.2.6 --require-value 'Reply text'
```

Step 3 uses `press`, an `external-commit` command: first verify that the live target
is the intended conversation. Step 6 sends the message and requires authorization.

### Rules for the agent

- Re-run `find` immediately before any mutation. A path read thirty seconds ago may
  now address a different element.
- Pass `--pid` on input commands. It makes Blindly verify the foreground application
  before emitting a system-wide event, so a window that steals focus cannot receive
  the keystrokes.
- Never send with bare `type` followed by `key --key return`. Use
  `paste --target-path` with `press --require-value`, or guarded
  `key --target-path --require-value` when no Send control is available. Both
  fail closed unless the composer exposes exactly the intended text.
- There is no universal unread state in the accessibility tree. Compare before/after
  observations in the caller; Blindly retains no snapshots between commands.
- Serialize the entire desktop workflow in the caller; do not run concurrent input.
- Add `--require-selected` to `press` when the target exposes `AXSelected`, so a
  follow-up step cannot act on a selection that never happened.
- Check the exit code. `64` is invalid usage, `77` is a permission or accessibility
  failure, `1` is unexpected. Do not continue a mutation sequence after a non-zero
  exit.

## Project layout

```text
shared/                 shared CLI, validation, activation, guarded input, tree traversal
adapters/mod.rs         selects the platform adapter at compile time
macos/src/              macOS adapter: AX, AppKit, Quartz, clipboard, and test fixture
windows/src/            Windows adapter: UI Automation, Win32, clipboard, and fixture
spec/                   RSpec CLI and live desktop behavior
```

Commands are declared once in `shared/registry.rs`, together with their usage,
summary, risk, accessibility requirement, and handler. Platform backends preserve
native AX/UIA behavior and the existing platform-specific output contracts.

## Development

All tests are RSpec behavioral tests that run the compiled executable. Build for
your platform, install Ruby 3.4 and Bundler, then run from the repository root:

```sh
./macos/build.sh debug
bundle install
bundle exec rspec
```

On Windows, use `windows/build.ps1` in place of `./macos/build.sh debug`. The default RSpec
suite needs no Accessibility permission. CI runs it on macOS Apple Silicon and Intel, Windows x64, and Windows ARM64. There are no unit tests or embedded self-test runners. See
[behavioral test coverage and live desktop scenarios](spec/README.md).

Live scenarios run with `BLINDLY4_LIVE=1 bundle exec rspec` on an unlocked
desktop. The macOS fixture is a native Rust/AppKit form; Accessibility permission
is required. Hosted CI runs only permission-free examples. Exit status `64`
indicates invalid CLI usage, `77` indicates an Accessibility failure, and `1`
indicates an unexpected error. `AGENTS.md` documents the architecture, output
contracts, and safety invariants for coding agents and contributors.

## Performance

Every `find` traverses the current accessibility tree, stopping at its depth and
result limits. Repeated `find --limit 1` calls no longer reuse a path hint; direct
path operations still resolve only the requested live path. Batched AX reads and
bounded traversal remain. Add `--profile` to inspect elapsed time; no profiling data is stored.

For system-wide input commands (`click`, `type`, `paste`, `scroll`, and `key`), pass `--pid` to
make Blindly activate and verify the intended foreground application before it emits the
event. For external messages, also pass `paste --target-path` and use `press` with
`--require-value-path` / `--require-value`, or guarded `key --target-path --require-value`;
a PID guard alone cannot prove that a global
keyboard event reached the intended composer.


## License

Blindly4 is source-available under the [Sustainable Use License 1.0](license/LICENSE.md).
See [licensing and commercial services](license/LICENSING.md) for community use,
contributions, and future enterprise additions. Commercial inquiries:
[license@sapiens4.ai](mailto:license@sapiens4.ai).
