# Agent guide

## Purpose

blindly4 has a macOS Swift implementation and a Windows C# implementation for reading and operating the accessibility
tree. It does not control VoiceOver. Most commands return JSON so programs and coding
agents can consume them safely.

## Build and validation

For Windows, read `windows/README.md`, build with `windows/build.ps1`, and run
`.build/windows/blindly4.exe --self-test`. Add permission-free coverage in
`windows/CLI/SelfTest.cs`. Input changes also require the explicit interactive
`--integration-test` against the bundled harmless fixture. The Swift instructions
below apply to the macOS implementation; retain its existing validation workflow.

Run these commands from the repository root:

```sh
swift build
swift run blindly4 --self-test
swift run blindly4 schema
```

The package requires macOS 13 or newer and Swift 6. Commands that inspect or operate
the AX tree also require Accessibility permission for the terminal or host process.
`--self-test` must not require that permission.

`--self-test` is the only automated gate, and it depends on nothing beyond the
package itself, so it runs anywhere the executable builds. Add coverage for new
parsing, traversal, normalization, or safety preconditions to
`Sources/blindly4/Support/SelfTest.swift`.

## How to run

Clone the repository into your coding agent's working folder. Prompt it:

```text
Using blindly4 only do:
open app {APP}, open section/chat with {WHAT}, do {THIS} and {THAT}
```

If automation is needed, do it every `{T}` minutes/hours.

## Architecture

- `Sources/blindly4/main.swift`: one-shot process entry point
- `Sources/blindly4/CLI/`: command registry, metadata, help, and command handlers
- `Sources/blindly4/Accessibility/`: live AX reads, tree traversal, and paths
- `Sources/blindly4/Input/`: application activation and synthetic keyboard/mouse input
- `Sources/blindly4/Support/`: parsing, errors, output, profiling, and self-tests

Commands are declared once in a `CommandGroup`. Keep their summary, risk,
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

Keep checks permission-free and inside `--self-test`. Accessibility integration
testing is manual because CI cannot inspect arbitrary desktop applications. When
changing UI operations, test against a harmless local target before trying a composer
or control with external effects.
