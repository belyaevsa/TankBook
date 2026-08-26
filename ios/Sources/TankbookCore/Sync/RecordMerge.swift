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
        let envelope = PayloadEnvelope(entityType: record.entityType,
                                       schemaVersion: record.schemaVersion,
                                       payload: record.payload)
        return try PayloadCodec.decode(envelope, as: Vehicle.self).entity
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
