import Foundation

// The `data.json` shape of the archive (docs/SCHEMA.md -> "Backup format"):
//
//     {
//       "vehicles":  [<payload>...],   // raw entity payloads (PayloadCodec),
//       "entries":   [<envelope>...],  // { entityType, schemaVersion, payload }
//       "reminders": [<payload>...],
//       "stations":  [<payload>...],
//       "tariffs":   [<payload>...],
//       "attachments":[<payload>...]   // the matching attachment records
//     }
//
// Every payload is exactly the sync payload shape (`PayloadCodec.encode` -
// decimals as strings, dates ISO-8601 UTC, tombstones included via `deletedAt`)
// so there is exactly ONE encoder for both wire and archive; the archive never
// grows a second spelling. The `entries` array is the one mixed-type array, so
// its elements carry the sync envelope's discriminator.

/// The typed contents of an archive: everything the writer collected, and what
/// the reader produces after it has validated and decoded. Equatable so the
/// whole-account round-trip (PJ.36) can pin that write -> read is lossless:
/// the collected contents and the decoded contents must be equal, blobs and
/// all, or an export silently dropped something.
struct VehicleArchiveContents: Sendable, Equatable {
    var vehicles: [Vehicle] = []
    var fillUps: [FillUp] = []
    var chargeSessions: [ChargeSession] = []
    var serviceRecords: [ServiceRecord] = []
    var expenses: [Expense] = []
    var reminders: [Reminder] = []
    var stations: [Station] = []
    var tariffs: [Tariff] = []
    var attachments: [Attachment] = []
    /// The blob bytes that travel with the archive, keyed by content address.
    var blobs: [String: Data] = [:]

    var entryCount: Int {
        fillUps.count + chargeSessions.count + serviceRecords.count + expenses.count
    }

    /// Every record in apply order: the vehicle(s) first (the entry FKs point
    /// at them), then the referenced/supporting rows, then the entries, then
    /// reminders. Stations/tariffs/attachments carry no hard FK constraints but
    /// precede the entries that reference them so the graph reads top-down.
    var importRecords: [ArchiveImportRecord] {
        var records: [ArchiveImportRecord] = []
        records += vehicles.map(ArchiveImportRecord.vehicle)
        records += stations.map(ArchiveImportRecord.station)
        records += tariffs.map(ArchiveImportRecord.tariff)
        records += attachments.map(ArchiveImportRecord.attachment)
        records += fillUps.map(ArchiveImportRecord.fillUp)
        records += chargeSessions.map(ArchiveImportRecord.chargeSession)
        records += serviceRecords.map(ArchiveImportRecord.serviceRecord)
        records += expenses.map(ArchiveImportRecord.expense)
        records += reminders.map(ArchiveImportRecord.reminder)
        return records
    }
}

/// The parsed-but-unvalidated `data.json` tree. Structure only - payload
/// semantics (schemas, typed decode) are the reader's job, and every element is
/// validated before ANY record is written.
/// One element of the mixed-type `entries` array: the sync envelope's
/// discriminator plus the payload it names.
struct ArchiveEntryElement {
    var entityType: String
    var schemaVersion: Int
    var payload: JSONValue
}

/// The parsed-but-unvalidated `data.json` tree. Structure only - payload
/// semantics (schemas, typed decode) are the reader's job, and every element is
/// validated before ANY record is written.
struct ArchiveDataTree {
    var vehicles: [JSONValue]
    /// `schemaVersion` is the envelope's declared version (advisory after
    /// migration; the reader validates against the effective version).
    var entries: [ArchiveEntryElement]
    var reminders: [JSONValue]
    var stations: [JSONValue]
    var tariffs: [JSONValue]
    var attachments: [JSONValue]

    var entryCount: Int { entries.count }

    /// The single-typed arrays plus their fixed entity types, as the reader
    /// walks them.
    var singleTypedArrays: [(entityType: String, payloads: [JSONValue])] {
        [
            ("vehicle", vehicles),
            ("reminder", reminders),
            ("station", stations),
            ("tariff", tariffs),
            ("attachment", attachments)
        ]
    }
}

enum ArchiveDataJSON {
    static let fileName = "data.json"

    /// The entry types the `entries` array may carry - a per-car archive moves
    /// exactly the four entry kinds (docs/SCHEMA.md, Entry).
    static let entryEntityTypes: [String] = [
        FillUp.entityType, ChargeSession.entityType, ServiceRecord.entityType, Expense.entityType
    ]

