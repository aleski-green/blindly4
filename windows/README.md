# Windows

Requires Rust, MSVC C++ tools and Windows SDK; use the logged-in interactive desktop.
Elevated apps and the secure desktop are unsupported.

```powershell
.\windows\build.ps1 -Runtime win-x64
```

Use `win-arm64` with a matching toolchain. GNU LLVM builds accept `-Toolchain gnullvm`.
Target the native window owner PID from `apps`, including separate WebView windows.
`cmd`/`command` map to Ctrl. Passwords are redacted; stale/inaccessible targets fail.
Clipboard restoration preserves competing copies; unsupported formats fail before input.

[Usage and safety](../README.md) · [Tests](../spec/README.md)
