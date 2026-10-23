// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"])
    ],
    targets: [
        .target(name: "PulseCore"),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"])
    ]
)
