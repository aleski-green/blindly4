# Linux development preview

Build with `./linux/build.sh debug` or `./linux/build.sh release`. The output
contains `blindly4` and the optional `blindly4-input` portal helper.
Rust 1.99.1 was used for validation; dependency versions are locked.

AT-SPI supplies native discovery, identity, writable controls and text actions.
Guarded paste uses native editable-text insertion without reading or replacing
the clipboard. The shared exact-draft, secure-control and focus checks still
apply. macOS and Windows retain their clipboard transfer paths.

Wayland requires the optional GNOME 42/46/50 extension for foreground verification.
Review `gnome/Foreground.js` and `gnome/install.sh`, explicitly install with
`sh linux/gnome/install.sh --accept-foreground-verification`, then explicitly
enable `foreground@blindly4.sapiens4` after logging back in. Installation does not
enable it. The extension verifies foreground PID and point ownership and has no input,
capture, clipboard, network or logging functions. GNOME extensions nevertheless
run with Shell privileges; their source must be audited.

Start `blindly4-input --consent` and approve GNOME's dialog for temporary keyboard
input; add `--pointer` to request pointer permission explicitly. This separate
process retains the portal connection, not UI targets or
drafts. CLI invocations still read fresh state and exit. No permission token is
persisted and nothing autostarts. The helper rechecks foreground identity before
key presses. Exit the helper or revoke portal permission to stop input.

Xorg uses XRes PIDs, EWMH and XTest; a Wayland session never falls back to Xwayland.
The extension rejects X11/Xwayland PID claims; only native Wayland windows qualify.
Wayland clicks verify destination ownership, confirm pointer arrival, then press.
At most two corrective motions use observed input-to-screen scaling within one
second. Unexpected motion or failure to arrive prevents the click.
Scrolling rechecks pointer ownership before each step. No EIS, screen capture or
clipboard permission is requested. Nested X11-backed Mutter does not forward
scroll here; native headless Wayland provides the pointer integration test.
GTK 4.14 cannot focus arbitrary
controls through AT-SPI or provide useful global coordinates. Linux paste needs
an editable provider by default. An explicit keyboard transport is available below.
Secure-value protection depends on the provider declaring password roles.

For browsers without a working editable-text writer, explicitly set
`BLINDLY4_LINUX_TEXT_INPUT=keyboard` before launching Sapiens4 or the CLI. This
transport accepts printable ASCII only, up to 4096 bytes. Wayland requires a
single GNOME US input source with no XKB options and the consented helper. Xorg
resolves characters against the current keymap without remapping it. Unsupported
text, layout or absent consent is rejected before clearing a draft. Unicode
remains supported by editable AT-SPI controls and Sapiens4's headless browsers.
There is no automatic fallback after a failed native edit.

Keyboard replacement retains the native target, verifies focus and the empty
draft, then checks foreground and focus before each character. Typed/replaced
text must verify against the expected draft before success. A failure is not a
rollback: inspect the field before retrying. The clipboard is untouched.
Chromium can expose focused document containers alongside the focused control;
lookup prefers a unique focused control and rejects ambiguous control focus.

Xorg coordinates are converted only when accessible window bounds match
XRes-verified window geometry, accounting for client and server decorations.
Unknown geometry is omitted. Integer 1×/2× GTK/WebKit Xorg clicks and actual 1×/2× Wayland virtual-monitor
input are tested; fractional and mixed-monitor scaling remain unqualified.

Linux behavior is exercised by the parent Sapiens4 `spec/linux_*_spec.rb` suites
using actual GTK controls, nested GNOME and Xvfb. The existing permission-free CLI
suite also runs. Use `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings`
from `linux/`. Ubuntu 22.04/24.04 software-rendered GNOME and Xorg fixtures are covered.
Physical desktop, managed-browser and enrolled-enterprise qualification remain pending; this is not an enterprise production release.
