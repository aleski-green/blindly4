mod application;
mod desktop;
mod element;
mod error;
mod guards;
mod input;
mod invocation;
mod keyboard;
#[path = "../adapters/mod.rs"]
mod platform;
mod registry;

use error::{Error, Result};
use serde_json::{Value, json};
use std::{
    io::{self, Write},
    time::{Duration, Instant},
};

pub fn json(value: &Value) -> Result<()> {
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, value)?;
    writeln!(out)?;
    Ok(())
}
fn run(args: &[String]) -> Result<()> {
    if args.is_empty() || platform::help_requested(args, true) {
        println!("{}", registry::help());
        return Ok(());
    }
    let command = registry::get(&args[0])?;
    if platform::help_requested(&args[1..], false) {
        return platform::command_help(command);
    }
    let invocation = invocation::Invocation::new(command, &args[1..])?;
    let _session = platform::prepare(command, &invocation)?;
    (command.execute)(&invocation)
}
fn main() {
    let result = platform::with_runtime(|| {
        let start = Instant::now();
        let mut args: Vec<String> = std::env::args().skip(1).collect();
        if let Some(result) = platform::fixture(&args) {
            return result;
        }
        let profile = args.iter().any(|arg| arg == "--profile");
        args.retain(|arg| arg != "--profile");
        std::thread::spawn(|| {
            std::thread::sleep(Duration::from_secs(25));
            report(&Error::access(
                "Accessibility command timed out; inspect the target before retrying input.",
            ));
            std::process::exit(77);
        });
        let result = run(&args);
        if profile {
            eprintln!("{}", platform::profile(start.elapsed()));
        }
        result
    });
    if let Err(error) = result {
        report(&error);
        std::process::exit(error.exit);
    }
}
fn report(error: &Error) {
    if error.exit == 64 && platform::USAGE_ON_STDERR {
        eprintln!("Error: {}", error.message);
    } else {
        let _ = json(&json!({"code": error.code, "error": error.message}));
    }
}
