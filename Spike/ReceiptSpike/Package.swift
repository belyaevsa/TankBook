// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReceiptSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ReceiptSpike", path: "Sources/ReceiptSpike"),
        .testTarget(
            name: "ReceiptSpikeTests",
            dependencies: ["ReceiptSpike"],
            path: "Tests/ReceiptSpikeTests"
        ),
    ]
)
