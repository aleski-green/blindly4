use crate::{
    error::{Error, Result},
    platform,
};

// Fixture entry points and opt-in policy are identical for both native backends.
pub fn run(args: &[String]) -> Option<Result<()>> {
    let (start, message): (fn() -> Result<()>, _) = match args {
        [arg] if arg == "--test-app" => (platform::desktop_fixture, "The desktop fixture requires BLINDLY4_LIVE=1"),
        [arg] if arg == "--test-pasteboard" => (platform::clipboard_fixture, "Clipboard fixture requires BLINDLY4_LIVE=1"),
        _ => return None,
    };
    Some(if std::env::var("BLINDLY4_LIVE").as_deref() == Ok("1") { start() } else { Err(Error::usage(message)) })
}
