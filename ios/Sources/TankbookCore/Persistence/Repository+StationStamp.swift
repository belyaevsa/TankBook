import Foundation

// MARK: - Station stamp (RV.150) - split out so Repository.swift stays under
// the lint ceiling; these are still the Station extension's write surface.

extension TankbookRepository {
    /// One live station by id, or nil when it does not exist (or is tombstoned).
    public func station(id: UUID) throws -> Station? {
        try database.read { db in
            guard let row = try StationRow.fetchOne(db, key: id.uuidString),
                  row.station.deletedAt == nil else { return nil }
            return row.station
        }
    }

    /// RV.150: the save's stamp on the station a fill-up was just confirmed at
    /// (docs/SCHEMA.md -> Station). Writes `lastUsedAt`, the bought
    /// `defaults`, and a missing `location` adopted from the forecourt fix -
    /// fill-blanks-only, never over a coordinate the station already has. The
    /// stamp is applied to the LIVE row (whatever a sync merge or another save
    /// made of it since the sheet loaded), never to a stale view snapshot.
    ///
    /// The RV.136 guard: when the stamp changes nothing about the stored row
    /// (same `lastUsedAt`, same defaults, same location), nothing is written -
    /// no `.dirty`, no push. Returns whether a write happened.
    @discardableResult
    public func stampStation(id: UUID,
                             fuelKind: FuelKind?,
                             fuelGrade: String?,
                             locationFix: GeoCoordinate?,
                             at now: Date = Date()) throws -> Bool {
        guard let live = try station(id: id) else { return false }
        let stamped = StationStamp.applied(to: live, fuelKind: fuelKind,
                                           fuelGrade: fuelGrade,
                                           locationFix: locationFix, at: now)
        let changed = stamped.lastUsedAt != live.lastUsedAt
            || stamped.defaults != live.defaults
            || stamped.location != live.location
        guard changed else { return false }
        var updated = stamped
        updated.updatedAt = now
        try upsertStation(updated, syncState: .dirty)
        return true
    }

    /// Clears a station's captured location (RV.150 property 1: a coordinate
    /// the app captured must be removable where per-station settings live).
    /// Removing it is the user's own choice and a later save at the station
    /// with a fix re-adopts it. Returns whether a write happened (false when
    /// there was no location to clear).
    @discardableResult
    public func clearStationLocation(id: UUID, at now: Date = Date()) throws -> Bool {
        guard var live = try station(id: id), live.location != nil else { return false }
        live.location = nil
        live.updatedAt = now
        try upsertStation(live, syncState: .dirty)
        return true
    }

    /// PJ.55: sets or clears a station's favourite - the user's own statement,
    /// never inferred from use (hard rule 13). `Station.favorite` is what
    /// `StationSuggestion` reads for rung 1, so this is the write that lets a
    /// favourite within 300 m win. It is an ordinary `.dirty` station edit
    /// (record-level LWW, docs/SCHEMA.md -> Station) and reversible: clearing
    /// writes `false` just as setting writes `true`. Returns whether a write
    /// happened (false when the flag already held the requested value).
    @discardableResult
    public func setStationFavorite(id: UUID, _ favorite: Bool,
                                   at now: Date = Date()) throws -> Bool {
        guard var live = try station(id: id), live.favorite != favorite else { return false }
        live.favorite = favorite
        live.updatedAt = now
        try upsertStation(live, syncState: .dirty)
        return true
    }
}
