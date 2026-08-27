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
        // P0.3: the pseudo-localization gate. Runs in CI as a build-failing
        // step and is exercised by LocalizationGateTests.
        .executable(name: "localization-gate", targets: ["LocalizationGateTool"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TankbookCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                // Bundled config defaults (docs/CONFIG.md -> layer 1). The
                // bundled layer is not signed and is never signature-checked:
                // it is compiled into the binary, which is the root of trust.
                .copy("Config/Config.default.json"),
                // Bundled vehicle catalog seed pack (docs/SCHEMA.md -> Vehicle
                // catalog): Add-car autocomplete works offline on day one.
                .copy("Catalog/VehicleCatalog.seed.json"),
                // Bundled exchange-rate seed pack (docs/SCHEMA.md -> Exchange
                // rates): a first launch offline still converts common pairs.
                .copy("Rates/Rates.seed.json"),
                // Bundled payload JSON Schemas (docs/SCHEMA.md -> Payload
                // schemas). The per-car archive reader validates every payload
                // against the registered contract before it imports anything;
                // the schemas travel with the app so that check works offline.
                .copy("Schemas")
            ]
        ),
        .target(
            name: "LocalizationGate"
        ),
        .executableTarget(
            name: "LocalizationGateTool",
            dependencies: ["LocalizationGate"]
        ),
        .testTarget(
            name: "TankbookCoreTests",
            dependencies: ["TankbookCore"],
            // Fixtures are read from disk via #filePath, matching the existing
            // docs/fixtures convention, so they are not bundled resources.
            exclude: ["Fixtures"]
        ),
        .testTarget(
            name: "LocalizationGateTests",
            dependencies: ["LocalizationGate"]
        ),
    ]
)
