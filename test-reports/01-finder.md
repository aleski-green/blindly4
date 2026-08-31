# Test 1: Finder — File Operations

**Status: PARTIAL**

**Objective:** Navigate a native macOS app, use context menu, create and rename a folder.

**Blindy commands tested:** `apps`, `activate`, `show`, `find`, `inspect`, `actions`, `show-menu`, `press`, `click`, `type`, `key`

## Steps & Results

| Step | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| 1 | `activate --pid 703` | Finder comes to front | OK | PASS |
| 2 | `show --depth 5` | See Desktop files | All files listed with paths and titles | PASS |
| 3 | `actions --path 2.0` | Show available actions | `AXShowMenu` returned | PASS |
| 4 | `show-menu --path 2.0` | Context menu opens | Error -25204 | FAIL |
| 5 | `key --key command+shift+n` (workaround) | New folder created | Folder "untitled folder" created | PASS |
| 6 | `find --title 'untitled folder'` | Folder found | Found at path 3.0.55, selected: true | PASS |
| 7 | `click` + `key --key return` | Rename field appears | AXTextField appeared once, but inconsistently | PARTIAL |
| 8 | `key --key command+a` + `type --text 'blindy-test-folder'` | Name entered | Text did not land in field — rename failed | FAIL |
| 9 | `open --url 'file:///...'` | Open folder in Finder | Rejected: only http/https/slack supported | FAIL |

## Issues Found

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1 | `show-menu` fails on Finder Desktop elements | HIGH | Error -25204 on AXShowMenu. Consistent across multiple attempts on Desktop AXImage and AXGroup elements. |
| 2 | `focused` returns "No focused element" | MEDIUM | Even when a text field is visually active, `focused` command returns error. |
| 3 | `type` does not land in focused text field | HIGH | System-wide keystroke injection appears to lose target between commands. The rename field closes or loses focus before `type` executes. |
| 4 | `open --url` does not support `file://` | MEDIUM | Only http, https, and slack URLs accepted. Cannot open local folders/files through blindy. |
| 5 | AX paths unstable between calls | HIGH | Window indices shift between invocations (e.g., folder at path 3.0.55, then 2.0.55, then 5.0.55). |
| 6 | No timing/wait mechanism | HIGH | No way to wait for an element to appear (e.g., rename field) before acting on it. Sequential commands fire too fast. |

## Workarounds Applied

- **Context menu failed** → used keyboard shortcut `key --key command+shift+n` instead
- **`type` failed for rename** → renamed via shell `mv` command
- **`open --url file://` failed** → used macOS `open` command from shell

## Recommendations

### For AGENTS.md (coding agent guidance)
- Always re-discover paths with `find` immediately before any mutation
- Prefer keyboard shortcuts over context menus in Finder
- For text input into native fields, try `set-value` before falling back to `type`
- Use shell commands (`open`, `mv`) as fallbacks for file operations blindy cannot handle

### For blindy developers
- Investigate AXShowMenu error -25204 on Finder Desktop elements
- Add `file://` URL support to `open --url`
- Consider adding a `wait-for` or `--poll` mechanism to wait for an element to appear
- Consider adding a `--delay` option for sequential command timing
