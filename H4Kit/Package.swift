// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "H4Kit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "H4Kit", targets: ["H4Kit"]),
        .executable(name: "h4tool", targets: ["h4tool"]),
    ],
    targets: [
        .target(name: "H4Kit"),
        .executableTarget(name: "h4tool", dependencies: ["H4Kit"]),
        .testTarget(name: "H4KitTests", dependencies: ["H4Kit"]),
    ]
)
