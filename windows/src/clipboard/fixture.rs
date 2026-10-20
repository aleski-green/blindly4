// Opt-in native transport only; RSpec owns the behavioral assertions.
use super::*;
use serde_json::{Value, json};
use std::{collections::BTreeMap, io::BufRead, sync::mpsc};
use windows::core::PCWSTR;

fn snapshot(owner: HWND, supplied: &BTreeMap<String, u32>) -> Result<(Value, u32)> {
    let _lock = ClipboardLock::open(owner)?;
    let mut formats = vec![];
    let mut id = 0;
    loop {
        unsafe {
            SetLastError(ERROR_SUCCESS);
            id = EnumClipboardFormats(id);
        }
        if id == 0 {
            if unsafe { GetLastError() } != ERROR_SUCCESS {
                return Err(Error::access("Cannot enumerate fixture clipboard formats"));
            }
            break;
        }
        formats.push(id);
    }
    formats.sort_unstable();
    let mut data = BTreeMap::new();
    for (name, id) in supplied {
        if !formats.contains(id) {
            continue;
        }
        unsafe {
            let memory = HGLOBAL(GetClipboardData(*id)?.0);
            let size = GlobalSize(memory);
            let bytes = GlobalLock(memory) as *const u8;
            if bytes.is_null() {
                return Err(Error::access("Cannot read fixture clipboard bytes"));
            }
            let copy = std::slice::from_raw_parts(bytes, size).to_vec();
            let _ = GlobalUnlock(memory);
            data.insert(name, copy);
        }
    }
    Ok((json!({"formats": formats, "data": data}), unsafe { GetClipboardSequenceNumber() }))
}

pub fn run() -> Result<()> {
    if std::env::var("BLINDLY4_LIVE").as_deref() != Ok("1") {
        return Err(Error::usage("Clipboard fixture requires BLINDLY4_LIVE=1"));
    }
    // Save user data privately. Only RSpec-supplied format bytes go to stdout.
    let mut original = Clipboard::capture()?;
    let mut supplied = BTreeMap::new();
    let mut fixture_contents = None;
    let (sender, receiver) = mpsc::channel();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            if sender.send(line).is_err() {
                break;
            }
        }
    });
    let outcome = (|| -> Result<()> {
        loop {
            // Clipboard ownership notifications must be serviced while waiting
            // for RSpec, including when another process performs the paste.
            unsafe {
                let mut message = MSG::default();
                while PeekMessageW(&mut message, None, 0, 0, PM_REMOVE).as_bool() {
                    let _ = TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
            }
            let line = match receiver.recv_timeout(Duration::from_millis(10)) {
                Ok(line) => line?,
                Err(mpsc::RecvTimeoutError::Timeout) => continue,
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            };
            let request: Value = serde_json::from_str(&line)?;
            if let Some(write) = request.get("write") {
                let rows = write.as_object().ok_or_else(|| Error::usage("Expected clipboard format object"))?;
                let mut replacements = vec![];
                let mut next_supplied = BTreeMap::new();
                for (name, bytes) in rows {
                    let bytes: Vec<u8> = serde_json::from_value(bytes.clone())?;
                    if bytes.is_empty() || !(name == "CF_UNICODETEXT" || name.starts_with("org.blindly4.fixture")) {
                        return Err(Error::usage("Expected nonempty bytes in a supported fixture format"));
                    }
                    let wide = native::wide(name);
                    let id = if name == "CF_UNICODETEXT" { 13 } else { unsafe { RegisterClipboardFormatW(PCWSTR(wide.as_ptr())) } };
                    if id == 0 {
                        return Err(Error::access("Cannot register fixture clipboard format"));
                    }
                    let memory = unsafe { GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytes.len())? };
                    let format = OwnedClipboardFormat { id, handle: HANDLE(memory.0) };
                    unsafe {
                        let pointer = GlobalLock(memory) as *mut u8;
                        if pointer.is_null() {
                            return Err(Error::access("Cannot write fixture clipboard bytes"));
                        }
                        std::ptr::copy_nonoverlapping(bytes.as_ptr(), pointer, bytes.len());
                        let _ = GlobalUnlock(memory);
                    }
                    replacements.push(format);
                    next_supplied.insert(name.clone(), id);
                }
                {
                    let _lock = ClipboardLock::open(original.owner)?;
                    unsafe { EmptyClipboard()? };
                    original.replacement_sequence = Some(unsafe { GetClipboardSequenceNumber() });
                    for format in &mut replacements {
                        let result = format.transfer_to_clipboard();
                        original.replacement_sequence = Some(unsafe { GetClipboardSequenceNumber() });
                        result?;
                    }
                }
                supplied = next_supplied;
                fixture_contents = Some(snapshot(original.owner, &supplied)?.0);
            }
            if fixture_contents.is_none() {
                return Err(Error::usage("Write fixture data before inspecting it"));
            }
            crate::json(&snapshot(original.owner, &supplied)?.0)?;
        }
        Ok(())
    })();
    // A real paste restores our data with a new sequence number. Reclaim it only
    // if its native formats and bytes still match, preserving unrelated copies.
    if let Some(expected) = fixture_contents {
        let (observed, sequence) = snapshot(original.owner, &supplied)?;
        if observed == expected {
            original.replacement_sequence = Some(sequence);
        }
    }
    let restoration = original.restore();
    outcome?;
    restoration
}
