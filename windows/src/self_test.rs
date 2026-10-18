use crate::{
    error::{Error, Result},
    guards,
    invocation::Invocation,
    native, registry,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeSet,
    process::{Child, Command, Stdio},
    thread::sleep,
    time::{Duration, Instant},
};
use windows::Win32::UI::{
    Input::KeyboardAndMouse::INPUT,
    WindowsAndMessaging::{PostMessageW, WM_CLOSE},
};

struct Checks {
    count: usize,
}
impl Checks {
    fn check(&mut self, condition: bool, reason: &str) -> Result<()> {
        if !condition {
            return Err(Error::unexpected(format!("Self-test failed: {reason}")));
        }
        self.count += 1;
        Ok(())
    }
    fn rejects<T>(&mut self, value: Result<T>, exit: i32) -> Result<()> {
        self.check(
            matches!(value, Err(e) if e.exit == exit),
            "invalid/unsafe input was accepted or returned the wrong exit code",
        )
    }
}
fn invocation(name: &str, args: &[&str]) -> Result<Invocation> {
    Invocation::new(
        registry::get(name)?,
        &args.iter().map(|s| s.to_string()).collect::<Vec<_>>(),
    )
}

fn permission_free() -> Result<usize> {
    let mut c = Checks { count: 0 };
    c.check(
        registry::ALL
            .iter()
            .map(|x| x.name)
            .collect::<BTreeSet<_>>()
            .len()
            == registry::ALL.len(),
        "duplicate command",
    )?;
    c.check(registry::ALL.len() == 22, "command parity")?;
    let expected: Value = serde_json::from_str(include_str!("../tests/schema-v2.json"))?;
    c.check(
        expected["commands"]
            == json!(
                registry::ALL
                    .iter()
                    .map(|c| c.metadata())
                    .collect::<Vec<_>>()
            ),
        "schema-version-2 compatibility",
    )?;
    for name in ["press", "key"] {
        c.check(
            registry::get(name)?.risk == "external-commit",
            "send risk classification",
        )?;
    }
    for name in [
        "apps", "tree", "show", "find", "focused", "inspect", "actions", "schema",
    ] {
        c.check(
            registry::get(name)?.risk == "read-only",
            "read risk classification",
        )?;
    }
    for name in ["serve", "snapshot", "changes", "workflow"] {
        c.rejects(registry::get(name), 64)?;
    }
    for args in [
        &["--lease", "x"][..],
        &["--depth"],
        &["--depth", "2", "--depth", "3"],
        &["--no-log"],
        &["--no-service"],
        &["extra"],
    ] {
        c.rejects(invocation("tree", args), 64)?;
    }
    for value in ["-1", "65", "2147483648", "x"] {
        c.rejects(
            invocation("tree", &["--depth", value])?.integer("depth", 4, 0, 64),
            64,
        )?;
    }
    for value in ["NaN", "inf", "-inf", "1e999"] {
        c.rejects(invocation("click", &["--x", value])?.number("x"), 64)?;
    }
    c.check(guards::path("0.2.15")? == [0, 2, 15], "path indexes")?;
    c.check(guards::path("")?.is_empty(), "root path")?;
    for path in ["-1", "1..2", "1.", "a", "2147483648", "0. 1", "١", "+1"] {
        c.rejects(guards::path(path), 64)?;
    }
    c.rejects(guards::path(&vec!["0"; 65].join(".")), 64)?;
    c.check(
        guards::exact("caf\u{e9}", "cafe\u{301}"),
        "canonical Unicode",
    )?;
    c.check(guards::exact("\u{200f}مرحبا", "مرحبا"), "directionality")?;
    c.check(guards::exact("", ""), "empty draft")?;
    for value in ["draft\n", "old draft", "Draft", " draft", "draft "] {
        c.check(!guards::exact(value, "draft"), "exact draft mismatch")?;
    }
    for url in [
        "file:///C:/test",
        "javascript:alert(1)",
        "shell:AppsFolder",
        "relative",
        "https://",
        "slack:",
    ] {
        c.rejects(guards::url(url), 64)?;
    }
    for url in [
        "https://example.com",
        "http://localhost/a",
        "slack://channel?id=test",
    ] {
        guards::url(url)?;
        c.count += 1;
    }
    for bits in 0..15 {
        c.rejects(
            guards::draft(bits & 1 != 0, bits & 2 != 0, bits & 4 != 0, bits & 8 != 0),
            77,
        )?;
    }
    guards::draft(true, true, true, true)?;
    c.count += 1;
    for args in [
        &["--target-path", "0", "--require-value", "draft"][..],
        &["--pid", "1", "--target-path", "0"],
        &["--pid", "1", "--require-value", "draft"],
    ] {
        c.rejects(
            invocation("key", args)?.pair("target-path", "require-value", true),
            64,
        )?;
    }
    c.rejects(
        invocation("press", &["--require-value", "draft"])?.pair(
            "require-value-path",
            "require-value",
            false,
        ),
        64,
    )?;
    invocation(
        "key",
        &["--pid", "1", "--target-path", "0", "--require-value", ""],
    )?
    .pair("target-path", "require-value", true)?;
    c.count += 1;
    c.check(
        guards::parse_key("command+a")? == [17, 65],
        "command maps to control",
    )?;
    c.check(
        guards::parse_key("enter")? == guards::parse_key("return")?,
        "enter alias",
    )?;
    c.check(guards::parse_key("delete")? == [8], "backward delete")?;
    c.check(
        guards::parse_key("forward-delete")? == [46],
        "forward delete",
    )?;
    for key in ["ctrl+bogus", "unknown+a", "", "ctrl+", "f0", "f25"] {
        c.rejects(guards::parse_key(key), 64)?;
    }
    c.check(
        size_of::<INPUT>() == if size_of::<usize>() == 8 { 40 } else { 28 },
        "SendInput ABI",
    )?;
    c.check(
        crate::node::optional_element(Err(windows::core::Error::empty()))?.is_none(),
        "successful null UIA pointer ends traversal",
    )?;
    c.rejects(
        crate::node::optional_element(Err(windows::core::Error::from_hresult(
            windows::Win32::Foundation::E_POINTER,
        ))),
        77,
    )?;
    c.rejects(
        crate::node::optional_element(Err(windows::core::Error::from_hresult(
            windows::core::HRESULT(
                windows::Win32::UI::Accessibility::UIA_E_ELEMENTNOTAVAILABLE as i32,
            ),
        ))),
        77,
    )?;
    Ok(c.count)
}
pub fn run() -> Result<()> {
    crate::json(
        &json!({"ok": true, "tests": permission_free()?, "platform": "windows", "suite": "permission-free"}),
    )
}
#[test]
fn safety_and_cli_contract() {
    permission_free().unwrap();
}

