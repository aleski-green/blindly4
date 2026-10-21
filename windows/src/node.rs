#![allow(non_upper_case_globals)]
use super::native;
use crate::error::{Error, Result};
use serde_json::{Value, json};
use windows::Win32::{
    Foundation::HWND,
    UI::WindowsAndMessaging::{GA_ROOT, GetAncestor, IsWindowVisible},
};
use windows::{
    Win32::{System::Com::*, UI::Accessibility::*},
    core::{BSTR, Interface},
};

#[derive(Clone)]
pub struct Node {
    element: Option<IUIAutomationElement>,
    pid: i32,
    automation: IUIAutomation,
}
impl Node {
    pub fn pid(&self) -> i32 {
        self.pid
    }
    pub fn root(pid: i32) -> Result<Self> {
        Ok(Self { element: None, pid, automation: unsafe { CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)? } })
    }
    pub fn application(pid: i32) -> Result<Self> {
        if pid <= 0 || !native::windows()?.iter().any(|window| window.pid == pid) {
            return Err(Error::access(format!("No visible windows for PID {pid}")));
        }
        Self::root(pid)
    }
    pub fn focused(&self) -> Result<Self> {
        self.with_application_element(unsafe { self.automation.GetFocusedElement()? })
    }
    pub fn window_application_pid(window: HWND) -> i32 {
        let pid = native::window_pid(window);
        let host = (|| -> Result<Option<i32>> {
            let node = Self::root(pid)?;
            unsafe { node.fragment_host(&node.automation.RawViewWalker()?, &node.automation.ElementFromHandle(window)?) }
        })();
        host.ok().flatten().unwrap_or(pid)
    }
    fn require_application_element(&self, element: &IUIAutomationElement) -> Result<()> {
        let observed_pid = unsafe { element.CurrentProcessId()? };
        if observed_pid == self.pid {
            return Ok(());
        }
        // Chromium providers may use another PID. Require native ownership or a
        // reciprocal UIA hosting link at the first HWND, never process ancestry.
        let walker = unsafe { self.automation.RawViewWalker()? };
        let mut current = element.clone();
        for _ in 0..128 {
            let handle = unsafe { current.CurrentNativeWindowHandle()? };
            if !handle.0.is_null() {
                let root = unsafe { GetAncestor(handle, GA_ROOT) };
                if !root.0.is_null() && native::window_pid(root) == self.pid && unsafe { IsWindowVisible(root).as_bool() } {
                    return Ok(());
                }
                if !root.0.is_null()
                    && unsafe { IsWindowVisible(root).as_bool() }
                    && self.fragment_host(&walker, &unsafe { self.automation.ElementFromHandle(root)? })? == Some(self.pid)
                {
                    return Ok(());
                }
                break;
            }
            let Some(parent) = nullable_uia_element(unsafe { walker.GetParentElement(&current) })? else { break };
            if unsafe { self.automation.CompareElements(&current, &parent)?.as_bool() } {
                break;
            }
            current = parent;
        }
        Err(Error::access(format!(
            "Target belongs to a different application (expected window PID {}, provider PID {observed_pid}); rediscover the target",
            self.pid
        )))
    }
    fn fragment_host(&self, walker: &IUIAutomationTreeWalker, fragment: &IUIAutomationElement) -> Result<Option<i32>> {
        // Composition WebViews can be native top-level windows hosted in another
        // process's UIA tree. Verify the host from its HWND, not just an upward link.
        unsafe {
            let Some(parent) = nullable_uia_element(walker.GetParentElement(fragment))? else { return Ok(None) };
            let handle = parent.CurrentNativeWindowHandle()?;
            let root = GetAncestor(handle, GA_ROOT);
            let pid = native::window_pid(handle);
            if handle.0.is_null()
                || root.0.is_null()
                || pid <= 0
                || native::window_pid(root) != pid
                || !IsWindowVisible(handle).as_bool()
                || !IsWindowVisible(root).as_bool()
            {
                return Ok(None);
            }
            let host = self.automation.ElementFromHandle(handle)?;
            if !self.automation.CompareElements(&parent, &host)?.as_bool() {
                return Ok(None);
            }
            let Some(child) = nullable_uia_element(walker.GetFirstChildElement(&host))? else { return Ok(None) };
            let Some(current_parent) = nullable_uia_element(walker.GetParentElement(&child))? else { return Ok(None) };
            Ok((self.automation.CompareElements(&child, fragment)?.as_bool()
                && self.automation.CompareElements(&current_parent, &host)?.as_bool())
            .then_some(pid))
        }
    }
    fn with_application_element(&self, element: IUIAutomationElement) -> Result<Self> {
        self.require_application_element(&element)?;
        Ok(Self { element: Some(element), pid: self.pid, automation: self.automation.clone() })
    }
    fn element(&self) -> Result<&IUIAutomationElement> {
        self.element.as_ref().ok_or_else(|| Error::usage("Choose a control path"))
    }
    fn pattern<T: Pattern>(&self) -> Result<Option<T>> {
        let Some(e) = &self.element else {
            return Ok(None);
        };
        unsafe {
            if !bool::try_from(&e.GetCurrentPropertyValue(T::AVAILABLE)?)? {
                return Ok(None);
            }
            Ok(Some(e.GetCurrentPatternAs::<T>(T::ID)?))
        }
    }

    pub fn is_root(&self) -> bool {
        self.element.is_none()
    }
    pub fn secure(&self) -> Result<bool> {
        Ok(!self.is_root() && unsafe { self.element()?.CurrentIsPassword()?.as_bool() })
    }

    pub fn value_settable(&self) -> Result<bool> {
        match self.pattern::<IUIAutomationValuePattern>()? {
            Some(p) => Ok(!unsafe { p.CurrentIsReadOnly()?.as_bool() }),
            None => Ok(false),
        }
    }

    pub fn focus_flag(&self) -> Result<bool> {
        Ok(!self.is_root() && unsafe { self.element()?.CurrentHasKeyboardFocus()?.as_bool() })
    }

    pub fn actions(&self) -> Result<Vec<&'static str>> {
        let mut result = vec![];
        for name in ["AXPress", "AXShowMenu", "AXScrollToVisible"] {
            if self.action(name, false)? {
                result.push(name);
            }
        }
        Ok(result)
    }
    pub fn property(&self, name: &str) -> Result<Option<Value>> {
        let Some(e) = &self.element else {
            return Ok(match name {
                "AXRole" => Some(json!("AXApplication")),
                "AXTitle" => Some(json!(native::process_name(self.pid))),
                _ => None,
            });
        };
        Ok(Some(unsafe {
            match name {
                "AXRole" => json!(if e.CurrentControlType()? == UIA_EditControlTypeId && self.secure()? {
                    "AXSecureTextField"
                } else {
                    control_type_names(e.CurrentControlType()?).1
                }),
                "AXSubrole" => json!(format!("ControlType.{}", control_type_names(e.CurrentControlType()?).0)),
                "AXTitle" => json!(e.CurrentName()?.to_string()),
                "AXDescription" => {
                    let help = e.CurrentHelpText()?.to_string();
                    json!(if help.is_empty() { e.CurrentName()?.to_string() } else { help })
                }
                "AXIdentifier" => json!(e.CurrentAutomationId()?.to_string()),
                "AXEnabled" => json!(e.CurrentIsEnabled()?.as_bool()),
                "AXFocused" => json!(e.CurrentHasKeyboardFocus()?.as_bool()),
                "AXSelected" => json!(match self.pattern::<IUIAutomationSelectionItemPattern>()? {
                    Some(p) => p.CurrentIsSelected()?.as_bool(),
                    None => false,
                }),
                "AXValue" if self.secure()? => Value::Null,
                "AXValue" => {
                    if let Some(p) = self.pattern::<IUIAutomationValuePattern>()? {
                        json!(p.CurrentValue()?.to_string())
                    } else if let Some(p) = self.pattern::<IUIAutomationTextPattern>()? {
                        json!(p.DocumentRange()?.GetText(65536)?.to_string())
                    } else {
                        Value::Null
                    }
                }
                "AXPosition" | "AXSize" => {
                    let b = e.CurrentBoundingRectangle()?;
                    if name == "AXPosition" {
                        json!({"x": b.left, "y": b.top})
                    } else {
                        json!({"width": i64::from(b.right) - i64::from(b.left), "height": i64::from(b.bottom) - i64::from(b.top)})
                    }
                }
                _ => return Ok(None),
            }
        }))
    }
    pub fn properties(&self) -> Result<std::collections::BTreeMap<String, Value>> {
        let mut values = std::collections::BTreeMap::new();
        for name in crate::element::ATTRIBUTES {
            if let Some(value) = self.property(name)? {
                values.insert((*name).into(), value);
            }
        }
        Ok(values)
    }
    pub fn attribute_names(&self) -> Result<Option<Vec<String>>> {
        Ok((!self.is_root()).then(|| {
            crate::element::ATTRIBUTES
                .iter()
                .filter(|name| !matches!(**name, "AXSubrole" | "AXIdentifier"))
                .map(|name| (*name).to_owned())
                .collect()
        }))
    }
    pub fn children(&self) -> Result<Vec<Self>> {
        let mut children = vec![];
        unsafe {
            if let Some(e) = &self.element {
                let walker = self.automation.ControlViewWalker()?;
                let mut child = nullable_uia_element(walker.GetFirstChildElement(e))?;
                while let Some(current) = child {
                    if children.len() == 10000 {
                        return Err(Error::access("Control has more than 10000 children; narrow the target"));
                    }
                    let parent = nullable_uia_element(walker.GetParentElement(&current))?
                        .ok_or_else(|| Error::access("Accessibility child lost its parent; rediscover the target"))?;
                    let has_expected_parent = self.automation.CompareElements(e, &parent)?.as_bool();
                    let desktop_parented_combo_popup = children.is_empty()
                        && e.CurrentControlType()? == UIA_ComboBoxControlTypeId
                        && current.CurrentControlType()? == UIA_ListControlTypeId
                        && self.automation.CompareElements(&parent, &self.automation.GetRootElement()?)?.as_bool();
                    if !has_expected_parent && !desktop_parented_combo_popup {
                        return Err(Error::access("Accessibility child changed parents; rediscover the target"));
                    }
                    children.push(self.with_application_element(current.clone())?);
                    if desktop_parented_combo_popup {
                        break;
                    }
                    child = nullable_uia_element(walker.GetNextSiblingElement(&current))?;
                }
            } else {
                for window in native::windows()?.into_iter().filter(|w| w.pid == self.pid) {
                    children.push(self.with_application_element(self.automation.ElementFromHandle(window.handle)?)?);
                }
            }
        }
        Ok(children)
    }
    pub fn same(&self, other: &Self) -> bool {
        if self.pid != other.pid {
            return false;
        }
        match (&self.element, &other.element) {
            (Some(a), Some(b)) => unsafe { self.automation.CompareElements(a, b) }.is_ok_and(|v| v.as_bool()),
            (None, None) => true,
            _ => false,
        }
    }

    pub fn focus_native(&self) -> Result<()> {
        self.require_application_element(self.element()?)?;
        unsafe {
            self.element()?.SetFocus()?;
        }
        Ok(())
    }
    pub fn selected_text_native(&self, text: &str) -> Result<()> {
        native::text(self.pid, text)
    }
    pub fn set_value_native(&self, text: &str) -> Result<()> {
        self.require_application_element(self.element()?)?;
        unsafe {
            self.pattern::<IUIAutomationValuePattern>()?
                .ok_or_else(|| Error::access("ValuePattern disappeared"))?
                .SetValue(&BSTR::from(text))?;
        }
        Ok(())
    }
    pub fn perform(&self, name: &str) -> Result<()> {
        self.require_application_element(self.element()?)?;
        if self.action(name, true)? { Ok(()) } else { Err(Error::usage(format!("Target does not support {name}"))) }
    }
}
fn nullable_uia_element(result: windows::core::Result<IUIAutomationElement>) -> Result<Option<IUIAutomationElement>> {
    match result {
        Ok(e) => Ok(Some(e)),
        Err(e) if e.code() == windows::Win32::Foundation::S_OK => Ok(None),
        Err(e) => Err(e.into()),
    }
}
fn control_type_names(id: UIA_CONTROLTYPE_ID) -> (&'static str, &'static str) {
    const NAMES: &[(&str, &str)] = &[
        ("Button", "AXButton"),
        ("Calendar", "AXGroup"),
        ("CheckBox", "AXCheckBox"),
        ("ComboBox", "AXComboBox"),
        ("Edit", "AXTextField"),
        ("Hyperlink", "AXLink"),
        ("Image", "AXImage"),
        ("ListItem", "AXRow"),
        ("List", "AXList"),
        ("Menu", "AXMenu"),
        ("MenuBar", "AXMenuBar"),
        ("MenuItem", "AXMenuItem"),
        ("ProgressBar", "AXProgressIndicator"),
        ("RadioButton", "AXRadioButton"),
        ("ScrollBar", "AXScrollBar"),
        ("Slider", "AXSlider"),
        ("Spinner", "AXGroup"),
        ("StatusBar", "AXGroup"),
        ("Tab", "AXTabGroup"),
        ("TabItem", "AXRadioButton"),
        ("Text", "AXStaticText"),
        ("ToolBar", "AXGroup"),
        ("ToolTip", "AXGroup"),
        ("Tree", "AXOutline"),
        ("TreeItem", "AXRow"),
        ("Custom", "AXGroup"),
        ("Group", "AXGroup"),
        ("Thumb", "AXGroup"),
        ("DataGrid", "AXTable"),
        ("DataItem", "AXGroup"),
        ("Document", "AXTextArea"),
        ("SplitButton", "AXGroup"),
        ("Window", "AXWindow"),
        ("Pane", "AXGroup"),
        ("Header", "AXGroup"),
        ("HeaderItem", "AXGroup"),
        ("Table", "AXTable"),
        ("TitleBar", "AXGroup"),
        ("Separator", "AXGroup"),
        ("SemanticZoom", "AXGroup"),
        ("AppBar", "AXGroup"),
    ];
    id.0.checked_sub(50000).and_then(|n| NAMES.get(n as usize)).copied().unwrap_or(("Custom", "AXGroup"))
}

