mod ax;
mod clipboard;
mod fixture;
mod native;
mod node;

use crate::{error::Result, input, invocation::Invocation, registry::Command};
pub use clipboard::Clipboard;
pub use native::{
    Key, PERMISSION_SUMMARY, SCHEMA_SUMMARY, VALUE_SUMMARY, activate_native, activation_pid, apps, click, foreground_pid, key, key_code,
    open_url, request_permission, schema, scroll, text, wait,
};
pub use node::Node;
use std::time::Duration;
use unicode_segmentation::UnicodeSegmentation;

pub struct Session;

pub const USAGE_ON_STDERR: bool = true;
pub fn with_runtime(run: impl FnOnce() -> Result<()>) -> Result<()> {
    objc2::rc::autoreleasepool(|_| run())
}
pub fn prepare(command: &Command, invocation: &Invocation) -> Result<Session> {
    input::validate(command, invocation)?;
    if command.accessibility {
        ax::require_accessibility()?;
    }
    Ok(Session)
}
pub fn fixture(args: &[String]) -> Option<Result<()>> {
    if args == ["--test-app"] {
        Some(fixture::run())
    } else if args == ["--test-pasteboard"] {
        Some(clipboard::fixture())
    } else {
        None
    }
}
pub fn help_requested(args: &[String], global: bool) -> bool {
    args.first().is_some_and(|arg| ["--help", "-h", "help"].contains(&arg.as_str())) || (!global && args.iter().any(|arg| arg == "--help"))
}
pub fn command_help(command: &Command) -> Result<()> {
    println!(
        "{}\n{}\nRisk: {}\nRequires Accessibility permission: {}",
        command.metadata()["usage"].as_str().unwrap(),
        command.summary,
        command.risk,
        if command.accessibility { "yes" } else { "no" }
    );
    Ok(())
}
pub fn profile(elapsed: Duration) -> String {
    format!("profile elapsed_ms={:.1}", elapsed.as_secs_f64() * 1000.0)
}
pub fn report_pid(explicit: bool) -> bool {
    explicit
}
pub fn characters(text: &str) -> usize {
    text.graphemes(true).count()
}
pub fn role_matches(actual: &str, expected: &str) -> bool {
    let expected = if expected.starts_with("ax") { expected.to_owned() } else { format!("ax{expected}") };
    actual.to_lowercase() == expected
}
pub fn mutation_key(action: &str) -> &'static str {
    if matches!(action, "AXFocused" | "AXValue") { "attribute" } else { "action" }
}

pub const DESCENDANT_DRAFT: bool = true;
pub const PASTE_POLL: (usize, f64) = (100, 0.01);
pub const FOCUS_SELECTION: bool = false;
pub const VALUE_ERROR: &str = "Target is not a writable text control";
