import Tests.Support
open Lean System
namespace Tests

private def frontmost (pid : Nat) : IO Unit := do
  check ((← arr (← success #["apps"]) "apps").any fun j => j.getObjValD "pid" == toJson pid && j.getObjValD "frontmost" == toJson true) "Wrong foreground PID"

def windowsCases : Array Case := Id.run do
  let mut cases := #[]
  cases := cases.push <| desktop "Windows foreground handoff across processes" (fun d =>
    withFixture #[("BLINDLY4_FIXTURE_BACKGROUND", "1")] (fun other => do
      discard <| d.app #["key", "--key", "escape"]
      for pid in #[other.pid, d.pid, other.pid, d.pid] do
        let out ← capture #["activate", "--pid", toString pid, "--profile"]
        eq out.exitCode 0
        has (← parse out.stdout) (json% {ok: true, pid: $(pid)})
        has ((← parse out.stderr).getObjValD "activation") (json% {targetPid: $(pid), activationAccepted: true})
        frontmost pid
        discard <| success #["key", "--pid", toString pid, "--key", "escape"]
      for app in #[other, d] do
        eq (← app.value) ""
        app.notSubmitted) false) "windows"
  cases := cases.push <| desktop "Windows native roles and actions" (fun d => do
    for (title, role, native, actions) in #[
      ("Draft", "AXTextField", "Edit", #[]), ("Password", "AXSecureTextField", "Edit", #[]),
      ("Submit test draft", "AXButton", "Button", #["AXPress"]), ("Test checkbox", "AXCheckBox", "CheckBox", #["AXPress"]),
      ("Delivery choice", "AXComboBox", "ComboBox", #["AXShowMenu"]), ("Scrollable options", "AXList", "List", #[]),
      ("Option 02", "AXRow", "ListItem", #["AXPress", "AXScrollToVisible"]), ("Fixture ready", "AXStaticText", "Text", #[])] do
      let path ← d.path title role
      let row ← d.app #["inspect", "--path", path]
      has row (json% {role: $(role), subrole: $("ControlType." ++ native)})
      let actual ← arr row "actions"
      check (actions.all (fun a => actual.contains (toJson a))) "Missing native action"
      check ((← d.app #["actions", "--path", path]) == (json% {path: $(path), actions: $(actual)})) "Action listing mismatch"
    d.notSubmitted
    discard <| d.app #["press", "--path", ← d.submit, "--expect-description", "Submit", "--require-value-path", ← d.draft, "--require-value", ""]
    d.label "Submission count: 1") "windows"
  for shortcut in #["ctrl+a", "command+a", "cmd+a"] do
    cases := cases.push <| desktop s!"Windows select-all alias {shortcut}" (fun d => do
      d.set "original"
      d.focusDraft
      has (← d.app #["key", "--key", shortcut, "--target-path", ← d.draft, "--require-value", "original"]) (json% {verified: true})
      discard <| d.app #["type", "--text", "Typed Unicode: مرحبا café 🪟"]
      eq (← d.value) "Typed Unicode: مرحبا café 🪟"
      d.notSubmitted) "windows"
  cases := cases.push <| desktop "Windows backward and forward delete" (fun d => do
    d.set "abc"
    d.focusDraft
    for key in #["end", "delete"] do discard <| d.app #["key", "--key", key]
    eq (← d.value) "ab"
    for key in #["home", "forward-delete"] do discard <| d.app #["key", "--key", key]
    eq (← d.value) "b") "windows"
  cases := cases.push <| desktop "Windows input rejects invisible target" (fun d => do
    let out ← capture #["key", "--pid", toString (← IO.Process.getPID), "--key", "return"]
    eq out.exitCode 77
    has (← parse out.stdout) (json% {code: "accessibility_error"})
    d.notSubmitted) "windows"
  cases := cases.push <| desktop "Retain native identity across sibling reorder" (fun d => do
    let path ← d.draft
    has (← d.app #["paste", "--target-path", path, "--text", "same native draft"]) (json% {verified: true})
    check ((← d.draft) != path) "Fixture did not reorder"
    eq (← d.value) "same native draft"
    d.notSubmitted
    eq (← d.value "First field") "first untouched"
    check ((← arr (← d.app #["find", "--role", "AXTextField"]) "matches").any fun j => j.getObjValD "identifier" == toJson "110" && j.getObjValD "value" == toJson "third untouched") "Third field changed") "windows" #[("BLINDLY4_FIXTURE_PASTE", "reorder")]
  cases := cases.push <| desktop "Retained text after clear blocks paste" (fun d => do
    discard <| d.reject 77 #["paste", "--target-path", ← d.draft, "--text", "must not be inserted"]
    eq (← d.value) "retained draft"
    d.notSubmitted
    d.neighbors) "windows" #[("BLINDLY4_FIXTURE_VALUE", "retained")]
  cases := cases.push <| desktop "Windows list selection" (fun d => do
    for title in #["Option 02", "Option 03"] do
      discard <| d.app #["press", "--path", ← d.path title "AXRow", "--require-selected"]
      has (← d.app #["inspect", "--path", ← d.path title "AXRow"]) (json% {selected: true})
    has (← d.app #["inspect", "--path", ← d.path "Option 02" "AXRow"]) (json% {selected: false})
    d.notSubmitted) "windows"
  cases := cases.push <| desktop "Windows dropdown selection and Escape" (fun d => do
    d.label "Dropdown: closed; choice: 1"
    let path ← d.path "Delivery choice" "AXComboBox"
    discard <| d.app #["focus", "--path", path]
    discard <| d.app #["show-menu", "--path", path]
    d.label "Dropdown: open; choice: 1"
    discard <| d.app #["press", "--path", ← d.path "Choice two" "AXRow", "--require-selected"]
    awaitState "dropdown choice" do
      return (← d.find "Dropdown:" "AXStaticText").any fun j => ((j.getObjValAs? String "title").toOption.getD "").endsWith "choice: 2"
    discard <| d.app #["show-menu", "--path", ← d.path "Delivery choice" "AXComboBox"]
    d.label "Dropdown: open; choice: 2"
    discard <| d.app #["key", "--key", "escape"]
    d.label "Dropdown: closed; choice: 2"
    d.notSubmitted) "windows"
  cases := cases.push <| desktop "Windows keyboard dropdown selection" (fun d => do
    let path ← d.path "Delivery choice" "AXComboBox"
    discard <| d.app #["focus", "--path", path]
    discard <| d.app #["show-menu", "--path", path]
    d.label "Dropdown: open; choice: 1"
    for key in #["down", "enter"] do discard <| d.app #["key", "--key", key]
    d.label "Dropdown: closed; choice: 2"
    d.label "Submission count: 0") "windows"
  cases := cases.push <| desktop "Windows native wheel scrolling" (fun d => do
    let pos := (← d.control "Scrollable options" "AXList").getObjValD "position"
    discard <| d.app #["click", "--x", toString ((← number pos "x") + 50), "--y", toString ((← number pos "y") + 30)]
    d.label "First visible option: 01"
    discard <| d.app #["scroll", "--direction", "down", "--amount", "3"]
    awaitState "scrolled list" do
      return (← d.find "First visible option:" "AXStaticText").any fun j =>
        (((j.getObjValAs? String "title").toOption.getD "").splitOn " ").getLast!.toNat?.getD 0 > 1
    discard <| d.app #["scroll", "--direction", "up", "--amount", "3"]
    d.label "First visible option: 01"
    d.notSubmitted) "windows"
  cases := cases.push <| desktop "Windows scroll-to exposes offscreen row" (fun d => do
    let list ← d.control "Scrollable options" "AXList"
    let top ← number (list.getObjValD "position") "y"
    let bottom := top + (← number (list.getObjValD "size") "height")
    let visible := fun (limit : Float) => do
      let row ← d.control "Option 80" "AXRow"
      let y ← number (row.getObjValD "position") "y"
      return (← number (row.getObjValD "size") "height") > 0 && y ≥ top && y ≤ limit
    check (!(← visible bottom)) "Fixture last row already visible"
    discard <| d.app #["scroll-to", "--path", ← d.path "Option 80" "AXRow"]
    awaitState "offscreen row" (visible (bottom - 1))
    discard <| d.app #["scroll-to", "--path", ← d.path "Option 01" "AXRow"]
    d.label "First visible option: 01"
    d.notSubmitted) "windows"
  for detached in #[false, true] do
    cases := cases.push <| desktop (if detached then "Detached provider rejects stale identity" else "Embedded provider retains owner and draft guard") (fun d => do
      awaitState "embedded child provider" (return (← d.find "Child process draft" "AXTextField").size == 1)
      let childRow ← d.control "Child process:" "AXStaticText"
      let some childPid := ((← str childRow "title").splitOn ": ").getLast!.toNat? | throw <| IO.userError "Missing child PID"
      let child ← d.control "Child process draft" "AXTextField"
      let target ← str child "path"
      if detached then
        d.press "Detach child window"
        awaitState "detached child visible" (return (← arr (← success #["apps"]) "apps").any (fun j => j.getObjValD "pid" == toJson childPid))
        let focused ← d.raw #["focused"]
        eq focused.exitCode 77
        has (← parse focused.stdout) (json% {code: "focus_unavailable"})
        eq (← d.find "Child process draft" "AXTextField").size 0
        discard <| d.reject 77 #["paste", "--target-path", target, "--text", "must not appear"]
        let rows ← arr (← success #["find", "--pid", toString childPid, "--title", "Child process draft", "--role", "AXTextField"]) "matches"
        check (!rows.isEmpty) "Detached provider disappeared"
        has rows[0]! (json% {value: ""})
      else
        has child (json% {pid: $(d.pid)})
        let message := "Embedded provider: مرحبا café 🪟"
        has (← d.app #["paste", "--target-path", target, "--text", message]) (json% {verified: true})
        has (← d.app #["focused"]) (json% {title: "Child process draft", value: $(message), pid: $(d.pid)})
        let path ← d.path "Child process draft" "AXTextField"
        has (← d.app #["inspect", "--path", path]) (json% {value: $(message)})
        discard <| d.reject 77 #["key", "--key", "return", "--target-path", path, "--require-value", "wrong draft"]
        eq (← d.find "Submission count: 0" "AXStaticText").size 2
        has (← d.app #["inspect", "--path", path]) (json% {value: $(message)})) "windows" #[("BLINDLY4_FIXTURE_CHILD", "1")]
  return cases

-- Explicit external-app opt-in, separate from fixture-only live runs.
def hostedWebView : IO Unit := do
  let some pid ← IO.getEnv "BLINDLY4_WEBVIEW_PID" | throw <| IO.userError "Set BLINDLY4_WEBVIEW_PID"
  let some title ← IO.getEnv "BLINDLY4_WEBVIEW_SEARCH_TITLE" | throw <| IO.userError "Set BLINDLY4_WEBVIEW_SEARCH_TITLE"
  let some text ← IO.getEnv "BLINDLY4_WEBVIEW_SEARCH_TEXT" | throw <| IO.userError "Set BLINDLY4_WEBVIEW_SEARCH_TEXT"
  check (!text.isEmpty) "Search text must be nonempty"
  let some pidNumber := pid.toNat? | throw <| IO.userError "Invalid WebView PID"
  let field := fun (value : Option String) => do
    let filter := value.map (fun v => #["--value", v]) |>.getD #["--title", title]
    let rows ← arr (← success (#["find", "--pid", pid] ++ filter ++ #["--role", "AXTextField", "--depth", "40", "--limit", "1"])) "matches"
    eq rows.size 1
    return rows[0]!
  let initial ← field none
  has initial (json% {title: $(title), value: "", pid: $(pidNumber)})
  let identity ← str initial "identifier"
  check (!identity.isEmpty) "Missing WebView field identity"
  try
    has (← success #["paste", "--pid", pid, "--target-path", ← str initial "path", "--text", text]) (json% {verified: true})
    has (← success #["focused", "--pid", pid]) (json% {identifier: $(identity), value: $(text), pid: $(pidNumber)})
    frontmost pidNumber
    let current ← field (some text)
    has current (json% {identifier: $(identity), value: $(text)})
    let out ← capture #["key", "--pid", pid, "--key", "return", "--target-path", ← str current "path", "--require-value", text ++ " must not submit"]
    eq out.exitCode 77
    has (← parse out.stdout) (json% {code: "accessibility_error"})
    has (← field (some text)) (json% {value: $(text)})
  finally
    let focused ← capture #["focused", "--pid", pid]
    if focused.exitCode == 0 then
      let current ← parse focused.stdout
      if current.getObjValD "identifier" == toJson identity && current.getObjValD "value" == toJson text then
        let current ← field (some text)
        has current (json% {identifier: $(identity)})
        discard <| success #["set-value", "--pid", pid, "--path", ← str current "path", "--value", ""]
        awaitState "WebView field cleanup" do
          let current ← field none
          return current.getObjValD "identifier" == toJson identity && current.getObjValD "value" == toJson ""
end Tests
