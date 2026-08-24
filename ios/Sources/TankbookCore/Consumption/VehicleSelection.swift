import Foundation

/// The selected-car invariant (P1.11, design/screens/CarSwitcher.dc.html
/// footer): "Capture always logs to the selected car." Every entry-creating
/// path and every stats-reading screen resolves the vehicle through here, so
/// they can never disagree about which car is on screen - the bug class where
/// an entry is filed against the wrong car and nobody notices until
/// consumption looks wrong months later.
public enum VehicleSelection {
    /// Resolves the selected vehicle from the live vehicles and the persisted
    /// preference (`Preferences.defaultVehicleId`, docs/SCHEMA.md).
    ///
    /// - The persisted selection wins when it is live and not archived.
    /// - An archived (or gone) selection falls back to the first live car:
    ///   archived cars are out of active stats and must not appear as the
    ///   selected car by default (J13).
    /// - The very first non-archived vehicle is the selection when nothing is
    ///   persisted yet (the pre-switcher behaviour, so nothing regresses).
    /// - Only when EVERY vehicle is archived does an archived car win, so Home
    ///   still has something honest to show.
    public static func resolve(_ vehicles: [Vehicle], defaultID: UUID?) -> Vehicle? {
        if let defaultID,
           let match = vehicles.first(where: { $0.id == defaultID && !$0.archived }) {
            return match
        }
        return vehicles.first(where: { !$0.archived }) ?? vehicles.first
    }
}

/// The free-tier car limit - the ONE monetization surface in the app
/// (docs/ERRORS.md -> Car switcher / Garage). Hard rule 5: monetization appears
/// nowhere else, and never mid-capture. The cap is a constant so the rule is
/// testable without a real entitlement system (Pro is P6).
public enum CarLimit {
    /// "Free keeps up to 3 cars." (docs/ERRORS.md, verbatim).
    public static let freeTierLimit = 3

    /// Whether adding a car is allowed. `activeCount` counts live, non-archived
    /// vehicles - an archived car frees a slot ("Archive one, or go Pro").
    /// Hitting the cap only refuses ADDS; existing cars are never locked
    /// (the anti-CarScope rule, docs/COMPETITORS.md).
    public static func canAddCar(activeCount: Int, pro: Bool = false) -> Bool {
        pro || activeCount < freeTierLimit
    }
}
