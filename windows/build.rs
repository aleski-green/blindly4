fn main() {
    println!("cargo:rerun-if-changed=app.manifest");
    if std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc") {
        let manifest = std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap())
            .join("app.manifest");
        println!("cargo:rustc-link-arg-bin=blindly4=/MANIFEST:EMBED");
        println!(
            "cargo:rustc-link-arg-bin=blindly4=/MANIFESTINPUT:{}",
            manifest.display()
        );
    }
}
