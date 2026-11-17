import Tests.Cli
import Tests.Form
import Tests.Mac
import Tests.Windows
import Tests.Clipboard
open Lean System Tests

def main (args : List String) : IO UInt32 := do
  let mut cases := cliCases ++ formCases ++ macCases ++ windowsCases ++ clipboardCases
  if (← IO.getEnv "BLINDLY4_WEBVIEW_PID").isSome then
    cases := cases.push ⟨"Hosted composition WebView", hostedWebView, "windows", true⟩
  check (args.isEmpty || args == ["--list"]) "Usage: lake -d spec test [-- --list]"
  let platform := if Platform.isOSX then "macos" else if Platform.isWindows then "windows" else "linux"
  let live := (← IO.getEnv "BLINDLY4_LIVE") == some "1"
  check (!live || Platform.isOSX || Platform.isWindows) "Live fixtures require macOS or Windows"
  let selected := cases.filter fun c => (c.platform == "all" || c.platform == platform) && (!c.live || live)
  check (!selected.isEmpty) "No tests selected"
  check (← (FilePath.mk (← binary)).pathExists) "Build blindly4 or set BLINDLY4_BIN"
  if args == ["--list"] then
    for c in selected do IO.println c.name
    return 0
  let mut failures := 0
  let mut results : Array Json := #[]
  for c in selected do
    try
      c.run
      IO.println s!"PASS {c.name}"
      results := results.push (json% {name: $(c.name), status: "passed"})
    catch error =>
      failures := failures + 1
      IO.eprintln s!"FAIL {c.name}: {error}"
      results := results.push (json% {name: $(c.name), status: "failed", error: $(toString error)})
  if let some path ← IO.getEnv "BLINDLY4_TEST_RESULTS" then
    IO.FS.writeFile path (json% {platform: $(platform), live: $(live), total: $(selected.size), failures: $(failures), tests: $(results)}).pretty
  IO.println s!"{selected.size - failures}/{selected.size} passed"
  return if failures == 0 then 0 else 1
