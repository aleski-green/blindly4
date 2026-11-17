import Lean.Data.Json
open Lean System
namespace Tests

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def eq [BEq α] [ToString α] (actual expected : α) : IO Unit :=
  check (actual == expected) s!"Expected {expected}, received {actual}"

def parse (text : String) : IO Json := IO.ofExcept (Json.parse text)
def str (value : Json) (key : String) : IO String := IO.ofExcept (value.getObjValAs? String key)
def arr (value : Json) (key : String) : IO (Array Json) := IO.ofExcept (value.getObjValAs? (Array Json) key)
def has (value expected : Json) : IO Unit := do
  for (key, wanted) in (← IO.ofExcept expected.getObj?).toList do
    let actual ← IO.ofExcept (value.getObjVal? key)
    check (actual == wanted) s!"Field {key}: expected {wanted.compress}, received {actual.compress}"
def contains (text part : String) : IO Unit := check (text.contains part) s!"Missing {part} in {text}"
def number (j : Json) (key : String) : IO Float := do
  let n ← IO.ofExcept (j.getObjValAs? JsonNumber key)
  return n.toFloat

def awaitState (label : String) (observe : IO Bool) (timeout := 5000) : IO Unit := do
  let endTime := (← IO.monoMsNow) + timeout
  repeat
    if ← observe then return
    if (← IO.monoMsNow) ≥ endTime then throw <| IO.userError s!"Timed out: {label}"
    IO.sleep 50

def root : IO FilePath := do
  let cwd ← IO.currentDir
  if ← (cwd / "shared").isDir then return cwd
  if let some parent := cwd.parent then
    if ← (parent / "shared").isDir then return parent
  throw <| IO.userError "Run lake -d spec test from the blindly4 checkout"

def binary : IO String := do
  let dir ← root
  return (dir / (← IO.getEnv "BLINDLY4_BIN").getD
    (if Platform.isWindows then ".build/windows/blindly4.exe" else ".build/release/blindly4")).toString

def fixtureBinary : IO String := do
  if let some path ← IO.getEnv "BLINDLY4_FIXTURE_BIN" then return ((← root) / path).toString
  binary

abbrev Env := Array (String × Option String)

