mod clipboard;
#[path = "../../shared/desktop.rs"]
mod desktop;
#[path = "../../shared/error.rs"]
mod error;
mod fixture;
#[path = "../../shared/guards.rs"]
mod guards;
mod input;
#[path = "../../shared/invocation.rs"]
mod invocation;
mod native;
mod node;
#[path = "../../shared/registry.rs"]
mod registry;

use error::Result;
use serde_json::{Value, json};
use std::{
    io::{self, Write},
    time::{Duration, Instant},
};
use windows::Win32::System::Com::{COINIT_MULTITHREADED, CoInitializeEx, CoUninitialize};

pub fn json(value: &Value) -> Result<()> {
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, value)?;
    writeln!(out)?;
    Ok(())
}
struct ComApartment;
impl ComApartment {
    fn initialize_multithreaded() -> Result<Self> {
        unsafe {
            CoInitializeEx(None, COINIT_MULTITHREADED).ok()?;
        }
        Ok(Self)
    }
}
impl Drop for ComApartment {
    fn drop(&mut self) {
        unsafe { CoUninitialize() }
    }
}

fn run(args: &[String]) -> Result<()> {
    if args.is_empty() || args == ["--help"] || args == ["help"] {
        println!("{}", registry::help());
        return Ok(());
    }
    let command = registry::get(&args[0])?;
    if args[1..] == ["--help"] {
        return json(&command.metadata());
    }
    let invocation = invocation::Invocation::new(command, &args[1..])?;
    let _com_apartment = ComApartment::initialize_multithreaded()?;
    native::dpi_awareness();
    (command.execute)(&invocation)
}
fn main() {
    let start = Instant::now();
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if args == ["--test-app"] {
        if let Err(e) = fixture::run() {
            let _ = json(&json!({"error": e.message, "code": e.code}));
            std::process::exit(e.exit);
        }
        return;
    }
    let profile = args.iter().any(|a| a == "--profile");
    args.retain(|a| a != "--profile");
    std::thread::spawn(|| {
        std::thread::sleep(Duration::from_secs(25));
        let _ = json(
            &json!({"error": "Accessibility command timed out; inspect the target before retrying input.", "code": "accessibility_error"}),
        );
        std::process::exit(77);
    });
    let result = run(&args);
    if profile {
        eprintln!(
            "{}",
            json!({"elapsedMs": start.elapsed().as_millis(), "platform": "windows"})
        );
    }
    if let Err(e) = result {
        let _ = json(&json!({"error": e.message, "code": e.code}));
        std::process::exit(e.exit);
    }
}
