import Foundation
import Testing
@testable import TankbookCore

/// PJ.29a - the cloud `invoice` reading. The gateway's answer is a
/// `GatewayExtraction`; this suite pins the ONE core mapping that turns it into
/// the service form's header pre-fill and the inbox's recognition, so the
/// on-time route (fill the open service form) and the late route (offer the
/// saved record) cannot disagree about what the invoice's header said.
///
/// The named vacuous trap this guards: letting a cloud answer's line items
/// replace the local deterministic split. `ServicePrefill` and the mapping's
/// `lineItems: []` make that inexpressible - the split's items are the form's.
@Suite struct ServiceGatewayMappingTests {

    private func answer(vendor: String? = nil, total: Decimal? = nil,
                        currency: CurrencyCode? = nil, date: String? = nil) -> GatewayExtraction {
        GatewayExtraction(
            total: total.map { .init(value: $0, confidence: 0.9) },
            date: date.map { .init(value: $0, confidence: 0.8) },
            currency: currency.map { .init(value: $0, confidence: 0.9) },
            vendor: vendor.map { .init(value: $0, confidence: 0.9) },
            pipeline: "cloud-fallback v1")
    }

    @Test func thePrefillAndRecognitionAgreeOnTheSameDecode() {
        let reading = ServiceRecognitionBuilder.reading(fromGateway: answer(
            vendor: "Bosch Service", total: Decimal(string: "148.00")!,
            currency: .eur, date: "17.08.2026"))

        #expect(reading.prefill.vendor == "Bosch Service")
        #expect(reading.prefill.total == Decimal(string: "148.00"))
        #expect(reading.prefill.currency == .eur)
        #expect(reading.prefill.date == ConfirmDate.parse("17.08.2026"))

        #expect(reading.recognition.vendor?.value == "Bosch Service")
        #expect(reading.recognition.total?.value == Decimal(string: "148.00"))
        #expect(reading.recognition.currency?.value == .eur)
        // One decode: the date the form would pre-fill and the date the inbox
        // would offer are the same instant, not two readings of the invoice.
        #expect(reading.recognition.date?.value == reading.prefill.date)
    }

    @Test func aCloudAnswerNeverCarriesLineItems() {
        // The line items are the local deterministic split's (docs/JOURNEYS.md
        // J7). The invoice prompt is header-only, but a model may still return
        // extra fields; the mapping has no channel for them and always produces
        // an empty list, so a cloud answer can never replace the split.
        let reading = ServiceRecognitionBuilder.reading(fromGateway: answer(
            vendor: "Bosch Service", total: Decimal(string: "148.00")!))
        #expect(reading.recognition.lineItems.isEmpty)
    }

    @Test func anUnknownCurrencyStringIsDroppedNeverGuessed() throws {
        // The wire decode maps `currency` against the device's codes; an unknown
        // string is dropped, so the form keeps the car's home currency and the
        // inbox offers nothing (hard rule 13).
        let json = "{\"fields\":{\"total\":{\"value\":148.0,\"confidence\":0.9}," +
                   "\"currency\":{\"value\":\"spaceship\",\"confidence\":0.9}}," +
                   "\"pipeline\":\"cloud-fallback v1\"}"
        let extraction = try GatewayExtraction.decode(Data(json.utf8))

        #expect(extraction.total?.value == Decimal(string: "148.0"))
        #expect(extraction.currency == nil,
                "a currency the device does not know is dropped, never guessed")
        let reading = ServiceRecognitionBuilder.reading(fromGateway: extraction)
        #expect(reading.prefill.currency == nil)
        #expect(reading.recognition.currency == nil)
    }

    @Test func aBlankUntouchedVendorIsFillableButATypedOneIsNot() {
        let extraction = answer(vendor: "Bosch Service")

        let blank = GatewaySuggestionPolicy.fillableFields(
            answer: extraction, snapshot: GatewaySuggestionSnapshot())
        #expect(blank.contains(.vendor),
                "a blank, untouched vendor may be filled by the cloud reading")

        let typed = GatewaySuggestionPolicy.fillableFields(
            answer: extraction, snapshot: GatewaySuggestionSnapshot(touched: [.vendor]))
        #expect(!typed.contains(.vendor),
                "a typed vendor is the user's own - the cloud reading must never overwrite it")

        let resolved = GatewaySuggestionPolicy.fillableFields(
            answer: extraction, snapshot: GatewaySuggestionSnapshot(onDeviceResolved: [.vendor]))
        #expect(!resolved.contains(.vendor),
                "the local split has first claim (F4); the gateway never fights it")
    }

    @Test func theWireDecodesTheInvoiceVendor() throws {
        let json = #"{"fields":{"vendor":{"value":"Bosch Service","confidence":0.9}},"pipeline":"cloud-fallback v1"}"#
        let extraction = try GatewayExtraction.decode(Data(json.utf8))
        #expect(extraction.vendor?.value == "Bosch Service")
        #expect(extraction.providedFields.contains(.vendor))
    }
}
