# Test 4: Cross-Application Workflow

**Status:** PASS

## Objective

Switch between multiple apps (Chrome, Finder, Telegram), read data from one app and use it in another.

## Steps and Results

1. `activate --pid 672` (Chrome) -- PASS. Chrome came to front.
2. Read Tab menu items -- found all tabs including "Isaac Asimov books list - Google Search". Tab menu (AXMenuItem) is the most reliable way to identify Chrome tabs. PASS.
3. `activate --pid 703` (Finder) -- PASS. Immediate switch.
4. `find --title 'blindly' --depth 10` in Finder -- found "blindly-test" folder at path 2.0.53. PASS.
5. `activate --pid 56688` (Telegram) -- PASS.
6. `activate --pid 672` (Chrome) back -- PASS.
7. Rapid switching test: Chrome -> Finder -> Telegram -> Chrome -- all 4 switches succeeded with correct app verification. PASS.
8. Cross-app data flow: used folder name from Finder step to construct Google search URL, opened via `open --url` in Chrome. PASS.

## Key Findings

- `activate` is the most reliable blindy command -- works consistently across all apps
- App switching is fast and deterministic
- Data extracted from one app (Finder file names, Chrome tab titles) can drive actions in another
- The main challenge is not switching but reading content within each app (AX tree instability)
- Tab menu items in Chrome provide the most stable way to identify open pages (vs unreliable AXWindow titles)

## Issues

| # | Issue | Severity |
|---|-------|----------|
| 1 | Chrome AXWindow elements appear/disappear unpredictably between reads | HIGH |
| 2 | No mechanism to pass clipboard data between apps via blindy (no "read clipboard" command) | MEDIUM |

## Recommendations

### For AGENTS.md

- Use `activate` confidently -- it is reliable across all tested apps
- For Chrome tab identification, read Tab menu items (path 0.8.0.x) -- more stable than AXWindow titles
- Cross-app workflows work best when data transfer uses URLs (`open --url`) rather than clipboard

### For Developers

- Consider adding a `frontmost` or `active-app` command to verify which app is currently in front
- Consider adding clipboard read/write commands for cross-app data transfer