    // MARK: Encoding

    /// Encodes the typed contents into the `data.json` tree. All payloads come
    /// from `PayloadCodec.encode` - never a second encoder.
    static func encode(_ contents: VehicleArchiveContents, schemaVersion: Int) throws -> JSONValue {
        var tree: [String: JSONValue] = [:]

        func payloads<E: SyncedEntity>(_ entities: [E]) throws -> [JSONValue] {
            try entities.map { try PayloadCodec.encode($0).payload }
        }
        func entryEnvelopes(_ envelopes: [PayloadEnvelope]) -> [JSONValue] {
            envelopes.map { envelope in
                .object([
                    "entityType": .string(envelope.entityType),
                    "schemaVersion": .number(String(envelope.schemaVersion)),
                    "payload": envelope.payload
                ])
            }
        }

        tree["vehicles"] = .array(try payloads(contents.vehicles))
        var entryEnvelopesOut: [PayloadEnvelope] = []
        entryEnvelopesOut += try contents.fillUps.map {
            PayloadEnvelope(entityType: FillUp.entityType, schemaVersion: schemaVersion,
                            payload: try PayloadCodec.encode($0).payload)
        }
        entryEnvelopesOut += try contents.chargeSessions.map {
            PayloadEnvelope(entityType: ChargeSession.entityType, schemaVersion: schemaVersion,
                            payload: try PayloadCodec.encode($0).payload)
        }
        entryEnvelopesOut += try contents.serviceRecords.map {
            PayloadEnvelope(entityType: ServiceRecord.entityType, schemaVersion: schemaVersion,
                            payload: try PayloadCodec.encode($0).payload)
        }
        entryEnvelopesOut += try contents.expenses.map {
            PayloadEnvelope(entityType: Expense.entityType, schemaVersion: schemaVersion,
                            payload: try PayloadCodec.encode($0).payload)
        }
        tree["entries"] = .array(entryEnvelopes(entryEnvelopesOut))
        tree["reminders"] = .array(try payloads(contents.reminders))
        tree["stations"] = .array(try payloads(contents.stations))
        tree["tariffs"] = .array(try payloads(contents.tariffs))
        tree["attachments"] = .array(try payloads(contents.attachments))

        return .object(tree)
    }

    // MARK: Parsing

    /// Extracts the tree's structure. Rejects a non-object document, a missing
    /// array, and a malformed entry envelope - but NOT payload semantics.
    static func parse(_ tree: JSONValue) throws -> ArchiveDataTree {
        guard let object = tree.objectValue else {
            throw VehicleArchiveError.malformedData("data.json must be a JSON object")
        }
        func array(_ key: String) throws -> [JSONValue] {
            guard case .array(let items)? = object[key] else {
                throw VehicleArchiveError.malformedData("data.json is missing the '\(key)' array")
            }
            return items
        }
        func payloadObjects(_ key: String) throws -> [JSONValue] {
            let items = try array(key)
            for item in items where !item.isObject {
                throw VehicleArchiveError.malformedData("'\(key)' must contain objects only")
            }
            return items
        }
        // Additive tolerance: a build that predates the `attachments` array
        // writes no such key, which means "no attachments", not "corrupt".
        func optionalPayloadObjects(_ key: String) throws -> [JSONValue] {
            guard object[key] != nil else { return [] }
            return try payloadObjects(key)
        }

        let entries = try array("entries").map { item -> ArchiveEntryElement in
            guard let envelope = item.objectValue,
                  case .string(let entityType)? = envelope["entityType"],
                  entryEntityTypes.contains(entityType),
                  case .number(let versionToken)? = envelope["schemaVersion"],
                  let version = Int(versionToken),
                  let payload = envelope["payload"], payload.isObject else {
                throw VehicleArchiveError.malformedData(
                    "an entry is not { entityType, schemaVersion, payload } for an entry type")
            }
            return ArchiveEntryElement(entityType: entityType, schemaVersion: version, payload: payload)
        }

        return ArchiveDataTree(
            vehicles: try payloadObjects("vehicles"),
            entries: entries,
            reminders: try payloadObjects("reminders"),
            stations: try payloadObjects("stations"),
            tariffs: try payloadObjects("tariffs"),
            attachments: try optionalPayloadObjects("attachments"))
    }
}
