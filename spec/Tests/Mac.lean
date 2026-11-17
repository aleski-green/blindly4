import Tests.Support
open Lean
namespace Tests

def macCases : Array Case := Id.run do
  let mut cases := #[]
  cases := cases.push <| desktop "Native macOS role matching" (fun d => do
    let fields ← arr (← d.app #["find", "--role", "TextField"]) "matches"
    check (!fields.isEmpty && fields.all (fun j => j.getObjValD "role" == toJson "AXTextField")) "Native text role"
    eq (← arr (← d.app #["find", "--role", "Text"]) "matches").size 0) "macos"
  cases := cases.push <| desktop "Omitted empty native value" (fun d => do
    has (← d.app #["inspect", "--path", ← d.draft]) (json% {value: ""})
    d.paste "verified draft"
    eq (← d.value) "verified draft"
    discard <| d.app #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", "verified draft"]
    d.label "Submitted: verified draft"
    d.label "Submission count: 1"
    d.neighbors) "macos" #[("BLINDLY4_FIXTURE_VALUE", "empty")]
  cases := cases.push <| desktop "Virtual Touch Bar traversal" (fun d => do
    let tree ← d.app #["tree", "--depth", "12", "--max-nodes", "1000"]
    has tree (json% {truncated: false})
    contains tree.compress "AXFunctionRowTopLevelElement"
    let rows ← arr (← d.app #["find", "--role", "AXFunctionRowTopLevelElement", "--depth", "2"]) "matches"
    check (!rows.isEmpty) "Missing Touch Bar"
    let path ← str rows[0]! "path"
    has (← d.app #["inspect", "--path", path]) (json% {role: "AXFunctionRowTopLevelElement", actions: []})
    eq (← arr (← d.app #["actions", "--path", path]) "actions").size 0
    let outline ← d.raw #["show", "--depth", "2"]
    eq outline.exitCode 0
    contains outline.stdout "AXFunctionRowTopLevelElement"
    discard <| d.reject 77 #["press", "--path", path]
    check ((← arr (← d.app #["actions", "--path", ← d.submit]) "actions").contains (toJson "AXPress")) "Missing submit action"
    eq (← d.value) ""
    d.neighbors
    d.notSubmitted) "macos"
  cases := cases.push <| desktop "Unavailable native action metadata" (fun d => do
    let row ← d.control "Unavailable actions" "AXGroup"
    eq (← arr row "actions").size 0
    contains (← d.app #["tree", "--depth", "6", "--max-nodes", "1000"]).compress "Submit test draft"
    discard <| d.reject 77 #["press", "--path", ← str row "path"]
    d.notSubmitted) "macos" #[("BLINDLY4_FIXTURE_ROLE", "AXGroup")]
  for mode in #["unreadable", "invalid-count"] do
    cases := cases.push <| desktop s!"Unreadable draft {mode}" (fun d => do
      d.set "unreadable draft"
      check (!((← d.app #["inspect", "--path", ← d.draft]).getObjVal? "value").isOk) "Unreadable value exposed"
      d.focusDraft
      discard <| d.reject 77 #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", "anything"]
      discard <| d.reject 77 #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", ""]
      d.neighbors
      d.notSubmitted) "macos" #[("BLINDLY4_FIXTURE_VALUE", mode)]
  cases := cases.push <| desktop "macOS popup menu" (fun d => do
    discard <| d.app #["show-menu", "--path", ← d.path "Delivery choice" "AXPopUpButton"]
    check (!(← d.find "Choice two" "AXMenuItem").isEmpty) "Menu item missing"
    discard <| d.app #["key", "--key", "escape"]
    d.notSubmitted) "macos"
  cases := cases.push <| desktop "macOS native click and wheel input" (fun d => do
    let field ← d.app #["inspect", "--path", ← d.draft]
    let pos := field.getObjValD "position"
    discard <| d.app #["click", "--x", toString ((← number pos "x") + 40), "--y", toString ((← number pos "y") + 12)]
    has (← d.app #["focused"]) (json% {title: "Draft"})
    let scroll ← d.control "Scrollable options" "AXScrollArea"
    let pos := scroll.getObjValD "position"
    discard <| d.app #["click", "--x", toString ((← number pos "x") + 100), "--y", toString ((← number pos "y") + 100)]
    let y := fun _ : Unit => do number ((← d.control "Option 40" "AXStaticText").getObjValD "position") "y"
    let before ← y ()
    discard <| d.app #["scroll", "--direction", "up", "--amount", "10"]
    awaitState "scroll up" (return (← y ()) != before)
    discard <| d.app #["scroll", "--direction", "down", "--amount", "10"]
    awaitState "scroll down" (return Float.abs ((← y ()) - before) < 2)
    discard <| d.reject 64 #["scroll-to", "--path", ← d.draft]
    d.notSubmitted) "macos"
  return cases
end Tests
