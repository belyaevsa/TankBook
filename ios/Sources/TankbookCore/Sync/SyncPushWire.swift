import Foundation

/// The `POST /sync/push` request body, byte-exact (docs/API.md ->
/// `POST /sync/push`). `RemoteSyncTransport.encodePush` serializes the body a
/// push sends over the wire; `SyncEngine` must bound a push batch by the
/// encoded size of that same body *before the request exists* (RV.97 - a
/// count-only batch of 200 rebuilt an unbounded ~150 KB body every cycle). One
/// builder feeds both, so the engine's measurement is the transport's bytes,
/// not a guess at them.
///
/// The body is the wrapper `{"changes":[ ... ]}` around one element per change.
/// `JSONValue` serializes an array by concatenating each element's own bytes
/// with a single comma between them, so element bytes + the wrapper + `n-1`
/// separators is EXACT - there is no per-change envelope allowance to estimate,
/// because a change that has not been measured here is a change the encoder has
/// not been asked to send.
internal enum SyncPushWire {
    /// One change as it appears in the request body (docs/API.md -> the change
    /// shape: `id`, `entityType`, `schemaVersion`, `baseScn`, `payload`,
    /// `clientUpdatedAt`, `deleted`).
    static func element(for change: SyncPushChange) -> JSONValue {
        .object([
            "id": .string(change.id.uuidString),
            "entityType": .string(change.entityType),
            "schemaVersion": .number(String(change.schemaVersion)),
            "baseScn": .number(String(change.baseScn)),
            "payload": change.payload,
            "clientUpdatedAt": .string(PayloadFormat.dateString(change.clientUpdatedAt)),
            "deleted": .bool(change.deleted),
        ])
    }

    /// The full request-body tree `encodePush` serializes.
    static func envelope(for changes: [SyncPushChange]) -> JSONValue {
        .object(["changes": .array(changes.map { element(for: $0) })])
    }

    /// The fixed wrapper the array sits in: `{"changes":[` and `]}`.
    static let wrapperBytes =
        Data(#"{"changes":["#.utf8).count + Data("]}".utf8).count

    /// Bytes of one change's own element in the request body (no separator -
    /// the comma between elements is the caller's, it exists only between them).
    static func elementBytes(for change: SyncPushChange) -> Int {
        (try? element(for: change).jsonData().count) ?? 0
    }

    /// The exact encoded size of a whole batch's request body - the number the
    /// byte bound compares against `SyncEngine.maxBatchBytes`.
    static func wireBytes(for changes: [SyncPushChange]) -> Int {
        var bytes = wrapperBytes
        for (index, change) in changes.enumerated() {
            if index > 0 { bytes += 1 }
            bytes += elementBytes(for: change)
        }
        return bytes
    }
}
