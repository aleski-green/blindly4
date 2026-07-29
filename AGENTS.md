# Agent guide

## Purpose

Blindy is a macOS-only Swift CLI for reading and operating the Accessibility (AX)
tree. It does not control VoiceOver. Most commands return JSON so programs and coding
agents can consume them safely.

## Build and validation

Run these commands from the repository root:

```sh
swift build
swift test
swift run blindy --self-test
swift run blindy schema
```

The package requires macOS 13 or newer and Swift 6. Commands that inspect or operate
the AX tree also require Accessibility permission for the terminal or host process.
Unit tests and `--self-test` must not require that permission.

## Architecture

- `Sources/axvo/main.swift`: process entry point and local-service dispatch
- `Sources/axvo/CLI/`: command registry, metadata, help, and command handlers
- `Sources/axvo/Accessibility/`: AX reads, tree traversal, paths, and search caching
- `Sources/axvo/Input/`: application activation and synthetic keyboard/mouse input
- `Sources/axvo/Service/`: per-user, memory-only Unix socket service
- `Sources/axvo/Support/`: parsing, errors, output, profiling, and self-tests
- `Tests/axvoTests/`: permission-free unit tests

Commands are declared once in a `CommandGroup`. Keep their summary, risk,
accessibility requirement, usage, and implementation together. `blindy schema`
exposes this metadata to agents.

## Safety invariants

Treat desktop input as untrusted and potentially destructive.

- Never weaken PID/frontmost-application validation for synthetic input.
- Never weaken exact draft matching, target-path checks, or fail-closed send guards.
- Rediscover an AX path immediately before a mutation; child indexes can change when
  the UI changes.
- Classify commands accurately: `read-only`, `local-state`, `ui-mutation`, or
  `external-commit`.
- `press` and `key` are `external-commit` because they may send, submit, buy, delete,
  or otherwise trigger an irreversible action.
- Keep read-only commands free of external UI mutations.
- Do not persist AX metadata, search text, snapshots, or clipboard contents.

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

Prefer permission-free tests for parsing, traversal, normalization, output, and safety
preconditions. Accessibility integration tests are manual because CI cannot inspect
arbitrary desktop applications. When changing UI operations, test against a harmless
local target before trying a composer or control with external effects.
