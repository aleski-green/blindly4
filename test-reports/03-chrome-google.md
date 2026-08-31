# Test 3: Chrome/Google — Web Form Input

**Status: PARTIAL**

**Objective:** Navigate Google search, interact with search form, read search results through AX tree.

**Blindy commands tested:** `activate`, `show`, `find`, `open`, `key`, `type`, `inspect`

## Steps & Results

| Step | Command | Expected | Actual | Status |
|------|---------|----------|--------|--------|
| 1 | `activate --pid 672` | Chrome comes to front | Chrome activated | PASS |
| 2 | `open --url 'https://www.google.com'` | Google homepage loaded | Google loaded | PASS |
| 3 | `find --role AXTextField --depth 20` | Google search field found | Only Chrome Help menu search found, NOT Google's search field | FAIL |
| 4 | `key --key command+l` + `type --text 'Isaac Asimov books list'` | Text entered into address bar | 23 chars typed but text didn't land in address bar. Address bar still showed "google.com" | FAIL |
| 5 | `open --url 'https://www.google.com/search?q=...'` (workaround) | Search results loaded | Window title confirmed: "Isaac Asimov books list - Google Search" | PASS |
| 6 | `find --role AXHeading --depth 25` | Headings found in web content | No headings found | FAIL |
| 7 | `find --role AXLink --depth 25` | Links found in web content | No links found | FAIL |
| 8 | `find --role AXWebArea --depth 20` | Web area found | Web area not found at all | FAIL |
| 9 | `find --role AXButton --depth 10` | Buttons found | Native Chrome buttons found (Back, Forward, "Search or type URL", New tab) | PASS |

## Critical Finding: Chrome Web Content Is Invisible to AX

Chrome's native UI controls (toolbar, tabs, navigation buttons) are fully accessible through the Accessibility API. However, web page content (DOM elements like links, headings, text fields, search boxes) is completely opaque. The AX tree stops at Chrome's native frame and does not expose any of the rendered web content.

This is consistent across YouTube (Test 0) and Google Search (Test 3), indicating a systemic limitation rather than a page-specific issue.

**What IS accessible:**
- Navigation buttons (Back, Forward, Reload)
- Address bar ("Search or type URL")
- Tab strip (tab titles, New Tab button)
- Chrome menus (File, Edit, View, etc.)
- Bookmarks bar items

**What is NOT accessible:**
- Any DOM element (links, headings, paragraphs, images)
- Web form inputs (search boxes, text fields, checkboxes)
- AXWebArea container itself
- Any content rendered by the web page

## Issues Found

| # | Issue | Severity | Category |
|---|-------|----------|----------|
| 1 | Chrome web content completely invisible to AX tree | CRITICAL | Browser limitation |
| 2 | `type` after `key --key command+l` didn't land in address bar | HIGH | Timing / focus race |
| 3 | AX paths for Chrome windows unstable between calls | HIGH | App limitation |
| 4 | Chrome windows sometimes don't appear in tree (require re-activate) | MEDIUM | App limitation |

## Workarounds Applied

- **Web content invisible** → use `open --url` with fully constructed URLs instead of navigating via UI
- **Address bar typing failed** → use `open --url` to navigate directly (bypass address bar entirely)
- **Cannot read page content** → verify page state via window title (most reliable signal available)
- **Chrome-native actions** → use `key` with shortcuts (Cmd+L for address bar, Cmd+T for new tab, Cmd+W to close tab)
- **Web form input needed** → fall back to coordinate-based `click` + `type`/`paste`

## Recommendations

### For AGENTS.md (coding agent guidance)
- Chrome web content is NOT accessible via AX tree — use `open --url` for all navigation
- Never rely on reading web page content (links, headings, text) from Chrome
- Native Chrome controls (toolbar, tabs, bookmarks bar) ARE accessible
- For web form input: use `click` on known coordinates + `type`/`paste`
- Window title is the most reliable way to verify page state in Chrome
- Construct search queries as URL parameters (e.g., `https://www.google.com/search?q=...`) rather than trying to type into search boxes

### For blindly developers
- Document Chrome web content AX limitation prominently in user-facing docs
- Consider integration with Chrome DevTools Protocol (CDP) as an alternative channel for web content accessibility
- Investigate why `type` after `key --key command+l` fails — likely a timing or focus race condition between the key event and the subsequent type command
- Consider adding a `--focus-wait` or `--delay` option to allow UI to settle between sequential commands
