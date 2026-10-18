#![allow(non_upper_case_globals)]
use crate::{
    error::{Error, Result},
    guards, native,
};
use serde_json::{Value, json};
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
    pub fn root(pid: i32) -> Result<Self> {
        Ok(Self {
            element: None,
            pid,
            automation: unsafe { CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)? },
        })
    }
    pub fn application(pid: i32) -> Result<Self> {
        if pid <= 0 || !native::windows()?.iter().any(|window| window.pid == pid) {
            return Err(Error::access(format!("No visible windows for PID {pid}")));
        }
        Self::root(pid)
    }
    pub fn resolve(&self, path: &str) -> Result<Self> {
        let mut node = self.clone();
        for index in guards::path(path)? {
            node = node.children()?.into_iter().nth(index).ok_or_else(|| {
                Error::access(format!(
                    "Path {path} no longer exists; rediscover the target"
                ))
            })?;
        }
        Ok(node)
    }
    pub fn focused(&self) -> Result<Self> {
        self.with_same_process_element(unsafe { self.automation.GetFocusedElement()? })
    }
    fn with_same_process_element(&self, element: IUIAutomationElement) -> Result<Self> {
        let observed_pid = unsafe { element.CurrentProcessId()? };
        if observed_pid != self.pid {
            return Err(Error::access(format!(
                "Target belongs to a different process (expected {}, observed {observed_pid}); rediscover the target",
                self.pid
            )));
        }
        Ok(Self {
            element: Some(element),
            pid: self.pid,
            automation: self.automation.clone(),
        })
    }
    fn element(&self) -> Result<&IUIAutomationElement> {
        self.element
            .as_ref()
            .ok_or_else(|| Error::usage("Choose a control path"))
    }
    fn available_pattern<T: Interface>(&self, id: UIA_PATTERN_ID) -> Result<Option<T>> {
        let Some(e) = &self.element else {
            return Ok(None);
        };
        let availability_property = match id {
            UIA_InvokePatternId => UIA_IsInvokePatternAvailablePropertyId,
            UIA_SelectionItemPatternId => UIA_IsSelectionItemPatternAvailablePropertyId,
            UIA_TogglePatternId => UIA_IsTogglePatternAvailablePropertyId,
            UIA_ExpandCollapsePatternId => UIA_IsExpandCollapsePatternAvailablePropertyId,
            UIA_ScrollItemPatternId => UIA_IsScrollItemPatternAvailablePropertyId,
            UIA_ValuePatternId => UIA_IsValuePatternAvailablePropertyId,
            UIA_TextPatternId => UIA_IsTextPatternAvailablePropertyId,
            _ => return Err(Error::unexpected("Unknown UIA pattern")),
        };
        unsafe {
            let value = e.GetCurrentPropertyValue(availability_property)?;
            if !bool::try_from(&value).map_err(Error::from)? {
                return Ok(None);
            }
            Ok(Some(e.GetCurrentPatternAs::<T>(id)?))
        }
    }
    pub fn role(&self) -> Result<&'static str> {
        let Some(e) = &self.element else {
            return Ok("AXApplication");
        };
        let control = unsafe { e.CurrentControlType()? };
        Ok(
            if control == UIA_EditControlTypeId && unsafe { e.CurrentIsPassword()?.as_bool() } {
                "AXSecureTextField"
            } else {
                control_type_names(control).1
            },
        )
    }
    pub fn value(&self) -> Result<Option<String>> {
        let Some(e) = &self.element else {
            return Ok(None);
        };
        unsafe {
            if e.CurrentIsPassword()?.as_bool() {
                return Ok(None);
            }
            if let Some(p) =
                self.available_pattern::<IUIAutomationValuePattern>(UIA_ValuePatternId)?
            {
                return Ok(Some(p.CurrentValue()?.to_string()));
            }
            if let Some(p) =
                self.available_pattern::<IUIAutomationTextPattern>(UIA_TextPatternId)?
            {
                return Ok(Some(p.DocumentRange()?.GetText(65536)?.to_string()));
            }
        }
        Ok(None)
    }
    pub fn writable(&self) -> Result<bool> {
        let Some(e) = &self.element else {
            return Ok(false);
        };
        unsafe {
            if e.CurrentIsPassword()?.as_bool()
                || !e.CurrentIsEnabled()?.as_bool()
                || !matches!(self.role()?, "AXTextField" | "AXTextArea" | "AXComboBox")
            {
                return Ok(false);
            }
            match self.available_pattern::<IUIAutomationValuePattern>(UIA_ValuePatternId)? {
                Some(p) => Ok(!p.CurrentIsReadOnly()?.as_bool()),
                None => Ok(false),
            }
        }
    }
    pub fn has_focus(&self) -> Result<bool> {
        let Some(e) = &self.element else {
            return Ok(false);
        };
        unsafe {
            Ok(e.CurrentHasKeyboardFocus()?.as_bool()
                && self
                    .automation
                    .CompareElements(e, &self.automation.GetFocusedElement()?)?
                    .as_bool())
        }
    }
    pub fn exact_draft(&self, expected: &str) -> Result<bool> {
        Ok(self.value()?.is_some_and(|v| guards::exact(&v, expected)))
    }
    pub fn require_focused_draft(&self, expected: &str) -> Result<()> {
        let writable = self.writable()?;
        let focused = self.has_focus()?;
        let matches = self.exact_draft(expected)?;
        let frontmost = native::foreground_pid() == self.pid;
        if !(writable && focused && matches && frontmost) {
            return Err(Error::access(
                "Input blocked: writable target, keyboard focus, exact draft and foreground PID must all match. Do not send.",
            ));
        }
        Ok(())
    }
    pub fn selected(&self) -> Result<bool> {
        match self
            .available_pattern::<IUIAutomationSelectionItemPattern>(UIA_SelectionItemPatternId)?
        {
            Some(p) => Ok(unsafe { p.CurrentIsSelected()?.as_bool() }),
            None => Ok(false),
        }
    }
    pub fn actions(&self) -> Result<Vec<&'static str>> {
        let mut actions = vec![];
        if self
            .available_pattern::<IUIAutomationInvokePattern>(UIA_InvokePatternId)?
            .is_some()
            || self
                .available_pattern::<IUIAutomationSelectionItemPattern>(UIA_SelectionItemPatternId)?
                .is_some()
            || self
                .available_pattern::<IUIAutomationTogglePattern>(UIA_TogglePatternId)?
                .is_some()
        {
            actions.push("AXPress");
        }
        if self
            .available_pattern::<IUIAutomationExpandCollapsePattern>(UIA_ExpandCollapsePatternId)?
            .is_some()
        {
            actions.push("AXShowMenu");
        }
        if self
            .available_pattern::<IUIAutomationScrollItemPattern>(UIA_ScrollItemPatternId)?
            .is_some()
        {
            actions.push("AXScrollToVisible");
        }
        Ok(actions)
    }
    pub fn detail(&self, path: Option<&str>) -> Result<Value> {
        let mut row = json!({"pid": self.pid, "role": self.role()?});
        if let Some(path) = path {
            row["path"] = json!(path);
        }
        let Some(e) = &self.element else {
            row["title"] = json!(native::process_name(self.pid));
            return Ok(row);
        };
        unsafe {
            let name = e.CurrentName()?.to_string();
            let help = e.CurrentHelpText()?.to_string();
            row["title"] = json!(name);
            row["description"] = json!(if help.is_empty() { name } else { help });
            row["identifier"] = json!(e.CurrentAutomationId()?.to_string());
            row["subrole"] = json!(format!(
                "ControlType.{}",
                control_type_names(e.CurrentControlType()?).0
            ));
            row["value"] = json!(self.value()?);
            row["enabled"] = json!(e.CurrentIsEnabled()?.as_bool());
            row["focused"] = json!(e.CurrentHasKeyboardFocus()?.as_bool());
            row["selected"] = json!(self.selected()?);
            row["actions"] = json!(self.actions()?);
            row["attributes"] = json!([
                "AXRole",
                "AXTitle",
                "AXDescription",
                "AXValue",
                "AXEnabled",
                "AXFocused",
                "AXSelected",
                "AXPosition",
                "AXSize"
            ]);
            let bounds = e.CurrentBoundingRectangle()?;
            row["position"] = json!({"x": bounds.left, "y": bounds.top});
            row["size"] = json!({"width": i64::from(bounds.right) - i64::from(bounds.left), "height": i64::from(bounds.bottom) - i64::from(bounds.top)});
        }
        Ok(row)
    }
    pub fn children(&self) -> Result<Vec<Self>> {
        let mut children = vec![];
        unsafe {
            if let Some(e) = &self.element {
                let walker = self.automation.ControlViewWalker()?;
                let mut child = nullable_uia_element(walker.GetFirstChildElement(e))?;
                while let Some(current) = child {
                    if children.len() == 10000 {
                        return Err(Error::access(
                            "Control has more than 10000 children; narrow the target",
                        ));
                    }
                    let parent = nullable_uia_element(walker.GetParentElement(&current))?
                        .ok_or_else(|| {
                            Error::access(
                                "Accessibility child lost its parent; rediscover the target",
                            )
                        })?;
                    let has_expected_parent =
                        self.automation.CompareElements(e, &parent)?.as_bool();
                    let desktop_parented_combo_popup = children.is_empty()
                        && e.CurrentControlType()? == UIA_ComboBoxControlTypeId
                        && current.CurrentControlType()? == UIA_ListControlTypeId
                        && self
                            .automation
                            .CompareElements(&parent, &self.automation.GetRootElement()?)?
                            .as_bool();
                    if !has_expected_parent && !desktop_parented_combo_popup {
                        return Err(Error::access(
                            "Accessibility child changed parents; rediscover the target",
                        ));
                    }
                    children.push(self.with_same_process_element(current.clone())?);
                    if desktop_parented_combo_popup {
                        break;
                    }
                    child = nullable_uia_element(walker.GetNextSiblingElement(&current))?;
                }
            } else {
                for window in native::windows()?.into_iter().filter(|w| w.pid == self.pid) {
                    children.push(self.with_same_process_element(
                        self.automation.ElementFromHandle(window.handle)?,
                    )?);
                }
            }
        }
        Ok(children)
    }
    pub fn focus(&self) -> Result<()> {
        let e = self.element()?;
        native::activate(self.pid)?;
        unsafe {
            e.SetFocus()?;
        }
        if !self.has_focus()? {
            return Err(Error::access("The target did not receive keyboard focus"));
        }
        Ok(())
    }
    pub fn set_value(&self, text: &str) -> Result<()> {
        if !self.writable()? {
            return Err(Error::usage(
                "Target is not a writable UI Automation text control",
            ));
        }
        unsafe {
            self.available_pattern::<IUIAutomationValuePattern>(UIA_ValuePatternId)?
                .ok_or_else(|| Error::access("ValuePattern disappeared"))?
                .SetValue(&BSTR::from(text))?;
        }
        Ok(())
    }
    pub fn press(&self) -> Result<()> {
        unsafe {
            if let Some(p) =
                self.available_pattern::<IUIAutomationInvokePattern>(UIA_InvokePatternId)?
            {
                p.Invoke()?;
            } else if let Some(p) = self.available_pattern::<IUIAutomationSelectionItemPattern>(
                UIA_SelectionItemPatternId,
            )? {
                p.Select()?;
            } else if let Some(p) =
                self.available_pattern::<IUIAutomationTogglePattern>(UIA_TogglePatternId)?
            {
                p.Toggle()?;
            } else {
                return Err(Error::usage("Target does not support AXPress"));
            }
        }
        Ok(())
    }
    pub fn expand(&self) -> Result<()> {
        unsafe {
            self.available_pattern::<IUIAutomationExpandCollapsePattern>(
                UIA_ExpandCollapsePatternId,
            )?
            .ok_or_else(|| Error::usage("Target does not support AXShowMenu"))?
            .Expand()?;
        }
        Ok(())
    }
    pub fn scroll_to(&self) -> Result<()> {
        unsafe {
            self.available_pattern::<IUIAutomationScrollItemPattern>(UIA_ScrollItemPatternId)?
                .ok_or_else(|| Error::usage("Target does not support AXScrollToVisible"))?
                .ScrollIntoView()?;
        }
        Ok(())
    }
}
fn nullable_uia_element(
    result: windows::core::Result<IUIAutomationElement>,
) -> Result<Option<IUIAutomationElement>> {
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
    id.0.checked_sub(50000)
        .and_then(|n| NAMES.get(n as usize))
        .copied()
        .unwrap_or(("Custom", "AXGroup"))
}
