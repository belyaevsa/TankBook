import Foundation

/// The pure merge decision (docs/SYNC.md -> "Client state & merge", S1-S9).
///
/// Record-level last-writer-wins by `clientUpdatedAt` for every entity type
/// except `Vehicle`, which merges field-by-field so a stale device cannot revert
/// a setting the user deliberately changed (S9, hard rule 13). Pure value types
/// only - no network, no database - so every scenario is deterministic and
/// testable without `URLSession` (docs/TESTING.md L3).
public enum RecordMerge {

    /// Which side the kept record came from.
    public enum Winner: Equatable, Sendable {
        case local
        case remote
        /// `Vehicle` field-level merge: fields came from both sides.
        case fieldMerge
    }

    /// The merge outcome: the record to keep, who won, and the losing version
    /// (for the local undo log, S1/S4). A field merge has no loser - nothing was
    /// lost (docs/SYNC.md S9).
    public struct Result: Equatable, Sendable {
        public let keep: SyncRecord
        public let winner: Winner
        public let loser: SyncRecord?

        public init(keep: SyncRecord, winner: Winner, loser: SyncRecord?) {
            self.keep = keep
            self.winner = winner
            self.loser = loser
        }
    }

    /// Merges two records for the same id/entityType. Deterministic, non-throwing:
    /// a `Vehicle` payload that cannot be decoded falls back to record-level LWW.
    public static func merge(local: SyncRecord, remote: SyncRecord) -> Result {
        if local.entityType == Vehicle.entityType, remote.entityType == Vehicle.entityType {
            return mergeVehicle(local: local, remote: remote)
        }
        return mergeRecord(local: local, remote: remote)
    }

    // MARK: - Record-level LWW (every entity except Vehicle)

    private static func mergeRecord(local: SyncRecord, remote: SyncRecord) -> Result {
        switch compare(local.clientUpdatedAt, remote.clientUpdatedAt, local.id, remote.id) {
        case .localWins:
            return Result(keep: local, winner: .local, loser: remote)
        case .remoteWins:
            return Result(keep: remote, winner: .remote, loser: local)
        }
    }

    // MARK: - Vehicle field-level merge

    private static func mergeVehicle(local: SyncRecord, remote: SyncRecord) -> Result {
        // Deletion is a whole-record decision (docs/SYNC.md S4/S5): a tombstone
        // against a live record resolves by LWW, not per-field.
        if local.deleted || remote.deleted {
            return mergeRecord(local: local, remote: remote)
        }
        guard let localVehicle = try? decodeVehicle(local),
              let remoteVehicle = try? decodeVehicle(remote) else {
            return mergeRecord(local: local, remote: remote)
        }

        // Non-mergeable fields follow whole-record LWW.
        let localWinsOverall = compare(local.clientUpdatedAt, remote.clientUpdatedAt,
                                       local.id, remote.id) == .localWins
        var merged = localWinsOverall ? localVehicle : remoteVehicle

        // Mergeable fields: newest per-field write wins.
        let localVersions = local.fieldVersions ?? [:]
        let remoteVersions = remote.fieldVersions ?? [:]
        var mergedVersions: [String: Date] = [:]
        for field in VehicleMergeFields.all {
            let localTime = localVersions[field] ?? local.clientUpdatedAt
            let remoteTime = remoteVersions[field] ?? remote.clientUpdatedAt
            let takeLocal = localTime > remoteTime
            applyVehicleField(field, from: takeLocal ? localVehicle : remoteVehicle, to: &merged)
            mergedVersions[field] = max(localTime, remoteTime)
        }

        // The envelope fields: id is shared; createdAt is the earlier stamp;
        // updatedAt is the later stamp (the merged record was last modified at
        // the newest of the two writes).
        if merged.createdAt > min(localVehicle.createdAt, remoteVehicle.createdAt) {
            merged.createdAt = min(localVehicle.createdAt, remoteVehicle.createdAt)
        }
        merged.updatedAt = max(local.clientUpdatedAt, remote.clientUpdatedAt)

        // RV.14: a field merge is only worth reporting when it produced
        // something new. Compare at the level the merge itself works at - the
        // decoded `Vehicle` plus the per-field versions - never the raw payload
        // bytes, which do not converge across a lossy re-encode (JSON key
        // ordering, decimal formatting, a field the server normalises) and
        // would swap one infinite push loop for a subtler one.
        if merged == remoteVehicle,
           mergedVersions == effectiveVersions(remoteVersions, fallback: remote.clientUpdatedAt) {
            // Nothing local to push: the merged result is exactly the remote.
            return Result(keep: remote, winner: .remote, loser: local)
        }
        if merged == localVehicle,
           mergedVersions == effectiveVersions(localVersions, fallback: local.clientUpdatedAt) {
            // Already correct here: the merged result is exactly the local.
            return Result(keep: local, winner: .local, loser: remote)
        }

        let domainPayload = (try? PayloadCodec.encode(merged).payload) ?? remote.payload
        let payload = VehicleFieldVersions.write(into: domainPayload, versions: mergedVersions)
        let keep = SyncRecord(
            id: local.id,
            entityType: Vehicle.entityType,
            schemaVersion: local.schemaVersion,
            payload: payload,
            clientUpdatedAt: merged.updatedAt,
            deleted: false,
            fieldVersions: mergedVersions
        )
        return Result(keep: keep, winner: .fieldMerge, loser: nil)
    }