struct Fixture(Child);
impl Drop for Fixture {
    fn drop(&mut self) {
        if let Ok(windows) = native::windows() {
            for window in windows.into_iter().filter(|w| w.pid == self.0.id() as i32) {
                unsafe {
                    let _ = PostMessageW(
                        Some(window.handle),
                        WM_CLOSE,
                        Default::default(),
                        Default::default(),
                    );
                }
            }
        }
        for _ in 0..30 {
            if self.0.try_wait().ok().flatten().is_some() {
                return;
            }
            sleep(Duration::from_millis(100));
        }
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}
struct Live {
    exe: std::path::PathBuf,
    pid: String,
    checks: Checks,
}
impl Live {
    fn run(&mut self, expected: i32, args: &[&str]) -> Result<Value> {
        let output = Command::new(&self.exe)
            .args(args)
            .stdin(Stdio::null())
            .output()?;
        if output.status.code() != Some(expected) {
            return Err(Error::unexpected(format!(
                "{} exited {:?}, expected {expected}: {} {}",
                args.join(" "),
                output.status.code(),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            )));
        }
        self.checks.count += 1;
        Ok(serde_json::from_slice(&output.stdout)?)
    }
    fn command(&mut self, expected: i32, command: &str, args: &[&str]) -> Result<Value> {
        let pid = self.pid.clone();
        let mut all = vec![command, "--pid", pid.as_str()];
        all.extend_from_slice(args);
        self.run(expected, &all)
    }
    fn find(&mut self, title: &str, role: &str) -> Result<String> {
        let result = self.command(
            0,
            "find",
            &["--title", title, "--role", role, "--depth", "6"],
        )?;
        result["matches"][0]["path"]
            .as_str()
            .map(str::to_owned)
            .ok_or_else(|| Error::unexpected(format!("Fixture control missing: {title} ({role})")))
    }
    fn draft(&mut self) -> Result<String> {
        self.find("Draft", "AXTextField")
    }
    fn value(&mut self) -> Result<Value> {
        let path = self.draft()?;
        Ok(self.command(0, "inspect", &["--path", &path])?["value"].clone())
    }
}
pub fn integration() -> Result<()> {
    use std::os::windows::process::CommandExt;
    let exe = std::env::current_exe()?;
    let mut fixture = Fixture(
        Command::new(&exe)
            .arg("--test-app")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .creation_flags(0x08000000)
            .spawn()?,
    );
    let start = Instant::now();
    while !native::windows()?
        .iter()
        .any(|w| w.pid == fixture.0.id() as i32)
    {
        if fixture.0.try_wait()?.is_some() || start.elapsed() > Duration::from_secs(10) {
            return Err(Error::unexpected("Fixture did not open"));
        }
        sleep(Duration::from_millis(100));
    }
    sleep(Duration::from_millis(300));
    let mut t = Live {
        exe,
        pid: fixture.0.id().to_string(),
        checks: Checks { count: 0 },
    };
    let apps = t.run(0, &["apps"])?;
    t.checks.check(
        apps["apps"]
            .as_array()
            .is_some_and(|apps| apps.iter().any(|a| a["pid"] == fixture.0.id())),
        "fixture in apps",
    )?;
    let tree = t.command(0, "tree", &["--depth", "5"])?;
    t.checks
        .check(tree["tree"]["role"] == "AXApplication", "application root")?;
    let tree = t.command(0, "tree", &["--max-nodes", "1"])?;
    t.checks
        .check(tree["truncated"] == true, "truncation reported")?;
    let draft = t.draft()?;
    t.command(0, "set-value", &["--path", &draft, "--value", "old draft"])?;
    let value = t.value()?;
    t.checks.check(value == "old draft", "ValuePattern write")?;
    let draft = t.draft()?;
    t.command(0, "focus", &["--path", &draft])?;
    let focus = t.command(0, "focused", &[])?;
    t.checks
        .check(focus["focused"] == true, "focused control")?;
    let draft = t.draft()?;
    t.command(0, "paste", &["--target-path", &draft, "--text", ""])?;
    let value = t.value()?;
    t.checks.check(value == "", "empty guarded paste")?;
    let message = "Windows مرحبا café 🪟";
    let draft = t.draft()?;
    t.command(0, "paste", &["--target-path", &draft, "--text", message])?;
    let value = t.value()?;
    t.checks.check(value == message, "Unicode paste")?;
    let draft = t.draft()?;
    t.command(
        77,
        "key",
        &[
            "--key",
            "return",
            "--target-path",
            &draft,
            "--require-value",
            "wrong draft",
        ],
    )?;
    let submit = t.find("Submit test draft", "AXButton")?;
    let draft = t.draft()?;
    t.command(
        77,
        "press",
        &[
            "--path",
            &submit,
            "--require-value-path",
            &draft,
            "--require-value",
            "wrong draft",
        ],
    )?;
    let submit = t.find("Submit test draft", "AXButton")?;
    t.command(
        64,
        "paste",
        &["--target-path", &submit, "--text", "never entered"],
    )?;
    let submit = t.find("Submit test draft", "AXButton")?;
    t.command(
        64,
        "press",
        &["--path", &submit, "--expect-description", "Wrong button"],
    )?;
    let unchanged = t.command(0, "find", &["--title", "Not submitted"])?;
    t.checks.check(
        !unchanged["matches"].as_array().unwrap().is_empty(),
        "rejected submissions had no side effect",
    )?;
    let submit = t.find("Submit test draft", "AXButton")?;
    let draft = t.draft()?;
    t.command(
        0,
        "press",
        &[
            "--path",
            &submit,
            "--expect-description",
            "Submit",
            "--require-value-path",
            &draft,
            "--require-value",
            message,
        ],
    )?;
    let result = t.command(0, "find", &["--title", &format!("Submitted: {message}")])?;
    t.checks.check(
        result["matches"].as_array().is_some_and(|a| a.len() == 1),
        "observed guarded submission",
    )?;
    let draft = t.draft()?;
    t.command(0, "focus", &["--path", &draft])?;
    let draft = t.draft()?;
    t.command(
        0,
        "key",
        &[
            "--key",
            "ctrl+a",
            "--target-path",
            &draft,
            "--require-value",
            message,
        ],
    )?;
    t.command(0, "type", &["--text", "Typed Unicode: مرحبا"])?;
    let value = t.value()?;
    t.checks.check(
        value == "Typed Unicode: مرحبا",
        &format!("Unicode SendInput: observed {value}"),
    )?;
    let password = t.find("Password", "AXSecureTextField")?;
    let secret = t.command(0, "inspect", &["--path", &password])?;
    t.checks
        .check(secret["value"].is_null(), "password redaction")?;
    let password = t.find("Password", "AXSecureTextField")?;
    t.command(
        64,
        "paste",
        &["--target-path", &password, "--text", "never entered"],
    )?;
    t.command(77, "inspect", &["--path", "99999"])?;
    t.command(77, "click", &["--x", "-99999", "--y", "-99999"])?;
    crate::json(
        &json!({"ok": true, "tests": t.checks.count, "suite": "live Windows UI Automation + SendInput", "fixturePid": fixture.0.id()}),
    )
}
