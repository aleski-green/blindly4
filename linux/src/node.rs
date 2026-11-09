use crate::error::{Error, Result};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use zbus::{
    blocking::{Connection, Proxy, connection::Builder, proxy},
    proxy::CacheProperties,
    zvariant::OwnedObjectPath,
};

type Reference = (String, OwnedObjectPath);
const ACCESSIBLE: &str = "org.a11y.atspi.Accessible";
const EDITABLE: &str = "org.a11y.atspi.EditableText";
const TEXT: &str = "org.a11y.atspi.Text";
const COMPONENT: &str = "org.a11y.atspi.Component";
const ACTION: &str = "org.a11y.atspi.Action";
const ACTIVE: u32 = 1;
const EDITABLE_STATE: u32 = 7;
const SENSITIVE: u32 = 24;
const FOCUSED: u32 = 12;
const MULTILINE: u32 = 17;
const SELECTED: u32 = 23;

#[derive(Clone)]
pub struct Node {
    connection: Connection,
    reference: Reference,
    window: Option<Reference>,
    web: bool,
    legacy_webkit_roles: bool,
    pid: i32,
    root: bool,
}
impl Node {
    pub fn desktop() -> Result<Self> {
        let session = Connection::session()?;
        let bus = Proxy::new(&session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus")?;
        let address: String = bus.call("GetAddress", &())?;
        let connection = Builder::address(address.as_str())?.build()?;
        Proxy::new(&connection, "org.a11y.atspi.Registry", "/org/a11y/atspi/registry", "org.a11y.atspi.Registry")?
            .call::<_, _, ()>("RegisterEvent", &("object:children-changed",))?;
        Ok(Self {
            connection,
            reference: ("org.a11y.atspi.Registry".into(), OwnedObjectPath::try_from("/org/a11y/atspi/accessible/root").unwrap()),
            window: None,
            web: false,
            legacy_webkit_roles: false,
            pid: 0,
            root: true,
        })
    }
    pub fn root(pid: i32) -> Result<Self> {
        Self::application(pid)
    }
    pub fn application(pid: i32) -> Result<Self> {
        if pid > 0 {
            for mut app in Self::desktop()?.children()? {
                if app.process_id().ok() == Some(pid) {
                    app.pid = pid;
                    app.root = true;
                    return Ok(app);
                }
            }
        }
        Err(Error::access(format!("No accessible application for PID {pid}")))
    }
    pub fn process_id(&self) -> Result<i32> {
        let bus = Proxy::new(&self.connection, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus")?;
        let pid: u32 = bus.call("GetConnectionUnixProcessID", &self.reference.0)?;
        i32::try_from(pid).map_err(|_| Error::access("Invalid application PID"))
    }
    fn proxy<'a>(&'a self, interface: &'a str) -> Result<Proxy<'a>> {
        self.reference_proxy(&self.reference, interface)
    }
    fn reference_proxy<'a>(&'a self, reference: &'a Reference, interface: &'a str) -> Result<Proxy<'a>> {
        if reference.1.as_str() == "/org/a11y/atspi/null" {
            return Err(Error::access(
                "Application returned a null accessibility element; rediscover the target. For Chromium, restart with --force-renderer-accessibility.",
            ));
        }
        // Each CLI observation reads fresh properties; subscriptions and GetAll
        // caches add work and can block on unrelated provider properties.
        Ok(proxy::Builder::new(&self.connection)
            .destination(reference.0.as_str())?
            .path(reference.1.as_str())?
            .interface(interface)?
            .cache_properties(CacheProperties::No)
            .build()?)
    }
    fn supports(&self, interface: &str) -> Result<bool> {
        let interfaces: Vec<String> = self.proxy(ACCESSIBLE)?.call("GetInterfaces", &())?;
        Ok(interfaces.iter().any(|value| value == interface))
    }
    fn state(&self, state: u32) -> Result<bool> {
        let states: Vec<u32> = self.proxy(ACCESSIBLE)?.call("GetState", &())?;
        if states.first().is_some_and(|value| value & (1 << 6) != 0) {
            return Err(Error::access("Accessible element is defunct; rediscover the target"));
        }
        Ok(states.get((state / 32) as usize).is_some_and(|value| value & (1 << (state % 32)) != 0))
    }
    pub fn pid(&self) -> i32 {
        self.pid
    }
    pub fn is_root(&self) -> bool {
        self.root
    }
    pub fn same(&self, other: &Self) -> bool {
        self.reference == other.reference
    }
    pub fn secure(&self) -> Result<bool> {
        let role: u32 = self.proxy(ACCESSIBLE)?.call("GetRole", &())?;
        Ok(role == 40)
    }
    pub fn value_settable(&self) -> Result<bool> {
        Ok(self.state(EDITABLE_STATE)? && self.supports(if super::keyboard_text_input() { TEXT } else { EDITABLE })?)
    }
    pub fn focus_flag(&self) -> Result<bool> {
        self.state(FOCUSED)
    }
    pub fn children(&self) -> Result<Vec<Self>> {
        let accessible = self.proxy(ACCESSIBLE)?;
        let mut children: Vec<Reference> = accessible.call("GetChildren", &())?;
        if children.is_empty() {
            let count: i32 = accessible.get_property("ChildCount")?;
            if !(0..=10000).contains(&count) {
                return Err(Error::access("Invalid accessibility child count"));
            }
            // Older ATK sockets expose embedded content only through indexed lookup.
            for index in 0..count {
                children.push(accessible.call("GetChildAtIndex", &index)?);
            }
        }
        if children.len() > 10000 {
            return Err(Error::access("Too many accessible children; narrow the target"));
        }
        // Web dialogs also expose AXWindow, but their bounds are not an X11 window.
        // Retain the outer native window used to verify screen coordinates.
        let (role, legacy_webkit_roles) = self.ax_role()?;
        let web = self.web || role == "AXWebArea";
        let window = match &self.window {
            Some(window) => Some(window.clone()),
            None if role == "AXWindow" => Some(self.reference.clone()),
            None => None,
        };
        Ok(children
            .into_iter()
            .map(|reference| Self {
                connection: self.connection.clone(),
                legacy_webkit_roles: legacy_webkit_roles && reference.0 == self.reference.0,
                reference,
                window: window.clone(),
                web,
                pid: self.pid,
                root: false,
            })
            .collect())
    }
    pub fn focused(&self) -> Result<Self> {
        let mut stack = vec![if self.root { self.clone() } else { Self::application(self.pid)? }];
        let mut control: Option<Self> = None;
        let mut container = None;
        let mut ambiguous_container = false;
        for _ in 0..10000 {
            let Some(node) = stack.pop() else {
                return control
                    .or_else(|| if ambiguous_container { None } else { container })
                    .ok_or_else(|| Error::access("No unambiguous focused control in the application"));
            };
            // WebKit may retain a focused control behind a native modal dialog.
            // Only the active top-level window can own the application's focus.
            if node.window.is_none() && node.role()? == "AXWindow" && !node.state(ACTIVE)? {
                continue;
            }
            if node.focus_flag()? {
                if matches!(node.role()?.as_str(), "AXApplication" | "AXWindow" | "AXWebArea" | "AXGroup") {
                    ambiguous_container |= container.is_some();
                    container = Some(node.clone());
                } else {
                    if control.as_ref().is_some_and(|previous| !previous.same(&node)) {
                        return Err(Error::access("Multiple controls report keyboard focus; rediscover the target"));
                    }
                    control = Some(node.clone());
                }
            }
            stack.extend(node.children()?);
        }
        Err(Error::access("Focus discovery exceeds the application traversal budget"))
    }
    fn coordinate_scale(&self) -> Result<i32> {
        let reference = match &self.window {
            Some(window) => window,
            None if self.role()? == "AXWindow" => &self.reference,
            None => return Err(Error::access("No accessible window for coordinate conversion")),
        };
        let window = self.reference_proxy(reference, COMPONENT)?;
        super::x11::coordinate_scale(self.pid, window.call("GetExtents", &0u32)?)
    }
    fn ax_role(&self) -> Result<(&'static str, bool)> {
        let accessible = self.proxy(ACCESSIBLE)?;
        let raw: u32 = accessible.call("GetRole", &())?;
        // WebKit before upstream fix 300090 used a shifted wire enum. Its web
        // document identifies the affected provider without guessing from an
        // individual editable control, distro name, or reported version.
        let legacy = self.legacy_webkit_roles
            || (raw == 94 && self.supports("org.a11y.atspi.Document")? && {
                let attributes: BTreeMap<String, String> = accessible.call("GetAttributes", &())?;
                matches!(attributes.get("toolkit").map(String::as_str), Some("WebKitGTK" | "WPEWebKit"))
            });
        let role = if legacy {
            match raw {
                72..=114 => raw + 1,  // Missing Footer before Paragraph.
                115 | 116 => 67,      // Nonstandard section footer/header (unknown).
                117..=129 => raw - 1, // Two extra roles before Static.
                _ => raw,
            }
        } else {
            raw
        };
        let mapped = match role {
            75 => "AXApplication",
            16 | 19 | 23 | 69 => "AXWindow",
            40 => "AXSecureTextField",
            61 | 79 if self.state(EDITABLE_STATE)? => {
                if self.state(MULTILINE)? {
                    "AXTextArea"
                } else {
                    "AXTextField"
                }
            }
            43 | 62 | 129 => "AXButton",
            7 | 130 => "AXCheckBox",
            44 | 37 => "AXRadioButton",
            11 => "AXComboBox",
            33 | 41 => "AXMenu",
            35 => "AXMenuItem",
            34 => "AXMenuBar",
            29 | 61 | 73 | 116 => "AXStaticText",
            88 => "AXLink",
            27 => "AXImage",
            31 => "AXList",
            32 | 90 => "AXRow",
            55 => "AXTable",
            48 => "AXScrollBar",
            51 => "AXSlider",
            95 => "AXWebArea",
            83 => "AXHeading",
            _ => "AXGroup",
        };
        Ok((mapped, legacy))
    }
    pub fn property(&self, name: &str) -> Result<Option<Value>> {
        let accessible = self.proxy(ACCESSIBLE)?;
        Ok(Some(match name {
            "AXRole" => json!(self.ax_role()?.0),
            // WebKit can stall on GetRoleName for table headers. The canonical
            // role above is sufficient; optional native role-name metadata is omitted.
            "AXSubrole" if self.web => return Ok(None),
            "AXSubrole" => json!(accessible.call::<_, _, String>("GetRoleName", &())?),
            "AXTitle" => json!(accessible.get_property::<String>("Name")?),
            "AXDescription" => {
                let description: String = accessible.get_property("Description")?;
                json!(if description.is_empty() { accessible.get_property::<String>("Name")? } else { description })
            }
            "AXIdentifier" => return Ok(accessible.get_property::<String>("AccessibleId").ok().map(Value::String)),
            "AXEnabled" => json!(self.state(SENSITIVE)?),
            "AXFocused" => json!(self.state(FOCUSED)?),
            "AXSelected" => json!(self.state(SELECTED)?),
            "AXValue" if self.secure()? => Value::Null,
            "AXValue" if self.supports(TEXT)? => {
                let text = self.proxy(TEXT)?;
                let count: i32 = text.get_property("CharacterCount")?;
                json!(text.call::<_, _, String>("GetText", &(0i32, count.min(65536)))?)
            }
            "AXPosition" | "AXSize" if self.supports(COMPONENT)? => {
                let bounds: std::result::Result<(i32, i32, i32, i32), _> = self.proxy(COMPONENT)?.call("GetExtents", &0u32);
                let Ok((x, y, width, height)) = bounds else { return Ok(None) };
                if width <= 0 || height <= 0 {
                    return Ok(None);
                }
                let Ok(scale) = self.coordinate_scale() else { return Ok(None) };
                let scale = i64::from(scale);
                if name == "AXPosition" {
                    json!({"x": i64::from(x) * scale, "y": i64::from(y) * scale})
                } else {
                    json!({"width": i64::from(width) * scale, "height": i64::from(height) * scale})
                }
            }
            _ => return Ok(None),
        }))
    }
    pub fn properties(&self) -> Result<BTreeMap<String, Value>> {
        let mut values = BTreeMap::new();
        for name in crate::element::ATTRIBUTES {
            if let Some(value) = self.property(name)? {
                values.insert((*name).into(), value);
            }
        }
        Ok(values)
    }
    pub fn attribute_names(&self) -> Result<Option<Vec<String>>> {
        Ok(Some(self.properties()?.into_keys().collect()))
    }
    fn native_actions(&self) -> Result<Vec<String>> {
        if !self.supports(ACTION)? {
            return Ok(vec![]);
        }
        let action = self.proxy(ACTION)?;
        let count: i32 = action.get_property("NActions")?;
        if !(0..=64).contains(&count) {
            return Err(Error::access("Invalid accessibility action count"));
        }
        (0..count).map(|index| Ok(action.call("GetName", &index)?)).collect()
    }
    pub fn actions(&self) -> Result<Vec<String>> {
        let actions = self.native_actions().unwrap_or_default();
        let mut result = vec![];
        if actions.iter().any(|name| matches!(name.as_str(), "click" | "press" | "activate" | "toggle")) {
            result.push("AXPress".into());
        }
        if actions.iter().any(|name| matches!(name.as_str(), "show menu" | "popup")) {
            result.push("AXShowMenu".into());
        }
        Ok(result)
    }
    fn accepted(value: bool) -> Result<()> {
        if value { Ok(()) } else { Err(Error::access("Accessibility provider declined the operation")) }
    }
    pub fn focus_native(&self) -> Result<()> {
        if self.has_focus()? {
            return Ok(());
        }
        Self::accepted(self.proxy(COMPONENT)?.call("GrabFocus", &())?)
    }
    pub fn focus_for_paste_native(&self) -> Result<()> {
        self.focus_native()
    }
    pub fn set_value_native(&self, text: &str) -> Result<()> {
        if super::keyboard_text_input() {
            self.focus_for_paste()?;
            let before = self.value()?.ok_or_else(|| Error::access("Text control has no readable draft"))?;
            self.require_focused_draft(&before)?;
            super::key(self.pid, &super::Key::new('a' as u32, &[1]))?;
            self.require_focused_draft(&before)?;
            super::key(self.pid, &super::Key::new(0xff08, &[]))?;
            for _ in 0..50 {
                if self.exact_draft("")? {
                    self.require_empty_draft()?;
                    return self.keyboard_text(text);
                }
                super::wait(0.01);
            }
            return Err(Error::access("Keyboard clear did not produce an empty draft; inspect before retrying"));
        }
        Self::accepted(self.proxy(EDITABLE)?.call("SetTextContents", &text)?)
    }
    pub fn selected_text_native(&self, text: &str) -> Result<()> {
        if super::keyboard_text_input() {
            return self.keyboard_text(text);
        }
        let reader = self.proxy(TEXT)?;
        let selections: i32 = reader.call("GetNSelections", &())?;
        if selections > 1 {
            return Err(Error::access("Multiple text selections are unsupported"));
        }
        let position: i32 = if selections == 1 {
            let (start, end): (i32, i32) = reader.call("GetSelection", &0i32)?;
            Self::accepted(self.proxy(EDITABLE)?.call("DeleteText", &(start, end))?)?;
            start
        } else {
            reader.get_property("CaretOffset")?
        };
        Self::accepted(self.proxy(EDITABLE)?.call("InsertText", &(position, text, text.len() as i32))?)
    }
    fn keyboard_text(&self, text: &str) -> Result<()> {
        let reader = self.proxy(TEXT)?;
        let before: Vec<_> = self.value()?.ok_or_else(|| Error::access("Text control has no readable draft"))?.chars().collect();
        // A verified empty draft has only one insertion point. WebKit may report
        // an unavailable/stale caret after clearing an address field.
        let (start, end): (i32, i32) = if before.is_empty() {
            self.require_focused_draft("")?;
            (0, 0)
        } else {
            match reader.call::<_, _, i32>("GetNSelections", &())? {
                0 => {
                    let caret = reader.get_property("CaretOffset")?;
                    (caret, caret)
                }
                1 => reader.call("GetSelection", &0i32)?,
                _ => return Err(Error::access("Multiple text selections are unsupported")),
            }
        };
        if start < 0 || end < start || end as usize > before.len() {
            return Err(Error::access("Invalid native text selection"));
        }
        let mut expected: String = before[..start as usize].iter().collect();
        expected.push_str(text);
        expected.extend(&before[end as usize..]);
        let focused = || {
            if self.focus_flag()? { Ok(()) } else { Err(Error::access("Text target lost focus; inspect the draft before retrying")) }
        };
        super::x11::text(self.pid, text, focused)?;
        // WebKit can still be draining queued key events after injection finishes.
        for _ in 0..500 {
            if self.exact_draft(&expected)? {
                return self.require_focused_draft(&expected);
            }
            super::wait(0.01);
        }
        Err(Error::access("Keyboard text failed exact draft verification; inspect before retrying"))
    }
    pub fn perform(&self, name: &str) -> Result<()> {
        self.check_control()?;
        if name == "AXScrollToVisible" {
            return Self::accepted(self.proxy(COMPONENT)?.call("ScrollTo", &6u32)?);
        }
        let actions = self.native_actions()?;
        let index = actions
            .iter()
            .position(|native| match name {
                "AXPress" => matches!(native.as_str(), "click" | "press" | "activate" | "toggle"),
                "AXShowMenu" => matches!(native.as_str(), "show menu" | "popup"),
                _ => false,
            })
            .ok_or_else(|| Error::usage(format!("Target does not support {name}")))?;
        Self::accepted(self.proxy(ACTION)?.call("DoAction", &(index as i32))?)
    }
}
