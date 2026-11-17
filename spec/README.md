# Tests

Install Lean from `lean-toolchain` and build the platform binary.

```sh
lake -d spec test
BLINDLY4_LIVE=1 lake -d spec test
```

The default suite needs no desktop permission. Live tests require an unlocked,
exclusive desktop and macOS Accessibility permission. Run them serially.
`BLINDLY4_BIN` selects the tested binary; `BLINDLY4_FIXTURE_BIN` selects fixtures.
`BLINDLY4_TEST_RESULTS` saves JSON results. `lake -d spec test -- --list` lists cases.

Windows live mode: `$env:BLINDLY4_LIVE='1'` before `lake -d spec test`.
For an installed composition WebView, also set `BLINDLY4_WEBVIEW_PID`,
`BLINDLY4_WEBVIEW_SEARCH_TITLE`, and `BLINDLY4_WEBVIEW_SEARCH_TEXT`; use a unique,
empty search field. The test never submits it.

Run `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` from each
platform directory. Input/safety changes require default and live tests.
Test public CLI behavior and native effects; do not add internal unit tests or self-test modes.