def capture (args : Array String) (env : Env := #[]) : IO IO.Process.Output := do
  let child ← IO.Process.spawn {cmd := ← binary, args, env, cwd := ← root, stdin := .null, stdout := .piped, stderr := .piped}
  let exited ← IO.asTask child.wait .dedicated
  let output ← IO.asTask child.stdout.readToEnd .dedicated
  let error ← IO.asTask child.stderr.readToEnd .dedicated
  try
    awaitState "CLI process" (IO.hasFinished exited) 30000
    return ⟨← IO.ofExcept (← IO.wait exited), ← IO.ofExcept (← IO.wait output), ← IO.ofExcept (← IO.wait error)⟩
  finally
    if !(← IO.hasFinished exited) then child.kill
    discard <| IO.wait exited

def success (args : Array String) : IO Json := do
  let out ← capture args
  check (out.exitCode == 0) s!"{args.toList}: exit {out.exitCode}: {out.stdout} {out.stderr}"
  eq out.stderr ""
  parse out.stdout

def usage (args : Array String) (env : Env := #[]) : IO Unit := do
  let out ← capture args env
  check (out.exitCode == 64) s!"{args.toList}: expected usage error, got {out.exitCode}: {out.stdout} {out.stderr}"
  if Platform.isWindows then
    let value ← parse out.stdout
    has value (json% {code: "usage_error"})
    check (!(← str value "error").trimAscii.isEmpty) "Missing error message"
  else
    eq out.stdout ""
    check (!out.stderr.trimAscii.isEmpty) "Missing usage diagnostic"

structure Case where
  name : String
  run : IO Unit
  platform : String := "all"
  live : Bool := false

def test (name : String) (run : IO Unit) (platform := "all") : Case := ⟨name, run, platform, false⟩

structure Desktop where
  pid : Nat

def Desktop.app (d : Desktop) (args : Array String) := success (#[args[0]!, "--pid", toString d.pid] ++ args.extract 1 args.size)
def Desktop.raw (d : Desktop) (args : Array String) := capture (#[args[0]!, "--pid", toString d.pid] ++ args.extract 1 args.size)
def Desktop.reject (d : Desktop) (status : UInt32) (args : Array String) : IO Json := do
  let out ← d.raw args
  check (out.exitCode == status) s!"Expected rejection {status}: {args.toList}: {out.stdout} {out.stderr}"
  if status == 64 && Platform.isOSX then
    eq out.stdout ""
    check (!out.stderr.trimAscii.isEmpty) "Missing rejection diagnostic"
    return Json.null
  let result ← parse out.stdout
  has result (json% {code: $(if status == 64 then "usage_error" else "accessibility_error")})
  check (!(← str result "error").trimAscii.isEmpty) "Missing rejection diagnostic"
  return result

def Desktop.find (d : Desktop) (title : String) (role := "") : IO (Array Json) := do
  arr (← d.app (#["find", "--title", title, "--depth", "6"] ++ if role == "" then #[] else #["--role", role])) "matches"
def Desktop.control (d : Desktop) (title role : String) : IO Json := do
  let rows ← d.find title role
  check (rows.size == 1) s!"Expected one {role} named {title}, got {Json.arr rows}"
  return rows[0]!
def Desktop.path (d : Desktop) (title role : String) : IO String := do str (← d.control title role) "path"
def Desktop.draft (d : Desktop) := d.path "Draft" "AXTextField"
def Desktop.submit (d : Desktop) := d.path "Submit test draft" "AXButton"
def Desktop.value (d : Desktop) (title := "Draft") := do str (← d.control title "AXTextField") "value"
def Desktop.set (d : Desktop) (text : String) : IO Unit := do discard <| d.app #["set-value", "--path", ← d.draft, "--value", text]
def Desktop.label (d : Desktop) (text : String) : IO Unit := awaitState text do
  return (← d.find text "AXStaticText").any (fun j => (j.getObjValAs? String "title").toOption == some text)
def Desktop.notSubmitted (d : Desktop) : IO Unit := do eq (← d.find "Not submitted").size 1
def Desktop.neighbors (d : Desktop) : IO Unit := do
  eq (← d.value "First field") "first untouched"
  eq (← d.value "Third field") "third untouched"
def Desktop.press (d : Desktop) (title : String) (role := "AXButton") : IO Unit := do discard <| d.app #["press", "--path", ← d.path title role]
def Desktop.focusDraft (d : Desktop) : IO Unit := do discard <| d.app #["focus", "--path", ← d.draft]
def Desktop.paste (d : Desktop) (text : String) : IO Unit := do has (← d.app #["paste", "--target-path", ← d.draft, "--text", text]) (json% {verified: true})

def withFixture (env : Env) (use : Desktop → IO Unit) (activate := true) : IO Unit := do
  check ((← IO.getEnv "BLINDLY4_LIVE") == some "1") "Live tests require BLINDLY4_LIVE=1"
  let cleared := #["VALUE", "ROLE", "PASTE", "CHILD", "BACKGROUND"].map fun key => ("BLINDLY4_FIXTURE_" ++ key, none)
  let child ← IO.Process.spawn {cmd := ← fixtureBinary, args := #["--test-app"], env := cleared ++ env, stdin := .null, stdout := .null, stderr := .null}
  let d := Desktop.mk child.pid.toNat
  let exited ← IO.asTask child.wait .dedicated
  try
    let previous ← IO.mkRef Json.null
    awaitState "stable foreground fixture" (do
      check (!(← IO.hasFinished exited)) "Fixture exited before opening"
      let apps ← arr (← success #["apps"]) "apps"
      if !apps.any (fun j => j.getObjValD "pid" == toJson child.pid.toNat) then return false
      if activate then
        let active ← d.raw #["activate"]
        if active.exitCode != 0 then return false
      let ready ← d.raw #["find", "--title", "Fixture ready", "--role", "AXStaticText", "--limit", "1"]
      if ready.exitCode != 0 then return false
      let observed ← parse ready.stdout
      let settled := !(← arr observed "matches").isEmpty && observed == (← previous.get)
      previous.set observed
      return settled) 10000
    use d
  catch error =>
    IO.eprintln s!"Fixture {child.pid}: {(← d.raw #["focused"]).stdout}"
    IO.eprintln s!"Draft: {(← d.raw #["find", "--title", "Draft"]).stdout}"
    throw error
  finally
    if Platform.isWindows then
      discard <| IO.Process.output {cmd := "taskkill", args := #["/PID", toString child.pid, "/T", "/F"]}
    else if !(← IO.hasFinished exited) then child.kill
    discard <| IO.wait exited

def desktop (name : String) (run : Desktop → IO Unit) (platform := "all") (env : Env := #[]) : Case :=
  ⟨name, withFixture env run, platform, true⟩
end Tests
