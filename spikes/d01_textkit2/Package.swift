// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TextKit2LiveRenderSpike",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "TextKit2LiveRenderSpike",
            targets: ["TextKit2LiveRenderSpike"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.3.0")
    ],
    targets: [
        .executableTarget(
            name: "TextKit2LiveRenderSpike",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/TextKit2LiveRenderSpike"
        )
    ]
)
