// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "D12CellCaretSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "D12Spike",
            path: "Sources/D12Spike"
        )
    ]
)
