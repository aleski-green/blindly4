# Blindly4 on Windows

The Windows implementation is a native C#/.NET 10 CLI backed by Microsoft UI Automation and Win32 SendInput. It preserves the stateless schema-version-2 verbs, JSON keys, exit codes, command risk classifications, AX-style roles, and guarded draft checks used by Sapiens4. The Swift/macOS implementation remains available unchanged.

## Build and run

Requires Windows 10/11 and .NET SDK 10 to build. Published packages include the runtime and require no administrator access or WSL.

```powershell
git clone https://github.com/fatmahalqaisi-code/blindly4.git
cd blindly4
.\windows\build.ps1 -Runtime win-arm64 # or win-x64
.\.build\windows\blindly4.exe --self-test
.\.build\windows\blindly4.exe schema
.\.build\windows\blindly4.exe apps
.\.build\windows\blindly4.exe show --pid 1234 --depth 6
```

All regular commands are supported: apps, activate, open, tree, show, find, focused, inspect, actions, focus, press, show-menu, scroll-to, set-value, set-selected-text, click, type, paste, scroll and key. `request-permission` explains Windows' access model; it never elevates the process or changes system permissions.

Paths begin at a synthetic `AXApplication` root. Its children (`0`, `1`, …) are visible top-level windows, sorted by handle; descendants use UI Automation's Control View. Rediscover paths immediately before mutation. Password values are never returned. `--profile` writes invocation timing only to stderr. Traversals are bounded and inaccessible or disappeared controls report errors.

Use `--pid` for input. Input requires the intended foreground process; coordinate clicks and wheel events also verify the app under the pointer. Windows may refuse to activate a background app; this fails closed. `command`/`cmd` key modifiers map to Ctrl on Windows. `delete` retains the macOS CLI's backward-delete meaning; use `forward-delete` for the Windows Delete key. Scroll amounts count wheel ticks and obey the user's Windows scroll settings.

Guarded paste requires a writable ValuePattern and verifies that exact control's value. Guarded key additionally checks focus and foreground PID. Guarded press checks only the specified draft control, not matching text elsewhere in a window. Unicode canonical normalization and directionality handling preserve the macOS matching rules. Focus/identity failures stop input. Clipboard formats are saved and restored unless another application changes the clipboard during the paste. Success indicates verified preconditions and local action, not external delivery.

UIA capability differences are explicit: `show-menu` requires ExpandCollapsePattern; `scroll-to` requires ScrollItemPattern; `set-value` and guarded editing require writable ValuePattern. Providers exposing only read-only TextPattern cannot satisfy a guarded draft operation. Elevated apps, other sessions and the Windows secure desktop are outside the supported target set.

## Validation

`--self-test` is permission-free and tests parsing, Unicode matching, URL/path validation, command metadata and fail-closed draft conditions.

On an unlocked interactive Windows desktop, run:

```powershell
.\.build\windows\blindly4.exe --integration-test
```

This opens a harmless local WinForms fixture, executes real CLI subprocesses against its accessibility tree, checks Unicode input and guarded submission, verifies rejected operations, then closes the fixture. It temporarily uses foreground focus and restores clipboard data. Do not use the desktop concurrently. It sends no messages to external services. CI builds native x64 and ARM64 packages and runs permission-free checks; live UI validation is an explicit local step.

Architecture: `CLI/` owns parsing, metadata, safety rules and checks; `Accessibility/` owns UIA nodes and traversal; `Input/` owns Win32/clipboard events. `Program.cs` is the entrypoint. Run both Windows checks after changing input or safety behavior; preserve the macOS Swift self-test in macOS CI.
