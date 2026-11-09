# Linux X11 driver

Build with `linux/build.sh release`. The Rust driver uses AT-SPI over D-Bus and
requires an X11 desktop session. GNOME is not required. Wayland sessions are
rejected, including those with an Xwayland display; schema and permission
status remain available without desktop access.

Foreground and pointer ownership use XRes PIDs, EWMH and XTest. Actions retain
PID, identity, focus and exact-draft checks. Clipboard access is unsupported.
Secure-value protection depends on providers declaring password roles.

Native editable AT-SPI controls support Unicode. Browser editors without a
working editable-text writer can explicitly use `BLINDLY4_LINUX_TEXT_INPUT=keyboard`.
This transport accepts printable ASCII up to 4096 bytes, resolves characters
against the existing X11 keymap and rejects unsupported text before clearing a
draft. There is no automatic fallback after a failed native edit.

Keyboard replacement retains the target, verifies focus and the empty draft,
and checks foreground and focus before each character. Success requires the
expected final text. Failures are not rolled back; inspect before retrying.
Focused document containers are distinguished from controls, and ambiguous
control focus is rejected.

Coordinates are reported only when accessible window bounds match XRes-verified
window geometry. Fractional and mixed-monitor scaling remain unqualified.

Run the permission-free RSpec CLI suite, `cargo fmt --check`, and
`cargo clippy --all-targets -- -D warnings` from `linux/`. Live Linux behavior is
covered by the parent Sapiens4 `spec/linux_*_spec.rb` suites using real GTK/WebKit
controls on X11. Physical and managed desktop qualification remain pending.
