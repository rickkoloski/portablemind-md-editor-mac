// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "D16Spike",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "D16Spike", targets: ["D16Spike"])
    ],
    targets: [
        .executableTarget(
            name: "D16Spike",
            path: "Sources/D16Spike")
    ]
)
