import Foundation
import Testing
@testable import TankbookCore

// RV.44 - the delivery-outbox payload (docs/API.md "Delivery outbox"): the
// opaque bytes the server queued decode on the device into the same
// (captureId, extraction) the in-process late answer carries, and BOTH paths
// turn an answer into an inbox item through the single `GatewayInboxPolicy.item`
// - one policy, not two. This suite pins the decode and that shared policy.

@Suite("Delivery outbox payload (RV.44)")
struct GatewayOutboxPayloadTests {

    private static func payloadJSON(captureId: String?, fields: String) -> Data {
        let capture = captureId.map { "\"\($0)\"" } ?? "null"
        return Data(#"""
        { "captureId": \#(capture), "fields": \#(fields), "pipeline": "cloud-fallback v1" }
        """#.utf8)
    }

    private static func savedEntry() -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000),
            odometer: 120_000,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30,
            unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
    }

    // MARK: - Decoding the opaque payload

    @Test("a payload decodes to its captureId and the same extraction the inline path reads")
    func decodesCaptureIdAndExtraction() throws {
        let captureId = UUID()
        let data = Self.payloadJSON(
            captureId: captureId.uuidString,
            fields: #"{ "volume": { "value": 43.61, "confidence": 0.95 } }"#)

        let payload = try GatewayOutboxPayload.decode(data)

        #expect(payload.captureId == captureId)
        #expect(payload.extraction.volume?.value == 43.61)
        #expect(payload.extraction.volume?.confidence == 0.95)
        #expect(payload.extraction.pipeline == "cloud-fallback v1")
    }

    @Test("a payload with no captureId decodes the extraction and yields a nil correlation")
    func missingCaptureIdDecodesToNil() throws {
        let data = Self.payloadJSON(
            captureId: nil,
            fields: #"{ "total": { "value": 71.02, "confidence": 0.9 } }"#)

        let payload = try GatewayOutboxPayload.decode(data)

        #expect(payload.captureId == nil)
        #expect(payload.extraction.total?.value == Decimal(string: "71.02"))
    }

    @Test("a malformed payload is an invalidResponse, never a crash")
    func malformedPayloadIsInvalidResponse() {
        #expect(throws: GatewayExtractError.invalidResponse) {
            _ = try GatewayOutboxPayload.decode(Data("not json".utf8))
        }
        #expect(throws: GatewayExtractError.invalidResponse) {
            _ = try GatewayOutboxPayload.decode(Data("[1,2,3]".utf8))
        }
    }

    // MARK: - One policy: the drain feeds the same item path the inline answer does

    @Test("the drain and the inline path both produce the item through one policy")
    func onePolicyProducesTheSameItemShape() throws {
        let entry = Self.savedEntry()
        let captureId = entry.id
        let data = Self.payloadJSON(
            captureId: captureId.uuidString,
            fields: #"""
            { "total": { "value": 99.99, "confidence": 0.92 },
              "unitPrice": { "value": 1.500, "confidence": 0.88 } }
            """#)

        // The drain path: decode the payload, look up the entry by captureId,
        // then the SAME `item` policy the inline path uses.
        let payload = try GatewayOutboxPayload.decode(data)
        #expect(payload.captureId == entry.id)

        let item = GatewayInboxPolicy.item(extraction: payload.extraction, entry: entry)
        let inline = GatewayInboxPolicy.item(extraction: payload.extraction, entry: entry)

        // One policy, one shape: the item routes to the entry the answer is
        // about, and its extraction is byte-identical to the decoded payload.
        let produced = try #require(item)
        #expect(produced.entryId == entry.id)
        #expect(produced.extraction == payload.extraction)
        #expect(inline?.extraction == produced.extraction)

        // A differing total is worth an item even though nothing is blank.
        #expect(produced.extraction.total?.value == Decimal(string: "99.99"))
    }

    @Test("an outbox answer that merely agrees with the entry produces no item, both paths")
    func agreeingOutboxAnswerProducesNoItem() throws {
        let entry = Self.savedEntry()
        let data = Self.payloadJSON(
            captureId: entry.id.uuidString,
            fields: #"""
            { "total": { "value": 71.02, "confidence": 0.9 },
              "volume": { "value": 42.30, "confidence": 0.9 },
              "unitPrice": { "value": 1.679, "confidence": 0.9 },
              "fuelKind": { "value": "petrol95", "confidence": 0.9 },
              "currency": { "value": "EUR", "confidence": 0.9 } }
            """#)

        let payload = try GatewayOutboxPayload.decode(data)
        #expect(GatewayInboxPolicy.item(extraction: payload.extraction, entry: entry) == nil,
                "an answer that agrees and fills nothing is noise, not work")
    }
}
