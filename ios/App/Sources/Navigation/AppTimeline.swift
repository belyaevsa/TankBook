import Foundation
import TankbookCore

/// The launch pass's timeline step: stored conflict flags are written on save
/// for the saved entry only, and CHECK 2's learned limit moves as entries
/// arrive, so every foreground pass re-derives every live car's flags
/// (`revalidateTimeline` writes only the rows whose flag changed).
@MainActor
enum AppTimeline {
    /// Re-derives the flags and calls `onChange` when the number of flagged
    /// entries moved, so Home reloads silently.
    static func revalidateAll(_ onChange: () -> Void) {
        #if DEBUG
        // A seeded launch (UI tests, screenshots) writes the flags it shows;
        // re-deriving them would erase the state the launch exists to show.
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-seed") }) { return }
        #endif
        guard let repository = try? AppStore.repository(),
              let vehicles = try? repository.liveVehicles() else { return }
        let before = try? repository.flaggedEntryCount()
        do {
            try repository.revalidateTimeline(vehicleIds: Set(vehicles.map(\.id)), log: AppLog.shared)
        } catch {
            AppLog.error(operation: "timeline.revalidate", category: .persistence, error: error)
            return
        }
        if (try? repository.flaggedEntryCount()) != before {
            onChange()
        }
    }
}
