# Test 2: Telegram Lite — Contact Search & Message Send

**Status: PASS (with heavy workarounds)**

**Objective:** Find contact @alexipu, open chat, send message "это тест агента от блайндли". Test snapshot/changes for monitoring.

**Blindy commands tested:** `activate`, `show`, `find`, `inspect`, `click`, `type`, `paste`, `key`, `snapshot`, `changes`

## Steps & Results

| Step | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| 1 | `activate --pid 56688` | Telegram comes to front | OK | PASS |
| 2 | `show --depth 6` | See Telegram UI | Only menu bar visible — no window, no content | FAIL |
| 3 | `key --key command+k` | Open search | Opened "Create Link" dialog instead | FAIL |
| 4 | `key --key escape` | Close dialog | AX tree disappeared entirely | PARTIAL |
| 5 | `click --x 250 --y 63` | Activate sidebar search | Global search opened, AX tree appeared | PASS |
| 6 | `type --text 'alexipu'` | Search query entered | Text entered (visually), AX value remained empty | PARTIAL |
| 7 | `key --key down` + `key --key return` | Select first result, open chat | Chat "اليكسي \| AŁĘXÌ" opened | PASS |
| 8 | `snapshot --name before-msg` | Store chat state | 25 elements captured | PASS |
| 9 | `click --x 800 --y 948` + `paste --text '...'` | Enter message | Text entered, "Send" button appeared (was "Record Voice Message") | PASS |
| 10 | `press --path 0.16 --expect-description Send` | Send message | Failed — description field doesn't match, path unstable | FAIL |
| 11 | `key --key return` (workaround) | Send message | Message sent, "Record Voice Message" returned | PASS |
| 12 | `changes --since before-msg` | Show new elements | Failed — snapshot lost in --no-service mode | FAIL |

## Critical Finding: Telegram Lite AX Behavior

Telegram Lite uses **custom rendering** (Metal/Core Graphics) and exposes AX elements **only when specific UI components are active**:

- **Default state:** Only AXMenuBar visible. No AXWindow, no content.
- **After click on input area:** Window and all buttons appear temporarily.
- **After Escape/unfocus:** AX tree disappears again.
- **Text field values:** Always empty string regardless of actual content.
- **Search results:** Buttons with no title, no description, no children.

This means the agent must:
1. Click to "wake up" the AX tree before reading
2. Navigate search results blindly (by position, not by content)
3. Verify state indirectly (e.g., "Send" button appearing = text was entered)

## Issues Found

| # | Issue | Severity | Category |
|---|-------|----------|----------|
| 1 | Telegram Lite AX tree invisible by default | CRITICAL | App limitation |
| 2 | AX text field values always empty | HIGH | App limitation |
| 3 | Search results have no accessible labels | HIGH | App limitation |
| 4 | `snapshot`/`changes` incompatible with `--no-service` | HIGH | Blindy bug/design |
| 5 | Service process lacks Accessibility permission (deadlock with snapshot) | HIGH | Deployment issue |
| 6 | `--expect-description` doesn't match title field | MEDIUM | Blindy UX |
| 7 | AX paths change between every read | HIGH | App limitation + timing |
| 8 | `key --key command+k` — Telegram interprets as "Create Link", not search | LOW | App-specific |

## Workarounds Applied

- **AX tree invisible** → `click` on any interactive area to wake it up
- **No search content** → navigate results with `key --key down` + `key --key return` (blind navigation)
- **No text verification** → infer from "Send" button appearing (indirect signal)
- **`press` with `--expect-description` failed** → used `key --key return` instead
- **`snapshot`/`changes` lost** → not possible in `--no-service` mode

## Recommendations

### For AGENTS.md (coding agent guidance)
- For apps with custom rendering (Telegram, Electron apps): always click to activate before reading AX tree
- Use indirect signals for verification (button label changes, element count changes)
- For search: type query + use arrow keys + Enter, don't try to read result labels
- For sending messages: `paste` + `key --key return` is more reliable than `press` with safety guards
- `snapshot`/`changes` only work with the service — ensure service has Accessibility permission before using them
- Know your keyboard shortcuts per app: Cmd+K in Telegram = Create Link, not search

### For blindly developers
- **Critical:** `snapshot`/`changes` silently succeed in `--no-service` mode but data is lost. Either error or warn.
- Add `--expect-title` as alternative to `--expect-description` for `press` command
- Consider adding a `wait-for --role AXTextField --timeout 2` mechanism
- Document that `--no-service` mode breaks stateful commands (snapshot/changes)
- Consider exposing service permission status in `apps` or `schema` output
