import Foundation

/// A record as it moves through the sync pipeline (docs/SYNC.md). The transport
/// layer and the pure merge (`RecordMerge`) both work in this shape; it is a plain
/// value type so every scenario is deterministic and testable without
/// `URLSession` (docs/TESTING.md L3).
///
/// `fieldVersions` carries the per-field last-write timestamps that make
/// `Vehicle` merge field-by-field (docs/SYNC.md: "Vehicle carries per-field
/// `updatedAt`"). Nil for every other entity type, and for records that do not
/// carry it - the merge degrades to whole-record LWW per field.
public struct SyncRecord: Equatable, Sendable {
    public var id: UUID
    public var entityType: String
    public var schemaVersion: Int
    /// The entity's fields as a JSON object (the payload contract's payload).
    public var payload: JSONValue
    /// Whole-record last-write time (docs/SCHEMA.md `updatedAt` = the LWW key).
    public var clientUpdatedAt: Date
    public var deleted: Bool
    /// Per-field last-write times keyed by payload field name. Meaningful for
    /// `Vehicle` only; nil means "no per-field information".
    public var fieldVersions: [String: Date]?

    public init(
        id: UUID,
        entityType: String,
        schemaVersion: Int,
        payload: JSONValue,
        clientUpdatedAt: Date,
        deleted: Bool,
        fieldVersions: [String: Date]? = nil
    ) {
        self.id = id
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.payload = payload
        self.clientUpdatedAt = clientUpdatedAt
        self.deleted = deleted
        self.fieldVersions = fieldVersions
    }
}

/// The `Vehicle` fields that merge field-by-field (docs/SYNC.md S9 and "the same
/// reasoning covers..."): user decisions that feed calculations and are edited
/// independently. Every other `Vehicle` field resolves by whole-record LWW.
public enum VehicleMergeFields {
    /// Payload keys (exact `Vehicle` Codable spellings) merged field-by-field.
    public static let all: [String] = [
        "name",
        "tankCapacityL",
        "initialOdometer",
        "homeCurrency",
        "units",
        "paceLimitKmPerDay",
        "archived",
    ]
}

/// Per-field version bookkeeping for `Vehicle` (docs/SYNC.md: "Vehicle carries
/// per-field `updatedAt`"). The map travels inside the payload under the
/// reserved key `fieldVersions` so a pulling device knows which fields the
/// writer actually touched. Pure functions - no I/O.
public enum VehicleFieldVersions {
    /// The reserved payload key holding the per-field version map.
    public static let key = "fieldVersions"

    /// Reads the per-field version map carried inside a payload.
    public static func read(from payload: JSONValue) -> [String: Date] {
        guard let map = payload.objectValue?[key]?.objectValue else { return [:] }
        var result: [String: Date] = [:]
        for (field, value) in map {
            if case .string(let raw) = value, let date = PayloadFormat.date(from: raw) {
                result[field] = date
            }
        }
        return result
    }

    /// Writes the per-field version map into a payload (sorted keys, canonical).
    public static func write(into payload: JSONValue, versions: [String: Date]) -> JSONValue {
        var object = payload.objectValue ?? [:]
        var map: [String: JSONValue] = [:]
        for (field, date) in versions.sorted(by: { $0.key < $1.key }) {
            map[field] = .string(PayloadFormat.dateString(date))
        }
        object[key] = .object(map)
        return .object(object)
    }

    /// Computes the per-field versions of a local `Vehicle` edit: a mergeable
    /// field whose current value differs from the last-synced payload is stamped
    /// with `updatedAt`; unchanged fields keep their previous version. With no
    /// last-synced payload (a first sync) every mergeable field is new.
    public static func compute(current: JSONValue, lastSynced: JSONValue?, updatedAt: Date) -> [String: Date] {
        let currentObject = current.objectValue ?? [:]
        let lastObject = lastSynced?.objectValue ?? [:]
        var versions = read(from: lastSynced ?? .object([:]))
        for field in VehicleMergeFields.all {
            let changed = lastSynced == nil || currentObject[field] != lastObject[field]
            if changed {
                versions[field] = updatedAt
            }
        }
        return versions
    }
}
