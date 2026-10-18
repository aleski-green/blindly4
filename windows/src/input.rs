use crate::{
    clipboard::Clipboard,
    desktop::Desktop,
    error::{Error, Result},
    guards,
    invocation::Invocation,
    native,
};
use serde_json::json;
use std::{thread::sleep, time::Duration};

fn target(i: &Invocation) -> Result<i32> {
    let pid = i.pid()?;
    native::activate(pid)?;
    Ok(pid)
}
pub fn click(i: &Invocation) -> Result<()> {
    let x = i.number("x")?;
    let y = i.number("y")?;
    if x.abs() > 100000.0 || y.abs() > 100000.0 {
        return Err(Error::usage("Screen coordinate out of range"));
    }
    let pid = target(i)?;
    native::click(pid, x.round_ties_even() as i32, y.round_ties_even() as i32)?;
    crate::json(&json!({"x": x, "y": y, "pid": pid, "ok": true}))
}
pub fn type_text(i: &Invocation) -> Result<()> {
    let text = i.value("text")?;
    let pid = target(i)?;
    native::text(pid, text)?;
    crate::json(&json!({"characters": text.chars().count(), "pid": pid, "ok": true}))
}
pub fn key(i: &Invocation) -> Result<()> {
    i.pair("target-path", "require-value", true)?;
    let key = i.value("key")?;
    let keys = guards::parse_key(key)?;
    let pid = target(i)?;
    if let Some(path) = i.optional("target-path") {
        let node = Desktop::new(pid)?.resolve(path)?;
        guards::draft(
            node.writable()?,
            node.has_focus()?,
            node.exact_draft(i.value("require-value")?)?,
            native::foreground_pid() == pid,
        )?;
    }
    native::key(pid, &keys)?;
    let mut result = json!({"key": key, "pid": pid, "ok": true});
    if let Some(path) = i.optional("target-path") {
        result["targetPath"] = json!(path);
        result["verified"] = json!(true);
    }
    crate::json(&result)
}
pub fn selected_text(i: &Invocation) -> Result<()> {
    let value = i.value("value")?;
    let pid = i.pid()?;
    let path = i.value("path")?;
    let node = Desktop::new(pid)?.resolve(path)?;
    if !node.writable()? {
        return Err(Error::usage("Target is not a writable text control"));
    }
    node.focus()?;
    native::require_foreground(pid)?;
    if !node.has_focus()? {
        return Err(Error::access("Target lost focus"));
    }
    native::text(pid, value)?;
    crate::json(&json!({"path": path, "attribute": "AXSelectedText", "ok": true}))
}
pub fn scroll(i: &Invocation) -> Result<()> {
    let direction = i.value("direction")?.to_lowercase();
    if !matches!(direction.as_str(), "up" | "down" | "left" | "right") {
        return Err(Error::usage("Invalid scroll direction"));
    }
    let amount = i.integer("amount", 3, 1, 100)?;
    let pid = target(i)?;
    native::scroll(pid, &direction, amount)?;
    crate::json(&json!({"direction": direction, "amount": amount, "pid": pid, "ok": true}))
}
pub fn paste(i: &Invocation) -> Result<()> {
    let text = i.value("text")?;
    let path = i.optional("target-path");
    if path.is_some() && !i.has("pid") {
        return Err(Error::usage("paste --target-path requires --pid"));
    }
    let pid = i.pid()?;
    let node = path
        .map(|path| Desktop::new(pid)?.resolve(path))
        .transpose()?;
    if let Some(node) = &node {
        if !node.writable()? {
            return Err(Error::usage(
                "Paste blocked: --target-path must resolve to a writable UI Automation text control",
            ));
        }
    }
    // Freeze every clipboard format before clearing any existing draft. A format
    // that cannot be copied aborts before changing either clipboard or target.
    let mut clipboard = Clipboard::capture()?;
    native::activate(pid)?;
    if let Some(node) = &node {
        node.set_value("")?;
        if !node.exact_draft("")? {
            return Err(Error::access(
                "Paste blocked: existing draft could not be cleared",
            ));
        }
        node.focus()?;
        guards::draft(
            node.writable()?,
            node.has_focus()?,
            node.exact_draft("")?,
            native::foreground_pid() == pid,
        )?;
    }
    clipboard.replace(text)?;
    let outcome = (|| -> Result<()> {
        if let Some(node) = &node {
            guards::draft(
                node.writable()?,
                node.has_focus()?,
                node.exact_draft("")?,
                native::foreground_pid() == pid,
            )?;
        }
        native::key_named(pid, "ctrl+v")?;
        if let Some(node) = &node {
            for _ in 0..40 {
                if node.exact_draft(text)? && node.has_focus()? && native::foreground_pid() == pid {
                    return Ok(());
                }
                sleep(Duration::from_millis(25));
            }
            return Err(Error::access(
                "Paste failed exact draft verification; do not send or repeat input without inspecting the draft",
            ));
        }
        sleep(Duration::from_millis(300));
        Ok(())
    })();
    let restore = clipboard.restore();
    outcome?;
    restore?;
    let mut result = json!({"characters": text.chars().count(), "pid": pid, "ok": true});
    if let Some(path) = path {
        result["targetPath"] = json!(path);
        result["verified"] = json!(true);
    }
    crate::json(&result)
}
