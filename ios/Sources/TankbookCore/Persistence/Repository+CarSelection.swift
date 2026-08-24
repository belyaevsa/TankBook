import Foundation

// The selected-car store (P1.11), kept in its own file so Repository.swift
// stays under the linter's file-length limit. The selected vehicle is
// `Preferences.defaultVehicleId` - a synced record with a fixed id
// (docs/SCHEMA.md) - so the switcher's write is durable and survives a
// relaunch, and every screen reads the same value.

extension TankbookRepository {
    /// Persists the selected vehicle - the switcher's write and the ONLY place
    /// the selection is stored. `nil` clears it, which makes
    /// `VehicleSelection.resolve` fall back to the first live car.
    public func selectVehicle(_ id: UUID?) throws {
        let now = Date()
        var preferences = (try? livePreferences()) ?? Preferences(createdAt: now, updatedAt: now)
        preferences.defaultVehicleId = id
        preferences.updatedAt = now
        try upsertPreferences(preferences)
    }

    /// The persisted selection (`Preferences.defaultVehicleId`), the durable
    /// half of the capture-logs-to-the-selected-car invariant: a switch
    /// survives a relaunch because the write landed here, not in memory.
    public func selectedVehicleID() throws -> UUID? {
        try livePreferences()?.defaultVehicleId
    }
}
