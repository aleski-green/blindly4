use crate::{
    ax,
    error::{Error, Result},
};
use core_graphics::{
    event::{
        CGEvent, CGEventFlags, CGEventTapLocation, CGEventType, CGMouseButton, ScrollEventUnit,
    },
    event_source::{CGEventSource, CGEventSourceStateID},
    geometry::CGPoint,
};
use objc2::rc::Retained;
use objc2_app_kit::{
    NSApplicationActivationOptions, NSApplicationActivationPolicy, NSRunningApplication,
    NSWorkspace,
};
use objc2_foundation::{NSDate, NSRunLoop, NSString, NSURL};
use serde_json::{Value, json};

pub const SCHEMA_SUMMARY: &str = "Print machine-readable command and safety metadata.";
pub const PERMISSION_SUMMARY: &str = "Request macOS Accessibility permission.";
pub const VALUE_SUMMARY: &str = "Write AXValue on a writable accessibility element.";
pub fn schema(commands: Vec<Value>) -> Value {
    json!({"schemaVersion": 2, "commands": commands})
}
pub fn activation_pid(pid: i32) -> Value {
    json!(pid.to_string())
}
pub fn request_permission() -> Value {
    let trusted = ax::request_permission();
    json!({"trusted": trusted, "message": if trusted { "Accessibility access is enabled." } else { "A permission prompt was requested. Enable your terminal in System Settings, then rerun the command." }})
}
pub fn wait(seconds: f64) {
    // NSRunLoop may return early when it has no pending sources. Keep Quartz
    // events and their source alive for the entire dispatch interval even then.
    let duration = std::time::Duration::from_secs_f64(seconds);
    let start = std::time::Instant::now();
    NSRunLoop::currentRunLoop().runUntilDate(&NSDate::dateWithTimeIntervalSinceNow(seconds));
    std::thread::sleep(duration.saturating_sub(start.elapsed()));
}

pub fn foreground_pid() -> i32 {
    // NSWorkspace refreshes running-application properties on the main run loop.
    // Pump it before every check so a mid-command focus change cannot use a
    // cached foreground PID. AXFocusedApplication is not supported by every host.
    wait(0.001);
    NSWorkspace::sharedWorkspace()
        .frontmostApplication()
        .map_or(0, |app| app.processIdentifier())
}

