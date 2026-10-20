use crate::error::{Error, Result};
use unicode_normalization::UnicodeNormalization;

pub fn normalize(text: &str) -> String {
    text.nfc().filter(|c| !matches!(c, '\u{200e}' | '\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')).collect()
}
pub fn exact(actual: &str, expected: &str) -> bool {
    normalize(actual) == normalize(expected)
}
pub fn path(text: &str) -> Result<Vec<usize>> {
    if text.is_empty() {
        return Ok(vec![]);
    }
    let invalid = || Error::usage("Path must contain nonnegative child indexes separated by dots");
    let parts: Vec<_> = text.split('.').collect();
    if parts.len() > 64 {
        return Err(invalid());
    }
    parts
        .into_iter()
        .map(|p| {
            if p.is_empty() || !p.bytes().all(|b| b.is_ascii_digit()) {
                return Err(invalid());
            }
            let n = p.parse::<i32>().map_err(|_| invalid())?;
            Ok(n as usize)
        })
        .collect()
}
pub fn url(value: &str) -> Result<()> {
    let parsed = url::Url::parse(value).map_err(|_| Error::usage("Only absolute HTTP, HTTPS or Slack URLs are supported"))?;
    if !matches!(parsed.scheme(), "http" | "https" | "slack") || parsed.host_str().is_none_or(str::is_empty) || value.contains('\0') {
        return Err(Error::usage("Only absolute HTTP, HTTPS or Slack URLs are supported"));
    }
    Ok(())
}
