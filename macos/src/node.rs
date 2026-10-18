use crate::{
    ax,
    error::{Error, Result},
    guards, native,
};
use core_foundation::{base::CFType, boolean::CFBoolean, string::CFString};
use serde_json::{Value, json};

#[derive(Clone)]
pub struct Node {
    element: CFType,
    pid: i32,
    root: bool,
}
impl Node {
    pub fn root(pid: i32) -> Result<Self> {
        Self::application(pid)
    }
    pub fn application(pid: i32) -> Result<Self> {
        native::require_app(pid)?;
        Ok(Self {
            element: ax::application(pid)?,
            pid,
            root: true,
        })
    }
    fn child(&self, element: CFType) -> Result<Self> {
        let element = ax::element(element)?;
        if ax::pid(&element)? != self.pid {
            return Err(Error::access(
                "Accessibility target changed process; rediscover it",
            ));
        }
        Ok(Self {
            element,
            pid: self.pid,
            root: false,
        })
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
    pub fn same(&self, other: &Self) -> bool {
        self.element == other.element
    }
    fn value_of(&self, name: &str) -> Result<Option<Value>> {
        Ok(ax::attribute(&self.element, name)?
            .as_ref()
            .and_then(ax::json_value))
    }
    fn text(&self, name: &str) -> Result<String> {
        Ok(self
            .value_of(name)?
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_default())
    }
    pub fn role(&self) -> Result<String> {
        self.text("AXRole")
    }
    fn secure(&self) -> Result<bool> {
        Ok(self.role()? == "AXSecureTextField" || self.text("AXSubrole")? == "AXSecureTextField")
    }
    pub fn value(&self) -> Result<Option<String>> {
        if self.secure()? {
            return Ok(None);
        }
        Ok(self
            .value_of("AXValue")?
            .and_then(|v| v.as_str().map(str::to_owned)))
    }
    pub fn writable(&self) -> Result<bool> {
        Ok(!self.root
            && !self.secure()?
            && matches!(
                self.role()?.as_str(),
                "AXTextField" | "AXTextArea" | "AXComboBox"
            )
            && self.value_of("AXEnabled")? != Some(json!(false))
            && ax::settable(&self.element, "AXValue")?)
    }
    pub fn focused(&self) -> Result<Self> {
        let focused = ax::attribute(&ax::application(self.pid)?, "AXFocusedUIElement")?
            .ok_or_else(|| Error::access("No focused element"))?;
        self.child(focused)
    }
    pub fn has_focus(&self) -> Result<bool> {
        Ok(self.same(&self.focused()?))
    }
    pub fn exact_draft(&self, expected: &str) -> Result<bool> {
        if self.secure()? {
            return Ok(false);
        }
        // A readable value is authoritative: a label or old descendant must never
        // override a mismatching draft. Web editors lacking AXValue can expose
        // their draft within their own bounded subtree.
        if let Some(actual) = self.value()? {
            return Ok(guards::exact(&actual, expected));
        }
        let mut stack = vec![(self.clone(), 4)];
        let mut count = 0;
        while let Some((node, depth)) = stack.pop() {
            count += 1;
            if count > 250 {
                return Err(Error::access("Draft subtree exceeds verification budget"));
            }
            if node.secure()? {
                continue;
            }
            for key in ["AXValue", "AXTitle", "AXDescription"] {
                if node
                    .value_of(key)?
                    .and_then(|v| v.as_str().map(|s| guards::exact(s, expected)))
                    == Some(true)
                {
                    return Ok(true);
                }
            }
            if depth > 0 {
                stack.extend(node.children()?.into_iter().map(|n| (n, depth - 1)));
            }
        }
        Ok(false)
    }
    pub fn require_focused_draft(&self, expected: &str) -> Result<()> {
        if self.writable()?
            && self.has_focus()?
            && self.exact_draft(expected)?
            && native::foreground_pid() == self.pid
        {
            return Ok(());
        }
        Err(Error::access(
            "Input blocked: writable target, keyboard focus, exact draft and foreground PID must all match. Do not send.",
        ))
    }
    pub fn selected(&self) -> Result<bool> {
        Ok(self.value_of("AXSelected")? == Some(json!(true)))
    }
    pub fn actions(&self) -> Result<Vec<String>> {
        ax::names(&self.element, true)
    }
    pub fn detail(&self, path: Option<&str>) -> Result<Value> {
        let mut result = json!({"pid": self.pid});
        let values = ax::attributes(
            &self.element,
            &[
                "AXRole",
                "AXSubrole",
                "AXTitle",
                "AXDescription",
                "AXValue",
                "AXIdentifier",
                "AXEnabled",
                "AXFocused",
                "AXSelected",
                "AXPosition",
                "AXSize",
            ],
        )?;
        let secure = values.get("AXRole").and_then(Value::as_str) == Some("AXSecureTextField")
            || values.get("AXSubrole").and_then(Value::as_str) == Some("AXSecureTextField");
        for (name, value) in values {
            if secure && name == "AXValue" {
                continue;
            }
            result[name[2..].to_lowercase()] = value;
        }
        result["attributes"] = json!(ax::names(&self.element, false)?);
        result["actions"] = json!(self.actions()?);
        if let Some(path) = path {
            result["path"] = json!(path);
        }
        Ok(result)
    }
    fn children_attribute(&self, name: &str) -> Result<Vec<Self>> {
        let Some(value) = ax::attribute(&self.element, name)? else {
            return Ok(vec![]);
        };
        let values = ax::array(&value)?;
        if values.len() > 10000 {
            return Err(Error::access(
                "Too many accessibility children; narrow the target",
            ));
        }
        values
            .into_iter()
            .map(|element| self.child(element))
            .collect()
    }
    pub fn children(&self) -> Result<Vec<Self>> {
        let mut children = self.children_attribute("AXChildren")?;
        if self.root
            && !children
                .iter()
                .any(|n| n.role().is_ok_and(|role| role == "AXWindow"))
        {
            for window in self.children_attribute("AXWindows")? {
                if !children.iter().any(|child| child.same(&window)) {
                    children.push(window);
                }
            }
        }
        Ok(children)
    }
    fn control(&self) -> Result<()> {
        if self.root {
            Err(Error::usage("Choose a control path"))
        } else {
            Ok(())
        }
    }
    pub fn focus(&self) -> Result<()> {
        self.control()?;
        native::activate(self.pid)?;
        ax::set(&self.element, "AXFocused", &CFBoolean::true_value())?;
        if !self.has_focus()? {
            return Err(Error::access("The target did not receive keyboard focus"));
        }
        Ok(())
    }
    pub fn set_value(&self, text: &str) -> Result<()> {
        if !self.writable()? {
            return Err(Error::usage("Target is not a writable text control"));
        }
        ax::set(&self.element, "AXValue", &CFString::new(text))
    }
    pub fn selected_text(&self, text: &str) -> Result<()> {
        if !self.writable()? || !self.has_focus()? {
            return Err(Error::access(
                "Selected text target must be writable and focused",
            ));
        }
        native::require_foreground(self.pid)?;
        ax::set(&self.element, "AXSelectedText", &CFString::new(text))
    }
    fn perform(&self, name: &str) -> Result<()> {
        self.control()?;
        if !self.actions()?.iter().any(|action| action == name) {
            return Err(Error::usage(format!("Target does not support {name}")));
        }
        ax::action(&self.element, name)
    }
    pub fn press(&self) -> Result<()> {
        self.perform("AXPress")
    }
    pub fn expand(&self) -> Result<()> {
        self.perform("AXShowMenu")
    }
    pub fn scroll_to(&self) -> Result<()> {
        self.perform("AXScrollToVisible")
    }
}
