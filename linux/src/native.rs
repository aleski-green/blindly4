use super::Node;
use crate::{
    application::require_foreground,
    error::{Error, Result},
};
use serde_json::{Value, json};
use std::{thread::sleep, time::Duration};
use zbus::blocking::{Connection, Proxy};

pub const SCHEMA_SUMMARY: &str = "Print command metadata. Linux AT-SPI retains AX names for compatibility.";
pub const PERMISSION_SUMMARY: &str = "Report Linux accessibility and foreground verification availability.";
pub const VALUE_SUMMARY: &str = "Set an editable AT-SPI text control.";
pub fn schema(commands: Vec<Value>) -> Value {
    json!({"schemaVersion": 2, "platform": "linux", "backend": "ATSPI", "commands": commands})
}
pub fn activation_pid(pid: i32) -> Value {
    json!(pid)
}
pub fn wayland() -> bool {
    std::env::var("XDG_SESSION_TYPE").map(|value| value == "wayland").unwrap_or_else(|_| std::env::var_os("WAYLAND_DISPLAY").is_some())
}
pub fn foreground_pid() -> i32 {
    if !wayland() {
        return super::x11::foreground_pid().unwrap_or(0);
    }
    fn query() -> Result<u32> {
        let session = Connection::session()?;
        Ok(Proxy::new(&session, "org.gnome.Shell", "/org/sapiens/Blindly/Foreground", "org.sapiens.Blindly.Foreground1")?
            .call("Get", &())?)
    }
    query().ok().and_then(|pid| i32::try_from(pid).ok()).unwrap_or(0)
}
pub fn request_permission() -> Value {
    let input = Connection::session().ok().is_some_and(|connection| {
        Proxy::new(&connection, "org.sapiens.Blindly.Input", "/org/sapiens/Blindly/Input", "org.freedesktop.DBus.Peer")
            .and_then(|proxy| proxy.call::<_, _, ()>("Ping", &()))
            .is_ok()
    });
    json!({"trusted": Node::desktop().is_ok(), "platform": "linux", "foregroundAvailable": foreground_pid() > 0,
        "inputAvailable": input,
        "note": "AT-SPI access does not grant input consent. Wayland requires the optional foreground extension and a portal session."})
}
pub fn apps() -> Result<Vec<Value>> {
    let foreground = foreground_pid();
    let mut result = vec![];
    for node in Node::desktop()?.children()? {
        if let Ok(pid) = node.process_id() {
            result.push(json!({"pid": pid, "name": node.text("AXTitle")?, "bundleIdentifier": null, "frontmost": pid == foreground}));
        }
    }
    Ok(result)
}
pub fn activate_native(pid: i32) -> Result<()> {
    if !wayland() {
        return super::x11::activate(pid);
    }
    let root = Node::application(pid)?;
    for window in root.children()? {
        if window.role()? == "AXWindow" && window.focus_native().is_ok() {
            return Ok(());
        }
    }
    Err(Error::access("Compositor declined activation; bring the target window to the foreground"))
}
pub fn open_url(url: &str) -> Result<()> {
    let status = std::process::Command::new("xdg-open").arg(url).status()?;
    if status.success() { Ok(()) } else { Err(Error::access("Desktop declined opening the URL")) }
}
pub fn wait(seconds: f64) {
    sleep(Duration::from_secs_f64(seconds));
}
pub struct Key {
    pub code: u32,
    pub modifiers: Vec<usize>,
}
impl Key {
    pub fn new(code: u32, modifiers: &[usize]) -> Self {
        Self { code, modifiers: modifiers.to_vec() }
    }
}
pub fn key_code(key: &str) -> Option<u32> {
    Some(match key {
        "enter" => 0xff0d,
        "tab" => 0xff09,
        "escape" => 0xff1b,
        "space" => 0x20,
        "backspace" => 0xff08,
        "forward-delete" => 0xffff,
        "up" => 0xff52,
        "down" => 0xff54,
        "left" => 0xff51,
        "right" => 0xff53,
        "home" => 0xff50,
        "end" => 0xff57,
        "pageup" => 0xff55,
        "pagedown" => 0xff56,
        _ if key.len() == 1 && key.as_bytes()[0].is_ascii_alphanumeric() => key.as_bytes()[0] as u32,
        _ => 0xffbe + key.strip_prefix('f')?.parse::<u32>().ok().filter(|n| (1..=24).contains(n))? - 1,
    })
}
pub fn text(pid: i32, text: &str) -> Result<()> {
    require_foreground(pid)?;
    Node::application(pid)?.focused()?.selected_text(text)
}
pub fn keyboard_text_input() -> bool {
    std::env::var("BLINDLY4_LINUX_TEXT_INPUT").as_deref() == Ok("keyboard")
}
pub fn keyboard_ready() -> Result<()> {
    if wayland() {
        for (key, expected) in [("sources", "[('xkb', 'us')]"), ("xkb-options", "@as []")] {
            let setting = std::process::Command::new("gsettings").args(["get", "org.gnome.desktop.input-sources", key]).output()?;
            if !setting.status.success() || String::from_utf8_lossy(&setting.stdout).trim() != expected {
                return Err(Error::access("Wayland keyboard text requires one US input source with no XKB options"));
            }
        }
        Proxy::new(&Connection::session()?, "org.sapiens.Blindly.Input", "/org/sapiens/Blindly/Input", "org.freedesktop.DBus.Peer")?
            .call::<_, _, ()>("Ping", &())?;
    }
    Ok(())
}
fn unavailable<T>(feature: &str) -> Result<T> {
    Err(Error::access(format!("{feature} is unavailable on this backend")))
}
pub fn key(pid: i32, key: &Key) -> Result<()> {
    if !wayland() {
        return super::x11::key(pid, key);
    }
    require_foreground(pid)?;
    let session = Connection::session()?;
    let mut modifiers: Vec<u32> = key.modifiers.iter().map(|index| [0xffe3, 0xffe3, 0xffe9, 0xffe1][*index]).collect();
    modifiers.sort_unstable();
    modifiers.dedup();
    Ok(Proxy::new(&session, "org.sapiens.Blindly.Input", "/org/sapiens/Blindly/Input", "org.sapiens.Blindly.Input1")?
        .call("Key", &(pid as u32, key.code, modifiers))?)
}
pub fn click(pid: i32, x: f64, y: f64) -> Result<()> {
    if wayland() {
        require_foreground(pid)?;
        Ok(Proxy::new(&Connection::session()?, "org.sapiens.Blindly.Input", "/org/sapiens/Blindly/Input", "org.sapiens.Blindly.Input1")?
            .call("Click", &(pid as u32, x, y))?)
    } else {
        super::x11::click(pid, x, y)
    }
}
pub fn scroll(pid: i32, direction: &str, amount: i32) -> Result<()> {
    if wayland() {
        require_foreground(pid)?;
        Ok(Proxy::new(&Connection::session()?, "org.sapiens.Blindly.Input", "/org/sapiens/Blindly/Input", "org.sapiens.Blindly.Input1")?
            .call("Scroll", &(pid as u32, direction, amount))?)
    } else {
        super::x11::scroll(pid, direction, amount)
    }
}
pub struct Clipboard;
impl Clipboard {
    pub fn capture() -> Result<Self> {
        unavailable("Clipboard transport")
    }
    pub fn replace(&mut self, _: &str) -> Result<()> {
        unavailable("Clipboard transport")
    }
    pub fn restore(&mut self) -> Result<()> {
        unavailable("Clipboard transport")
    }
}
pub fn desktop_fixture() -> Result<()> {
    unavailable("The shared desktop fixture")
}
pub fn clipboard_fixture() -> Result<()> {
    unavailable("The shared clipboard fixture")
}
