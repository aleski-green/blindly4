mod ax;
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

pub fn json(value: &Value) -> Result<()> {
    let mut out = io::stdout().lock();
    serde_json::to_writer(&mut out, value)?;
    writeln!(out)?;
    Ok(())
}

fn run(args: &[String]) -> Result<()> {
    if args.is_empty() || ["--help", "-h", "help"].contains(&args[0].as_str()) {
        println!("{}", registry::help());
        return Ok(());
    }
    let command = registry::get(&args[0])?;
    if args
        .get(1)
        .is_some_and(|arg| ["--help", "-h", "help"].contains(&arg.as_str()))
        || args[1..].iter().any(|arg| arg == "--help")
    {
        println!(
            "{}\n{}\nRisk: {}\nRequires Accessibility permission: {}",
            command.metadata()["usage"].as_str().unwrap(),
            command.summary,
            command.risk,
            if command.accessibility { "yes" } else { "no" }
        );
        return Ok(());
    }
    let invocation = invocation::Invocation::new(command, &args[1..])?;
    input::validate(command.name, &invocation)?;
    if command.accessibility {
        ax::require_accessibility()?;
    }
    (command.execute)(&invocation)
}

fn main() {
    objc2::rc::autoreleasepool(|_| {
        let start = Instant::now();
        let mut args: Vec<String> = std::env::args().skip(1).collect();
        let result = if args == ["--test-app"] {
            fixture::run()
        } else if args == ["--test-pasteboard"] {
            clipboard::fixture()
        } else {
            let profile = args.iter().any(|arg| arg == "--profile");
            args.retain(|arg| arg != "--profile");
            std::thread::spawn(|| {
                std::thread::sleep(Duration::from_secs(25));
                let _ = json(
                    &json!({"code": "accessibility_error", "error": "Accessibility command timed out; inspect the target before retrying input."}),
                );
                std::process::exit(77);
            });
            let result = run(&args);
            if profile {
                eprintln!(
                    "profile elapsed_ms={:.1}",
                    start.elapsed().as_secs_f64() * 1000.0
                );
            }
            result
        };
        if let Err(error) = result {
            if error.exit == 64 {
                eprintln!("Error: {}", error.message);
            } else {
                let _ = json(&json!({"code": error.code, "error": error.message}));
            }
            std::process::exit(error.exit);
        }
    });
}
