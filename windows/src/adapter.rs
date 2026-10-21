mod clipboard;
mod fixture;
mod native;
mod node;

use crate::{
    error::{Error, Result},
    input,
    invocation::Invocation,
    registry::Command,
};
pub use clipboard::Clipboard;
pub use native::{
    Key, PERMISSION_SUMMARY, SCHEMA_SUMMARY, VALUE_SUMMARY, activate_native, activation_pid, apps, click, foreground_pid, key, key_code,
    open_url, request_permission, schema, scroll, text, wait,
};
pub use node::Node;
use serde_json::json;
use std::time::Duration;
use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx, CoUninitialize};

pub const USAGE_ON_STDERR: bool = false;
pub struct ComApartment;
impl Drop for ComApartment {
    fn drop(&mut self) {
        unsafe { CoUninitialize() }
    }
}
pub fn with_runtime(run: impl FnOnce() -> Result<()>) -> Result<()> {
    run()
}
pub fn prepare(command: &Command, invocation: &Invocation) -> Result<ComApartment> {
    unsafe {
        CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
    }
    let session = ComApartment;
    native::dpi_awareness();
    // Preserve the published Windows error precedence for these commands.
    if command.name == "press" {
        invocation.pair("require-value-path", "require-value", false)?;
    }
    if matches!(command.name, "inspect" | "press") {
        Node::application(invocation.pid()?)?;
    }
    input::validate(command, invocation)?;
    Ok(session)
}
pub fn fixture(args: &[String]) -> Option<Result<()>> {
    if args == ["--test-app"] {
        Some(fixture::run())
    } else if args == ["--test-pasteboard"] {
        Some(clipboard::fixture::run())
    } else {
        None
    }
}
pub fn help_requested(args: &[String], global: bool) -> bool {
    args == ["--help"] || (global && args == ["help"])
}
pub fn command_help(command: &Command) -> Result<()> {
    crate::json(&command.metadata())
}
pub fn profile(elapsed: Duration) -> String {
    json!({"elapsedMs": elapsed.as_millis(), "platform": "windows"}).to_string()
}
pub fn report_pid(_: bool) -> bool {
    true
}
pub fn characters(text: &str) -> usize {
    text.chars().count()
}
pub fn role_matches(actual: &str, expected: &str) -> bool {
    actual.to_lowercase().contains(expected)
}
pub fn mutation_key(_: &str) -> &'static str {
    "action"
}
impl From<windows::core::Error> for Error {
    fn from(value: windows::core::Error) -> Self {
        Self::access(value.to_string())
    }
}

pub const DESCENDANT_DRAFT: bool = false;
pub const PASTE_POLL: (usize, f64) = (40, 0.025);
pub const FOCUS_SELECTION: bool = true;
pub const VALUE_ERROR: &str = "Target is not a writable UI Automation text control";
