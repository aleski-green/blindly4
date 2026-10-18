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
    let parsed = url::Url::parse(value)
        .map_err(|_| Error::usage("Only absolute HTTP, HTTPS or Slack URLs are supported"))?;
    if !matches!(parsed.scheme(), "http" | "https" | "slack")
        || parsed.host_str().is_none_or(str::is_empty)
        || value.contains('\0')
    {
        return Err(Error::usage(
            "Only absolute HTTP, HTTPS or Slack URLs are supported",
        ));
    }
    Ok(())
}
#[cfg(windows)]
pub fn parse_key(text: &str) -> Result<Vec<u16>> {
    let lower = text.to_lowercase();
    let parts: Vec<_> = lower.split('+').collect();
    let mut keys = Vec::new();
    for modifier in &parts[..parts.len() - 1] {
        keys.push(match *modifier {
            "ctrl" | "control" | "command" | "cmd" => 0x11,
            "shift" => 0x10,
            "alt" | "option" => 0x12,
            _ => return Err(Error::usage(format!("Unsupported modifier: {modifier}"))),
        });
    }
    let key = parts[parts.len() - 1];
    let value = match key {
        "return" | "enter" => 0x0d,
        "tab" => 9,
        "escape" | "esc" => 0x1b,
        "space" => 0x20,
        "delete" | "backspace" => 8,
        "forward-delete" => 0x2e,
        "up" => 0x26,
        "down" => 0x28,
        "left" => 0x25,
        "right" => 0x27,
        "home" => 0x24,
        "end" => 0x23,
        "pageup" => 0x21,
        "pagedown" => 0x22,
        _ if key.len() == 1 && key.as_bytes()[0].is_ascii_alphanumeric() => {
            key.as_bytes()[0].to_ascii_uppercase() as u16
        }
        _ => match key
            .strip_prefix('f')
            .and_then(|s| s.parse::<u16>().ok())
            .filter(|f| (1..=24).contains(f))
        {
            Some(f) => 0x70 + f - 1,
            None => return Err(Error::usage(format!("Unsupported key: {key}"))),
        },
    };
    keys.push(value);
    Ok(keys)
}
