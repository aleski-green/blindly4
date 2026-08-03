# Agent guide

## Purpose

Blindy is a macOS-only Swift CLI for reading and operating the Accessibility (AX)
tree. It does not control VoiceOver. Most commands return JSON so programs and coding
agents can consume them safely.

## Build and validation

Run these commands from the repository root:

```sh
swift build
swift run blindy --self-test
swift run blindy schema
```

The package requires macOS 13 or newer and Swift 6. Commands that inspect or operate
the AX tree also require Accessibility permission for the terminal or host process.
`--self-test` must not require that permission.

`--self-test` is the only automated gate, and it depends on nothing beyond the
package itself, so it runs anywhere the executable builds. Add coverage for new
parsing, traversal, normalization, or safety preconditions to
`Sources/axvo/Support/SelfTest.swift`.

## Architecture

- `Sources/axvo/main.swift`: process entry point and local-service dispatch
- `Sources/axvo/CLI/`: command registry, metadata, help, and command handlers
- `Sources/axvo/Accessibility/`: AX reads, tree traversal, paths, and search caching
- `Sources/axvo/Input/`: application activation and synthetic keyboard/mouse input
- `Sources/axvo/Service/`: per-user, memory-only Unix socket service
- `Sources/axvo/Support/`: parsing, errors, output, profiling, and self-tests

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
- Compact snapshot-and-path session logging is enabled by default. Discovery snapshots
  are unredacted and may contain AX metadata, search text, text values, URLs, and other
  visible private text; later command events contain only metadata and AX paths. They are
  written to `.logs/` at the package root and must remain gitignored. Set
  `BLINDY_LOG_MODE=full` only when the legacy full plaintext format is required.
- Use `--no-log` to omit one command from the session log, or start Blindly with
  `BLINDY_NO_LOG=1` to disable logging for the whole service process.
- Search caches and named AX snapshots remain memory-only. They are distinct from
  audit discovery snapshots written by the session logger.

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
