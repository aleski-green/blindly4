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

On Windows, `pid` identifies a native window owner, as in the original C# CLI. UI Automation's composed tree can include providers from other processes; those controls remain discoverable and actionable. A popup/fragment with a different reverse parent ends sibling traversal at that branch instead of aborting discovery. Foreground and pointer checks use Win32's actual window PID. If an app exposes a separate top-level WebView window, target that window's PID from `apps` for keyboard input; do not assume its outer host owns the foreground window.

macOS discovery tolerates unavailable optional AX properties and action lists, as Swift did. Native action/write failures still return errors. Rich-text draft verification reads only the selected writer's own subtree.

Focus requests are issued once, then observed for up to 500 ms to allow asynchronous providers to settle. The shared wait also follows macOS click-to-focus paste. If another application takes the foreground after clearing, paste stops instead of activating the target again. This wait never repeats text input or submission.

Windows clipboard publication gives asynchronous readers 50 ms to start, then waits for clipboard access before Ctrl+V. This avoids the observed Explorer read-lock race; it cannot guarantee that another process will not open the clipboard later. Input remains single-attempt and its result must verify exactly.

- Serialize whole workflows across apps; input, focus and clipboard are shared. Keep Sapiens4 host ownership; standalone callers supply coordination.
- Input needs `--pid`. Verify app/recipient/writable child; rediscover paths before mutation. Never invent changing child indexes or infer writability from focus. Use `--require-selected` for selectable press targets.
- Authorized sends require fresh PID/paths and guards below, or focused `key --pid PID --key return --target-path COMPOSER --require-value TEXT`. Never send with bare `type` then Return.

```sh
blindly4 paste --pid PID --target-path COMPOSER --text TEXT
blindly4 press --pid PID --path SEND --expect-description Send --require-value-path COMPOSER --require-value TEXT
```

Guarded paste retains the resolved native control while clearing, focusing and verifying it; changing sibling indexes cannot retarget it. Formatting whitespace after clear is accepted as empty, while nonempty draft verification remains exact with Unicode normalization/direction handling. macOS paste focuses by clicking the writer's live bounds, as Swift did. Clipboard restoration waits up to one second for verification. Guarded keys require PID, nonempty target/draft, matching focus/foreground app; keyboard input does not require a native value-setter capability. Missing exact text fails closed. Refresh send guards and inspect outcomes: `verified`, injected keys or empty composers do not prove delivery.

Stop on errors. Confirmed *pre-input* nonwritable rejection permits one rediscovery/inspection and guarded-paste retry; missing focus permits one rediscovery/refocus. Never bypass draft/focus/send guards. Exit codes cannot prove absence of input; inspect uncertain input/submission before retrying. An app consuming paste only after clipboard restoration can insert the restored clipboard text even after the command reports failure; a timeout is not a rollback.

Commands read fresh state and exit; callers retain comparisons/audits. No universal unread state, service, cache, snapshots, leases or file logs. Traversals are bounded; `--profile` writes invocation-local stderr. Old service/workflow/snapshot commands, lease/log options and `BLINDLY4_LOG_*`/`BLINDLY4_NO_LOG` are obsolete. Preserve existing ignored logs.

## Development and license

[AGENTS.md](AGENTS.md) defines architecture/contracts; [spec/README.md](spec/README.md) defines validation. Source-available under [Sustainable Use License 1.0](license/LICENSE.md); [licensing](license/LICENSING.md), [contributions](CONTRIBUTING.md), [commercial inquiries](mailto:license@sapiens4.ai).
