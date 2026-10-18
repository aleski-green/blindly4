use std::fmt;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug)]
pub struct Error {
    pub message: String,
    pub exit: i32,
    pub code: &'static str,
}

impl Error {
    pub fn usage(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            exit: 64,
            code: "usage_error",
        }
    }
    pub fn access(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            exit: 77,
            code: "accessibility_error",
        }
    }
    pub fn unexpected(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            exit: 1,
            code: "unexpected_error",
        }
    }
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}
impl std::error::Error for Error {}
#[cfg(windows)]
impl From<windows::core::Error> for Error {
    fn from(value: windows::core::Error) -> Self {
        Self::access(value.to_string())
    }
}
impl From<std::io::Error> for Error {
    fn from(value: std::io::Error) -> Self {
        Self::unexpected(value.to_string())
    }
}
impl From<serde_json::Error> for Error {
    fn from(value: serde_json::Error) -> Self {
        Self::unexpected(value.to_string())
    }
}
