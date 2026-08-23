import Foundation

/// Encodes synced entities into their payload envelopes and decodes them back,
/// preserving everything this build does not understand
/// (docs/SYNC.md -> "Payload contract and versioning" -> forward compatibility:
/// a record with unknown fields or an unknown enum case survives decode ->
/// encode unchanged; it is stored opaquely, never dropped).
///
/// Preservation works in two layers:
/// 1. Unknown object keys at any depth are kept: decode encodes a "peek" of the
///    entity, diffs it against the incoming payload, and re-adds on encode the
///    keys the typed value cannot represent.
/// 2. Unknown tagged-enum cases (a newer client's enum value) are pulled out
///    before typed decoding (a benign known value stands in), then spliced back
///    byte-for-byte on encode.
public enum PayloadCodec {
    public enum Error: Swift.Error, Equatable, Sendable {
        case malformedEnvelope(String)
        case malformedPayload(String)
        case mismatchedEntityType(expected: String, actual: String)
        case unsupportedSchemaVersion(Int)
        case decodeFailed(String)
    }

    /// Current payload contract version (docs/SCHEMA.md -> Payload schemas).
    public static let currentSchemaVersion = 1

    // MARK: - Public API

    /// Encodes an entity into its envelope. Pass the result of a prior
    /// `decode` to carry preserved unknown data back out unchanged.
    public static func encode<Entity: SyncedEntity>(
        _ entity: Entity,
        preserving decoded: DecodedPayload<Entity>? = nil
    ) throws -> PayloadEnvelope {
        var tree = try encodeEntity(entity)
        if let preserved = decoded?.preserved {
            tree = mergeDroppedKeys(original: preserved.baseTree, into: tree)
            tree = spliceTagged(preserved.taggedValues, into: tree)
        }
        return PayloadEnvelope(entityType: Entity.entityType,
                               schemaVersion: currentSchemaVersion,
                               payload: tree)
    }

