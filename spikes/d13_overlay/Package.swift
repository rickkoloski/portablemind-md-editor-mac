// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "D13CellEditOverlaySpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "D13Spike",
            path: "Sources/D13Spike"
        )
    ]
)
