use super::native;
use crate::error::{Error, Result};
use windows::{
    Win32::{
        Foundation::*,
        System::LibraryLoader::GetModuleHandleW,
        UI::{
            Input::KeyboardAndMouse::{GetKeyState, SetFocus, VK_CONTROL},
            WindowsAndMessaging::*,
        },
    },
    core::{PCWSTR, w},
};

const FIRST: i32 = 108;
const DRAFT: i32 = 101;
const THIRD: i32 = 110;
const SUBMIT: i32 = IDOK.0;
const RESULT: i32 = 103;
const CHECKBOX: i32 = 105;
const COMBO: i32 = 201;
const LIST: i32 = 202;
const CHECK_STATUS: i32 = 301;
const COMBO_STATUS: i32 = 302;
const SCROLL_STATUS: i32 = 303;
const SEND_COUNT: i32 = 304;
const READY: i32 = 305;
const PASTE_STATUS: i32 = 306;
const RELEASE_PASTE: i32 = 307;
const SWITCH_FIXTURE: i32 = 308;
const DETACH_CHILD: i32 = 309;
const SELECT_EDIT_TEXT_MESSAGE: u32 = 0x00b1;
static ORIGINAL_EDIT: std::sync::OnceLock<WNDPROC> = std::sync::OnceLock::new();

unsafe extern "system" fn draft_procedure(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    unsafe {
        let original = *ORIGINAL_EDIT.get().unwrap();
        if message == WM_SETTEXT && lparam.0 != 0 && *(lparam.0 as *const u16) == 0 {
            let mode = std::env::var("BLINDLY4_FIXTURE_VALUE").unwrap_or_default();
            let value = native::wide(if mode == "whitespace" { "\r\n" } else { "retained draft" });
            let result = CallWindowProcW(original, window, message, wparam, LPARAM(value.as_ptr() as isize));
            SendMessageW(window, SELECT_EDIT_TEXT_MESSAGE, Some(WPARAM(0)), Some(LPARAM(-1)));
            return result;
        }
        CallWindowProcW(original, window, message, wparam, lparam)
    }
}

unsafe fn release_paste(window: HWND) {
    unsafe {
        if let (Ok(status), Ok(draft)) = (GetDlgItem(Some(window), PASTE_STATUS), GetDlgItem(Some(window), DRAFT)) {
            let label = read_window_text(status);
            if let Some(count) = label.strip_prefix("Paste pending: ") {
                SendMessageW(draft, WM_PASTE, None, None);
                set_label_text(window, PASTE_STATUS, &format!("Paste completed: {count}"));
            }
        }
    }
}

