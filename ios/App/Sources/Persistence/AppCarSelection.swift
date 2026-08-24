import Foundation
import Observation
import TankbookCore

/// The single source of truth for which car is on screen (P1.11). Home, Trends,
/// the manual form and Edit entry all resolve the vehicle through this object,
/// so they can never disagree about the selected car; the switcher writes
/// through it too. The durable value IS `Preferences.defaultVehicleId` (a
/// synced record with a fixed id, docs/SCHEMA.md); this object mirrors it for
/// observation so screens reload the moment a switch happens instead of waiting
/// for a re-appear (sheets don't re-trigger the presenting view's `task`).
@MainActor
@Observable
final class AppCarSelection {
    private(set) var selectedID: UUID?
    private var didLoad = false

    /// Resolves the vehicle a screen should show, loading the persisted
    /// selection once on first use. Every entry-creating and stats-reading
    /// screen calls this - the app-layer half of the capture-logs-to-the-
    /// selected-car invariant.
    func selectedVehicle(_ vehicles: [Vehicle]) -> Vehicle? {
        if !didLoad { reload() }
        return VehicleSelection.resolve(vehicles, defaultID: selectedID)
    }

    /// The switcher's write: persist the choice, then mirror it for observers.
    func select(_ vehicle: Vehicle) throws {
        let repository = try AppStore.repository()
        try repository.selectVehicle(vehicle.id)
        selectedID = vehicle.id
    }

    func reload() {
        didLoad = true
        guard let repository = try? AppStore.repository() else { return }
        selectedID = try? repository.selectedVehicleID()
    }
}
