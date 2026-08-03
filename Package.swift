// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "blindly4",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "blindly4", targets: ["blindly4"])],
    targets: [.executableTarget(name: "blindly4")]
)
