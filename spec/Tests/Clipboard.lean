import Tests.Support
open Lean System
namespace Tests
abbrev Clipboard := Json → IO Json

def withClipboard (use : Clipboard → IO Unit) : IO Unit := do
  let spawned ← IO.Process.spawn {cmd := ← fixtureBinary, args := #["--test-pasteboard"], stdin := .piped, stdout := .piped, stderr := .piped}
  let (input, child) ← spawned.takeStdin
  let writer ← IO.mkRef (some input)
  let exited ← IO.asTask child.wait .dedicated
  let errors ← IO.asTask child.stderr.readToEnd .dedicated
  let request := fun (value : Json) => do
    let some stream ← writer.get | throw <| IO.userError "Clipboard transport closed"
    stream.putStrLn value.compress
    stream.flush
    let line ← IO.asTask child.stdout.getLine .dedicated
    awaitState "clipboard reply" (IO.hasFinished line)
    parse (← IO.ofExcept (← IO.wait line))
  try use request
  finally
    writer.set none
    try
      awaitState "clipboard EOF cleanup" (IO.hasFinished exited)
      let status ← IO.ofExcept (← IO.wait exited)
      check (status == 0) s!"Clipboard fixture failed: {← IO.ofExcept (← IO.wait errors)}"
    finally
      if !(← IO.hasFinished exited) then child.kill
      discard <| IO.wait exited

def clipboardText (text : String) : Json := Id.run do
  if !Platform.isWindows then
    return Json.mkObj [("public.utf8-plain-text", toJson (text.toUTF8.data.map UInt8.toNat))]
  let mut units : Array Nat := #[]
  for c in text.toList do
    let n := c.toNat
    if n ≤ 65535 then units := units.push n
    else
      units := units.push (55296 + (n - 65536) / 1024)
      units := units.push (56320 + (n - 65536) % 1024)
  let bytes := (units.push 0).flatMap fun n => #[n % 256, n / 256]
  return Json.mkObj [("CF_UNICODETEXT", toJson bytes)]

def clipboardItems (items : Array Json) : Json :=
  if Platform.isWindows then Json.mkObj (items.toList.flatMap fun j => j.getObj?.toOption.get!.toList)
  else Json.arr items

def expectClipboard (snapshot : Json) (items : Array Json) : IO Unit := do
  if !Platform.isWindows then
    check (snapshot == Json.arr items) "Clipboard contents mismatch"
  else
    let expected ← IO.ofExcept (clipboardItems items).getObj?
    let data ← IO.ofExcept (snapshot.getObjValD "data").getObj?
    eq data.toList.length expected.toList.length
    for (name, value) in expected.toList do
      let wanted ← IO.ofExcept (fromJson? value : Except String (Array Nat))
      let actual ← IO.ofExcept ((snapshot.getObjValD "data").getObjValAs? (Array Nat) name)
      check (actual.extract 0 wanted.size == wanted && (actual.extract wanted.size actual.size).all (· == 0)) s!"Clipboard format {name} changed"
    if expected.toList.isEmpty then eq (← arr snapshot "formats").size 0

private def pasteRejected (d : Desktop) (out : IO.Process.Output) : IO Json := do
  eq out.exitCode 77
  let value ← parse out.stdout
  has value (json% {code: "accessibility_error"})
  check (!(value.getObjVal? "verified").isOk) "Rejected paste claims verification"
  d.notSubmitted
  d.label "Submission count: 0"
  return value

private def duringPaste (d : Desktop) (text : String) (interfere : String → IO Unit) : IO IO.Process.Output := do
  let path ← d.draft
  let release ← d.path "Release pending paste" "AXButton"
  let worker ← IO.asTask (d.raw #["paste", "--target-path", path, "--text", text]) .dedicated
  try
    d.label "Paste pending: 1"
    check (!(← IO.hasFinished worker)) "Paste finished before interference"
    interfere release
    IO.ofExcept (← IO.wait worker)
  finally
    discard <| IO.wait worker

private def interrupted (name : String) (run : Desktop → IO Unit) (env : Env := #[]) : Case :=
  desktop name (fun d => withClipboard fun clip => do
    discard <| clip (json% {write: $(clipboardItems #[clipboardText "interruption fixture clipboard"])})
    run d) "windows" env

def clipboardCases : Array Case := Id.run do
  let mut cases := #[]
  for contents in #["empty", "unicode", "binary"] do
    cases := cases.push <| desktop s!"Restore {contents} clipboard after paste" fun d => do
      let text := clipboardText "clipboard مرحبا café 🪟"
      let items := if contents == "empty" then #[] else if contents == "unicode" then #[text] else
        #[text.setObjVal! "org.blindly4.fixture" (toJson (#[0,255,17,0] : Array Nat)), json% {"org.blindly4.fixture-second": [1,2,3,128]}]
      withClipboard fun clip => do
        let original ← clip (json% {write: $(clipboardItems items)})
        expectClipboard original items
        for value in #["", "pasted into fixture only: مرحبا café 🪟"] do
          d.set "replace this draft"
          d.paste value
          eq (← d.value) value
          check ((← clip (json% {})) == original) "Clipboard not restored"
          d.notSubmitted
          d.neighbors
  cases := cases.push <| desktop "Clipboard transport EOF restores prior contents" fun d => do
    withClipboard fun outer => do
      let original ← outer (json% {write: $(clipboardItems #[json% {"org.blindly4.fixture-original": [0,128,255,17]}])})
      withClipboard fun inner => do
        expectClipboard (← inner (json% {write: $(clipboardItems #[])})) #[]
        d.paste "cleanup check"
        eq (← d.value) "cleanup check"
      check ((← outer (json% {})) == original) "Nested transport did not restore clipboard"
    d.notSubmitted
  cases := cases.push <| desktop "Windows clipboard reader contention" (fun d => do
    withClipboard fun clip => do
      let original ← clip (json% {write: $(clipboardText "clipboard مرحبا café 🪟")})
      check ((← clip (json% {"read-next-update-ms": 100})) == (json% {readerArmed: true})) "Reader not armed"
      d.paste "after clipboard reader"
      eq (← d.value) "after clipboard reader"
      check ((← clip (json% {"reader-status": true})) == (json% {readUpdates: 1})) "Reader did not observe publication"
      check ((← clip (json% {})) == original) "Clipboard not restored"
    d.neighbors
    d.notSubmitted) "windows"
  cases := cases.push <| interrupted "Activate background fixture" (fun d => do
    check ((← arr (← success #["apps"]) "apps").any (fun j => j.getObjValD "pid" == toJson d.pid && j.getObjValD "frontmost" == toJson true)) "Background fixture not activated"
    eq (← d.value) ""
    d.notSubmitted) #[("BLINDLY4_FIXTURE_BACKGROUND", "1")]
  cases := cases.push <| interrupted "Busy clipboard preserves original draft" fun d => do
    d.set "original draft"
    let target ← d.draft
    withClipboard fun clip => do
      let original ← clip (json% {write: $(clipboardText "original clipboard")})
      let result ← try
        check ((← clip (json% {lock: true})) == (json% {locked: true})) "Clipboard did not lock"
        d.raw #["paste", "--target-path", target, "--text", "must not appear"]
      finally discard <| clip (json% {lock: false})
      let error ← pasteRejected d result
      contains (← str error "error") "Clipboard is busy"
      eq (← d.value) "original draft"
      check ((← clip (json% {})) == original) "Busy clipboard changed"
    d.neighbors
  cases := cases.push <| interrupted "Delayed paste consumes before clipboard restoration" (fun d => do
    withClipboard fun clip => do
      let original ← clip (json% {write: $(clipboardText "original clipboard")})
      let text := "Delayed native paste: مرحبا café 🪟"
      d.paste text
      eq (← d.value) text
      d.label "Paste completed: 1"
      check ((← clip (json% {})) == original) "Delayed clipboard restoration"
    d.neighbors
    d.notSubmitted) #[("BLINDLY4_FIXTURE_PASTE", "delay")]
  cases := cases.push <| interrupted "Competing copy preserved and substituted draft rejected" (fun d => do
    withClipboard fun clip => do
      discard <| clip (json% {write: $(clipboardText "original clipboard")})
      let newer ← IO.mkRef Json.null
      let result ← duringPaste d "requested draft" fun release => do
        newer.set (← clip (json% {write: $(clipboardText "newer copy")}))
        discard <| d.app #["press", "--path", release]
      discard <| pasteRejected d result
      eq (← d.value) "newer copy"
      d.label "Paste completed: 1"
      check ((← clip (json% {})) == (← newer.get)) "Competing copy overwritten"
    d.neighbors) #[("BLINDLY4_FIXTURE_PASTE", "hold")]
  cases := cases.push <| interrupted "Paste rejects changed focus after consumption" (fun d => do
    discard <| pasteRejected d (← d.raw #["paste", "--target-path", ← d.draft, "--text", "matching draft"])
    eq (← d.value) "matching draft"
    has (← d.app #["focused"]) (json% {title: "First field"})
    discard <| d.reject 77 #["key", "--key", "enter", "--target-path", ← d.draft, "--require-value", "matching draft"]
    d.label "Paste completed: 1"
    d.neighbors
    d.notSubmitted) #[("BLINDLY4_FIXTURE_PASTE", "focus-after")]
  cases := cases.push <| interrupted "Late paste consumption is not retried or submitted" (fun d => do
    withClipboard fun clip => do
      let original ← clip (json% {write: $(clipboardText "restored fixture clipboard")})
      let error ← pasteRejected d (← d.raw #["paste", "--target-path", ← d.draft, "--text", "requested draft"])
      contains (← str error "error") "Paste failed exact draft verification"
      eq (← d.value) ""
      d.label "Paste pending: 1"
      check ((← clip (json% {})) == original) "Clipboard not restored on failure"
      d.press "Release pending paste"
      eq (← d.value) "restored fixture clipboard"
      d.label "Paste completed: 1"
      discard <| d.reject 77 #["press", "--path", ← d.submit, "--require-value-path", ← d.draft, "--require-value", "requested draft"]
      d.notSubmitted
    d.neighbors) #[("BLINDLY4_FIXTURE_PASTE", "hold")]
  cases := cases.push <| interrupted "Other process takes focus during pending paste" (fun d =>
    withFixture #[("BLINDLY4_FIXTURE_BACKGROUND", "1")] (fun other => do
      let switch ← d.path "Switch fixture focus" "AXButton"
      let result ← duringPaste d "requested draft" fun release => do
        discard <| d.app #["press", "--path", switch]
        check ((← arr (← success #["apps"]) "apps").any (fun j => j.getObjValD "pid" == toJson other.pid && j.getObjValD "frontmost" == toJson true)) "Other fixture did not take focus"
        discard <| d.app #["press", "--path", release]
      discard <| pasteRejected d result
      eq (← d.value) "requested draft"
      d.neighbors
      other.neighbors
      eq (← other.value) ""
      other.notSubmitted) false) #[("BLINDLY4_FIXTURE_PASTE", "hold")]
  return cases
end Tests
