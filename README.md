# Blindly4

Stateless native accessibility CLI for macOS 13+, Windows 10/11 and Linux X11.
Requires Rust and platform build tools.

- macOS: `./macos/build.sh` → `.build/release/blindly4`.
- [Windows](windows/README.md): `.\windows\build.ps1` → `.build/windows/blindly4.exe`.
- [Linux](linux/README.md): `./linux/build.sh release`.

On macOS, run `blindly4 request-permission` and grant the hosting app/terminal
Accessibility access. Add the binary directory to PATH.

## Use

`blindly4 schema` lists commands, options and risks. `COMMAND --help` gives syntax.
Find the app PID with `apps`, controls with `find`/`show`, then inspect the target.

```sh
blindly4 paste --pid PID --target-path COMPOSER --text TEXT
blindly4 press --pid PID --path SEND --expect-description Send --require-value-path COMPOSER --require-value TEXT
```

## Safe operation

- Serialize desktop workflows. Focus, input and clipboard are shared.
- Rediscover targets before mutations. Verify PID, recipient and writable control.
- Submission requires fresh exact-draft/focus guards and authorization.
- `press` and `key` can commit external actions. Read-only commands must not change UI.
- Stop on errors; inspect uncertain effects before retrying. A timeout is not rollback.
- Never bypass PID, identity, focus, password-redaction or draft checks.
- Verification confirms the local control value, not message delivery.

Exit codes: `0` success, `64` usage, `77` access/permission, `1` unexpected failure.
`--profile` writes diagnostics to stderr. Preserve existing `.logs/` files.

[Tests](spec/README.md) · [Agent guide](AGENTS.md) · [Contributing](CONTRIBUTING.md) · [License](license/LICENSE.md)
