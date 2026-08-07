# Test 5: Snapshot & Changes (Monitoring)

**Status:** FAIL

## Objective

Test `snapshot` and `changes` commands for monitoring UI state changes.

## Steps and Results

1. `snapshot --name before-msg --path 0 --depth 4` on Telegram -- appeared to succeed: "25 elements captured". PASS (misleading).
2. After sending message, `changes --since before-msg --path 0 --depth 4` -- FAIL. Error: "No in-memory snapshot named before-msg for this app and path".

## Root Cause

`snapshot` and `changes` store data in the blindy service process memory. With `--no-service` mode, each command runs in its own process -- the snapshot is created and immediately lost when the process exits. The `changes` command starts a new process that has no knowledge of the snapshot.

This creates a **deadlock**:

- `snapshot`/`changes` require the service (shared memory)
- The service process doesn't have Accessibility permission (it runs as a daemon with PPID 1)
- `--no-service` mode gives Accessibility access but loses snapshot state

## Issues

| # | Issue | Severity |
|---|-------|----------|
| 1 | `snapshot` silently "succeeds" in --no-service mode but data is immediately lost | CRITICAL |
| 2 | Service process lacks Accessibility permission -- separate from terminal permission | HIGH |
| 3 | No way to use snapshot/changes without the service | HIGH |
| 4 | No warning or error when using stateful commands in --no-service mode | HIGH |

## Recommendations

### For AGENTS.md

- Do NOT use `snapshot` or `changes` with `--no-service` -- they silently fail
- These commands require the service process to have Accessibility permission
- Alternative monitoring: compare `show` or `find` output between two reads manually

### For Developers

- CRITICAL: `snapshot` should error or warn when running in --no-service mode
- Document that stateful commands (snapshot, changes) are incompatible with --no-service
- Consider file-based snapshot storage as alternative to in-memory service storage
- Consider adding service permission status to `apps` or `schema` output
- Grant Accessibility permission to the blindy binary itself, not just the terminal
