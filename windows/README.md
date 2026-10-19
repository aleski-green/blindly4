# Blindly4 on Windows

The Windows implementation is a native Rust CLI backed by Microsoft UI Automation and Win32 SendInput through Microsoft's `windows` crate. It preserves the stateless schema-version-2 verbs, JSON keys, exit codes, command risk classifications, AX-style roles, and guarded draft checks used by Sapiens4. The macOS implementation also uses Rust with Apple Accessibility; both platforms are tested through RSpec.

## Build and run

Requires Windows 10/11, stable Rust (edition 2024), and Visual Studio C++ Build Tools with the Windows SDK to build with the default MSVC toolchain. Install the C++ tools for the target architecture. The executable requires no separately installed language runtime, administrator access, or WSL.

```powershell
git clone https://github.com/fatmahalqaisi-code/blindly4.git
cd blindly4
rustup target add aarch64-pc-windows-msvc # x86_64-pc-windows-msvc for win-x64
.\windows\build.ps1 -Runtime win-arm64 # or win-x64
.\.build\windows\blindly4.exe schema
.\.build\windows\blindly4.exe apps
.\.build\windows\blindly4.exe show --pid 1234 --depth 6
```

The default build selects the host architecture; `-Runtime` selects explicitly. For development without MSVC, install the matching `*-pc-windows-gnullvm` Rust toolchain and LLVM-MinGW, add its `bin` directory to `PATH`, and pass `-Toolchain gnullvm`. Both toolchains statically link their C/unwind runtime. CI validates MSVC packages on native x64 and ARM64 runners.

All regular commands are supported: apps, activate, open, tree, show, find, focused, inspect, actions, focus, press, show-menu, scroll-to, set-value, set-selected-text, click, type, paste, scroll and key. `request-permission` explains Windows' access model; it never elevates the process or changes system permissions.

Paths begin at a synthetic `AXApplication` root. Its children (`0`, `1`, …) are visible top-level windows, sorted by handle; descendants use UI Automation's Control View. Rediscover paths immediately before mutation. Password values are never returned. `--profile` writes invocation timing only to stderr. Traversals are bounded and inaccessible or disappeared controls report errors.

Use `--pid` for input. Input requires the intended foreground process; coordinate clicks and wheel events also verify the app under the pointer. Windows may refuse to activate a background app; this fails closed. `command`/`cmd` key modifiers map to Ctrl on Windows. `delete` retains the macOS CLI's backward-delete meaning; use `forward-delete` for the Windows Delete key. Scroll amounts count wheel ticks and obey the user's Windows scroll settings.

Guarded paste requires a writable ValuePattern and verifies that exact control's value. Guarded key additionally checks focus and foreground PID. Guarded press checks only the specified draft control, not matching text elsewhere in a window. Unicode canonical normalization and directionality handling preserve the macOS matching rules. Focus/identity failures stop input. Clipboard formats are copied before editing and restored unless another application changes the clipboard during the paste. Owner-managed private formats or formats that cannot be copied cause a pre-input failure; they are never silently discarded. Success indicates verified preconditions and local action, not external delivery.

UIA capability differences are explicit: `show-menu` requires ExpandCollapsePattern; `scroll-to` requires ScrollItemPattern; `set-value` and guarded editing require writable ValuePattern. Providers exposing only read-only TextPattern cannot satisfy a guarded draft operation. Elevated apps, other sessions and the Windows secure desktop are outside the supported target set.

## Validation

All tests use RSpec to execute the compiled binary and observe its behavior. Install Ruby 3.4 and Bundler, then run from the repository root:

```powershell
bundle install
bundle exec rspec
```

The default suite checks the public schema, help, errors, argument validation, and profiling without desktop access. From `windows/`, also run the static checks `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings`. No unit tests or embedded self-test runners remain.

On an unlocked interactive Windows desktop, run:

```powershell
$env:BLINDLY4_LIVE = '1'
bundle exec rspec
Remove-Item Env:BLINDLY4_LIVE
```

RSpec opens a fresh harmless Win32 fixture for each desktop scenario, executes real CLI subprocesses against its accessibility tree, checks Unicode input and guarded submission, verifies rejected operations and password redaction, and closes the fixture even after a failure. It temporarily uses foreground focus and restores clipboard data. Do not use the desktop concurrently. It sends no messages to external services. CI builds native x64 and ARM64 packages and runs the permission-free RSpec suite; live UI validation is an explicit local step. See [test coverage and configuration](../spec/README.md).

Architecture: `src/main.rs` is the entry point; `registry.rs`, `invocation.rs` and `guards.rs` own the CLI contract; `desktop.rs` and `node.rs` own UIA traversal; `native.rs`, `input.rs` and `clipboard.rs` own Win32 input and resource lifetimes. `fixture.rs` supplies only the harmless test window; all test orchestration and expectations live in `spec/`. Run both default and live RSpec suites after changing input or safety behavior.
