# Agent guide

Read [safe operation](README.md#safe-operation), [tests](spec/README.md) and
[contribution requirements](CONTRIBUTING.md).

- `shared/` owns CLI, validation, traversal, guards and JSON; no OS branches.
- `adapters/mod.rs` selects native platform implementations.
- `shared/registry.rs` declares commands, options, permissions and risks.
- Preserve PID/frontmost, identity, exact-draft and fail-closed guards.
  Safety changes require explicit review and focused tests.
- Provider PIDs may differ from window owners. Optional metadata may be absent.
  Retain native target identity when sibling indexes change.
- Preserve read-only/UI-mutation/external-commit classifications and schema contracts.
- Use the [Lean behavioral suite](spec/README.md); follow `rustfmt.toml`.
- Keep `.logs/` ignored; never delete prior logs.
