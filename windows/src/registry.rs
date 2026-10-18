use crate::{
    desktop,
    error::{Error, Result},
    guards, input,
    invocation::Invocation,
    native,
};
use serde_json::{Value, json};

pub struct Command {
    pub name: &'static str,
    pub arguments: &'static str,
    pub summary: &'static str,
    pub risk: &'static str,
    pub accessibility: bool,
    pub execute: fn(&Invocation) -> Result<()>,
}
impl Command {
    pub fn options(&self) -> Vec<&str> {
        let mut options: Vec<_> = self
            .arguments
            .split("--")
            .skip(1)
            .map(|s| {
                s.split(|c: char| !c.is_ascii_lowercase() && c != '-')
                    .next()
                    .unwrap()
            })
            .collect();
        options.sort_unstable();
        options.dedup();
        options
    }
    pub fn metadata(&self) -> Value {
        json!({"name": self.name, "usage": format!("blindly4 {} {}", self.name, self.arguments).trim(), "summary": self.summary, "risk": self.risk, "requiresAccessibility": self.accessibility, "options": self.options()})
    }
}
macro_rules! command {
    ($name:literal, $args:expr, $summary:literal, $risk:literal, $access:literal, $execute:expr) => {
        Command {
            name: $name,
            arguments: $args,
            summary: $summary,
            risk: $risk,
            accessibility: $access,
            execute: $execute,
        }
    };
}
const PATH_ARGS: &str = "--path INDEX[.INDEX...] [--pid PID]";
pub static ALL: &[Command] = &[
    command!(
        "schema",
        "",
        "Print command metadata. Windows UIA retains AX role/action names for compatibility.",
        "read-only",
        false,
        |_| {
            crate::json(
                &json!({"schemaVersion": 2, "platform": "windows", "backend": "UIAutomation", "commands": ALL.iter().map(Command::metadata).collect::<Vec<_>>()}),
            )
        }
    ),
    command!(
        "request-permission",
        "",
        "Windows UI Automation needs no macOS permission. Elevated and secure desktops remain inaccessible.",
        "ui-mutation",
        false,
        |_| {
            crate::json(
                &json!({"trusted": true, "platform": "windows", "note": "Available on the current interactive desktop at the same integrity level. Does not elevate or change permissions."}),
            )
        }
    ),
    command!(
        "apps",
        "",
        "List visible GUI applications and PIDs.",
        "read-only",
        false,
        |_| crate::json(&json!({"apps": native::apps()?}))
    ),
    command!(
        "activate",
        "--pid PID",
        "Bring an application to the foreground and verify it.",
        "ui-mutation",
        true,
        |i| {
            i.value("pid")?;
            let pid = i.pid()?;
            native::activate(pid)?;
            crate::json(&json!({"pid": pid, "ok": true}))
        }
    ),
    command!(
        "open",
        "--url URL",
        "Open an HTTP, HTTPS or Slack URL.",
        "ui-mutation",
        true,
        |i| {
            let url = i.value("url")?;
            guards::url(url)?;
            native::open_url(url)?;
            crate::json(&json!({"url": url, "ok": true}))
        }
    ),
    command!(
        "tree",
        "[--pid PID] [--depth N] [--max-nodes N]",
        "Read a bounded live accessibility tree.",
        "read-only",
        true,
        desktop::tree
    ),
    command!(
        "show",
        "[--pid PID] [--depth N]",
        "Print a readable live outline with paths.",
        "read-only",
        true,
        desktop::show
    ),
    command!(
        "find",
        "[--title TEXT] [--role ROLE] [--value TEXT] [--description TEXT] [--pid PID] [--depth N] [--limit N]",
        "Search current accessible properties.",
        "read-only",
        true,
        desktop::find
    ),
    command!(
        "focused",
        "[--pid PID]",
        "Read the focused control without changing focus.",
        "read-only",
        true,
        desktop::focused
    ),
    command!(
        "inspect",
        PATH_ARGS,
        "Inspect one live element.",
        "read-only",
        true,
        |i| crate::json(
            &desktop::Desktop::new(i.pid()?)?
                .resolve(i.value("path")?)?
                .detail(None)?
        )
    ),
    command!(
        "actions",
        PATH_ARGS,
        "List supported actions.",
        "read-only",
        true,
        |i| crate::json(
            &json!({"path": i.value("path")?, "actions": desktop::Desktop::new(i.pid()?)?.resolve(i.value("path")?)?.actions()?})
        )
    ),
    command!(
        "focus",
        PATH_ARGS,
        "Focus an element.",
        "ui-mutation",
        true,
        |i| desktop::mutate(i, "AXFocused", |n| n.focus())
    ),
    command!(
        "show-menu",
        PATH_ARGS,
        "Expand an accessible menu control when supported.",
        "ui-mutation",
        true,
        |i| desktop::mutate(i, "AXShowMenu", |n| n.expand())
    ),
    command!(
        "scroll-to",
        PATH_ARGS,
        "Scroll an accessible item into view.",
        "ui-mutation",
        true,
        |i| desktop::mutate(i, "AXScrollToVisible", |n| n.scroll_to())
    ),
    command!(
        "press",
        "--path INDEX[.INDEX...] [--pid PID] [--expect-description TEXT] [--require-selected] [--require-value-path PATH --require-value TEXT]",
        "Invoke or select a control; may submit external data.",
        "external-commit",
        true,
        desktop::press
    ),
    command!(
        "set-value",
        "--path INDEX[.INDEX...] [--pid PID] --value TEXT",
        "Set a writable ValuePattern.",
        "ui-mutation",
        true,
        |i| {
            let value = i.value("value")?;
            desktop::mutate(i, "AXValue", |n| n.set_value(value))
        }
    ),
    command!(
        "set-selected-text",
        "--path INDEX[.INDEX...] [--pid PID] --value TEXT",
        "Replace selected text in a focused writable control.",
        "ui-mutation",
        true,
        input::selected_text
    ),
    command!(
        "click",
        "--x X --y Y [--pid PID]",
        "Click a screen coordinate in the verified target application.",
        "ui-mutation",
        true,
        input::click
    ),
    command!(
        "type",
        "--text TEXT [--pid PID]",
        "Inject Unicode text into the foreground application.",
        "ui-mutation",
        true,
        input::type_text
    ),
    command!(
        "paste",
        "--text TEXT [--pid PID] [--target-path PATH]",
        "Paste, optionally verifying an exact writable target draft.",
        "ui-mutation",
        true,
        input::paste
    ),
    command!(
        "scroll",
        "--direction up|down|left|right [--amount LINES] [--pid PID]",
        "Inject bounded wheel input into the foreground application.",
        "ui-mutation",
        true,
        input::scroll
    ),
    command!(
        "key",
        "--key KEY [--pid PID] [--target-path PATH --require-value TEXT]",
        "Inject a key; a guarded key requires exact focused draft and PID.",
        "external-commit",
        true,
        input::key
    ),
];
pub fn get(name: &str) -> Result<&'static Command> {
    ALL.iter()
        .find(|c| c.name == name)
        .ok_or_else(|| Error::usage(format!("Unknown command: {name}")))
}
pub fn help() -> String {
    format!(
        "Blindly4 for Windows — native UI Automation, stateless CLI\n{}\nGlobal: --profile. Paths are live: rediscover before input. Serialize desktop workflows.",
        ALL.iter()
            .map(|c| format!(
                "  {} {}\n    {} [{}]",
                c.name, c.arguments, c.summary, c.risk
            ))
            .collect::<Vec<_>>()
            .join("\n")
    )
}
