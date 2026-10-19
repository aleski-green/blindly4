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