trait Pattern: Interface {
    const ID: UIA_PATTERN_ID;
    const AVAILABLE: UIA_PROPERTY_ID;
}
macro_rules! patterns {
    ($($kind:ty, $id:ident, $available:ident $(, $action:literal, $method:ident)?;)*) => {
        $(impl Pattern for $kind {
            const ID: UIA_PATTERN_ID = $id;
            const AVAILABLE: UIA_PROPERTY_ID = $available;
        })*
        impl Node {
            fn action(&self, name: &str, execute: bool) -> Result<bool> {
                $($(if name == $action {
                    if let Some(pattern) = self.pattern::<$kind>()? {
                        if execute { unsafe { pattern.$method()?; } }
                        return Ok(true);
                    }
                })?)*
                Ok(false)
            }
        }
    };
}
patterns! {
    IUIAutomationInvokePattern, UIA_InvokePatternId, UIA_IsInvokePatternAvailablePropertyId, "AXPress", Invoke;
    IUIAutomationSelectionItemPattern, UIA_SelectionItemPatternId, UIA_IsSelectionItemPatternAvailablePropertyId, "AXPress", Select;
    IUIAutomationTogglePattern, UIA_TogglePatternId, UIA_IsTogglePatternAvailablePropertyId, "AXPress", Toggle;
    IUIAutomationExpandCollapsePattern, UIA_ExpandCollapsePatternId, UIA_IsExpandCollapsePatternAvailablePropertyId, "AXShowMenu", Expand;
    IUIAutomationScrollItemPattern, UIA_ScrollItemPatternId, UIA_IsScrollItemPatternAvailablePropertyId, "AXScrollToVisible", ScrollIntoView;
    IUIAutomationValuePattern, UIA_ValuePatternId, UIA_IsValuePatternAvailablePropertyId;
    IUIAutomationTextPattern, UIA_TextPatternId, UIA_IsTextPatternAvailablePropertyId;
}
