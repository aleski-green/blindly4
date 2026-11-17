import Tests.Support
open Lean System
namespace Tests

def commands := #["schema", "request-permission", "apps", "activate", "open", "tree", "show", "find", "focused", "inspect", "actions", "focus", "press", "show-menu", "scroll-to", "set-value", "set-selected-text", "click", "type", "paste", "scroll", "key"]

def cliCases : Array Case := Id.run do
  let mut cases := #[]
  for name in #["--test-app", "--test-pasteboard"] do
    cases := cases.push <| test s!"Fixture opt-in: {name}" (usage #[name] #[("BLINDLY4_LIVE", none)])
  cases := cases.push <| test "Duplicate options" (usage #["tree", "--depth", "2", "--depth", "3"])
  cases := cases.push <| test "Schema command catalog" do
    let schema ← success #["schema"]
    has schema (json% {schemaVersion: 2})
    let rows ← arr schema "commands"
    eq rows.size commands.size
    let names ← rows.mapM (fun row => str row "name")
    check (commands.all names.contains) "Incomplete command catalog"
    for row in rows do
      check ((← str row "usage").startsWith ("blindly4 " ++ (← str row "name"))) "Invalid usage"
      check (!(← str row "summary").trimAscii.isEmpty) "Empty summary"
      discard <| arr row "options"
      discard <| IO.ofExcept (row.getObjValAs? Bool "requiresAccessibility")
  cases := cases.push <| test "Schema risks and guards" do
    let rows ← arr (← success #["schema"]) "commands"
    for (risk, names) in #[("external-commit", #["press", "key"]), ("read-only", #["schema", "apps", "tree", "show", "find", "focused", "inspect", "actions"]), ("ui-mutation", #["scroll", "scroll-to"])] do
      for name in names do
        let some row := rows.find? (fun row => row.getObjValD "name" == toJson name) | throw <| IO.userError name
        has row (json% {risk: $(risk)})
    for (name, options) in #[("key", #["pid", "target-path", "require-value"]), ("press", #["require-selected", "require-value-path", "require-value"])] do
      let row := rows.find? (fun row => row.getObjValD "name" == toJson name)
      let actual ← arr row.get! "options"
      check (options.all (fun value => actual.contains (toJson value))) "Missing guard option"
  cases := cases.push <| test "Stateless profiling" do
    let first ← capture #["schema"]
    let profiled ← capture #["schema", "--profile"]
    let second ← capture #["schema"]
    for out in #[first, profiled, second] do eq out.exitCode 0
    eq profiled.stdout first.stdout
    eq second.stdout first.stdout
    eq first.stderr ""
    eq second.stderr ""
    contains profiled.stderr.toLower "elapsed"
    check (!profiled.stderr.contains "cache_") "Profiling leaked cached state"
  for args in #[#[], #["--help"], #["help"]] do
    cases := cases.push <| test s!"Help {args.toList}" do
      let out ← capture args
      eq out.exitCode 0
      eq out.stderr ""
      for name in #["schema", "paste", "key"] do contains out.stdout name
  for name in commands do
    cases := cases.push <| test s!"Command help {name}" do
      let out ← capture #[name, "--help"]
      eq out.exitCode 0
      eq out.stderr ""
      contains out.stdout ("blindly4 " ++ name)
    cases := cases.push <| test s!"Unknown option {name}" (usage #[name, "--not-a-real-option", "value"])
  for name in #["serve", "workflow", "snapshot", "changes", "unknown-command", "--self-test", "--integration-test"] do
    cases := cases.push <| test s!"Unsupported command {name}" (usage #[name])
  let invalid := #[
    #["--no-service", "schema"], #["schema", "--no-log"], #["schema", "--lease", "old-token"], #["schema", "unexpected"],
    #["tree", "--depth"], #["find", "--titel", "Settings"], #["type", "--text"], #["paste", "--target-path"],
    #["type", "--text", "help", "--not-a-real-option", "value"], #["set-value", "--path", "0", "--value", "-h", "--not-a-real-option", "value"],
    #["key", "--key", "return", "--target-path", "0", "--require-value", "draft"],
    #["key", "--key", "return", "--pid", "1", "--target-path", "0"], #["key", "--key", "return", "--pid", "1", "--require-value", "draft"],
    #["press", "--path", "0", "--require-value", "draft"], #["press", "--path", "0", "--require-value-path", "0"],
    #["paste", "--target-path", "0", "--text", "draft"], #["scroll", "--direction", "diagonal"], #["scroll", "--direction", "down", "--amount", "0"],
    #["tree", "--pid", "0"], #["tree", "--max-nodes", "0"], #["find", "--limit", "0", "--title", "Draft"],
    #["key", "--key", "return", "--pid", "1", "--target-path", "", "--require-value", "draft"],
    #["key", "--key", "return", "--pid", "1", "--target-path", "0", "--require-value", "  "],
    #["activate"], #["open"], #["click", "--x", "0"], #["type"], #["paste"], #["key"], #["scroll"], #["set-value", "--path", "0"], #["set-selected-text", "--path", "0"]]
  for args in invalid do cases := cases.push <| test s!"Invalid arguments {args.toList}" (usage args)
  for path in #["-1", "1..2", "1.", "a", "2147483648", "0. 1", "١", "+1", String.intercalate "." (List.replicate 65 "0")] do
    cases := cases.push <| test s!"Invalid path {path}" (usage #["focus", "--path", path])
  for depth in #["-1", "65", "2147483648", "x"] do
    cases := cases.push <| test s!"Invalid depth {depth}" (usage #["tree", "--depth", depth])
  for coordinate in #["NaN", "inf", "-inf", "1e999", "100001"] do
    cases := cases.push <| test s!"Invalid coordinate {coordinate}" (usage #["click", "--x", coordinate, "--y", "0"])
  for url in #["file:///C:/test", "javascript:alert(1)", "shell:AppsFolder", "relative", "https://", "slack:"] do
    cases := cases.push <| test s!"Unsupported URL {url}" (usage #["open", "--url", url])
  for key in #["ctrl+bogus", "command+bogus", "unknown+a", "", "ctrl+", "command+", "f0", "f25"] do
    cases := cases.push <| test s!"Invalid key {key}" (usage #["key", "--key", key])
  for key in #["RETURN", "ctrl+alt+shift+a", "cmd+v", "command+control+option+shift+F12", "9", "forward-delete", "pageup", "pagedown"] do
    cases := cases.push <| test s!"Accepted key grammar {key}" do
      let out ← capture #["key", "--key", key, "--pid", "2147483647"]
      eq out.exitCode 77
      check (#["accessibility_error", "accessibility_permission_denied"].contains (← str (← parse out.stdout) "code")) "Wrong absent-target error"
  cases := cases.push <| test "macOS app metadata" (do
    for row in (← arr (← success #["apps"]) "apps") do
      for key in #["name", "pid", "bundleId"] do discard <| IO.ofExcept (row.getObjVal? key)) "macos"
  cases := cases.push <| test "macOS function keys" (do
    for key in #["f01", "f13", "f24"] do usage #["key", "--key", key, "--pid", "2147483647"]) "macos"
  cases := cases.push <| test "Windows schema snapshot" (do
    let expected ← parse (← IO.FS.readFile ((← root) / "spec/fixtures/windows-schema-v2.json"))
    check ((← success #["schema"]) == expected) "Schema snapshot mismatch") "windows"
  cases := cases.push <| test "Windows invisible-process validation" (do
    let pid := toString (← IO.Process.getPID)
    for command in #["inspect", "press"] do
      let out ← capture #[command, "--pid", pid]
      eq out.exitCode 77
      has (← parse out.stdout) (json% {code: "accessibility_error", error: $("No visible windows for PID " ++ pid)})
    for command in #["actions", "focus"] do usage #[command, "--pid", pid]
    let out ← capture #["inspect", "--pid", pid, "--path", "malformed"]
    eq out.exitCode 77
    has (← parse out.stdout) (json% {error: $("No visible windows for PID " ++ pid)})) "windows"
  cases := cases.push <| test "Windows function keys" (do
    for key in #["f01", "f13", "f24"] do
      let out ← capture #["key", "--key", key, "--pid", "2147483647"]
      eq out.exitCode 77
      has (← parse out.stdout) (json% {code: "accessibility_error"})) "windows"
  for (session, display, wayland) in #[(some "wayland", some ":99", some "wayland-0"), (none, some ":99", some "wayland-0"), (some "tty", some ":99", none), (some "x11", none, none)] do
    cases := cases.push <| test s!"Linux session boundary {session} {display} {wayland}" (do
      let env := #[("XDG_SESSION_TYPE", session), ("DISPLAY", display), ("WAYLAND_DISPLAY", wayland)]
      let out ← capture #["request-permission"] env
      eq out.exitCode 0
      let permission ← parse out.stdout
      has permission (json% {trusted: false, foregroundAvailable: false, inputAvailable: false})
      contains (← str permission "error") "requires an X11 session"
      eq (← capture #["schema"] env).exitCode 0
      for args in #[#["apps"], #["key", "--pid", "1", "--key", "enter"], #["click", "--pid", "1", "--x", "0", "--y", "0"], #["paste", "--pid", "1", "--target-path", "0", "--text", "replacement"]] do
        let result ← capture args env
        eq result.exitCode 77
        contains (result.stdout ++ result.stderr) "requires an X11 session") "linux"
  return cases
end Tests
