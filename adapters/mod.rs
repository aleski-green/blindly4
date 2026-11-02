// Select one native adapter; the shared engine contains no OS branches.
#[cfg(target_os = "macos")]
#[path = "../macos/src/adapter.rs"]
mod selected;
#[cfg(target_os = "linux")]
#[path = "../linux/src/adapter.rs"]
mod selected;
#[cfg(windows)]
#[path = "../windows/src/adapter.rs"]
mod selected;

pub use selected::*;
