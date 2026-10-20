# Agent guide

Read [usage/safety](README.md#safe-operation), [validation](spec/README.md) and [contribution requirements](CONTRIBUTING.md). Never weaken PID/frontmost, identity, exact-draft or fail-closed guards. Safety changes require explicit review and focused tests.

## Architecture

- `shared/`: CLI, validation, keys, activation, traversal, policies, guarded input, JSON; no OS branches.
- `adapters/mod.rs`: compile-time selection of `macos/src/` or `windows/src/` native properties, identity, capabilities, operations and fixtures.
- `shared/registry.rs`: single command declaration: summary, risk, permission, usage, handler; exposed by `schema`.

Keep writable-control, secure-value, exact-draft and key-syntax policies shared; do not duplicate per OS.

## Contracts

- Preserve `read-only`, `ui-mutation`, `external-commit` classifications and README safety/statelessness rules. Keep `.logs/` gitignored; never delete prior logs.
- Structured success: stdout JSON; profiling: stderr. Exit 64: usage; 77: access/permission; 1: unexpected. Reject unknown options. Preserve JSON keys; incompatible changes increment `schemaVersion`.
- Follow the linked RSpec validation requirements before reporting completion.
- Follow root `rustfmt.toml`: compact expressions within 140 columns.
