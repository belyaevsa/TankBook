import CryptoKit
import Foundation

// An imported file's free-text station column (Drivvo's `Азс` / `Gas station`,
// docs/SCHEMA.md -> Import mapping) becomes a real `Station` record so the Log
// row can title itself with the name (docs/DESIGN.md -> "Entry card content",
// RV.142). The resolution is decided once, here, and is PURE: the classifier
// runs without a repository (docs/TESTING.md, L1), so the fill carries the
// station id it will have AFTER the commit, and the commit simply materialises
// the missing Station rows.

/// Resolves an imported station name to a `Station`. Decision: match an
/// existing station whose name is exactly the trimmed file value, else create a
/// new record. Brand normalisation (Газпром / Газпромнефть / ...) is [RV.115]'s
/// reference-data list; this matcher deliberately does not fork it - two
/// spellings are two stations until the brand list exists.
public enum ImportStationResolver {

    /// The `Station` an imported name maps to. `existing` is the destination
    /// device's live stations, so a name the user already uses (typed or a
    /// previous import) keeps ITS record - its `favorite`, `defaults` and
    /// `lastUsedAt` are never clobbered. An unmatched name gets a NEW record
    /// whose id is deterministic in the name.
    ///
    /// Determinism is what keeps the flow honest: the pure classifier mints the
    /// id at conversion time (before any write - F6a), and the commit re-creates
    /// the same id from the same name, so a rebuild after a review edit cannot
    /// drift, and two devices parsing the same file resolve to the same station.
    public static func station(for name: String, existing: [Station],
                               now: Date = Date()) -> Station {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = existing.first(where: { $0.name == trimmed }) {
            return match
        }
        return Station(
            id: stableID(for: trimmed), createdAt: now, updatedAt: now,
            deletedAt: nil, name: trimmed, brand: nil, location: nil,
            favorite: false, defaults: Station.Defaults(fuelKind: nil, fuelGrade: nil),
            lastUsedAt: now)
    }

    /// The station rows an import commit must create: one per unmatched derived
    /// id that a KEPT fill references, keyed by the parse's name map. Rows the
    /// user skipped never mint a station, and a matched existing station is
    /// already in the repository.
    ///
    /// `keptStationIDs` is read from the fills the commit writes; `nameByID` is
    /// derived from the parse's candidates (id is a deterministic function of
    /// name, so the two sides cannot drift). Built as `ArchiveImportRecord
    /// .station` entries and appended to the commit, so the creation rides the
    /// import's single transaction.
    public static func missingStations(keptStationIDs: Set<UUID>,
                                       nameByID: [UUID: String],
                                       existing: [Station],
                                       now: Date = Date()) -> [Station] {
        let existingIDs = Set(existing.map(\.id))
        var ordered: [Station] = []
        var seen = Set<UUID>()
        for (id, name) in nameByID.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            guard keptStationIDs.contains(id), !existingIDs.contains(id),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append(station(for: name, existing: existing, now: now))
        }
        return ordered
    }

    /// The id an unmatched imported name maps to: a UUIDv5-style digest of the
    /// name under a fixed namespace, so the same name always yields the same id
    /// without any shared state.
    static func stableID(for name: String) -> UUID {
        let digest = SHA256.hash(data: Data(("import.station\0" + name).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = bytes.withUnsafeBytes { raw in
            raw.bindMemory(to: uuid_t.self).baseAddress!.pointee
        }
        return UUID(uuid: uuid)
    }
}

extension ImportCandidate {
    /// The candidate's station name trimmed of the surrounding whitespace the
    /// CSV may carry, or nil when the file has no station for the row.
    public var trimmedStation: String? {
        guard let station, !station.isEmpty else { return nil }
        let trimmed = station.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
