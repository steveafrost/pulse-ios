// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThirdHandCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ThirdHandCore", targets: ["ThirdHandCore"])
    ],
    targets: [
        .target(name: "ThirdHandCore"),
        .testTarget(name: "ThirdHandCoreTests", dependencies: ["ThirdHandCore"])
    ]
)
