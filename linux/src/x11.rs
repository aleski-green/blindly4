use super::native::Key;
use crate::{
    application::require_foreground,
    error::{Error, Result},
};
use x11rb::{
    connection::Connection,
    protocol::{
        res::{ClientIdMask, ClientIdSpec, ConnectionExt as _},
        xproto::*,
        xtest::ConnectionExt as _,
    },
    rust_connection::RustConnection,
};

struct Display {
    connection: RustConnection,
    root: Window,
}
impl Display {
    fn open() -> Result<Self> {
        let (connection, screen) = x11rb::connect(None)?;
        let root = connection.setup().roots[screen].root;
        Ok(Self { connection, root })
    }
    fn atom(&self, name: &[u8]) -> Result<Atom> {
        Ok(self.connection.intern_atom(false, name)?.reply()?.atom)
    }
    fn frame(&self, window: Window, property: &[u8]) -> Result<[i32; 4]> {
        let value = self.connection.get_property(false, window, self.atom(property)?, AtomEnum::CARDINAL, 0, 4)?.reply()?;
        let values: Vec<_> = value.value32().map(Iterator::collect).unwrap_or_default();
        match values.as_slice() {
            [] => Ok([0; 4]),
            [l, r, t, b] if [l, r, t, b].iter().all(|value| **value < 65536) => Ok([*l as i32, *r as i32, *t as i32, *b as i32]),
            _ => Err(Error::access("Invalid X11 frame extents")),
        }
    }
    fn windows(&self, property: &[u8]) -> Result<Vec<u32>> {
        let value = self.connection.get_property(false, self.root, self.atom(property)?, AtomEnum::WINDOW, 0, 10000)?.reply()?;
        Ok(value.value32().map(Iterator::collect).unwrap_or_default())
    }
    fn pid(&self, window: Window) -> Result<i32> {
        let result =
            self.connection.res_query_client_ids(&[ClientIdSpec { client: window, mask: ClientIdMask::LOCAL_CLIENT_PID }])?.reply()?;
        result
            .ids
            .iter()
            .filter(|id| id.spec.mask.contains(ClientIdMask::LOCAL_CLIENT_PID))
            .flat_map(|id| id.value.iter())
            .find_map(|pid| i32::try_from(*pid).ok().filter(|pid| *pid > 0))
            .ok_or_else(|| Error::access("XRes could not verify the window owner"))
    }
    fn point_pid(&self, x: i16, y: i16) -> Result<i32> {
        let mut window = self.root;
        for _ in 0..64 {
            let point = self.connection.translate_coordinates(self.root, window, x, y)?.reply()?;
            if !point.same_screen {
                break;
            }
            if point.child == 0 {
                return self.pid(window);
            }
            window = point.child;
        }
        Err(Error::access("Cannot verify the screen point's owner"))
    }
    fn emit(&self, kind: u8, detail: u8, x: i16, y: i16) -> Result<()> {
        self.connection.xtest_fake_input(kind, detail, x11rb::CURRENT_TIME, self.root, x, y, 0)?.check()?;
        Ok(())
    }
    fn text_keys(&self, text: &str) -> Result<Vec<(u8, Option<u8>)>> {
        let setup = self.connection.setup();
        let mapping = self.connection.get_keyboard_mapping(setup.min_keycode, setup.max_keycode - setup.min_keycode + 1)?.reply()?;
        let shift = self.keycode(0xffe1)?;
        let mut ascii = [None; 128];
        for (index, symbols) in mapping.keysyms.chunks(mapping.keysyms_per_keycode as usize).enumerate() {
            for (level, symbol) in symbols.iter().take(2).enumerate() {
                if let Some(entry) = ascii.get_mut(*symbol as usize) {
                    entry.get_or_insert((setup.min_keycode + index as u8, if level == 0 { None } else { Some(shift) }));
                }
            }
        }
        text.bytes()
            .map(|character| {
                ascii
                    .get(character as usize)
                    .copied()
                    .flatten()
                    .ok_or_else(|| Error::access("Text is unavailable in the current X11 keymap"))
            })
            .collect()
    }
    fn press(&self, keys: &[u8]) -> Result<()> {
        let mut pressed = vec![];
        let result = (|| {
            for code in keys {
                self.emit(KEY_PRESS_EVENT, *code, 0, 0)?;
                pressed.push(*code);
            }
            Ok(())
        })();
        let mut released = Ok(());
        for code in pressed.into_iter().rev() {
            if let Err(error) = self.emit(KEY_RELEASE_EVENT, code, 0, 0) {
                released = Err(error);
            }
        }
        result.and(released)
    }
    fn keycode(&self, symbol: u32) -> Result<u8> {
        let setup = self.connection.setup();
        let count = setup.max_keycode - setup.min_keycode + 1;
        let mapping = self.connection.get_keyboard_mapping(setup.min_keycode, count)?.reply()?;
        mapping
            .keysyms
            .chunks(mapping.keysyms_per_keycode as usize)
            .position(|symbols| symbols.first() == Some(&symbol))
            .map(|index| setup.min_keycode + index as u8)
            .ok_or_else(|| Error::access("Key is unavailable in the current X11 keymap"))
    }
}
pub fn validate_text(text: &str) -> Result<()> {
    Display::open()?.text_keys(text).map(|_| ())
}
pub fn text(pid: i32, text: &str, focused: impl Fn() -> Result<()>) -> Result<()> {
    let display = Display::open()?;
    for (code, shift) in display.text_keys(text)? {
        require_foreground(pid)?;
        focused()?;
        if let Some(shift) = shift {
            display.press(&[shift, code])?;
        } else {
            display.press(&[code])?;
        }
    }
    Ok(())
}
pub fn foreground_pid() -> Result<i32> {
    let display = Display::open()?;
    let window = display
        .windows(b"_NET_ACTIVE_WINDOW")?
        .first()
        .copied()
        .filter(|value| *value != 0)
        .ok_or_else(|| Error::access("No active X11 window"))?;
    display.pid(window)
}
pub fn coordinate_scale(pid: i32, bounds: (i32, i32, i32, i32)) -> Result<i32> {
    let display = Display::open()?;
    let mut matched = None;
    for window in display.windows(b"_NET_CLIENT_LIST_STACKING")? {
        if display.pid(window).ok() != Some(pid) {
            continue;
        }
        let geometry = display.connection.get_geometry(window)?.reply()?;
        let origin = display.connection.translate_coordinates(window, display.root, 0, 0)?.reply()?;
        let [left, right, top, bottom] = display.frame(window, b"_GTK_FRAME_EXTENTS")?;
        let [outer_left, outer_right, outer_top, outer_bottom] = display.frame(window, b"_NET_FRAME_EXTENTS")?;
        let physical = (
            i32::from(origin.dst_x) + left - outer_left,
            i32::from(origin.dst_y) + top - outer_top,
            i32::from(geometry.width) - left - right + outer_left + outer_right,
            i32::from(geometry.height) - top - bottom + outer_top + outer_bottom,
        );
        for scale in 1..=4 {
            if (i64::from(bounds.0) * scale, i64::from(bounds.1) * scale, i64::from(bounds.2) * scale, i64::from(bounds.3) * scale)
                == (physical.0.into(), physical.1.into(), physical.2.into(), physical.3.into())
            {
                if matched.is_some_and(|previous| previous != scale as i32) {
                    return Err(Error::access("Ambiguous accessibility coordinate scale"));
                }
                matched = Some(scale as i32);
            }
        }
    }
    matched.ok_or_else(|| Error::access("Accessibility coordinates do not match a verified X11 window"))
}
pub fn activate(pid: i32) -> Result<()> {
    let display = Display::open()?;
    let window = display
        .windows(b"_NET_CLIENT_LIST_STACKING")?
        .into_iter()
        .rev()
        .find(|window| display.pid(*window).ok() == Some(pid))
        .ok_or_else(|| Error::access("No X11 window for the requested PID"))?;
    let event = ClientMessageEvent::new(32, window, display.atom(b"_NET_ACTIVE_WINDOW")?, [2, x11rb::CURRENT_TIME, 0, 0, 0]);
    display
        .connection
        .send_event(false, display.root, EventMask::SUBSTRUCTURE_REDIRECT | EventMask::SUBSTRUCTURE_NOTIFY, event)?
        .check()?;
    Ok(())
}
pub fn key(pid: i32, key: &Key) -> Result<()> {
    let display = Display::open()?;
    let mut keys =
        key.modifiers.iter().map(|index| display.keycode([0xffe3, 0xffe3, 0xffe9, 0xffe1][*index])).collect::<Result<Vec<_>>>()?;
    keys.dedup();
    keys.push(display.keycode(key.code)?);
    require_foreground(pid)?;
    display.press(&keys)
}
pub fn click(pid: i32, x: f64, y: f64) -> Result<()> {
    if x < i16::MIN as f64 || x > i16::MAX as f64 || y < i16::MIN as f64 || y > i16::MAX as f64 {
        return Err(Error::usage("Coordinate exceeds the X11 screen range"));
    }
    let (x, y) = (x.round() as i16, y.round() as i16);
    let display = Display::open()?;
    require_foreground(pid)?;
    if display.point_pid(x, y)? != pid {
        return Err(Error::access("Screen point belongs to another application"));
    }
    display.emit(MOTION_NOTIFY_EVENT, 0, x, y)?;
    require_foreground(pid)?;
    if display.point_pid(x, y)? != pid {
        return Err(Error::access("Screen point changed ownership"));
    }
    display.emit(BUTTON_PRESS_EVENT, 1, x, y)?;
    display.emit(BUTTON_RELEASE_EVENT, 1, x, y)
}
pub fn scroll(pid: i32, direction: &str, amount: i32) -> Result<()> {
    let display = Display::open()?;
    let point = display.connection.query_pointer(display.root)?.reply()?;
    require_foreground(pid)?;
    if !point.same_screen || display.point_pid(point.root_x, point.root_y)? != pid {
        return Err(Error::access("Pointer belongs to another application"));
    }
    let button = match direction {
        "up" => 4,
        "down" => 5,
        "left" => 6,
        _ => 7,
    };
    for _ in 0..amount {
        require_foreground(pid)?;
        display.emit(BUTTON_PRESS_EVENT, button, 0, 0)?;
        display.emit(BUTTON_RELEASE_EVENT, button, 0, 0)?;
    }
    Ok(())
}
macro_rules! errors {
    ($($kind:ty),*) => { $(impl From<$kind> for Error { fn from(value: $kind) -> Self { Self::access(value.to_string()) } })* };
}
errors!(x11rb::errors::ConnectError, x11rb::errors::ConnectionError, x11rb::errors::ReplyError);
