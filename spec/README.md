# Behavioral tests

All automated tests use RSpec. Every example executes the compiled CLI in a fresh
process and observes public output, exit codes, or the live desktop. There are no
unit tests, internal-function calls, mocks, or embedded self-test runners.

Build the executable first, install Ruby 3.4 and Bundler, and run from the repository
root:

```sh
bundle install
bundle exec rspec
```

The default executable is `.build/windows/blindly4.exe` on Windows and
`.build/debug/blindly4` on macOS. Set `BLINDLY4_BIN` to test another build. RSpec fails
if the binary is missing or no examples are selected. Dependencies are pinned in
`Gemfile.lock`; Ruby and the gems are development dependencies only.

## Coverage

- `cli_spec.rb`: shared command discovery, help, risk classifications, option
  rejection, removed commands, and invocation-local profiling.
- `windows_cli_spec.rb`: the complete Windows schema-v2 fixture, strict numeric
  arguments, URL restrictions, key validation, and incomplete safety guards.
- `windows_desktop_spec.rb`: real UI Automation and SendInput against a local
  native window, including traversal bounds, Unicode paste/type, exact matching,
  keyboard aliases, focus guards, password redaction, and rejected input with no
  submission or draft changes.
- `windows_form_spec.rb`: three text fields, paste/type into only the second,
  a real two-second delay, then submission by accessible press or Space/Enter on
  the focused Send button. Also covers guarded Enter from the second field,
  Space as ordinary input, selected-text replacement, exactly one submission,
  unchanged neighboring fields, and drafts changed during the delay.
- `windows_controls_spec.rb`: checkbox toggles by press and Space, exclusive list
  selection, dropdown opening/selection/closing and keyboard selection, actual
  wheel scrolling down/up, and bringing offscreen list options into view.

The tests intentionally verify platform-specific output where the existing Windows
and macOS contracts differ. macOS usage errors use stderr; Windows usage errors are
JSON on stdout. Shared tests need no Accessibility permission.

## Live Windows behavior

Use an unlocked interactive Windows desktop and do not use it concurrently:

```powershell
$env:BLINDLY4_LIVE = '1'
bundle exec rspec
Remove-Item Env:BLINDLY4_LIVE
```

To run only desktop examples, use `bundle exec rspec --tag live` with the same
environment variable. Each example starts its own harmless `--test-app` fixture,
discovers controls by visible labels, and cleans up its process even on failure.
Paths are rediscovered before mutations. The fixture performs no external actions.
Tests temporarily use focus and the clipboard; paste restores clipboard data.
RSpec randomizes example order and prints a seed for reproduction.

The fixture is a local form with a default Send button. Enter in its second input
submits; Space in that input inserts a space. Both Space and Enter activate the
focused Send button. These are explicit behaviors of this fixture, not a guarantee
that arbitrary applications use the same shortcuts. Dropdown Enter selects an
option without submitting the form. Visible status labels expose actual native
checkbox, dropdown, scroll, and submission state; assertions remain in RSpec.

CI runs the permission-free RSpec suite on macOS, Windows x64, and Windows ARM64.
Live Windows scenarios are an explicit local validation step because hosted CI
does not guarantee an unlocked interactive desktop. Rust formatting and Clippy are
separate static checks. After input or safety changes, run both the default suite
and the live suite. The former `--self-test`, `--integration-test`, and `cargo test`
commands are replaced by RSpec.
