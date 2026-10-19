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
const SELECT_EDIT_TEXT_MESSAGE: u32 = 0x00b1;

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
            set_label_text(
                window,
                CHECK_STATUS,
                if checked {
                    "Checkbox: checked"
                } else {
                    "Checkbox: unchecked"
                },
            );
        }
        if let Ok(combo) = GetDlgItem(Some(window), COMBO) {
            let open = SendMessageW(combo, CB_GETDROPPEDSTATE, None, None).0 != 0;
            let selection = SendMessageW(combo, CB_GETCURSEL, None, None).0;
            set_label_text(
                window,
                COMBO_STATUS,
                &format!(
                    "Dropdown: {}; choice: {}",
                    if open { "open" } else { "closed" },
                    selection + 1
                ),
            );
        }
        if let Ok(list) = GetDlgItem(Some(window), LIST) {
            let top = SendMessageW(list, LB_GETTOPINDEX, None, None).0;
            set_label_text(
                window,
                SCROLL_STATUS,
                &format!("First visible option: {:02}", top + 1),
            );
        }
        set_label_text(window, READY, "Fixture ready");
    }
}
unsafe extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match message {
            DM_GETDEFID => LRESULT(((DC_HASDEFID << 16) | SUBMIT as u32) as isize),
            WM_COMMAND if (wparam.0 & 0xffff) == SUBMIT as usize => {
                if let Ok(draft) = GetDlgItem(Some(window), DRAFT) {
                    set_label_text(
                        window,
                        RESULT,
                        &format!("Submitted: {}", read_window_text(draft)),
                    );
                    let count = GetWindowLongPtrW(window, GWLP_USERDATA) + 1;
                    SetWindowLongPtrW(window, GWLP_USERDATA, count);
                    set_label_text(window, SEND_COUNT, &format!("Submission count: {count}"));
                }
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
    unsafe {
        let instance = HINSTANCE(GetModuleHandleW(None)?.0);
        let class = w!("Blindly4RustFixture");
        if RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(procedure),
            hInstance: instance,
            lpszClassName: class,
            ..Default::default()
        }) == 0
        {
            return Err(Error::access("Cannot register fixture window"));
        }
        let window = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class,
            w!("Blindly4 Windows Test Fixture"),
            WS_OVERLAPPEDWINDOW,
            40,
            40,
            800,
            650,
            None,
            None,
            Some(instance),
            None,
        )?;
        let _ = ShowWindow(window, SW_SHOW);
        let _ = SetForegroundWindow(window);
        let create_control = |class: PCWSTR,
                              title: &str,
                              style: WINDOW_STYLE,
                              [x, y, width, height]: [i32; 4],
                              id: i32| {
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
        let create_caption = |title: &str, bounds, id| {
            create_control(w!("STATIC"), title, WINDOW_STYLE::default(), bounds, id)
        };
        let create_text_field =
            |title: &str, value: &str, [caption_id, field_id]: [i32; 2], y, extra_style| {
                create_caption(title, [20, y, 390, 20], caption_id)?;
                create_control(
                    w!("EDIT"),
                    value,
                    WS_TABSTOP | WS_BORDER | extra_style,
                    [20, y + 20, 390, 28],
                    field_id,
                )
            };
        create_caption(
            "Local accessibility test — no external actions",
            [20, 10, 730, 20],
            100,
        )?;
        let first = create_text_field(
            "First field",
            "first untouched",
            [109, FIRST],
            35,
            WINDOW_STYLE::default(),
        )?;
        let draft = create_text_field(
            "Draft",
            "",
            [104, DRAFT],
            90,
            WINDOW_STYLE(ES_AUTOHSCROLL as u32),
        )?;
        let third = create_text_field(
            "Third field",
            "third untouched",
            [111, THIRD],
            195,
            WINDOW_STYLE::default(),
        )?;
        create_control(
            w!("BUTTON"),
            "Submit test draft",
            WS_TABSTOP | WINDOW_STYLE(BS_DEFPUSHBUTTON as u32),
            [20, 255, 180, 32],
            SUBMIT,
        )?;
        create_control(
            w!("BUTTON"),
            "Test checkbox",
            WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
            [215, 255, 195, 32],
            CHECKBOX,
        )?;
        create_caption("Not submitted", [20, 300, 390, 40], RESULT)?;
        create_caption("Submission count: 0", [20, 345, 390, 20], SEND_COUNT)?;
        create_caption("Password", [20, 375, 100, 20], 106)?;
        create_control(
            w!("EDIT"),
            "fixture secret",
            WS_BORDER | WINDOW_STYLE(ES_PASSWORD as u32),
            [125, 375, 285, 25],
            107,
        )?;
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
            SendMessageW(
                combo,
                CB_ADDSTRING,
                None,
                Some(LPARAM(text.as_ptr() as isize)),
            );
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
            SendMessageW(
                list,
                LB_ADDSTRING,
                None,
                Some(LPARAM(text.as_ptr() as isize)),
            );
        }
        for (id, y, text) in [
            (CHECK_STATUS, 425, "Checkbox: unchecked"),
            (COMBO_STATUS, 455, "Dropdown: closed; choice: 1"),
            (SCROLL_STATUS, 485, "First visible option: 01"),
            (READY, 515, "Starting fixture"),
        ] {
            create_caption(text, [20, y, 730, 22], id)?;
        }
        if SetTimer(Some(window), 1, 50, None) == 0 {
            return Err(Error::access("Cannot start fixture status timer"));
        }
        let _ = ShowWindow(window, SW_SHOW);
        let _ = SetForegroundWindow(window);
        let _ = SetFocus(Some(draft));
        let mut message = MSG::default();
        loop {
            let status = GetMessageW(&mut message, None, 0, 0).0;
            if status == -1 {
                return Err(Error::access("Fixture message loop failed"));
            }
            if status == 0 {
                break;
            }
            if [first, draft, third].contains(&message.hwnd)
                && message.message == WM_KEYDOWN
                && message.wParam.0 == b'A' as usize
                && GetKeyState(VK_CONTROL.0 as i32) < 0
            {
                SendMessageW(
                    message.hwnd,
                    SELECT_EDIT_TEXT_MESSAGE,
                    Some(WPARAM(0)),
                    Some(LPARAM(-1)),
                );
                continue;
            }
            if !IsDialogMessageW(window, &message).as_bool() {
                let _ = TranslateMessage(&message);
                DispatchMessageW(&message);
            }
        }
    }
    Ok(())
}