    /// Decodes a typed entity from an envelope. Unknown top-level fields land in
    /// `unknownFields` (the record wrapper's side dictionary); unknown nested
    /// keys and enum tags are preserved for the matching `encode(preserving:)`.
    public static func decode<Entity: SyncedEntity>(
        _ envelope: PayloadEnvelope,
        as type: Entity.Type
    ) throws -> DecodedPayload<Entity> {
        guard envelope.entityType == Entity.entityType else {
            throw Error.mismatchedEntityType(expected: Entity.entityType, actual: envelope.entityType)
        }
        guard envelope.schemaVersion == currentSchemaVersion else {
            throw Error.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        let original = envelope.payload
        let (sanitized, tagged) = sanitizeTaggedEnums(original, for: Entity.entityType)
        let entity = try decodeEntity(Entity.self, from: sanitized)
        let peek = try encodeEntity(entity)
        let unknownFields = topLevelUnknownFields(original: original, encoded: peek)
        return DecodedPayload(entity: entity,
                              unknownFields: unknownFields,
                              preserved: PreservedPayload(baseTree: sanitized, taggedValues: tagged))
    }

    // MARK: - Entity <-> JSON tree

    static func encodeEntity<Entity: Encodable>(_ entity: Entity) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.singleValueContainer()
            try container.encode(PayloadFormat.dateString(date))
        }
        let data = try encoder.encode(entity)
        let tree = try JSONValue.parse(data)
        guard tree.isObject else {
            throw Error.malformedPayload("encoded payload must be a JSON object")
        }
        return tree
    }

    static func decodeEntity<Entity: Decodable>(_ type: Entity.Type, from tree: JSONValue) throws -> Entity {
        let data = try tree.jsonData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = PayloadFormat.date(from: raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: dec.codingPath, debugDescription: "Invalid ISO-8601 date '\(raw)'"))
            }
            return date
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw Error.decodeFailed(String(describing: error))
        }
    }

    // MARK: - Unknown-key preservation (add back what typed decoding dropped)

    /// Adds to `encoded` every object key present in `original` but absent in
    /// `encoded`, recursively (arrays element-wise). Known values are never
    /// touched - only keys the typed value cannot represent.
    static func mergeDroppedKeys(original: JSONValue, into encoded: JSONValue) -> JSONValue {
        switch (original, encoded) {
        case (.object(let od), .object(let ed)):
            var out = ed
            for (key, originalValue) in od {
                if let encodedValue = ed[key] {
                    out[key] = mergeDroppedKeys(original: originalValue, into: encodedValue)
                } else {
                    out[key] = originalValue
                }
            }
            return .object(out)
        case (.array(let oa), .array(let ea)):
            var out = ea
            for i in 0 ..< min(oa.count, ea.count) {
                out[i] = mergeDroppedKeys(original: oa[i], into: ea[i])
            }
            return .array(out)
        default:
            return encoded
        }
    }

    static func topLevelUnknownFields(original: JSONValue, encoded: JSONValue) -> [String: JSONValue] {
        guard let originalObject = original.objectValue,
              let encodedObject = encoded.objectValue else { return [:] }
        var unknown: [String: JSONValue] = [:]
        for (key, value) in originalObject where encodedObject[key] == nil {
            unknown[key] = value
        }
        return unknown
    }

    // MARK: - Unknown-tag preservation (tagged enums)

    /// Replaces unknown tagged-enum values with a known stand-in so typed
    /// decoding never sees a case it does not know, collecting the original
    /// values (with their full JSON paths) for splice-back on encode.
    static func sanitizeTaggedEnums(_ tree: JSONValue, for entityType: String)
        -> (sanitized: JSONValue, extracted: [(path: [String], value: JSONValue)])
    {
        let fields = PayloadContract.taggedEnumFields(for: entityType)
        var extracted: [(path: [String], value: JSONValue)] = []

        func walk(_ node: JSONValue, objectPath: [String], jsonPath: [String]) -> JSONValue {
            if case .array(let items) = node {
                return .array(items.enumerated().map { index, item in
                    walk(item, objectPath: objectPath, jsonPath: jsonPath + [String(index)])
                })
            }
            guard case .object(let dict) = node else { return node }
            if let field = fields.first(where: { $0.path == objectPath }) {
                if case .string(let tag)? = dict["tag"], !field.knownTags.contains(tag) {
                    extracted.append((jsonPath, node))
                    return field.benignDefault
                }
            }
            var out = dict
            for (key, value) in dict {
                out[key] = walk(value, objectPath: objectPath + [key], jsonPath: jsonPath + [key])
            }
            return .object(out)
        }

        let sanitized = walk(tree, objectPath: [], jsonPath: [])
        return (sanitized, extracted)
    }

    /// Replaces values at the recorded paths with the original bytes.
    static func spliceTagged(_ tagged: [(path: [String], value: JSONValue)], into tree: JSONValue) -> JSONValue {
        var result = tree
        for item in tagged {
            result = splicePath(item.path, value: item.value, into: result)
        }
        return result
    }

    private static func splicePath(_ path: [String], value: JSONValue, into tree: JSONValue) -> JSONValue {
        guard let head = path.first else { return value }
        let rest = Array(path.dropFirst())
        switch tree {
        case .object(var dict):
            if let child = dict[head] {
                dict[head] = splicePath(rest, value: value, into: child)
            }
            return .object(dict)
        case .array(var items):
            if let index = Int(head), index < items.count {
                items[index] = splicePath(rest, value: value, into: items[index])
            }
            return .array(items)
        default:
            return tree
        }
    }
}

/// The result of `PayloadCodec.decode`: the typed entity plus everything the
/// build could not represent. Hand the whole value back to
/// `PayloadCodec.encode(preserving:)` to round-trip unknown data unchanged.
public struct DecodedPayload<Entity> {
    public let entity: Entity
    /// Top-level payload keys this build does not understand (the record
    /// wrapper's side dictionary - docs/SYNC.md).
    public let unknownFields: [String: JSONValue]
    internal let preserved: PreservedPayload
}

internal struct PreservedPayload {
    /// The sanitized incoming tree; keys the typed value drops are re-added
    /// from here on encode.
    var baseTree: JSONValue
    /// Original tagged-enum values (full JSON paths) to splice back on encode.
    var taggedValues: [(path: [String], value: JSONValue)]
}
