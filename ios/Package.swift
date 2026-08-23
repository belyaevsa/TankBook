// swift-tools-version: 6.0
// TankbookCore: all pure logic and persistence for the Tankbook iOS app.
// The SwiftUI app target (P1.1) and widgets/extensions depend on this package.
// macOS is a supported platform so `swift test` runs in CI without a simulator.

import PackageDescription

let package = Package(
    name: "TankbookCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TankbookCore", targets: ["TankbookCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TankbookCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "TankbookCoreTests",
            dependencies: ["TankbookCore"]
        ),
    ]
)
