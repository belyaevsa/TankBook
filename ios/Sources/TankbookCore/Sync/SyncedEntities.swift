import Foundation

/// A domain entity that participates in the sync payload contract
/// (docs/SYNC.md -> Payload contract and versioning). `entityType` is the wire
/// name used as `records.entity_type`; the schema files live at
/// `docs/schemas/v<N>/<entityType>.schema.json`.
public protocol SyncedEntity: Codable, Entity {
    static var entityType: String { get }
}

extension Vehicle: SyncedEntity {
    public static let entityType = "vehicle"
}

extension FillUp: SyncedEntity {
    public static let entityType = "fillUp"
}

extension ChargeSession: SyncedEntity {
    public static let entityType = "chargeSession"
}

extension ServiceRecord: SyncedEntity {
    public static let entityType = "serviceRecord"
}

extension Expense: SyncedEntity {
    public static let entityType = "expense"
}

extension Reminder: SyncedEntity {
    public static let entityType = "reminder"
}

extension Station: SyncedEntity {
    public static let entityType = "station"
}

extension Tariff: SyncedEntity {
    public static let entityType = "tariff"
}

extension TireSet: SyncedEntity {
    public static let entityType = "tireSet"
}

extension Attachment: SyncedEntity {
    public static let entityType = "attachment"
}

extension Preferences: SyncedEntity {
    public static let entityType = "preferences"
}

/// The closed set of synced entities. The schema-coverage test walks this list
/// and fails when an entity has no registered schema - the guard that stops a
/// new entity shipping without its contract (docs/SYNC.md, "How this is
/// assured").
public enum SyncedEntityCatalog {
    public static var all: [any SyncedEntity.Type] {
        [
            Vehicle.self,
            FillUp.self,
            ChargeSession.self,
            ServiceRecord.self,
            Expense.self,
            Reminder.self,
            Station.self,
            Tariff.self,
            TireSet.self,
            Attachment.self,
            Preferences.self,
        ]
    }
    public static func entityType<T: SyncedEntity>(for type: T.Type) -> String {
        type.entityType
    }
}

/// Registry of JSON paths whose values are tagged-object enums, used by the
/// codec to keep records with unknown enum tags opaquely intact
/// (docs/SYNC.md, forward compatibility - a newer client's enum case must
/// survive an older client decode -> encode unchanged).
internal struct TaggedEnumField {
    /// Object-key path from the payload root; array components match every
    /// element (e.g. ["items", "category"] matches each ServiceItem.category).
    let path: [String]
    /// The case names this build knows (exact SCHEMA.md spellings).
    let knownTags: Set<String>
    /// A known value to substitute while decoding so an unknown tag never
    /// blocks the record; the original bytes are spliced back on encode.
    let benignDefault: JSONValue
}

internal enum PayloadContract {
    static func taggedEnumFields(for entityType: String) -> [TaggedEnumField] {
        switch entityType {
        case Vehicle.entityType:
            return []
        case FillUp.entityType:
            return [
                TaggedEnumField(path: ["conflict"], knownTags: conflictTags, benignDefault: .object(["tag": .string("none")])),
                TaggedEnumField(path: ["provenance"], knownTags: provenanceTags, benignDefault: .object(["tag": .string("manual")])),
                TaggedEnumField(path: ["crossCheck"], knownTags: crossCheckTags, benignDefault: .object(["tag": .string("verified")])),
            ]
        case ChargeSession.entityType:
            return [
                TaggedEnumField(path: ["conflict"], knownTags: conflictTags, benignDefault: .object(["tag": .string("none")])),
                TaggedEnumField(path: ["provenance"], knownTags: provenanceTags, benignDefault: .object(["tag": .string("manual")])),
            ]
        case ServiceRecord.entityType:
            return [
                TaggedEnumField(path: ["conflict"], knownTags: conflictTags, benignDefault: .object(["tag": .string("none")])),
                TaggedEnumField(path: ["provenance"], knownTags: provenanceTags, benignDefault: .object(["tag": .string("manual")])),
                TaggedEnumField(path: ["items", "category"], knownTags: serviceCategoryTags,
                                benignDefault: .object(["tag": .string("other"), "value": .string("unknown")])),
            ]
        case Expense.entityType:
            return [
                TaggedEnumField(path: ["conflict"], knownTags: conflictTags, benignDefault: .object(["tag": .string("none")])),
                TaggedEnumField(path: ["provenance"], knownTags: provenanceTags, benignDefault: .object(["tag": .string("manual")])),
                TaggedEnumField(path: ["category"], knownTags: expenseCategoryTags,
                                benignDefault: .object(["tag": .string("other"), "value": .string("unknown")])),
            ]
        case Reminder.entityType:
            return [
                TaggedEnumField(path: ["category"], knownTags: reminderCategoryTags, benignDefault: .object(["tag": .string("custom")])),
                TaggedEnumField(path: ["status"], knownTags: reminderStatusTags, benignDefault: .object(["tag": .string("scheduled")])),
            ]
        default:
            return []
        }
    }

    private static let provenanceTags: Set<String> =
        ["receiptScan", "pumpPhoto", "fiscalQR", "screenshot", "manual", "import"]
    private static let conflictTags: Set<String> = ["none", "flagged"]
    private static let crossCheckTags: Set<String> = ["verified", "notApplicable", "mismatch"]
    private static let serviceCategoryTags: Set<String> =
        ["oil", "brakes", "tires", "battery", "filters", "inspection", "repair", "parts", "wash", "other"]
    private static let expenseCategoryTags: Set<String> =
        ["insurance", "tax", "parking", "toll", "fine", "accessory", "parts", "other"]
    private static let reminderCategoryTags: Set<String> =
        ["oil", "brakes", "tires", "battery", "filters", "inspection", "repair", "parts", "wash", "insurance", "custom", "other"]
    private static let reminderStatusTags: Set<String> = ["scheduled", "attention", "done", "dismissed"]
}
