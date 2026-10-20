# Behavioral tests

Ruby 3.4/Bundler; RSpec tests fresh compiled CLI processes via output, exit codes or desktop effects. No Rust unit/internal-function tests, mocks or embedded self-tests.

Default tests must be permission-free.

Build with `./macos/build.sh debug` or `.\windows\build.ps1`, then from the root:

```sh
bundle install
bundle exec rspec
```

Defaults: `.build/debug/blindly4` (macOS), `.build/windows/blindly4.exe` (Windows); override with `BLINDLY4_BIN`. Missing binary/no examples fails. Ruby/gems are development-only.

From each platform directory run `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings`.

## Live tests

After input/safety changes, run default **and** live suites against harmless fixtures before external-effect controls. Use an unlocked desktop exclusively; grant the macOS host Accessibility permission.

macOS: `BLINDLY4_LIVE=1 bundle exec rspec`. Windows PowerShell:

```powershell
$env:BLINDLY4_LIVE = '1'
bundle exec rspec
Remove-Item Env:BLINDLY4_LIVE
```

Tag cases `:macos, :live` or `:windows, :live`; select with `--tag live`. Fixtures use focus/clipboard, rediscover paths and clean up on failure. Assert visible results and no rejection side effects; retain seeds/failure logs.

Specs define CLI/desktop/clipboard behavior. Windows interruption specs cover clipboard contention, a competing copy during pending paste, delayed consumption, verification timeout, and focus changes within/across fixture processes. macOS concurrent clipboard changes remain untested. macOS usage errors use stderr; Windows uses stdout JSON.

The Windows fixture supports live-only paste modes (`delay`, `hold`, `focus-after`) and background startup. RSpec coordinates native controls and real clipboard operations; production input code has no test hooks. A late-consumption test explicitly demonstrates that restored clipboard text may reach the draft after a failed paste: failure is not a rollback guarantee. Never retry or submit without inspecting the resulting draft.

Fixture only: Enter submits from field two; Space inserts there. Space/Enter activate focused Send; dropdown Enter selects without submission.

Windows provider specs spawn a separate-process native child window. They verify window-owner PID reporting, guarded Unicode input, exact-draft rejection, and refusal of stale paths/focus after the child detaches. Process ancestry alone never authorizes a control. The fixture child mode is live-only.

CI runs permission-free suites on macOS Apple Silicon/Intel and Windows x64/ARM64; live validation is local. Use RSpec, not `cargo test`, `--self-test` or `--integration-test`.
