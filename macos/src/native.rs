use super::ax;
use crate::application::require_foreground;
use crate::error::{Error, Result};
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
pub fn activate_native(pid: i32) -> Result<()> {
    let app = require_app(pid)?;
    app.unhide();
    #[allow(deprecated)]
    if !app.activateWithOptions(NSApplicationActivationOptions::ActivateIgnoringOtherApps) {
        return Err(Error::access(format!("Could not activate PID {pid}")));
    }
    Ok(())
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
    post(pid, &[down, up])
}
fn post(pid: i32, events: &[CGEvent]) -> Result<()> {
    require_foreground(pid)?;
    for event in events {
        event.post(CGEventTapLocation::HID);
    }
    // Keep events and their retained sources alive until Quartz has consumed them.
    wait(0.05);
    Ok(())
}
fn keyboard_events(code: u16) -> Result<[CGEvent; 2]> {
    let source = source()?;
    let [down, up] = [true, false].map(|pressed| {
        CGEvent::new_keyboard_event(source.clone(), code, pressed)
            .map_err(|_| Error::access("Could not create key event"))
    });
    Ok([down?, up?])
}
pub struct Key(u16, CGEventFlags);

impl Key {
    pub fn new(code: u16, modifiers: &[usize]) -> Self {
        let flags = [
            CGEventFlags::CGEventFlagCommand,
            CGEventFlags::CGEventFlagControl,
            CGEventFlags::CGEventFlagAlternate,
            CGEventFlags::CGEventFlagShift,
        ];
        Self(
            code,
            modifiers
                .iter()
                .fold(CGEventFlags::empty(), |all, &i| all | flags[i]),
        )
    }
}
pub fn key_code(key: &str) -> Option<u16> {
    // Quartz codes are physical positions, not ASCII values.
    const LETTERS: [u16; 26] = [
        0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16,
        6,
    ];
    const DIGITS: [u16; 10] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25];
    const FUNCTIONS: [u16; 12] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111];
    if key.len() == 1 {
        match key.as_bytes()[0] {
            b'a'..=b'z' => return Some(LETTERS[(key.as_bytes()[0] - b'a') as usize]),
            b'0'..=b'9' => return Some(DIGITS[(key.as_bytes()[0] - b'0') as usize]),
            _ => {}
        }
    }
    if let Some(number) = key.strip_prefix('f').and_then(|s| s.parse::<usize>().ok()) {
        // Preserve the Mac grammar: f01 is not an alias for f1.
        if key == format!("f{number}") {
            return number
                .checked_sub(1)
                .and_then(|i| FUNCTIONS.get(i))
                .copied();
        }
    }
    Some(match key {
        "enter" => 36,
        "tab" => 48,
        "space" => 49,
        "escape" => 53,
        "backspace" => 51,
        "forward-delete" => 117,
        "left" => 123,
        "right" => 124,
        "down" => 125,
        "up" => 126,
        "home" => 115,
        "end" => 119,
        "pageup" => 116,
        "pagedown" => 121,
        _ => return None,
    })
}
pub fn key(pid: i32, key: &Key) -> Result<()> {
    let events = keyboard_events(key.0)?;
    for event in &events {
        event.set_flags(key.1);
    }
    post(pid, &events)
}
pub fn text(pid: i32, text: &str) -> Result<()> {
    // Quartz limits Unicode event payloads. Chunk on scalar boundaries, never in
    // the middle of a surrogate pair, and recheck the foreground for every chunk.
    let mut chunk = String::new();
    let mut units = 0;
    for c in text.chars().chain(std::iter::once('\0')) {
        if (units + c.len_utf16() > 20 || c == '\0') && !chunk.is_empty() {
            let events = keyboard_events(0)?;
            for event in &events {
                event.set_string(&chunk);
                event.set_flags(CGEventFlags::empty());
            }
            post(pid, &events)?;
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
    post(pid, &[event])
}
