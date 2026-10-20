# blindly4

Stateless Rust accessibility CLI: macOS 13+ (Apple AX) and Windows 10/11 x64/ARM64 (UIA/Win32), not VoiceOver or `say`. [Upstream](https://github.com/aleski-green/blindly4); [Windows-contributing fork](https://github.com/fatmahalqaisi-code/blindly4).

## Build

From the cloned fork, with stable Rust:

- macOS: Xcode Command Line Tools; `./macos/build.sh` (or `./macos/build.sh debug`) → `.build/<profile>/blindly4` (default release).
- Windows: MSVC C++ tools/Windows SDK; `.\windows\build.ps1` → `.build/windows/blindly4.exe`. [Platform details](windows/README.md).

Add the output directory to `PATH`; no language runtime needed. On macOS, run `blindly4 request-permission`; grant Codex/the hosting terminal access in System Settings → Privacy & Security → Accessibility. Missing permission fails closed.

## Use

Invoke directly: `blindly4 schema` lists options, risks and permissions; `--help`/`COMMAND --help` explain commands. Discover PID with `apps`, controls with `show`/`find`, then `inspect`. Read-only commands must not mutate UI; `press`/`key` are external commits, never speculative.

## Safe operation

- Serialize whole workflows across apps; input, focus and clipboard are shared. Keep Sapiens4 host ownership; standalone callers supply coordination.
- Input needs `--pid`. Verify app/recipient/writable child; rediscover paths before mutation. Never invent changing child indexes or infer writability from focus. Use `--require-selected` for selectable press targets.
- Authorized sends require fresh PID/paths and guards below, or focused `key --pid PID --key return --target-path COMPOSER --require-value TEXT`. Never send with bare `type` then Return.

```sh
blindly4 paste --pid PID --target-path COMPOSER --text TEXT
blindly4 press --pid PID --path SEND --expect-description Send --require-value-path COMPOSER --require-value TEXT
```

Guarded paste clears/verifies the target draft, allowing Unicode normalization/direction handling and up to one second before clipboard restoration. Guarded keys require PID, nonempty target/draft, matching focus/foreground app. Missing exact text fails closed. Reuse paste verification, but refresh send guards and inspect outcomes: `verified`, injected keys or empty composers do not prove delivery.

Stop on errors. Confirmed *pre-input* nonwritable rejection permits one rediscovery/inspection and guarded-paste retry; missing focus permits one rediscovery/refocus. Never bypass draft/focus/send guards. Exit codes cannot prove absence of input; inspect uncertain input/submission before retrying.

Commands read fresh state and exit; callers retain comparisons/audits. No universal unread state, service, cache, snapshots, leases or file logs. Traversals are bounded; `--profile` writes invocation-local stderr. Old service/workflow/snapshot commands, lease/log options and `BLINDLY4_LOG_*`/`BLINDLY4_NO_LOG` are obsolete. Preserve existing ignored logs.

## Development and license

[AGENTS.md](AGENTS.md) defines architecture/contracts; [spec/README.md](spec/README.md) defines validation. Source-available under [Sustainable Use License 1.0](license/LICENSE.md); [licensing](license/LICENSING.md), [contributions](CONTRIBUTING.md), [commercial inquiries](mailto:license@sapiens4.ai).
