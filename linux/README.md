# Linux X11

Build: `./linux/build.sh release`.
Requires AT-SPI/D-Bus, X11, XRes, EWMH and XTest. Wayland is unsupported.

Editable AT-SPI controls support Unicode. For editors without a native writer,
`BLINDLY4_LINUX_TEXT_INPUT=keyboard` accepts printable ASCII up to 4096 bytes.
It verifies focus and text; failed input is not rolled back. Clipboard is unsupported.
Coordinates require matching accessible/native window bounds. Mixed-monitor and
fractional scaling are unqualified. Secure fields depend on provider password roles.

Run `lake -d spec test` with `BLINDLY4_BIN=.build/release/blindly4`.
Native GTK/WebKit scenarios run through Sapiens4's Lean suite on X11.
[Usage and safety](../README.md) · [Tests](../spec/README.md)