    private static func decodeVehicle(_ record: SyncRecord) throws -> Vehicle {
        try decodedEntity(record, as: Vehicle.self)
    }

    // MARK: - Record-level equivalence (RV.35)

    /// True when two records for the same non-`Vehicle` entity type decode to
    /// equal entities. Record-level LWW keeps a whole record, so "nothing
    /// changed" is judged at the decoded level - never the raw payload bytes,
    /// which do not converge across a lossy round-trip (a normalised number
    /// token `1.0` vs `1`, a decimal string with a dropped trailing zero
    /// `289.50` vs `289.5`, a date re-serialised without fractional seconds).
    /// Re-dirtying on those bytes is the echo loop RV.35 fixes. When either side
    /// cannot be decoded the comparison falls back to payload bytes, so a
    /// genuinely unreadable divergence is still treated as a difference (the
    /// same fallback the field merge uses) - hard rule 8, nothing lost silently.
    static func recordsEqual(_ local: SyncRecord, _ remote: SyncRecord) -> Bool {
        switch local.entityType {
        case FillUp.entityType: return equivalent(local, remote, FillUp.self)
        case ChargeSession.entityType: return equivalent(local, remote, ChargeSession.self)
        case ServiceRecord.entityType: return equivalent(local, remote, ServiceRecord.self)
        case Expense.entityType: return equivalent(local, remote, Expense.self)
        case Reminder.entityType: return equivalent(local, remote, Reminder.self)
        case Station.entityType: return equivalent(local, remote, Station.self)
        case Tariff.entityType: return equivalent(local, remote, Tariff.self)
        case TireSet.entityType: return equivalent(local, remote, TireSet.self)
        case Attachment.entityType: return equivalent(local, remote, Attachment.self)
        case Preferences.entityType: return equivalent(local, remote, Preferences.self)
        default:
            // An entity type this build does not understand has no typed decode
            // to reason at; the record is opaque, so bytes are the honest
            // comparison.
            return local.payload == remote.payload
        }
    }

    private static func equivalent<E: SyncedEntity & Equatable>(
        _ local: SyncRecord, _ remote: SyncRecord, _ type: E.Type
    ) -> Bool {
        guard let lhs = try? decodedEntity(local, as: type),
              let rhs = try? decodedEntity(remote, as: type) else {
            return local.payload == remote.payload
        }
        return lhs == rhs
    }

    private static func decodedEntity<E: SyncedEntity>(_ record: SyncRecord, as type: E.Type) throws -> E {
        try PayloadCodec.decode(
            PayloadEnvelope(entityType: record.entityType,
                            schemaVersion: record.schemaVersion,
                            payload: record.payload),
            as: E.self
        ).entity
    }

    /// The per-field versions the merge would fall back to for a record: each
    /// mergeable field carries its explicit version, or the record's whole
    /// `clientUpdatedAt` when none is present (the same degradation the merge
    /// loop itself applies). Used by the RV.14 "did the merge change anything"
    /// comparison, mirroring the merge's own semantics so the comparison and
    /// the merge can never disagree about what "new" means.
    private static func effectiveVersions(_ versions: [String: Date], fallback: Date) -> [String: Date] {
        var result: [String: Date] = [:]
        for field in VehicleMergeFields.all {
            result[field] = versions[field] ?? fallback
        }
        return result
    }

    private static func applyVehicleField(_ field: String, from source: Vehicle, to target: inout Vehicle) {
        switch field {
        case "name": target.name = source.name
        case "tankCapacityL": target.tankCapacityL = source.tankCapacityL
        case "initialOdometer": target.initialOdometer = source.initialOdometer
        case "homeCurrency": target.homeCurrency = source.homeCurrency
        case "units": target.units = source.units
        case "paceLimitKmPerDay": target.paceLimitKmPerDay = source.paceLimitKmPerDay
        case "archived": target.archived = source.archived
        default: break
        }
    }

    // MARK: - Comparison

    private enum Comparison {
        case localWins
        case remoteWins
    }

    /// Newer `clientUpdatedAt` wins; on an exact tie the lexicographically
    /// smaller id wins (docs/SYNC.md: deterministic tiebreak - the record id
    /// stands in for the origin device id, which the wire record does not carry).
    private static func compare(_ local: Date, _ remote: Date, _ localId: UUID, _ remoteId: UUID) -> Comparison {
        if local > remote { return .localWins }
        if remote > local { return .remoteWins }
        return localId.uuidString < remoteId.uuidString ? .localWins : .remoteWins
    }
}
