use super::Node;
pub use super::x11::{activate as activate_native, click, key, scroll};
use crate::{
    application::require_foreground,
    error::{Error, Result},
};
use serde_json::{Value, json};
use std::{thread::sleep, time::Duration};

pub const SCHEMA_SUMMARY: &str = "Print command metadata. Linux AT-SPI retains AX names for compatibility.";
pub const PERMISSION_SUMMARY: &str = "Report Linux accessibility and foreground verification availability.";
pub const VALUE_SUMMARY: &str = "Set an editable AT-SPI text control.";
pub fn schema(commands: Vec<Value>) -> Value {
    json!({"schemaVersion": 2, "platform": "linux", "backend": "ATSPI", "commands": commands})
}
pub fn activation_pid(pid: i32) -> Value {
    json!(pid)
}
pub const SESSION_ERROR: &str = "Linux desktop access requires an X11 session; Wayland is not supported";
pub fn x11_session() -> bool {
    let session = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    (session == "x11" || (session.is_empty() && std::env::var_os("WAYLAND_DISPLAY").is_none()))
        && std::env::var_os("DISPLAY").is_some_and(|value| !value.is_empty())
}
pub fn foreground_pid() -> i32 {
    if x11_session() { super::x11::foreground_pid().unwrap_or(0) } else { 0 }
}
pub fn request_permission() -> Value {
    let supported = x11_session();
    json!({"trusted": supported && Node::desktop().is_ok(), "platform": "linux", "foregroundAvailable": foreground_pid() > 0,
        "inputAvailable": supported, "error": if supported { "" } else { SESSION_ERROR },
        "note": "X11 window ownership and exact-draft guards are checked for each action."})
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
fn unavailable<T>(feature: &str) -> Result<T> {
    Err(Error::access(format!("{feature} is unavailable on this backend")))
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
