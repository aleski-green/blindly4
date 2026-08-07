# Blindly4 Test Summary

**Date:** 2026-08-01
**Tester:** Claude Code (Opus 4.6) + human operator
**Environment:** macOS 14, Google Chrome, Finder, Telegram Lite
**Mode:** `--no-service` (service process lacked Accessibility permission)

## Test Matrix

| # | Test | App | Status | Key Finding |
|---|------|-----|--------|-------------|
| D | Deployment & Setup | — | PARTIAL | Service permission deadlock, `--no-service` workaround |
| 0 | YouTube video search | Chrome | PASS | `open --url` is the reliable way to navigate web |
| 1 | File operations | Finder | PARTIAL | Folder created, rename via AX failed |
| 2 | Contact search + message | Telegram Lite | PASS* | Heavy workarounds — app barely exposes AX |
| 3 | Web form input | Chrome | PARTIAL | Native controls work, web content invisible |
| 4 | Cross-app switching | Chrome/Finder/Telegram | PASS | `activate` is fast and reliable |
| 5 | Snapshot/Changes | Telegram | FAIL | Incompatible with `--no-service` mode |

*With workarounds

## Command Reliability Matrix

| Command | Reliability | Notes |
|---------|------------|-------|
| `apps` | HIGH | Always works correctly |
| `activate` | HIGH | Most reliable command across all apps |
| `open --url` | HIGH | Works for http/https/slack, not file:// |
| `show` | MEDIUM | Output varies between calls, windows appear/disappear |
| `find` | MEDIUM | Works when AX tree is populated, empty for hidden apps |
| `key` | MEDIUM | Keystroke lands but target uncertain without `--pid` verification |
| `click` | MEDIUM | Coordinate-based, works but no content verification |
| `type` | LOW | System-wide, often misses target field |
| `paste` | MEDIUM | More reliable than `type` for text input |
| `press` | LOW | Path instability makes targeting unreliable |
| `show-menu` | LOW | Fails on Finder Desktop elements (error -25204) |
| `set-value` | UNTESTED | Not reached due to path instability |
| `inspect` | LOW | Paths change between `find` and `inspect` calls |
| `focused` | LOW | Often returns "no focused element" |
| `snapshot` | BROKEN | Silently loses data in `--no-service` mode |
| `changes` | BROKEN | Cannot find snapshots created in `--no-service` mode |

## Top Issues by Severity

### CRITICAL
1. **`snapshot`/`changes` silently fail in `--no-service` mode** — Data created and immediately lost. No warning.
2. **Chrome web content invisible to AX** — Links, headings, text fields in web pages are not accessible.
3. **Service vs permission deadlock** — Service needs AX permission but runs as daemon (PPID 1) separate from terminal.

### HIGH
4. **AX paths unstable between reads** — Elements shift indices, making path-based targeting unreliable.
5. **`type` doesn't land in focused fields** — System-wide keystroke injection loses target between commands.
6. **`show-menu` fails on Finder Desktop** — Error -25204 consistently.
7. **Telegram Lite AX tree invisible by default** — Custom rendering, elements only appear on interaction.
8. **No timing/wait mechanism** — Cannot wait for an element to appear before acting.

### MEDIUM
9. **`open --url` doesn't support `file://`** — Cannot open local files/folders.
10. **`--expect-description` doesn't match `title` field** — Need `--expect-title` alternative.
11. **`focused` unreliable** — Often returns no element even when one is visually focused.

## Working Patterns (for AGENTS.md)

### Reliable
- `activate --pid` → `open --url` for browser navigation
- `activate --pid` → `click` → `paste` → `key --key return` for messaging
- Tab menu items (`0.8.0.x`) for Chrome tab identification
- `key` with keyboard shortcuts (Cmd+Shift+N, Cmd+L, etc.)
- Indirect verification (button label changes, window title changes)
- `apps` for PID discovery

### Unreliable — Avoid
- `show` → `inspect` chains (paths shift between calls)
- `type` into text fields (use `paste` or `set-value` instead)
- `press` without immediate prior `find` (stale path)
- `show-menu` on Finder Desktop elements
- `snapshot`/`changes` in `--no-service` mode
- Reading web content from Chrome (headings, links, text)

## Async Agent Coordination (Experimental)

During testing, we used a cooperative async model:
- **Main agent** held the "blindy lock" — performed all UI interactions
- **Background agents** wrote reports in parallel (no blindy access needed)
- This improved throughput: UI testing and report writing overlapped

See `00-questions-and-ideas.md` for the full async coordination proposal.

## Deployment Issues

1. **Build:** `swift build -c release` works but takes ~42 seconds
2. **Accessibility permission:** Must be granted to the specific process running blindy, not just "Terminal"
   - Claude Desktop app needed separate permission
   - Service process (daemon) doesn't inherit terminal permission
3. **`--no-service` required:** Workaround for permission issue, but breaks stateful commands

## Files

- `00-deployment.md` — Deployment & setup test report
- `00-questions-and-ideas.md` — Open questions and feature ideas
- `01-finder.md` — Finder test report
- `02-telegram.md` — Telegram Lite test report
- `03-chrome-google.md` — Chrome/Google test report
- `04-cross-app.md` — Cross-application test report
- `05-monitoring.md` — Snapshot/Changes test report
