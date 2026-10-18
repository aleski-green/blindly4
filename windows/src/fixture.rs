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

const DRAFT: i32 = 101;
const SUBMIT: i32 = 102;
const RESULT: i32 = 103;
unsafe extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    unsafe {
        match message {
            WM_COMMAND if (wparam.0 & 0xffff) == SUBMIT as usize => {
                if let (Ok(edit), Ok(result)) = (
                    GetDlgItem(Some(window), DRAFT),
                    GetDlgItem(Some(window), RESULT),
                ) {
                    let mut text = vec![0u16; GetWindowTextLengthW(edit) as usize + 1];
                    let count = GetWindowTextW(edit, &mut text);
                    let value = native::wide(&format!(
                        "Submitted: {}",
                        String::from_utf16_lossy(&text[..count as usize])
                    ));
                    let _ = SetWindowTextW(result, PCWSTR(value.as_ptr()));
                }
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
        let atom = RegisterClassW(&WNDCLASSW {
            lpfnWndProc: Some(procedure),
            hInstance: instance,
            lpszClassName: class,
            ..Default::default()
        });
        if atom == 0 {
            return Err(Error::access("Cannot register fixture window"));
        }
        let window = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class,
            w!("Blindly4 Windows Test Fixture"),
            WS_OVERLAPPEDWINDOW,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            660,
            390,
            None,
            None,
            Some(instance),
            None,
        )?;
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
            590,
            25,
            100,
        )?;
        // A preceding static label supplies the accessible name for a native edit.
        control(
            w!("STATIC"),
            w!("Draft"),
            WINDOW_STYLE::default(),
            20,
            35,
            590,
            20,
            104,
        )?;
        let edit = control(
            w!("EDIT"),
            w!(""),
            WS_TABSTOP | WS_BORDER | WINDOW_STYLE(ES_MULTILINE as u32 | ES_AUTOVSCROLL as u32),
            20,
            60,
            590,
            110,
            DRAFT,
        )?;
        control(
            w!("BUTTON"),
            w!("Submit test draft"),
            WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
            20,
            185,
            180,
            32,
            SUBMIT,
        )?;
        control(
            w!("BUTTON"),
            w!("Test checkbox"),
            WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
            230,
            185,
            180,
            32,
            105,
        )?;
        control(
            w!("STATIC"),
            w!("Not submitted"),
            WINDOW_STYLE::default(),
            20,
            230,
            590,
            40,
            RESULT,
        )?;
        control(
            w!("STATIC"),
            w!("Password"),
            WINDOW_STYLE::default(),
            20,
            280,
            120,
            20,
            106,
        )?;
        control(
            w!("EDIT"),
            w!("fixture secret"),
            WS_BORDER | WINDOW_STYLE(ES_PASSWORD as u32),
            150,
            280,
            250,
            24,
            107,
        )?;
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
            // Unlike WinForms, a multiline Win32 EDIT does not provide Ctrl+A.
            // Give the fixture the same conventional select-all shortcut.
            if message.hwnd == edit
                && message.message == WM_KEYDOWN
                && message.wParam.0 == b'A' as usize
                && GetKeyState(VK_CONTROL.0 as i32) < 0
            {
                SendMessageW(
                    edit,
                    0x00b1, /* EM_SETSEL */
                    Some(WPARAM(0)),
                    Some(LPARAM(-1)),
                );
                continue;
            }
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
    Ok(())
}
