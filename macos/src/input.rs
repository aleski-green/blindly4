use crate::{
    clipboard::Clipboard,
    error::{Error, Result},
    guards,
    invocation::Invocation,
    native,
    node::Node,
};
use serde_json::{Value, json};
use unicode_segmentation::UnicodeSegmentation;

// Validate syntax before requesting Accessibility access or touching the UI.
pub fn validate(command: &str, i: &Invocation) -> Result<()> {
    if i.has("pid") {
        i.integer("pid", 0, 1, i32::MAX)?;
    }
    for name in ["path", "target-path", "require-value-path"] {
        if let Some(value) = i.optional(name) {
            guards::path(value)?;
        }
    }
    match command {
        "activate" => {
            i.value("pid")?;
        }
        "open" => guards::url(i.value("url")?)?,
        "tree" | "show" | "find" => {
            i.integer("depth", 4, 0, 64)?;
            if command == "tree" {
                i.integer("max-nodes", 250, 1, 10000)?;
            }
            if command == "find" {
                i.integer("limit", 25, 1, 10000)?;
                if !["title", "role", "value", "description"]
                    .iter()
                    .any(|name| i.has(name))
                {
                    return Err(Error::usage("find requires a search filter"));
                }
            }
        }
        "inspect" | "actions" | "focus" | "show-menu" | "scroll-to" => {
            i.value("path")?;
        }
        "press" => {
            i.value("path")?;
            i.pair("require-value-path", "require-value", false)?;
        }
        "set-value" | "set-selected-text" => {
            i.value("path")?;
            i.value("value")?;
        }
        "click" => {
            coordinates(i)?;
        }
        "type" | "paste" => {
            i.value("text")?;
            if i.has("target-path") && !i.has("pid") {
                return Err(Error::usage("paste --target-path requires --pid"));
            }
        }
        "key" => {
            native::parse_key(i.value("key")?)?;
            i.pair("target-path", "require-value", true)?;
            if i.has("target-path")
                && (i.value("target-path")?.is_empty()
                    || guards::normalize(i.value("require-value")?)
                        .trim()
                        .is_empty())
            {
                return Err(Error::usage(
                    "Guarded key requires a nonempty target path and draft",
                ));
            }
        }
        "scroll" => {
            direction(i)?;
            i.integer("amount", 3, 1, 100)?;
        }
        _ => {}
    }
    Ok(())
}
fn target(i: &Invocation) -> Result<i32> {
    let pid = i.pid()?;
    native::activate(pid)?;
    Ok(pid)
}
fn response(i: &Invocation, pid: i32, mut result: Value) -> Result<()> {
    if i.has("pid") {
        result["pid"] = json!(pid);
    }
    crate::json(&result)
}
fn coordinates(i: &Invocation) -> Result<(f64, f64)> {
    let (x, y) = (i.number("x")?, i.number("y")?);
    if x.abs() > 100000.0 || y.abs() > 100000.0 {
        return Err(Error::usage("Screen coordinate out of range"));
    }
    Ok((x, y))
}
fn direction(i: &Invocation) -> Result<String> {
    let direction = i.value("direction")?.to_lowercase();
    if !matches!(direction.as_str(), "up" | "down" | "left" | "right") {
        return Err(Error::usage("Invalid scroll direction"));
    }
    Ok(direction)
}
pub fn click(i: &Invocation) -> Result<()> {
    let (x, y) = coordinates(i)?;
    let pid = target(i)?;
    native::click(pid, x, y)?;
    response(i, pid, json!({"x": x, "y": y, "ok": true}))
}
pub fn type_text(i: &Invocation) -> Result<()> {
    let text = i.value("text")?;
    let pid = target(i)?;
    native::text(pid, text)?;
    response(
        i,
        pid,
        json!({"characters": text.graphemes(true).count(), "ok": true}),
    )
}
pub fn key(i: &Invocation) -> Result<()> {
    let key = i.value("key")?;
    let parsed = native::parse_key(key)?;
    let pid = target(i)?;
    if let Some(path) = i.optional("target-path") {
        Node::application(pid)?
            .resolve(path)?
            .require_focused_draft(i.value("require-value")?)?;
    }
    native::key(pid, parsed)?;
    let mut result = json!({"key": key, "ok": true});
    if let Some(path) = i.optional("target-path") {
        result["targetPath"] = json!(path);
        result["verified"] = json!(true);
    }
    response(i, pid, result)
}
pub fn selected_text(i: &Invocation) -> Result<()> {
    let path = i.value("path")?;
    let value = i.value("value")?;
    Node::application(i.pid()?)?
        .resolve(path)?
        .selected_text(value)?;
    crate::json(&json!({"path": path, "attribute": "AXSelectedText", "ok": true}))
}
pub fn scroll(i: &Invocation) -> Result<()> {
    let direction = direction(i)?;
    let amount = i.integer("amount", 3, 1, 100)?;
    let pid = target(i)?;
    native::scroll(pid, &direction, amount)?;
    response(
        i,
        pid,
        json!({"direction": direction, "amount": amount, "ok": true}),
    )
}
pub fn paste(i: &Invocation) -> Result<()> {
    let text = i.value("text")?;
    let path = i.optional("target-path");
    let pid = i.pid()?;
    let root = Node::application(pid)?;
    let initial = path.map(|p| root.resolve(p)).transpose()?;
    if let Some(node) = &initial {
        if !node.writable()? {
            return Err(Error::usage("Paste target is not a writable text control"));
        }
    }
    let mut clipboard = Clipboard::capture()?;
    native::activate(pid)?;
    // Re-resolve after activation; reject path changes instead of editing a new control.
    let resolve = || -> Result<Option<Node>> {
        let current = path.map(|p| root.resolve(p)).transpose()?;
        if let (Some(first), Some(current)) = (&initial, &current) {
            if !first.same(current) {
                return Err(Error::access(
                    "Paste target path changed; rediscover the control",
                ));
            }
        }
        Ok(current)
    };
    if let Some(node) = resolve()? {
        node.focus()?;
        node.set_value("")?;
        node.require_focused_draft("")?;
    }
    clipboard.replace(text)?;
    let outcome = (|| -> Result<()> {
        if let Some(node) = resolve()? {
            node.require_focused_draft("")?;
        }
        // Pasting an empty string is already complete after the verified clear.
        if !text.is_empty() || path.is_none() {
            native::key(pid, native::parse_key("command+v")?)?;
        }
        if path.is_some() {
            for _ in 0..100 {
                native::wait(0.01);
                if let Some(node) = resolve()? {
                    if node.exact_draft(text)?
                        && node.has_focus()?
                        && native::foreground_pid() == pid
                    {
                        return Ok(());
                    }
                }
            }
            return Err(Error::access(
                "Paste failed exact draft verification; do not send or repeat input without inspecting the draft",
            ));
        }
        native::wait(0.3);
        Ok(())
    })();
    let restoration = clipboard.restore();
    outcome?;
    restoration?;
    let mut result = json!({"characters": text.graphemes(true).count(), "ok": true});
    if let Some(path) = path {
        result["targetPath"] = json!(path);
        result["verified"] = json!(true);
    }
    response(i, pid, result)
}
