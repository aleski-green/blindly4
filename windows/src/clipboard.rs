use super::native;
use crate::error::{Error, Result};
use std::{thread::sleep, time::Duration};
use windows::{
    Win32::{
        Foundation::*,
        Graphics::Gdi::*,
        System::{DataExchange::*, Memory::*, Ole::*},
        UI::WindowsAndMessaging::*,
    },
    core::w,
};

struct ClipboardLock;
impl ClipboardLock {
    fn open(owner: HWND) -> Result<Self> {
        for _ in 0..20 {
            if unsafe { OpenClipboard(Some(owner)) }.is_ok() {
                return Ok(Self);
            }
            sleep(Duration::from_millis(10));
        }
        Err(Error::access("Clipboard is busy; input was not attempted"))
    }
}
impl Drop for ClipboardLock {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseClipboard();
        }
    }
}
struct OwnedClipboardFormat {
    id: u32,
    handle: HANDLE,
}
impl OwnedClipboardFormat {
    fn copy(id: u32, handle: HANDLE) -> Result<Self> {
        if (0x200..=0x2ff).contains(&id) || id == 0x80 {
            return Err(Error::access(
                "Clipboard contains an owner-managed format that cannot be safely preserved",
            ));
        }
        let handle = unsafe {
            match id {
                14 | 0x8e => HANDLE(CopyEnhMetaFileW(HENHMETAFILE(handle.0), None).0),
                _ => OleDuplicateData(
                    handle,
                    CLIPBOARD_FORMAT(match id {
                        0x82 => 2,
                        0x83 => 3,
                        _ => id,
                    } as u16),
                    GMEM_MOVEABLE,
                ),
            }
        };
        if handle.is_invalid() {
            return Err(Error::access(format!(
                "Cannot preserve clipboard format {id}; input was not attempted"
            )));
        }
        Ok(Self { id, handle })
    }
    fn text(text: &str) -> Result<Self> {
        let units = native::wide(text);
        let handle = unsafe { GlobalAlloc(GMEM_MOVEABLE, units.len() * size_of::<u16>())? };
        let format = Self {
            id: 13,
            handle: HANDLE(handle.0),
        };
        unsafe {
            let ptr = GlobalLock(handle) as *mut u16;
            if ptr.is_null() {
                return Err(Error::access("Cannot lock clipboard text memory"));
            }
            std::ptr::copy_nonoverlapping(units.as_ptr(), ptr, units.len());
            let _ = GlobalUnlock(handle);
        }
        Ok(format)
    }
    fn transfer_to_clipboard(&mut self) -> Result<()> {
        unsafe {
            SetClipboardData(self.id, Some(self.handle))?;
        }
        self.handle = HANDLE::default();
        Ok(())
    }
}
impl Drop for OwnedClipboardFormat {
    fn drop(&mut self) {
        if self.handle.is_invalid() {
            return;
        }
        unsafe {
            match self.id {
                2 | 9 | 0x82 => {
                    let _ = DeleteObject(HGDIOBJ(self.handle.0));
                }
                14 | 0x8e => {
                    let _ = DeleteEnhMetaFile(Some(HENHMETAFILE(self.handle.0)));
                }
                3 | 0x83 => {
                    let memory = HGLOBAL(self.handle.0);
                    let picture = GlobalLock(memory) as *const METAFILEPICT;
                    if !picture.is_null() {
                        let _ = DeleteMetaFile((*picture).hMF);
                        let _ = GlobalUnlock(memory);
                    }
                    let _ = GlobalFree(Some(memory));
                }
                _ => {
                    let _ = GlobalFree(Some(HGLOBAL(self.handle.0)));
                }
            }
        }
    }
}

pub struct Clipboard {
    owner: HWND,
    formats: Vec<OwnedClipboardFormat>,
    captured_sequence: u32,
    replacement_sequence: Option<u32>,
}
impl Clipboard {
    pub fn capture() -> Result<Self> {
        let owner = unsafe {
            CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                w!("STATIC"),
                w!("Blindly4 Clipboard"),
                WINDOW_STYLE::default(),
                0,
                0,
                0,
                0,
                Some(HWND_MESSAGE),
                None,
                None,
                None,
            )?
        };
        let mut clipboard = Self {
            owner,
            formats: vec![],
            captured_sequence: 0,
            replacement_sequence: None,
        };
        let _lock = ClipboardLock::open(owner)?;
        let mut id = 0;
        loop {
            unsafe {
                SetLastError(ERROR_SUCCESS);
                id = EnumClipboardFormats(id);
            }
            if id == 0 {
                if unsafe { GetLastError() } != ERROR_SUCCESS {
                    return Err(Error::access("Cannot enumerate clipboard formats"));
                }
                break;
            }
            let handle = unsafe { GetClipboardData(id)? };
            clipboard
                .formats
                .push(OwnedClipboardFormat::copy(id, handle)?);
        }
        clipboard.captured_sequence = unsafe { GetClipboardSequenceNumber() };
        Ok(clipboard)
    }
    pub fn replace(&mut self, text: &str) -> Result<()> {
        let mut replacement = OwnedClipboardFormat::text(text)?;
        let _lock = ClipboardLock::open(self.owner)?;
        if unsafe { GetClipboardSequenceNumber() } != self.captured_sequence {
            return Err(Error::access(
                "Clipboard changed before paste; input blocked",
            ));
        }
        unsafe {
            EmptyClipboard()?;
        }
        let result = replacement.transfer_to_clipboard();
        self.replacement_sequence = Some(unsafe { GetClipboardSequenceNumber() });
        result
    }
    pub fn restore(&mut self) -> Result<()> {
        let Some(sequence) = self.replacement_sequence else {
            return Ok(());
        };
        let _lock = ClipboardLock::open(self.owner)?;
        if unsafe { GetClipboardSequenceNumber() } != sequence {
            self.replacement_sequence = None;
            return Ok(());
        }
        unsafe {
            EmptyClipboard()?;
        }
        self.replacement_sequence = None;
        for format in &mut self.formats {
            format.transfer_to_clipboard()?;
        }
        Ok(())
    }
}
impl Drop for Clipboard {
    fn drop(&mut self) {
        if let Err(error) = self.restore() {
            eprintln!("Clipboard restoration failed: {error}");
        }
        unsafe {
            let _ = DestroyWindow(self.owner);
        }
    }
}
