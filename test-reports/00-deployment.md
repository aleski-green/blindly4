# Test 0: Deployment & Setup

**Status: PARTIAL**

**Objective:** Build blindly4 from source, grant permissions, verify operational readiness.

## Steps & Results

| Step | Action | Expected | Actual | Status |
|------|--------|----------|--------|--------|
| 1 | `swift build -c release` | Binary built | Built successfully in ~42 seconds | PASS |
| 2 | `.build/release/blindy apps` | List running apps | Listed all GUI apps with PIDs and bundle IDs | PASS |
| 3 | `blindy request-permission` | Prompt for Accessibility access | Prompt appeared, `trusted: false` returned | PASS |
| 4 | Grant Terminal in System Settings → Accessibility | Commands work | Still failed — wrong process granted | FAIL |
| 5 | Grant Claude (desktop app) in System Settings → Accessibility | Commands work | Still failed — Claude desktop app is not the executing process | FAIL |
| 6 | Identify actual process chain | Understand who needs permission | `Terminal (692) → login → zsh → claude (65680)` — permission needed for Terminal, but service process is separate | PARTIAL |
| 7 | `blindy activate --pid 672` | Activate Chrome | Error 77: Accessibility not enabled | FAIL |
| 8 | `blindy --no-service activate --pid 672` | Activate Chrome bypassing service | Success — direct invocation works | PASS |
| 9 | All subsequent tests with `--no-service` | Commands work | Work, but stateful commands (snapshot/changes) broken | PARTIAL |

## Issues Found

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | Unclear which process needs Accessibility permission | HIGH | README says "enable your terminal" but the actual process hierarchy matters. Claude Code runs as `Terminal → login → zsh → claude`, and permission must be granted to **Terminal.app**, not the `claude` binary or Claude desktop app. |
| 2 | Service process runs as daemon (PPID 1) — separate from terminal | HIGH | The blindy service spawns as a background daemon. It does NOT inherit Accessibility permission from the terminal that launched it. This is never documented. |
| 3 | `--no-service` workaround breaks stateful features | HIGH | Using `--no-service` bypasses the permission issue but `snapshot` and `changes` silently lose data (stored in per-process memory that dies on exit). |
| 4 | No diagnostic for permission status | MEDIUM | No command like `blindy check-permission` or `blindy doctor` to verify setup is correct. `request-permission` only triggers the OS prompt. |
| 5 | Build time ~42 seconds | LOW | Acceptable for one-time setup, but no pre-built binary available. |
| 6 | No install command | LOW | README shows `swift build` but doesn't include `cp .build/release/blindy /usr/local/bin/` in the quick-start. Binary stays in `.build/` unless manually copied. |

## Permission Grant Flow (What Actually Happened)

```
Attempt 1: Granted "Terminal" in Accessibility settings
  → blindy activate → Error 77
  → Why: Service process (PPID 1) is not Terminal

Attempt 2: Granted "Claude" (desktop app) in Accessibility settings
  → blindy activate → Error 77
  → Why: Claude desktop app ≠ the claude CLI process

Attempt 3: Used --no-service flag
  → blindy --no-service activate → Success
  → Why: Direct invocation runs under Terminal's process tree,
          which HAS Accessibility permission
  → Tradeoff: snapshot/changes broken (no shared memory)
```

## What the README Says vs Reality

| README | Reality |
|--------|---------|
| "Enable your terminal in System Settings → Accessibility" | Terminal permission is necessary but not sufficient — service process is separate |
| `blindy request-permission` then enable terminal | `request-permission` triggers OS prompt but doesn't indicate WHICH process to enable |
| Snapshot/changes examples work seamlessly | Only work with the service, which may not have permission |
| No mention of `--no-service` for permission workaround | `--no-service` is the only way to run if service lacks permission |

## Recommendations

### For README / AGENTS.md
- Add a "Troubleshooting permissions" section explaining:
  - Which process needs permission depends on how blindly is launched
  - Service process (daemon) needs SEPARATE permission grant
  - `--no-service` as a workaround, with its limitations
- Add a `blindy doctor` or `blindy check-setup` command description
- Add explicit install step: `cp .build/release/blindy /usr/local/bin/`

### For blindly developers
- **Add `blindy doctor` command** — checks: binary exists, Accessibility granted, service running, service has permission
- **Surface service permission status** in `blindy apps` or `blindy schema` output
- **Warn on `snapshot`/`changes` in `--no-service` mode** — currently silently "succeeds"
- **Consider service permission inheritance** — launch service from the permitted terminal process tree instead of daemonizing
- **Add pre-built binaries** to GitHub releases for faster onboarding
