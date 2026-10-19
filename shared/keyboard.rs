use crate::{
    error::{Error, Result},
    platform,
};

// Parse the public key grammar once; adapters supply native codes and modifiers.
pub fn parse(text: &str) -> Result<platform::Key> {
    let lower = text.to_lowercase();
    let mut parts = lower.rsplit('+');
    let key = parts.next().unwrap();
    let canonical = match key {
        "return" => "enter",
        "esc" => "escape",
        "delete" => "backspace",
        other => other,
    };
    let mut modifiers = Vec::new();
    for modifier in parts.rev() {
        let index = match modifier {
            "command" | "cmd" => 0,
            "control" | "ctrl" => 1,
            "option" | "alt" => 2,
            "shift" => 3,
            _ => return Err(Error::usage(format!("Unsupported modifier: {modifier}"))),
        };
        modifiers.push(index);
    }
    let code = platform::key_code(canonical)
        .ok_or_else(|| Error::usage(format!("Unsupported key: {key}")))?;
    Ok(platform::Key::new(code, &modifiers))
}
