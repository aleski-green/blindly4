// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "blindy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "blindy", targets: ["axvo"])],
    targets: [
        .executableTarget(name: "axvo"),
        .testTarget(name: "axvoTests", dependencies: ["axvo"])
    ]
)
