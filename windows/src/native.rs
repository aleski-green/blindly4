use crate::application::require_foreground;
use crate::error::{Error, Result};
use serde_json::{Value, json};
use std::{collections::BTreeMap, thread::sleep, time::Duration};
use windows::{
    Win32::{
        Foundation::*,
        System::Threading::*,
        UI::{HiDpi::*, Input::KeyboardAndMouse::*, Shell::ShellExecuteW, WindowsAndMessaging::*},
    },
    core::{BOOL, PCWSTR, PWSTR},
};

pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
pub fn dpi_awareness() {
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    }
}
pub struct Window {
    pub handle: HWND,
    pub pid: i32,
    pub title: String,
}
pub fn window_pid(handle: HWND) -> i32 {
    let mut pid = 0;
    unsafe {
        GetWindowThreadProcessId(handle, Some(&mut pid));
    }
    pid as i32
}
pub fn foreground_pid() -> i32 {
    let window = unsafe { GetForegroundWindow() };
    let pid = super::node::Node::window_application_pid(window);
    if unsafe { GetForegroundWindow() } == window { pid } else { 0 }
}
pub fn windows() -> Result<Vec<Window>> {
    unsafe extern "system" fn collect_visible_window(handle: HWND, windows_pointer: LPARAM) -> BOOL {
        unsafe {
            if IsWindowVisible(handle).as_bool() {
                let mut title = [0u16; 1024];
                let length = GetWindowTextW(handle, &mut title) as usize;
                let pid = window_pid(handle);
                if pid > 0 && length > 0 {
                    let visible_windows = &mut *(windows_pointer.0 as *mut Vec<Window>);
                    visible_windows.push(Window { handle, pid, title: String::from_utf16_lossy(&title[..length]) });
                }
            }
        }
        BOOL(1)
    }
    let mut visible_windows = Vec::<Window>::new();
    unsafe {
        EnumWindows(Some(collect_visible_window), LPARAM(&mut visible_windows as *mut _ as isize))?;
    }
    visible_windows.sort_by_key(|window| window.handle.0 as isize);
    Ok(visible_windows)
}
pub fn process_name(pid: i32) -> String {
    unsafe {
        let Ok(process) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid as u32) else {
            return String::new();
        };
        let mut path = [0u16; 32768];
        let mut length = path.len() as u32;
        let result = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(path.as_mut_ptr()), &mut length);
        let _ = CloseHandle(process);
        if result.is_err() {
            return String::new();
        }
        std::path::Path::new(&String::from_utf16_lossy(&path[..length as usize]))
            .file_stem()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned()
    }
}
pub fn apps() -> Result<Vec<Value>> {
    let mut groups = BTreeMap::<i32, Vec<String>>::new();
    for window in windows()? {
        groups.entry(window.pid).or_default().push(window.title);
    }
    let foreground = foreground_pid();
    Ok(groups.into_iter().map(|(pid, titles)| json!({"pid": pid, "name": process_name(pid), "bundleIdentifier": null, "frontmost": pid == foreground, "windows": titles})).collect())
}
pub fn activate_native(pid: i32) -> Result<()> {
    let window = windows()?.into_iter().find(|w| w.pid == pid).ok_or_else(|| Error::access(format!("No visible window for PID {pid}")))?;
    unsafe {
        if IsIconic(window.handle).as_bool() {
            let _ = ShowWindow(window.handle, SW_RESTORE);
        }
        let _ = SetForegroundWindow(window.handle);
    }
    Ok(())
}
pub fn require_point(pid: i32, x: i32, y: i32) -> Result<()> {
    let handle = unsafe { GetAncestor(WindowFromPoint(POINT { x, y }), GA_ROOT) };
    if super::node::Node::window_application_pid(handle) != pid {
        return Err(Error::access("Input blocked: the screen point belongs to a different application"));
    }
    Ok(())
}
pub fn send(pid: i32, events: &[INPUT]) -> Result<()> {
    require_foreground(pid)?;
    if unsafe { SendInput(events, size_of::<INPUT>() as i32) } != events.len() as u32 {
        return Err(Error::access("Windows rejected input (possibly an elevated or secure window). Inspect the target before retrying."));
    }
    Ok(())
}
fn key_event(key: u16, up: bool, unicode: bool) -> INPUT {
    let extended = !unicode && matches!(key, 0x21..=0x28 | 0x2e);
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: VIRTUAL_KEY(if unicode { 0 } else { key }),
                wScan: if unicode { key } else { 0 },
                dwFlags: KEYBD_EVENT_FLAGS(
                    (if up { KEYEVENTF_KEYUP.0 } else { 0 })
                        | (if unicode { KEYEVENTF_UNICODE.0 } else { 0 })
                        | (if extended { KEYEVENTF_EXTENDEDKEY.0 } else { 0 }),
                ),
                ..Default::default()
            },
        },
    }
}
pub fn text(pid: i32, text: &str) -> Result<()> {
    for c in text.encode_utf16() {
        send(pid, &[key_event(c, false, true), key_event(c, true, true)])?;
    }
    Ok(())
}
pub fn key(pid: i32, key: &Key) -> Result<()> {
    let keys = &key.0;
    let events: Vec<_> =
        keys.iter().map(|k| key_event(*k, false, false)).chain(keys.iter().rev().map(|k| key_event(*k, true, false))).collect();
    send(pid, &events)
}
fn mouse(flags: MOUSE_EVENT_FLAGS, data: u32) -> INPUT {
    INPUT { r#type: INPUT_MOUSE, Anonymous: INPUT_0 { mi: MOUSEINPUT { dwFlags: flags, mouseData: data, ..Default::default() } } }
}
pub fn click(pid: i32, x: f64, y: f64) -> Result<()> {
    let (x, y) = (x.round_ties_even() as i32, y.round_ties_even() as i32);
    require_foreground(pid)?;
    require_point(pid, x, y)?;
    unsafe {
        SetCursorPos(x, y)?;
    }
    require_point(pid, x, y)?;
    send(pid, &[mouse(MOUSEEVENTF_LEFTDOWN, 0), mouse(MOUSEEVENTF_LEFTUP, 0)])
}
pub fn scroll(pid: i32, direction: &str, amount: i32) -> Result<()> {
    let mut point = POINT::default();
    unsafe {
        GetCursorPos(&mut point)?;
    }
    require_point(pid, point.x, point.y)?;
    let delta = amount * 120 * if matches!(direction, "down" | "left") { -1 } else { 1 };
    send(pid, &[mouse(if matches!(direction, "left" | "right") { MOUSEEVENTF_HWHEEL } else { MOUSEEVENTF_WHEEL }, delta as u32)])
}
pub fn open_url(url: &str) -> Result<()> {
    let operation = wide("open");
    let url = wide(url);
    let result = unsafe { ShellExecuteW(None, PCWSTR(operation.as_ptr()), PCWSTR(url.as_ptr()), None, None, SW_SHOWNORMAL) };
    if result.0 as isize <= 32 {
        return Err(Error::access("Windows could not open the URL"));
    }
    Ok(())
}

pub fn schema(commands: Vec<serde_json::Value>) -> serde_json::Value {
    serde_json::json!({"schemaVersion": 2, "platform": "windows", "backend": "UIAutomation", "commands": commands})
}
pub fn activation_pid(pid: i32) -> serde_json::Value {
    serde_json::json!(pid)
}
pub fn request_permission() -> serde_json::Value {
    serde_json::json!({"trusted": true, "platform": "windows", "note": "Available on the current interactive desktop at the same integrity level. Does not elevate or change permissions."})
}

pub const SCHEMA_SUMMARY: &str = "Print command metadata. Windows UIA retains AX role/action names for compatibility.";
pub const PERMISSION_SUMMARY: &str = "Windows UI Automation needs no macOS permission. Elevated and secure desktops remain inaccessible.";
pub const VALUE_SUMMARY: &str = "Set a writable ValuePattern.";

pub struct Key(Vec<u16>);

impl Key {
    pub fn new(code: u16, modifiers: &[usize]) -> Self {
        let mut keys: Vec<_> = modifiers.iter().map(|&i| [0x11, 0x11, 0x12, 0x10][i]).collect();
        keys.push(code);
        Self(keys)
    }
}
pub fn key_code(key: &str) -> Option<u16> {
    Some(match key {
        "enter" => 0x0d,
        "tab" => 9,
        "escape" => 0x1b,
        "space" => 0x20,
        "backspace" => 8,
        "forward-delete" => 0x2e,
        "up" => 0x26,
        "down" => 0x28,
        "left" => 0x25,
        "right" => 0x27,
        "home" => 0x24,
        "end" => 0x23,
        "pageup" => 0x21,
        "pagedown" => 0x22,
        _ if key.len() == 1 && key.as_bytes()[0].is_ascii_alphanumeric() => key.as_bytes()[0].to_ascii_uppercase() as u16,
        _ => 0x70 + key.strip_prefix('f')?.parse::<u16>().ok().filter(|f| (1..=24).contains(f))? - 1,
    })
}

pub fn wait(seconds: f64) {
    sleep(Duration::from_secs_f64(seconds));
}
