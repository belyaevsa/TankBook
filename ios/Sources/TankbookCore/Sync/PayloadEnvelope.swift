import Foundation

/// The sync record envelope (docs/SYNC.md -> "Payload contract and versioning").
/// On the wire it is exactly `{ "entityType", "schemaVersion", "payload" }`;
/// `payload` is a JSON object holding the entity's fields for that
/// `schemaVersion`. The version lives in the envelope (mirroring the server's
/// `records.schema_version` column), never buried in the payload.
public struct PayloadEnvelope: Equatable, Sendable {
    /// The entity type, matching `docs/schemas/v<N>/<entityType>.schema.json`.
    public var entityType: String
    /// The payload contract version. Current version is `PayloadCodec.currentSchemaVersion`.
    public var schemaVersion: Int
    /// The entity's fields as a JSON object.
    public var payload: JSONValue

    public init(entityType: String, schemaVersion: Int, payload: JSONValue) {
        self.entityType = entityType
        self.schemaVersion = schemaVersion
        self.payload = payload
    }

    /// Serializes the envelope (compact, sorted keys).
    public func jsonData() throws -> Data {
        guard payload.isObject else {
            throw PayloadCodec.Error.malformedPayload("payload must be a JSON object")
        }
        let envelope = JSONValue.object([
            "entityType": .string(entityType),
            "schemaVersion": .number(String(schemaVersion)),
            "payload": payload,
        ])
        return try envelope.jsonData()
    }

    /// Parses a serialized envelope and validates its outer shape.
    public static func parse(_ data: Data) throws -> PayloadEnvelope {
        let tree = try JSONValue.parse(data)
        guard let object = tree.objectValue else {
            throw PayloadCodec.Error.malformedEnvelope("envelope must be a JSON object")
        }
        guard case .string(let entityType)? = object["entityType"],
              case .number(let versionToken)? = object["schemaVersion"],
              let version = Int(versionToken),
              let payload = object["payload"], payload.isObject else {
            throw PayloadCodec.Error.malformedEnvelope(
                "envelope must be { entityType: string, schemaVersion: int, payload: object }")
        }
        return PayloadEnvelope(entityType: entityType, schemaVersion: version, payload: payload)
    }
}
