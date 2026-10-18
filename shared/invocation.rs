use crate::{
    error::{Error, Result},
    native,
    registry::Command,
};
use std::collections::BTreeMap;

pub struct Invocation {
    values: BTreeMap<String, String>,
}
impl Invocation {
    pub fn new(command: &Command, args: &[String]) -> Result<Self> {
        let mut values = BTreeMap::new();
        let options = command.options();
        let mut args = args.iter();
        while let Some(arg) = args.next() {
            let key = arg
                .strip_prefix("--")
                .filter(|k| options.contains(k))
                .ok_or_else(|| {
                    Error::usage(format!("Unknown option for {}: {arg}", command.name))
                })?;
            if values.contains_key(key) {
                return Err(Error::usage(format!("Duplicate option --{key}")));
            }
            let value = if key == "require-selected" {
                "true".to_owned()
            } else {
                args.next()
                    .filter(|v| !v.starts_with("--"))
                    .ok_or_else(|| Error::usage(format!("Missing value for --{key}")))?
                    .clone()
            };
            values.insert(key.to_owned(), value);
        }
        Ok(Self { values })
    }
    pub fn optional(&self, name: &str) -> Option<&str> {
        self.values.get(name).map(String::as_str)
    }
    pub fn value(&self, name: &str) -> Result<&str> {
        self.optional(name)
            .ok_or_else(|| Error::usage(format!("Missing --{name}")))
    }
    pub fn has(&self, name: &str) -> bool {
        self.values.contains_key(name)
    }
    pub fn integer(&self, name: &str, fallback: i32, min: i32, max: i32) -> Result<i32> {
        let Some(raw) = self.optional(name) else {
            return Ok(fallback);
        };
        raw.trim()
            .parse::<i32>()
            .ok()
            .filter(|n| *n >= min && *n <= max)
            .ok_or_else(|| Error::usage(format!("--{name} must be an integer from {min} to {max}")))
    }
    pub fn number(&self, name: &str) -> Result<f64> {
        self.value(name)?
            .trim()
            .parse::<f64>()
            .ok()
            .filter(|n| n.is_finite())
            .ok_or_else(|| Error::usage(format!("--{name} must be finite and numeric")))
    }
    pub fn pid(&self) -> Result<i32> {
        self.integer("pid", native::foreground_pid(), 1, i32::MAX)
    }
    pub fn pair(&self, a: &str, b: &str, require_pid: bool) -> Result<()> {
        if self.has(a) != self.has(b) || (self.has(a) && require_pid && !self.has("pid")) {
            return Err(Error::usage(format!(
                "--{a} and --{b} must be supplied together{}",
                if require_pid { " with --pid" } else { "" }
            )));
        }
        Ok(())
    }
}
