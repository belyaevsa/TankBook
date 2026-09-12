import Foundation
import TankbookCore

/// RV.260 launch hook: builds the UI-test/screenshot backup archive when
/// `-seedRestoreBackup` is present. A no-op in Release - the real seed lives
/// behind `#if DEBUG` below.
@MainActor
enum RestoreBackupLaunchHook {
    static func runIfRequested() {
        #if DEBUG
        RestoreBackupTestSeed.seedIfRequested()
        #endif
    }
}

#if DEBUG
/// RV.260 UI-test/screenshot seed: builds a REAL per-car backup archive through
/// the app's own `ExportBuilder`, then removes the seeded car so the archive is
/// the only source of the data the restore door reads. The UI test taps the row
/// and asserts the car and its entries reappear - the archive comes from the
/// production export path, never hand-made in the test.
@MainActor
enum RestoreBackupTestSeed {
    /// The archive directory built this launch, if `-seedRestoreBackup` asked.
    static var archiveURL: URL?

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedRestoreBackup") else { return }
        guard let repository = try? AppStore.repository() else { return }

        let vehicle = HomeTestSeed.makeVehicle()
        try? repository.upsertVehicle(vehicle)
        try? repository.upsertFillUp(HomeTestSeed.makeFill(
            vehicleID: vehicle.id,
            HomeTestSeed.FillSpec(daysAgo: 3, odometer: 118_420, litres: 42.3,
                                  amount: "71.02", price: "1.679", stationID: nil)))

        guard let shareable = try? ExportBuilder.buildCarExport(vehicleID: vehicle.id),
              let directory = shareable.items.compactMap({ $0 as? URL }).last else { return }
        // Remove the seeded car so the restore is what puts it back on Home;
        // otherwise the assertion would pass on data that never left.
        try? repository.hardDeleteVehicle(id: vehicle.id)
        archiveURL = directory
    }
}
#endif