pub fn require_app(pid: i32) -> Result<Retained<NSRunningApplication>> {
    NSRunningApplication::runningApplicationWithProcessIdentifier(pid)
        .filter(|app| !app.isTerminated())
        .ok_or_else(|| Error::access(format!("PID {pid} is not a running application")))
}
pub fn apps() -> Result<Vec<Value>> {
    Ok(NSWorkspace::sharedWorkspace().runningApplications().iter()
        .filter(|app| app.activationPolicy() == NSApplicationActivationPolicy::Regular)
        .map(|app| json!({"name": app.localizedName().map(|s| s.to_string()).unwrap_or_default(), "pid": app.processIdentifier(), "bundleId": app.bundleIdentifier().map(|s| s.to_string()).unwrap_or_default()})).collect())
}
pub fn activate(pid: i32) -> Result<()> {
    let app = require_app(pid)?;
    if foreground_pid() == pid {
        return Ok(());
    }
    app.unhide();
    #[allow(deprecated)]
    if !app.activateWithOptions(NSApplicationActivationOptions::ActivateIgnoringOtherApps) {
        return Err(Error::access(format!("Could not activate PID {pid}")));
    }
    for _ in 0..20 {
        wait(0.05);
        if foreground_pid() == pid {
            return Ok(());
        }
    }
    require_foreground(pid)
}
pub fn require_foreground(pid: i32) -> Result<()> {
    if pid > 0 && foreground_pid() == pid {
        Ok(())
    } else {
        Err(Error::access(
            "Target application is not frontmost; refusing cross-app input",
        ))
    }
}
pub fn open_url(value: &str) -> Result<()> {
    let url = NSURL::URLWithString(&NSString::from_str(value))
        .ok_or_else(|| Error::usage("Invalid URL"))?;
    if NSWorkspace::sharedWorkspace().openURL(&url) {
        Ok(())
    } else {
        Err(Error::access("Could not open URL"))
    }
}
fn source() -> Result<CGEventSource> {
    CGEventSource::new(CGEventSourceStateID::HIDSystemState)
        .map_err(|_| Error::access("Could not create event source"))
}
pub fn click(pid: i32, x: f64, y: f64) -> Result<()> {
    require_foreground(pid)?;
    if ax::pid(&ax::hit_test(x, y)?)? != pid {
        return Err(Error::access("Click point belongs to another process"));
    }
    let source = source()?;
    let point = CGPoint::new(x, y);
    let down = CGEvent::new_mouse_event(
        source.clone(),
        CGEventType::LeftMouseDown,
        point,
        CGMouseButton::Left,
    )
    .map_err(|_| Error::access("Could not create mouse event"))?;
    let up = CGEvent::new_mouse_event(source, CGEventType::LeftMouseUp, point, CGMouseButton::Left)
        .map_err(|_| Error::access("Could not create mouse event"))?;
    require_foreground(pid)?;
    down.post(CGEventTapLocation::HID);
    up.post(CGEventTapLocation::HID);
    wait(0.05);
    Ok(())
}
pub fn parse_key(text: &str) -> Result<(u16, CGEventFlags)> {
    let lower = text.to_lowercase();
    let parts: Vec<_> = lower.split('+').collect();
    let mut flags = CGEventFlags::empty();
    for modifier in &parts[..parts.len() - 1] {
        flags |= match *modifier {
            "command" | "cmd" => CGEventFlags::CGEventFlagCommand,
            "control" | "ctrl" => CGEventFlags::CGEventFlagControl,
            "option" | "alt" => CGEventFlags::CGEventFlagAlternate,
            "shift" => CGEventFlags::CGEventFlagShift,
            _ => return Err(Error::usage(format!("Unsupported modifier: {modifier}"))),
        };
    }
    let code = match parts[parts.len() - 1] {
        "return" | "enter" => 36,
        "tab" => 48,
        "space" => 49,
        "escape" | "esc" => 53,
        "delete" | "backspace" => 51,
        "forward-delete" => 117,
        "left" => 123,
        "right" => 124,
        "down" => 125,
        "up" => 126,
        "home" => 115,
        "end" => 119,
        "pageup" => 116,
        "pagedown" => 121,
        "a" => 0,
        "b" => 11,
        "c" => 8,
        "d" => 2,
        "e" => 14,
        "f" => 3,
        "g" => 5,
        "h" => 4,
        "i" => 34,
        "j" => 38,
        "k" => 40,
        "l" => 37,
        "m" => 46,
        "n" => 45,
        "o" => 31,
        "p" => 35,
        "q" => 12,
        "r" => 15,
        "s" => 1,
        "t" => 17,
        "u" => 32,
        "v" => 9,
        "w" => 13,
        "x" => 7,
        "y" => 16,
        "z" => 6,
        "0" => 29,
        "1" => 18,
        "2" => 19,
        "3" => 20,
        "4" => 21,
        "5" => 23,
        "6" => 22,
        "7" => 26,
        "8" => 28,
        "9" => 25,
        "f1" => 122,
        "f2" => 120,
        "f3" => 99,
        "f4" => 118,
        "f5" => 96,
        "f6" => 97,
        "f7" => 98,
        "f8" => 100,
        "f9" => 101,
        "f10" => 109,
        "f11" => 103,
        "f12" => 111,
        key => return Err(Error::usage(format!("Unsupported key: {key}"))),
    };
    Ok((code, flags))
}
pub fn key(pid: i32, key: (u16, CGEventFlags)) -> Result<()> {
    let source = source()?;
    let down = CGEvent::new_keyboard_event(source.clone(), key.0, true)
        .map_err(|_| Error::access("Could not create key event"))?;
    let up = CGEvent::new_keyboard_event(source, key.0, false)
        .map_err(|_| Error::access("Could not create key event"))?;
    down.set_flags(key.1);
    up.set_flags(key.1);
    require_foreground(pid)?;
    down.post(CGEventTapLocation::HID);
    up.post(CGEventTapLocation::HID);
    wait(0.05);
    Ok(())
}
pub fn text(pid: i32, text: &str) -> Result<()> {
    // Quartz limits Unicode event payloads. Chunk on scalar boundaries, never in
    // the middle of a surrogate pair, and recheck the foreground for every chunk.
    let mut chunk = String::new();
    let mut units = 0;
    for c in text.chars().chain(std::iter::once('\0')) {
        if (units + c.len_utf16() > 20 || c == '\0') && !chunk.is_empty() {
            let source = source()?;
            let down = CGEvent::new_keyboard_event(source.clone(), 0, true)
                .map_err(|_| Error::access("Could not create text event"))?;
            let up = CGEvent::new_keyboard_event(source, 0, false)
                .map_err(|_| Error::access("Could not create text event"))?;
            down.set_string(&chunk);
            up.set_string(&chunk);
            down.set_flags(CGEventFlags::empty());
            up.set_flags(CGEventFlags::empty());
            require_foreground(pid)?;
            down.post(CGEventTapLocation::HID);
            up.post(CGEventTapLocation::HID);
            wait(0.01);
            chunk.clear();
            units = 0;
        }
        if c != '\0' {
            chunk.push(c);
            units += c.len_utf16();
        }
    }
    Ok(())
}
pub fn scroll(pid: i32, direction: &str, amount: i32) -> Result<()> {
    let (vertical, horizontal) = match direction {
        "up" => (amount, 0),
        "down" => (-amount, 0),
        "left" => (0, amount),
        _ => (0, -amount),
    };
    let event =
        CGEvent::new_scroll_event(source()?, ScrollEventUnit::LINE, 2, vertical, horizontal, 0)
            .map_err(|_| Error::access("Could not create scroll event"))?;
    require_foreground(pid)?;
    event.post(CGEventTapLocation::HID);
    wait(0.05);
    Ok(())
}