unsafe fn read_window_text(window: HWND) -> String {
    unsafe {
        let mut text = vec![0u16; GetWindowTextLengthW(window) as usize + 1];
        let count = GetWindowTextW(window, &mut text);
        String::from_utf16_lossy(&text[..count as usize])
    }
}
unsafe fn set_label_text(window: HWND, id: i32, text: &str) {
    unsafe {
        if let Ok(control) = GetDlgItem(Some(window), id) {
            if read_window_text(control) != text {
                let wide = native::wide(text);
                let _ = SetWindowTextW(control, PCWSTR(wide.as_ptr()));
            }
        }
    }
}
unsafe fn refresh_control_status(window: HWND) {
    unsafe {
        if let Ok(checkbox) = GetDlgItem(Some(window), CHECKBOX) {
            let checked = SendMessageW(checkbox, BM_GETCHECK, None, None).0 != 0;
            set_label_text(window, CHECK_STATUS, if checked { "Checkbox: checked" } else { "Checkbox: unchecked" });
        }
        if let Ok(combo) = GetDlgItem(Some(window), COMBO) {
            let open = SendMessageW(combo, CB_GETDROPPEDSTATE, None, None).0 != 0;
            let selection = SendMessageW(combo, CB_GETCURSEL, None, None).0;
            set_label_text(window, COMBO_STATUS, &format!("Dropdown: {}; choice: {}", if open { "open" } else { "closed" }, selection + 1));
        }
        if let Ok(list) = GetDlgItem(Some(window), LIST) {
            let top = SendMessageW(list, LB_GETTOPINDEX, None, None).0;
            set_label_text(window, SCROLL_STATUS, &format!("First visible option: {:02}", top + 1));
        }
        set_label_text(window, READY, "Fixture ready");
    }
}
unsafe extern "system" fn procedure(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    unsafe {
        match message {
            WM_COMMAND if (wparam.0 & 0xffff) == DETACH_CHILD as usize => {
                let _ = SetParent(window, None);
                SetWindowLongPtrW(window, GWL_STYLE, WS_OVERLAPPEDWINDOW.0 as isize | WS_VISIBLE.0 as isize);
                let _ = SetWindowPos(window, None, 900, 40, 800, 650, SWP_FRAMECHANGED | SWP_NOZORDER);
                let _ = SetForegroundWindow(window);
                LRESULT(0)
            }
            DM_GETDEFID => LRESULT(((DC_HASDEFID << 16) | SUBMIT as u32) as isize),
            WM_COMMAND if (wparam.0 & 0xffff) == RELEASE_PASTE as usize => {
                release_paste(window);
                LRESULT(0)
            }
            WM_COMMAND if (wparam.0 & 0xffff) == SWITCH_FIXTURE as usize => {
                // The foreground fixture cooperatively activates a second fixture.
                // No foreground restrictions in the production CLI are bypassed.
                if let Ok(windows) = native::windows()
                    && let Some(other) =
                        windows.iter().find(|w| w.pid != std::process::id() as i32 && w.title == "Blindly4 Windows Test Fixture")
                {
                    let _ = SetForegroundWindow(other.handle);
                }
                LRESULT(0)
            }
            WM_COMMAND if (wparam.0 & 0xffff) == SUBMIT as usize => {
                if let Ok(draft) = GetDlgItem(Some(window), DRAFT) {
                    set_label_text(window, RESULT, &format!("Submitted: {}", read_window_text(draft)));
                    let count = GetWindowLongPtrW(window, GWLP_USERDATA) + 1;
                    SetWindowLongPtrW(window, GWLP_USERDATA, count);
                    set_label_text(window, SEND_COUNT, &format!("Submission count: {count}"));
                }
                LRESULT(0)
            }
            WM_TIMER if wparam.0 == 2 => {
                let _ = KillTimer(Some(window), 2);
                release_paste(window);
                LRESULT(0)
            }
            WM_TIMER => {
                refresh_control_status(window);
                LRESULT(0)
            }
            WM_SETFOCUS => {
                if let Ok(draft) = GetDlgItem(Some(window), DRAFT) {
                    let _ = SetFocus(Some(draft));
                }
                LRESULT(0)
            }
            WM_DESTROY => {
                PostQuitMessage(0);
                LRESULT(0)
            }
            _ => DefWindowProcW(window, message, wparam, lparam),
        }
    }
}
pub fn run() -> Result<()> {
    native::dpi_awareness();
    let live = std::env::var("BLINDLY4_LIVE").as_deref() == Ok("1");
    let background = live && std::env::var("BLINDLY4_FIXTURE_BACKGROUND").as_deref() == Ok("1");
    let paste_mode = if live { std::env::var("BLINDLY4_FIXTURE_PASTE").unwrap_or_default() } else { String::new() };
    let host_pid = if live { std::env::var("BLINDLY4_FIXTURE_HOST_PID").ok().and_then(|p| p.parse::<i32>().ok()) } else { None };
    let host = match host_pid {
        Some(pid) => Some(
            native::windows()?
                .into_iter()
                .find(|w| w.pid == pid && w.title == "Blindly4 Windows Test Fixture")
                .ok_or_else(|| Error::access("Fixture host window is missing"))?
                .handle,
        ),
        None => None,
    };
    unsafe {
        let instance = HINSTANCE(GetModuleHandleW(None)?.0);
        let class = w!("Blindly4RustFixture");
        if RegisterClassW(&WNDCLASSW { lpfnWndProc: Some(procedure), hInstance: instance, lpszClassName: class, ..Default::default() }) == 0
        {
            return Err(Error::access("Cannot register fixture window"));
        }
        let window = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class,
            w!("Blindly4 Windows Test Fixture"),
            if host.is_some() { WS_CHILD } else { WS_OVERLAPPEDWINDOW },
            40,
            40,
            800,
            650,
            host,
            None,
            Some(instance),
            None,
        )?;
        let _ = ShowWindow(window, if background { SW_SHOWNOACTIVATE } else { SW_SHOW });
        if !background {
            let _ = SetForegroundWindow(window);
        }
        let create_control = |class: PCWSTR, title: &str, style: WINDOW_STYLE, [x, y, width, height]: [i32; 4], id: i32| {
            let title = native::wide(title);
            CreateWindowExW(
                WINDOW_EX_STYLE::default(),
                class,
                PCWSTR(title.as_ptr()),
                WS_CHILD | WS_VISIBLE | style,
                x,
                y,
                width,
                height,
                Some(window),
                Some(HMENU(id as usize as *mut _)),
                Some(instance),
                None,
            )
        };
        let create_caption = |title: &str, bounds, id| create_control(w!("STATIC"), title, WINDOW_STYLE::default(), bounds, id);
        let create_text_field = |title: &str, value: &str, [caption_id, field_id]: [i32; 2], y, extra_style| {
            create_caption(title, [20, y, 390, 20], caption_id)?;
            create_control(w!("EDIT"), value, WS_TABSTOP | WS_BORDER | extra_style, [20, y + 20, 390, 28], field_id)
        };
        create_caption("Local accessibility test — no external actions", [20, 10, 730, 20], 100)?;
        let first = create_text_field("First field", "first untouched", [109, FIRST], 35, WINDOW_STYLE::default())?;
        let draft_title = if host.is_some() { "Child process draft" } else { "Draft" };
        let draft = create_text_field(draft_title, "", [104, DRAFT], 90, WINDOW_STYLE(ES_AUTOHSCROLL as u32))?;
        if live && std::env::var_os("BLINDLY4_FIXTURE_VALUE").is_some() {
            let original = SetWindowLongPtrW(draft, GWLP_WNDPROC, draft_procedure as *const () as isize);
            let _ = ORIGINAL_EDIT.set(std::mem::transmute::<isize, WNDPROC>(original));
        }
        let third = create_text_field("Third field", "third untouched", [111, THIRD], 195, WINDOW_STYLE::default())?;
        create_control(w!("BUTTON"), "Submit test draft", WS_TABSTOP | WINDOW_STYLE(BS_DEFPUSHBUTTON as u32), [20, 255, 180, 32], SUBMIT)?;
        create_control(w!("BUTTON"), "Test checkbox", WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32), [215, 255, 195, 32], CHECKBOX)?;
        create_caption("Not submitted", [20, 300, 390, 40], RESULT)?;
        create_caption("Submission count: 0", [20, 345, 390, 20], SEND_COUNT)?;
        create_caption("Password", [20, 375, 100, 20], 106)?;
        create_control(w!("EDIT"), "fixture secret", WS_BORDER | WINDOW_STYLE(ES_PASSWORD as u32), [125, 375, 285, 25], 107)?;
        create_caption("Delivery choice", [445, 35, 300, 20], 203)?;
        let combo = create_control(
            w!("COMBOBOX"),
            "",
            WS_TABSTOP | WS_VSCROLL | WINDOW_STYLE(CBS_DROPDOWNLIST as u32),
            [445, 55, 300, 180],
            COMBO,
        )?;
        for text in ["Choice one", "Choice two", "Choice three"] {
            let text = native::wide(text);
            SendMessageW(combo, CB_ADDSTRING, None, Some(LPARAM(text.as_ptr() as isize)));
        }
        SendMessageW(combo, CB_SETCURSEL, Some(WPARAM(0)), None);
        create_caption("Scrollable options", [445, 110, 300, 20], 204)?;
        let list = create_control(
            w!("LISTBOX"),
            "",
            WS_TABSTOP | WS_BORDER | WS_VSCROLL | WINDOW_STYLE(LBS_NOTIFY as u32),
            [445, 135, 300, 260],
            LIST,
        )?;
        for index in 1..=80 {
            let text = native::wide(&format!("Option {index:02}"));
            SendMessageW(list, LB_ADDSTRING, None, Some(LPARAM(text.as_ptr() as isize)));
        }
        for (id, y, text) in [
            (CHECK_STATUS, 425, "Checkbox: unchecked"),
            (COMBO_STATUS, 455, "Dropdown: closed; choice: 1"),
            (SCROLL_STATUS, 485, "First visible option: 01"),
            (READY, 515, "Starting fixture"),
        ] {
            create_caption(text, [20, y, 730, 22], id)?;
        }
        if !paste_mode.is_empty() {
            create_caption("Paste attempts: 0", [20, 545, 300, 22], PASTE_STATUS)?;
            create_control(w!("BUTTON"), "Release pending paste", WS_TABSTOP, [445, 545, 250, 28], RELEASE_PASTE)?;
            create_control(w!("BUTTON"), "Switch fixture focus", WS_TABSTOP, [445, 580, 250, 28], SWITCH_FIXTURE)?;
        }
        if host.is_some() {
            create_control(w!("BUTTON"), "Detach child window", WS_TABSTOP, [445, 580, 250, 28], DETACH_CHILD)?;
        }
        let mut child_process = if live && std::env::var("BLINDLY4_FIXTURE_CHILD").as_deref() == Ok("1") && host.is_none() {
            let child = std::process::Command::new(std::env::current_exe()?)
                .arg("--test-app")
                .env("BLINDLY4_FIXTURE_HOST_PID", std::process::id().to_string())
                .env_remove("BLINDLY4_FIXTURE_CHILD")
                .spawn()?;
            create_caption(&format!("Child process: {}", child.id()), [20, 545, 400, 22], 310)?;
            Some(child)
        } else {
            None
        };
        if SetTimer(Some(window), 1, 50, None) == 0 {
            return Err(Error::access("Cannot start fixture status timer"));
        }
        let _ = ShowWindow(window, if background { SW_SHOWNOACTIVATE } else { SW_SHOW });
        if !background {
            let _ = SetForegroundWindow(window);
            let _ = SetFocus(Some(draft));
        }
        let mut message = MSG::default();
        let mut paste_count = 0;
        loop {
            let status = GetMessageW(&mut message, None, 0, 0).0;
            if status == -1 {
                return Err(Error::access("Fixture message loop failed"));
            }
            if status == 0 {
                break;
            }
            // Native fixture behaviors, reached only after real Ctrl+V input.
            // Hold mode lets RSpec coordinate another process without timing guesses.
            if !paste_mode.is_empty()
                && message.hwnd == draft
                && message.message == WM_KEYDOWN
                && message.wParam.0 == b'V' as usize
                && GetKeyState(VK_CONTROL.0 as i32) < 0
            {
                paste_count += 1;
                set_label_text(window, PASTE_STATUS, &format!("Paste pending: {paste_count}"));
                if paste_mode == "delay" {
                    if SetTimer(Some(window), 2, 250, None) == 0 {
                        return Err(Error::access("Cannot start delayed paste timer"));
                    }
                } else if paste_mode == "focus-after" {
                    release_paste(window);
                    let _ = SetFocus(Some(first));
                } else if paste_mode == "reorder" {
                    release_paste(window);
                    SetWindowPos(third, Some(HWND_TOP), 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)?;
                }
                continue;
            }
            if [first, draft, third].contains(&message.hwnd)
                && message.message == WM_KEYDOWN
                && message.wParam.0 == b'A' as usize
                && GetKeyState(VK_CONTROL.0 as i32) < 0
            {
                SendMessageW(message.hwnd, SELECT_EDIT_TEXT_MESSAGE, Some(WPARAM(0)), Some(LPARAM(-1)));
                continue;
            }
            if !IsDialogMessageW(window, &message).as_bool() {
                let _ = TranslateMessage(&message);
                DispatchMessageW(&message);
            }
        }
        if let Some(child) = child_process.as_mut() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
    Ok(())
}
