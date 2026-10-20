# Windows specifics

See [usage/safety](../README.md), [tests](../spec/README.md). Only the logged-in interactive desktop is supported, excluding elevated apps/secure desktop. No admin/WSL required; `request-permission` only explains access.

Build defaults to host architecture; override `-Runtime win-x64`/`win-arm64`, installing matching Rust/MSVC targets. Alternatively use matching `*-pc-windows-gnullvm`, LLVM-MinGW on `PATH`, and `-Toolchain gnullvm`. C/unwind runtimes link statically; CI uses native MSVC.

Paths: synthetic `AXApplication`, handle-sorted windows, UIA Control View children. Passwords are redacted; inaccessible/stale controls error. Activation failure blocks input; clicks/wheel verify the pointer's app.

`command`/`cmd` = Ctrl; `delete`/`backspace` = backward, `forward-delete` = forward. Scroll uses Windows-configured wheel ticks. `show-menu` needs ExpandCollapsePattern; `scroll-to`: ScrollItemPattern; guarded editing: writable ValuePattern, not read-only TextPattern. Guards inspect only the target. Owner-managed/uncopyable clipboard formats fail before input; restoration preserves newer copies.
