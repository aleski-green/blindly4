mod native;
mod node;
mod x11;

use crate::{
    error::{Error, Result},
    input,
    invocation::Invocation,
    registry::Command,
};
pub use native::*;
pub use node::Node;
use std::time::Duration;

pub const USAGE_ON_STDERR: bool = true;
pub const PASTE_USES_CLIPBOARD: bool = false;
pub const DESCENDANT_DRAFT: bool = false;
pub const PASTE_POLL: (usize, f64) = (100, 0.01);
pub const FOCUS_SELECTION: bool = true;
pub const VALUE_ERROR: &str = "Target is not a writable AT-SPI text control";
pub fn with_runtime(run: impl FnOnce() -> Result<()>) -> Result<()> {
    run()
}
pub struct Session;
pub fn prepare(command: &Command, invocation: &Invocation) -> Result<Session> {
    input::validate(command, invocation)?;
    if !matches!(command.name, "schema" | "request-permission") && !x11_session() {
        return Err(Error::access(SESSION_ERROR));
    }
    match std::env::var("BLINDLY4_LINUX_TEXT_INPUT").as_deref() {
        Err(_) | Ok("atspi") => (),
        Ok("keyboard") => {
            if matches!(command.name, "paste" | "type" | "set-value" | "set-selected-text") {
                if let Some(text) = invocation.optional("text").or_else(|| invocation.optional("value")) {
                    if text.len() > 4096 || !text.is_ascii() || text.chars().any(char::is_control) {
                        return Err(Error::usage(
                            "Keyboard text input requires printable ASCII, at most 4096 bytes; use native editable text for Unicode",
                        ));
                    }
                    x11::validate_text(text)?;
                }
            }
        }
        Ok(_) => return Err(Error::usage("BLINDLY4_LINUX_TEXT_INPUT must be atspi or keyboard")),
    }
    Ok(Session)
}
pub fn help_requested(args: &[String], _: bool) -> bool {
    matches!(args, [value] if matches!(value.as_str(), "--help" | "help" | "-h"))
}
pub fn command_help(command: &Command) -> Result<()> {
    crate::json(&command.metadata())
}
pub fn profile(elapsed: Duration) -> String {
    format!("profile elapsed_ms={:.1} platform=linux", elapsed.as_secs_f64() * 1000.0)
}
pub fn report_pid(_: bool) -> bool {
    true
}
pub fn characters(text: &str) -> usize {
    text.chars().count()
}
pub fn role_matches(actual: &str, expected: &str) -> bool {
    actual.to_lowercase().trim_start_matches("ax") == expected.trim_start_matches("ax")
}
pub fn mutation_key(_: &str) -> &'static str {
    "action"
}
impl From<zbus::Error> for Error {
    fn from(value: zbus::Error) -> Self {
        Self::access(value.to_string())
    }
}
