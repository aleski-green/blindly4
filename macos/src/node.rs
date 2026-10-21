use super::ax;
use super::native;
use crate::error::{Error, Result};
use core_foundation::{base::CFType, boolean::CFBoolean, string::CFString};
use serde_json::Value;

#[derive(Clone)]
pub struct Node {
    element: CFType,
    pid: i32,
    root: bool,
}
impl Node {
    pub fn pid(&self) -> i32 {
        self.pid
    }
    pub fn root(pid: i32) -> Result<Self> {
        Self::application(pid)
    }
    pub fn application(pid: i32) -> Result<Self> {
        native::require_app(pid)?;
        Ok(Self { element: ax::application(pid)?, pid, root: true })
    }
    fn child(&self, element: CFType) -> Result<Self> {
        let element = ax::element(element)?;
        Ok(Self { element, pid: self.pid, root: false })
    }
    pub fn same(&self, other: &Self) -> bool {
        self.element == other.element
    }
    pub fn property(&self, name: &str) -> Result<Option<Value>> {
        Ok(ax::attribute(&self.element, name)?.as_ref().and_then(ax::json_value))
    }

    pub fn secure(&self) -> Result<bool> {
        Ok(self.role()? == "AXSecureTextField" || self.text("AXSubrole")? == "AXSecureTextField")
    }

    pub fn is_root(&self) -> bool {
        self.root
    }

    pub fn value_settable(&self) -> Result<bool> {
        ax::settable(&self.element, "AXValue")
    }
    pub fn focus_flag(&self) -> Result<bool> {
        Ok(true)
    }
    pub fn focused(&self) -> Result<Self> {
        let focused =
            ax::attribute(&ax::application(self.pid)?, "AXFocusedUIElement")?.ok_or_else(|| Error::access("No focused element"))?;
        self.child(focused)
    }

    pub fn actions(&self) -> Result<Vec<String>> {
        ax::names(&self.element, true)
    }
    pub fn properties(&self) -> Result<std::collections::BTreeMap<String, Value>> {
        let mut values = ax::attributes(&self.element, crate::element::ATTRIBUTES)?;
        if !values.contains_key("AXValue")
            && matches!(values.get("AXRole").and_then(Value::as_str), Some("AXTextField" | "AXTextArea" | "AXComboBox"))
            && let Some(value) = self.property("AXValue")?
        {
            values.insert("AXValue".into(), value);
        }
        Ok(values)
    }
    pub fn attribute_names(&self) -> Result<Option<Vec<String>>> {
        ax::names(&self.element, false).map(Some)
    }
    fn children_attribute(&self, name: &str) -> Result<Vec<Self>> {
        let Some(value) = ax::attribute(&self.element, name)? else {
            return Ok(vec![]);
        };
        let values = ax::array(&value)?;
        if values.len() > 10000 {
            return Err(Error::access("Too many accessibility children; narrow the target"));
        }
        values.into_iter().map(|element| self.child(element)).collect()
    }
    pub fn children(&self) -> Result<Vec<Self>> {
        let mut children = self.children_attribute("AXChildren")?;
        if self.root && !children.iter().any(|n| n.role().is_ok_and(|role| role == "AXWindow")) {
            for window in self.children_attribute("AXWindows")? {
                if !children.iter().any(|child| child.same(&window)) {
                    children.push(window);
                }
            }
        }
        Ok(children)
    }

    pub fn focus_native(&self) -> Result<()> {
        ax::set(&self.element, "AXFocused", &CFBoolean::true_value())
    }
    pub fn focus_for_paste(&self) -> Result<()> {
        let position = self.property("AXPosition")?.ok_or_else(|| Error::access("Paste target has no screen position"))?;
        let size = self.property("AXSize")?.ok_or_else(|| Error::access("Paste target has no screen size"))?;
        let (x, y, width, height) = (position["x"].as_f64(), position["y"].as_f64(), size["width"].as_f64(), size["height"].as_f64());
        match (x, y, width, height) {
            (Some(x), Some(y), Some(w), Some(h)) if w > 0.0 && h > 0.0 => native::click(self.pid, x + w / 2.0, y + h / 2.0),
            _ => Err(Error::access("Paste target has no usable on-screen bounds")),
        }
    }
    pub fn set_value_native(&self, text: &str) -> Result<()> {
        ax::set(&self.element, "AXValue", &CFString::new(text))
    }
    pub fn selected_text_native(&self, text: &str) -> Result<()> {
        ax::set(&self.element, "AXSelectedText", &CFString::new(text))
    }
    pub fn perform(&self, name: &str) -> Result<()> {
        self.check_control()?;
        if name != "AXPress" && !self.actions()?.iter().any(|action| action == name) {
            return Err(Error::usage(format!("Target does not support {name}")));
        }
        ax::action(&self.element, name)
    }
}
