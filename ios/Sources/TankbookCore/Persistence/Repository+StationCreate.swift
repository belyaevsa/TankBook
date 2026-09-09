import Foundation

// MARK: - Station creation (RV.156) - the typed door into the station set

// Split out so Repository.swift stays under the lint ceiling; this is still the
// Station extension's write surface. The minting rule is deliberately NOT
// copied here - creation routes through `ImportStationResolver.station(for:)`,
// the one deterministic name-to-Station rule the import path already uses, so
// two devices that type the same name mint the same id and converge instead of
// duplicating (docs/JOURNEYS.md -> J4, docs/SCHEMA.md -> Station).

extension TankbookRepository {
    /// RV.156: creates - or resolves - the `Station` a user named on the entry
    /// row or in the Garage's Stations list. An exact name match on a live
    /// station returns that station UNCHANGED (its `favorite`, `defaults` and
    /// `lastUsedAt` stay theirs) and writes nothing; an unmatched non-empty
    /// name mints a new record through the shared deterministic helper and
    /// writes it `.dirty` - an ordinary synced station edit (record-level LWW,
    /// docs/SCHEMA.md -> Station).
    ///
    /// Resolution runs against the LIVE stations, never a caller-held list, so
    /// a name another device synced in after this screen loaded still matches
    /// instead of minting a second id. The caller selects the returned station;
    /// it must not look like a second row was created when the name matched.
    ///
    /// Returns nil for a blank name: a station's row and its Log title live on
    /// the name, so an unnamed station is not creatable (the UI treats a blank
    /// submission as a cancel).
    @discardableResult
    public func createStation(named name: String,
                              at now: Date = Date()) throws -> Station? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = try liveStations()
        let resolved = ImportStationResolver.station(for: trimmed,
                                                     existing: existing, now: now)
        guard !existing.contains(where: { $0.id == resolved.id }) else {
            return resolved
        }
        try upsertStation(resolved, syncState: .dirty)
        return resolved
    }
}
