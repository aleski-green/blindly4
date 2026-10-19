# Agent guide

## Purpose

blindly4 has native macOS and Windows Rust implementations for reading and operating the accessibility
tree. It does not control VoiceOver. Most commands return JSON so programs and coding
agents can consume them safely.

## Build and validation

All tests must be RSpec behavioral tests of the compiled CLI. Read `spec/README.md`.
Do not add Rust unit tests, internal-function assertions, mocks, or embedded
self-test runners. Build with `windows/build.ps1` on Windows or `macos/build.sh debug` on
macOS, then run from the repository root:

```sh
bundle install
bundle exec rspec
```

Tests require Ruby 3.4 and Bundler. Static checks are `cargo fmt --check` and
`cargo clippy --all-targets -- -D warnings` from each platform directory.
Desktop input changes also require `BLINDLY4_LIVE=1 bundle exec rspec` on an
unlocked interactive desktop (set the environment variable using PowerShell on
Windows). This runs the harmless fixture through real CLI subprocesses.

The macOS package requires macOS 13 or newer, stable Rust, and Xcode Command Line Tools. Commands that inspect or
operate the AX tree also require Accessibility permission for the terminal or host
process. Default RSpec checks must not require that permission.

## How to run

Clone the repository into your coding agent's working folder. Prompt it:

```text
Using blindly4 only do:
open app {APP}, open section/chat with {WHAT}, do {THIS} and {THAT}
```

If automation is needed, do it every `{T}` minutes/hours.

## Architecture

- `shared/`: command engine, key grammar, validation, activation, traversal, control policies, and JSON assembly
- `adapters/mod.rs`: compile-time platform selection; shared code must contain no OS branches
- `macos/src/`: macOS adapter, AX/AppKit/Quartz operations, clipboard, and fixture
- `windows/src/`: Windows adapter, UI Automation/Win32 operations, clipboard, and fixture

Adapters provide native properties, identity, capabilities, and operations. Keep writable-control,
secure-value, exact-draft, and key-syntax rules in the shared layer; do not duplicate them per OS.
- `spec/`: shared CLI and platform desktop behavior, all in RSpec

Commands are declared once in `shared/registry.rs`. Keep their summary, risk,
accessibility requirement, usage, and implementation together. `blindly4 schema`
exposes this metadata to agents.

## Safety invariants

Treat desktop input as untrusted and potentially destructive.

- Never weaken PID/frontmost-application validation for synthetic input.
- Never weaken exact draft matching, target-path checks, or fail-closed send guards.
- Rediscover an AX path immediately before a mutation; child indexes can change when
  the UI changes.
- Classify commands accurately: `read-only`, `ui-mutation`, or
  `external-commit`.
- `press` and `key` are `external-commit` because they may send, submit, buy, delete,
  or otherwise trigger an irreversible action.
- Keep read-only commands free of external UI mutations.
- Keep execution stateless across invocations: no service, cache, named snapshots,
  workflow leases, or file logging. Profiling is invocation-local stderr only.
- The caller must serialize whole desktop workflows; removing Blindly's lease does
  not make concurrent input safe. Keep Sapiens4's host-level computer ownership.
- Existing `.logs/` files must remain gitignored; removing logging does not authorize
  deleting users' prior logs.

Changes to these invariants require explicit review and focused tests.

## CLI and output contracts

- Successful structured commands write JSON to stdout.
- Usage errors exit 64; Accessibility/permission failures exit 77; unexpected errors
  exit 1.
- Profiling data goes to stderr.
- Reject unknown options instead of silently ignoring them.
- Preserve existing JSON keys unless the change is deliberately versioned.
- Increment `schemaVersion` when the machine-readable schema changes incompatibly.

## Testing changes

Keep default RSpec examples permission-free. Mark desktop scenarios with
`:macos, :live` or `:windows, :live`; they require the explicit `BLINDLY4_LIVE=1` opt-in. Assert visible
behavior and absence of side effects after rejected input. CI runs the default
RSpec suite on every supported platform. Run live scenarios locally after changing
UI operations, against the harmless fixture before trying a composer or control
with external effects.
