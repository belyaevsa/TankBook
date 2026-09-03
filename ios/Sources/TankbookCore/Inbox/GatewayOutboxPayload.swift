import Foundation

// MARK: - RV.44 the delivery-outbox payload (docs/API.md "Delivery outbox")
//
// A result the gateway computed but could not hand back is queued server-side
// as OPAQUE BYTES and drained on the device's next launch. The payload is the
// extract response plus the device's own correlation token, so the device can
// match the drained answer to the entry it belongs to. The server never reads a
// field of it (hard rule 9); this decoder is the one place the bytes become a
// typed answer on the device.

/// The decoded delivery-outbox payload: the correlation token (the entry id, by
/// convention the capture's id) and the gateway reading. The extraction part is
/// decoded by the SAME `GatewayExtraction.decode` the in-process `/extract`
/// response uses - one decoder, not two.
public struct GatewayOutboxPayload: Sendable, Equatable {
    /// The device's correlation token, echoed back verbatim. nil when the
    /// request carried none - in which case there is no entry to match and the
    /// answer cannot become an inbox item.
    public var captureId: UUID?
    /// The gateway reading the answer carries.
    public var extraction: GatewayExtraction

    public init(captureId: UUID?, extraction: GatewayExtraction) {
        self.captureId = captureId
        self.extraction = extraction
    }

    /// Decodes the opaque payload bytes. `captureId` is a UUID string (or
    /// absent); the `fields`/`pipeline` half is the same wire shape
    /// `POST /extract` returns, decoded by the shared path.
    public static func decode(_ data: Data) throws -> GatewayOutboxPayload {
        let tree: JSONValue
        do {
            tree = try JSONValue.parse(data)
        } catch {
            throw GatewayExtractError.invalidResponse
        }
        guard let object = tree.objectValue else { throw GatewayExtractError.invalidResponse }
        let captureId = object["captureId"]?.stringValue.flatMap(UUID.init(uuidString:))
        let extraction = try GatewayExtraction.decode(data)
        return GatewayOutboxPayload(captureId: captureId, extraction: extraction)
    }
}
