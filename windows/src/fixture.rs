//! Harmless native Win32 fixture driven by the RSpec desktop behavior suite.
use crate::{
    error::{Error, Result},
    native,
};
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
// IDOK is also the default action used by Windows dialog keyboard navigation.
const SUBMIT: i32 = 1;
const RESULT: i32 = 103;
const CHECKBOX: i32 = 105;
const COMBO: i32 = 201;
const LIST: i32 = 202;
const CHECK_STATUS: i32 = 301;
const COMBO_STATUS: i32 = 302;
const SCROLL_STATUS: i32 = 303;
const SEND_COUNT: i32 = 304;
const READY: i32 = 305;

unsafe fn window_text(window: HWND) -> String {
    unsafe {
        let mut text = vec![0u16; GetWindowTextLengthW(window) as usize + 1];
        let count = GetWindowTextW(window, &mut text);
        String::from_utf16_lossy(&text[..count as usize])
    }
}
unsafe fn label(window: HWND, id: i32, text: &str) {
    unsafe {
        if let Ok(control) = GetDlgItem(Some(window), id) {
            // Avoid continuously replacing unchanged accessible text.
            if window_text(control) != text {
                let wide = native::wide(text);
                let _ = SetWindowTextW(control, PCWSTR(wide.as_ptr()));
            }
        }
    }
}
// Visible status labels let a human or an accessibility client observe the
// controls. This fixture contains no test assertions or automation shortcuts.
unsafe fn refresh_status(window: HWND) {
    unsafe {
        if let Ok(control) = GetDlgItem(Some(window), CHECKBOX) {
            let checked = SendMessageW(control, BM_GETCHECK, None, None).0 != 0;
            label(
                window,
                CHECK_STATUS,
                if checked {
                    "Checkbox: checked"
                } else {
                    "Checkbox: unchecked"
                },
            );
        }
        if let Ok(control) = GetDlgItem(Some(window), COMBO) {
            let open = SendMessageW(control, CB_GETDROPPEDSTATE, None, None).0 != 0;
            let selection = SendMessageW(control, CB_GETCURSEL, None, None).0;
            label(
                window,
                COMBO_STATUS,
                &format!(
                    "Dropdown: {}; choice: {}",
                    if open { "open" } else { "closed" },
                    selection + 1
                ),
            );
        }
        if let Ok(control) = GetDlgItem(Some(window), LIST) {
            let top = SendMessageW(control, LB_GETTOPINDEX, None, None).0;
            label(
                window,
                SCROLL_STATUS,
                &format!("First visible option: {:02}", top + 1),
            );
        }
        label(window, READY, "Fixture ready");
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
            // A regular window supplies the default-button ID explicitly when
            // using IsDialogMessage instead of DefDlgProc.
            DM_GETDEFID => LRESULT(((DC_HASDEFID << 16) | SUBMIT as u32) as isize),
            WM_COMMAND if (wparam.0 & 0xffff) == SUBMIT as usize => {
                if let Ok(edit) = GetDlgItem(Some(window), DRAFT) {
                    label(window, RESULT, &format!("Submitted: {}", window_text(edit)));
                    let count = GetWindowLongPtrW(window, GWLP_USERDATA) + 1;
                    SetWindowLongPtrW(window, GWLP_USERDATA, count);
                    label(window, SEND_COUNT, &format!("Submission count: {count}"));
                }
                LRESULT(0)
            }
            WM_TIMER => {
                refresh_status(window);
                LRESULT(0)
            }
            WM_SETFOCUS => {
                if let Ok(edit) = GetDlgItem(Some(window), DRAFT) {
                    let _ = SetFocus(Some(edit));
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
        // Claim initial foreground ownership before populating the large list.
        let _ = ShowWindow(window, SW_SHOW);
        let _ = SetForegroundWindow(window);
        let control =
            |class: PCWSTR, title: PCWSTR, style: WINDOW_STYLE, x, y, width, height, id: i32| {
                CreateWindowExW(
                    WINDOW_EX_STYLE::default(),
                    class,
                    title,
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
        control(
            w!("STATIC"),
            w!("Local accessibility test — no external actions"),
            WINDOW_STYLE::default(),
            20,
            10,
            730,
            20,
            100,
        )?;
        // Preceding labels name the three ordinary text fields. Draft is second
        // in both visual order and the accessibility tree.
        control(
            w!("STATIC"),
            w!("First field"),
            WINDOW_STYLE::default(),
            20,
            35,
            390,
            20,
            109,
        )?;
        let first = control(
            w!("EDIT"),
            w!("first untouched"),
            WS_TABSTOP | WS_BORDER,
            20,
            55,
            390,
            28,
            FIRST,
        )?;
        control(
            w!("STATIC"),
            w!("Draft"),
            WINDOW_STYLE::default(),
            20,
            90,
            390,
            20,
            104,
        )?;
        let edit = control(
            w!("EDIT"),
            w!(""),
            WS_TABSTOP | WS_BORDER | WINDOW_STYLE(ES_AUTOHSCROLL as u32),
            20,
            110,
            390,
            28,
            DRAFT,
        )?;
        control(
            w!("STATIC"),
            w!("Third field"),
            WINDOW_STYLE::default(),
            20,
            195,
            390,
            20,
            111,
        )?;
        let third = control(
            w!("EDIT"),
            w!("third untouched"),
            WS_TABSTOP | WS_BORDER,
            20,
            215,
            390,
            28,
            THIRD,
        )?;
        control(
            w!("BUTTON"),
            w!("Submit test draft"),
            WS_TABSTOP | WINDOW_STYLE(BS_DEFPUSHBUTTON as u32),
            20,
            255,
            180,
            32,
            SUBMIT,
        )?;
        control(
            w!("BUTTON"),
            w!("Test checkbox"),
            WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
            215,
            255,
            195,
            32,
            CHECKBOX,
        )?;
        control(
            w!("STATIC"),
            w!("Not submitted"),
            WINDOW_STYLE::default(),
            20,
            300,
            390,
            40,
            RESULT,
        )?;
        control(
            w!("STATIC"),
            w!("Submission count: 0"),
            WINDOW_STYLE::default(),
            20,
            345,
            390,
            20,
            SEND_COUNT,
        )?;
        control(
            w!("STATIC"),
            w!("Password"),
            WINDOW_STYLE::default(),
            20,
            375,
            100,
            20,
            106,
        )?;
        control(
            w!("EDIT"),
            w!("fixture secret"),
            WS_BORDER | WINDOW_STYLE(ES_PASSWORD as u32),
            125,
            375,
            285,
            25,
            107,
        )?;
        control(
            w!("STATIC"),
            w!("Delivery choice"),
            WINDOW_STYLE::default(),
            445,
            35,
            300,
            20,
            203,
        )?;
        let combo = control(
            w!("COMBOBOX"),
            w!(""),
            WS_TABSTOP | WS_VSCROLL | WINDOW_STYLE(CBS_DROPDOWNLIST as u32),
            445,
            55,
            300,
            180,
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
        control(
            w!("STATIC"),
            w!("Scrollable options"),
            WINDOW_STYLE::default(),
            445,
            110,
            300,
            20,
            204,
        )?;
        let list = control(
            w!("LISTBOX"),
            w!(""),
            WS_TABSTOP | WS_BORDER | WS_VSCROLL | WINDOW_STYLE(LBS_NOTIFY as u32),
            445,
            135,
            300,
            260,
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
            let text = native::wide(text);
            control(
                w!("STATIC"),
                PCWSTR(text.as_ptr()),
                WINDOW_STYLE::default(),
                20,
                y,
                730,
                22,
                id,
            )?;
        }
        if SetTimer(Some(window), 1, 50, None) == 0 {
            return Err(Error::access("Cannot start fixture status timer"));
        }
        let _ = ShowWindow(window, SW_SHOW);
        let _ = SetForegroundWindow(window);
        let _ = SetFocus(Some(edit));
        let mut message = MSG::default();
        loop {
            let status = GetMessageW(&mut message, None, 0, 0).0;
            if status == -1 {
                return Err(Error::access("Fixture message loop failed"));
            }
            if status == 0 {
                break;
            }
            // Supply conventional select-all in native EDIT controls.
            if [first, edit, third].contains(&message.hwnd)
                && message.message == WM_KEYDOWN
                && message.wParam.0 == b'A' as usize
                && GetKeyState(VK_CONTROL.0 as i32) < 0
            {
                SendMessageW(
                    message.hwnd,
                    0x00b1, /* EM_SETSEL */
                    Some(WPARAM(0)),
                    Some(LPARAM(-1)),
                );
                continue;
            }
            // Standard dialog navigation handles Enter/default-button submission,
            // Tab focus, dropdown keys, and Space on a focused native button.
            if !IsDialogMessageW(window, &message).as_bool() {
                let _ = TranslateMessage(&message);
                DispatchMessageW(&message);
            }
        }
    }
    Ok(())
}
