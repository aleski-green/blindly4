import Tests.Support
open Lean System
namespace Tests

def formCases : Array Case := Id.run do
  let mut cases := #[]
  cases := cases.push <| desktop "Three fields in order" fun d => do
    let fields := (← arr (← d.app #["find", "--role", "AXTextField"]) "matches").filter (fun j => j.getObjValD "subrole" != toJson "AXSecureTextField")
    check ((← fields.mapM (fun j => str j "title")) == #["First field", "Draft", "Third field"]) "Field order"
    let positions ← fields.mapM (fun j => number (j.getObjValD "position") "y")
    check (positions[0]! ≤ positions[1]! && positions[1]! ≤ positions[2]!) "Fields not vertically ordered"
    d.neighbors
    eq (← d.value) ""
  for (input, submission) in #[("paste", "press"), ("type", "enter"), ("paste", "space")] do
    cases := cases.push <| desktop s!"{input} second field and submit with {submission}" fun d => do
      let message := s!"Second field via {input}: مرحبا café 🪟"
      if input == "paste" then
        d.set "old draft"
        d.paste message
      else
        d.focusDraft
        has (← d.app #["focused"]) (json% {title: "Draft", focused: true})
        discard <| d.app #["type", "--text", message]
        has (← d.app #["focused"]) (json% {focused: true, value: $(message)})
      eq (← d.value) message
      d.neighbors
      d.notSubmitted
      if submission == "press" then
        has (← d.app #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", message]) (json% {verified: true})
      else
        discard <| d.app #["focus", "--path", ← d.submit]
        has (← d.app #["focused"]) (json% {title: "Submit test draft", role: "AXButton", focused: true})
        discard <| d.app #["key", "--key", submission]
      d.label ("Submitted: " ++ message)
      d.label "Submission count: 1"
      eq (← d.value) message
      d.neighbors
  cases := cases.push <| desktop "Guarded Enter submits once" fun d => do
    let message := "Enter from the second field"
    d.paste message
    has (← d.app #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", message]) (json% {verified: true})
    eq (← d.value) message
    d.label ("Submitted: " ++ message)
    d.label "Submission count: 1"
    d.neighbors
  cases := cases.push <| desktop "Space edits without submission" fun d => do
    d.focusDraft
    discard <| d.app #["type", "--text", "hello"]
    discard <| d.app #["key", "--key", "space", "--target-path", ← d.draft, "--require-value", "hello"]
    eq (← d.value) "hello "
    d.notSubmitted
    d.label "Submission count: 0"
    d.neighbors
  cases := cases.push <| desktop "Replace selected text" fun d => do
    d.set "replace this"
    d.focusDraft
    discard <| d.app #["key", "--key", if Platform.isWindows then "ctrl+a" else "command+a", "--target-path", ← d.draft, "--require-value", "replace this"]
    discard <| d.app #["set-selected-text", "--path", ← d.draft, "--value", "replacement مرحبا"]
    eq (← d.value) "replacement مرحبا"
    d.neighbors
    d.notSubmitted
  for submission in #["press", "enter"] do
    cases := cases.push <| desktop s!"{submission} rejects changed second field" fun d => do
      discard <| d.app #["set-value", "--path", ← d.path "First field" "AXTextField", "--value", "original draft"]
      d.paste "original draft"
      d.set "changed before submission"
      if submission == "press" then
        discard <| d.reject 77 #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", "original draft"]
      else
        d.focusDraft
        discard <| d.reject 77 #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", "original draft"]
      eq (← d.value) "changed before submission"
      eq (← d.value "First field") "original draft"
      eq (← d.value "Third field") "third untouched"
      d.notSubmitted
      d.label "Submission count: 0"
  cases := cases.push <| desktop "Empty verified paste" fun d => do
    d.set "old draft"
    d.paste ""
    eq (← d.value) ""
    d.notSubmitted
  cases := cases.push <| desktop "Unicode character count and implicit PID" fun d => do
    let message := "é🙂"
    d.focusDraft
    let explicit ← d.app #["type", "--text", message]
    has explicit (json% {pid: $(d.pid), characters: $(if Platform.isWindows then 3 else 2)})
    eq (← d.value) message
    d.set ""
    d.focusDraft
    let implicit ← success #["type", "--text", message]
    check ((implicit.getObjVal? "pid").isOk == Platform.isWindows) "Implicit PID presence"
    if Platform.isWindows then has implicit (json% {pid: $(d.pid)})
    has implicit (json% {characters: $(explicit.getObjValD "characters")})
    eq (← d.value) message
    d.neighbors
    d.notSubmitted
  cases := cases.push <| desktop "Complete form discovery and submit action" fun d => do
    check ((← arr (← success #["apps"]) "apps").any (fun j => j.getObjValD "pid" == toJson d.pid)) "Fixture absent from apps"
    let tree ← d.app #["tree", "--depth", "6", "--max-nodes", "1000"]
    has tree (json% {truncated: false})
    has (tree.getObjValD "tree") (json% {role: "AXApplication"})
    contains tree.compress "Submit test draft"
    contains tree.compress "AXSecureTextField"
    has (← d.app #["inspect", "--path", ""]) (json% {role: "AXApplication"})
    let outline ← d.raw #["show", "--depth", "6"]
    eq outline.exitCode 0
    for text in #["AXApplication", "Draft", "Submit test draft"] do contains outline.stdout text
    check ((← arr (← d.app #["actions", "--path", ← d.submit]) "actions").contains (toJson "AXPress")) "Missing submit action"
  cases := cases.push <| desktop "Bounded traversal and secure-field redaction" fun d => do
    let tree ← d.app #["tree", "--max-nodes", "1"]
    has tree (json% {truncated: true})
    check (((tree.getObjValD "tree").getObjValAs? (Array Json) "children").toOption.getD #[] |>.isEmpty) "Traversal limit"
    eq (← arr (← d.app #["find", "--title", "Draft", "--depth", "0"]) "matches").size 0
    let limited ← d.app #["find", "--role", "AXTextField", "--limit", "1"]
    eq (← arr limited "matches").size 1
    has limited (json% {truncated: true})
    let passwords := (← d.find "Password").filter (fun j => #[j.getObjValD "role", j.getObjValD "subrole"].contains (toJson "AXSecureTextField"))
    eq passwords.size 1
    let path ← str passwords[0]! "path"
    check ((← d.app #["inspect", "--path", path]).getObjValD "value" == .null) "Password value exposed"
    check (!(← d.app #["tree", "--depth", "6", "--max-nodes", "1000"]).compress.contains "fixture secret") "Tree exposed password"
    eq (← arr (← d.app #["find", "--value", "fixture secret"]) "matches").size 0
    let shown ← d.raw #["show", "--depth", "6"]
    eq shown.exitCode 0
    check (!shown.stdout.contains "fixture secret") "Outline exposed password"
    discard <| d.reject 64 #["paste", "--target-path", path, "--text", "blocked"]
    d.notSubmitted
  for actual in #["old draft", " draft", "draft ", "draft\n", "Draft"] do
    cases := cases.push <| desktop s!"Exact draft rejection {repr actual}" fun d => do
      d.set actual
      d.focusDraft
      discard <| d.reject 77 #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", "draft"]
      discard <| d.reject 77 #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", "draft"]
      eq (← d.value) actual
      d.notSubmitted
  for (actual, expected) in #[("café", "café"), ("‏مرحبا", "مرحبا"), ("", "")] do
    cases := cases.push <| desktop s!"Normalized guarded submission {repr actual}" fun d => do
      d.set actual
      has (← d.app #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", expected]) (json% {verified: true})
      d.label ("Submitted: " ++ actual)
      d.label "Submission count: 1"
  cases := cases.push <| desktop "Wrong focus, target, description and cross-app click rejection" fun d => do
    d.set "unchanged"
    discard <| d.app #["focus", "--path", ← d.path "First field" "AXTextField"]
    discard <| d.reject 77 #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", "unchanged"]
    discard <| d.reject 64 #["press", "--path", ← d.submit, "--expect-description", "wrong button"]
    discard <| d.reject 64 #["paste", "--target-path", ← d.submit, "--text", "never entered"]
    discard <| d.reject 77 #["inspect", "--path", "99999"]
    discard <| d.reject 77 #["click", "--x", "-99999", "--y", "-99999"]
    eq (← d.value) "unchanged"
    d.notSubmitted
  cases := cases.push <| desktop "Checkbox accessible press" fun d => do
    d.label "Checkbox: unchecked"
    for state in #["checked", "unchecked"] do
      d.press "Test checkbox" "AXCheckBox"
      d.label ("Checkbox: " ++ state)
    d.notSubmitted
  cases := cases.push <| desktop "Delayed focus settles without repeated input" (fun d => do
    d.press "Delay draft focus"
    has (← d.app #["focused"]) (json% {title: "First field"})
    d.paste "entered once"
    has (← d.app #["focused"]) (json% {title: "Draft", value: "entered once"})
    d.notSubmitted
    d.neighbors) "all" #[("BLINDLY4_FIXTURE_VALUE", "delayed-focus")]
  cases := cases.push <| desktop "Formatting whitespace and exact nonempty matching" (fun d => do
    d.set ""
    eq (← d.value) "\r\n"
    d.paste "exact message"
    eq (← d.value) "exact message"
    d.set "exact message\r\n"
    discard <| d.reject 77 #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", "exact message"]
    d.paste ""
    eq (← d.value) "\r\n"
    d.notSubmitted
    d.neighbors) "all" #[("BLINDLY4_FIXTURE_VALUE", "whitespace")]
  cases := cases.push <| desktop "Successive Unicode typing processes" fun d => do
    for index in [:30] do
      let message := s!"{index}: " ++ String.join (List.replicate 3 "abcdefghij مرحبا café 🪟 ")
      d.set ""
      d.focusDraft
      has (← d.app #["type", "--text", message]) (json% {characters: $(message.length)})
      eq (← d.value) message
    d.neighbors
    d.notSubmitted
  cases := cases.push <| desktop "Readable root rejects mutations" fun d => do
    d.set "unchanged"
    check ((← d.app #["actions", "--path", ""]) == (json% {path: "", actions: []})) "Root actions"
    for command in #["focus", "press", "show-menu", "scroll-to"] do discard <| d.reject 64 #[command, "--path", ""]
    discard <| d.reject 64 #["set-value", "--path", "", "--value", "never entered"]
    discard <| d.reject 64 #["paste", "--target-path", "", "--text", "never entered"]
    discard <| d.reject 64 #["key", "--key", "enter", "--target-path", "", "--require-value", "unchanged"]
    eq (← d.value) "unchanged"
    d.notSubmitted
  cases := cases.push <| desktop "Checkbox keyboard Space" fun d => do
    discard <| d.app #["focus", "--path", ← d.path "Test checkbox" "AXCheckBox"]
    for state in #["checked", "unchecked"] do
      discard <| d.app #["key", "--key", "space"]
      d.label ("Checkbox: " ++ state)
    d.label "Submission count: 0"
  return cases
end Tests
