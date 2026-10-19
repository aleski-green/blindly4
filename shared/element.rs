use crate::{
    error::{Error, Result},
    guards,
    platform::{self, Node},
};

// These operations depend only on the adapter's element contract, never on
// AX or UIA handles. Both backends run the same resolution and safety checks.
impl Node {
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
    pub fn require_focused_draft(&self, expected: &str) -> Result<()> {
        if self.writable()?
            && self.has_focus()?
            && self.exact_draft(expected)?
            && platform::foreground_pid() == self.pid()
        {
            return Ok(());
        }
        Err(Error::access(
            "Input blocked: writable target, keyboard focus, exact draft and foreground PID must all match. Do not send.",
        ))
    }
    pub fn focus(&self) -> Result<()> {
        self.check_control()?;
        crate::application::activate(self.pid())?;
        self.focus_native()?;
        if !self.has_focus()? {
            return Err(Error::access("The target did not receive keyboard focus"));
        }
        Ok(())
    }
}

pub const ATTRIBUTES: &[&str] = &[
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
];
impl Node {
    pub fn check_control(&self) -> Result<()> {
        if self.is_root() {
            Err(Error::usage("Choose a control path"))
        } else {
            Ok(())
        }
    }
    pub fn text(&self, name: &str) -> Result<String> {
        Ok(self
            .property(name)?
            .and_then(|v| v.as_str().map(str::to_owned))
            .unwrap_or_default())
    }
    pub fn role(&self) -> Result<String> {
        self.text("AXRole")
    }
    pub fn selected(&self) -> Result<bool> {
        Ok(self.property("AXSelected")? == Some(serde_json::json!(true)))
    }
    pub fn value(&self) -> Result<Option<String>> {
        if self.secure()? {
            Ok(None)
        } else {
            Ok(self
                .property("AXValue")?
                .and_then(|v| v.as_str().map(str::to_owned)))
        }
    }
    pub fn writable(&self) -> Result<bool> {
        Ok(!self.is_root()
            && !self.secure()?
            && matches!(
                self.role()?.as_str(),
                "AXTextField" | "AXTextArea" | "AXComboBox"
            )
            && self.property("AXEnabled")? != Some(serde_json::json!(false))
            && self.value_settable()?)
    }
    pub fn has_focus(&self) -> Result<bool> {
        Ok(self.focus_flag()? && self.same(&self.focused()?))
    }
    pub fn set_value(&self, text: &str) -> Result<()> {
        if !self.writable()? {
            return Err(Error::usage(platform::VALUE_ERROR));
        }
        self.set_value_native(text)
    }
    pub fn selected_text(&self, text: &str) -> Result<()> {
        if platform::FOCUS_SELECTION {
            if !self.writable()? {
                return Err(Error::usage("Target is not a writable text control"));
            }
            self.focus()?;
        }
        if !self.writable()? || !self.has_focus()? {
            return Err(Error::access(
                "Selected text target must be writable and focused",
            ));
        }
        crate::application::require_foreground(self.pid())?;
        self.selected_text_native(text)
    }
    pub fn exact_draft(&self, expected: &str) -> Result<bool> {
        if self.secure()? {
            return Ok(false);
        }
        // A readable value is authoritative; descendants cannot override a mismatch.
        if let Some(actual) = self.value()? {
            return Ok(guards::exact(&actual, expected));
        }
        if !platform::DESCENDANT_DRAFT {
            return Ok(false);
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
                    .property(key)?
                    .as_ref()
                    .and_then(serde_json::Value::as_str)
                    .is_some_and(|value| guards::exact(value, expected))
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
    pub fn detail(&self, path: Option<&str>) -> Result<serde_json::Value> {
        use serde_json::{Value, json};
        let values = self.properties()?;
        let secure = ["AXRole", "AXSubrole"]
            .iter()
            .any(|key| values.get(*key).and_then(Value::as_str) == Some("AXSecureTextField"));
        let mut row = json!({"pid": self.pid()});
        for (name, value) in values {
            // Preserve Windows' explicit null and macOS' omitted secure value.
            if !(secure && name == "AXValue" && !value.is_null()) {
                row[name[2..].to_lowercase()] = value;
            }
        }
        if let Some(attributes) = self.attribute_names()? {
            row["attributes"] = json!(attributes);
            row["actions"] = json!(self.actions()?);
        }
        if let Some(path) = path {
            row["path"] = json!(path);
        }
        Ok(row)
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
