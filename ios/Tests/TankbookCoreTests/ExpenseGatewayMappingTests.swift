import Foundation
import Testing
@testable import TankbookCore

/// PJ.29 - the cloud `expense` reading. The gateway's answer is a
/// `GatewayExtraction`; this suite pins the ONE core mapping that turns it into
/// the form's pre-fill and the inbox's recognition, so the on-time route (fill
/// the open expense form) and the late route (offer the saved entry) cannot
/// disagree about what the receipt said.
///
/// The named mutation this row guards: sending `kind: "receipt"` for an expense
/// and mapping the fuel answer across - the fuel fields would then be dropped,
/// but the category the expense kind exists for would never arrive. These tests
/// assert the expense field set explicitly.
@Suite struct ExpenseGatewayMappingTests {

    private func answer(total: Decimal? = nil, currency: CurrencyCode? = nil,
                        date: String? = nil, category: ExpenseCategory? = nil,
                        volume: Double? = nil, fuelKind: FuelKind? = nil) -> GatewayExtraction {
        GatewayExtraction(
            total: total.map { .init(value: $0, confidence: 0.9) },
            volume: volume.map { .init(value: $0, confidence: 0.9) },
            date: date.map { .init(value: $0, confidence: 0.8) },
            fuelKind: fuelKind.map { .init(value: $0, confidence: 0.7) },
            currency: currency.map { .init(value: $0, confidence: 0.9) },
            category: category.map { .init(value: $0, confidence: 0.7) },
            pipeline: "cloud-fallback v1")
    }

    @Test func thePrefillAndRecognitionAgreeOnTheSameDecode() {
        let reading = ExpensePrefillBuilder.reading(fromGateway: answer(
            total: Decimal(string: "12.40")!, currency: .eur, date: "17.08.2026",
            category: .parking))

        #expect(reading.prefill.total == Decimal(string: "12.40"))
        #expect(reading.prefill.currency == .eur)
        #expect(reading.prefill.date == ConfirmDate.parse("17.08.2026"))

        #expect(reading.recognition.total?.value == Decimal(string: "12.40"))
        #expect(reading.recognition.currency?.value == .eur)
        #expect(reading.recognition.category?.value == .parking)
        // One decode: the date the form would pre-fill and the date the inbox
        // would offer are the same instant, not two readings of the receipt.
        #expect(reading.recognition.date?.value == reading.prefill.date)
    }

    @Test func fuelFieldsOnTheAnswerNeverReachTheExpenseReading() {
        // A `receipt` answer that carries a volume and a fuel kind - the mapping
        // must ignore them, exactly as `ExpensePrefillBuilder.prefill(from:)`
        // ignores the on-device fuel fields.
        let reading = ExpensePrefillBuilder.reading(fromGateway: answer(
            total: Decimal(string: "12.40")!, volume: 42.30, fuelKind: .petrol95))

        #expect(reading.prefill == ExpensePrefill(total: Decimal(string: "12.40")))
        #expect(reading.recognition.category == nil)
        // `providedFields` still reports what the answer carried, but the
        // expense reading simply has no home for the fuel fields.
        #expect(reading.recognition.total?.value == Decimal(string: "12.40"))
    }

    @Test func anUnknownCategoryStringIsDroppedNeverGuessed() throws {
        // The wire decode maps `category` against the device's codes; an unknown
        // string is dropped, so the form opens at its default (hard rule 13).
        let json = "{\"fields\":{\"total\":{\"value\":12.4,\"confidence\":0.9}," +
                   "\"category\":{\"value\":\"spaceship\",\"confidence\":0.7}}," +
                   "\"pipeline\":\"cloud-fallback v1\"}"
        let extraction = try GatewayExtraction.decode(Data(json.utf8))

        #expect(extraction.total?.value == Decimal(string: "12.4"))
        #expect(extraction.category == nil,
                "a category the device does not know is dropped, never guessed")
        #expect(!extraction.providedFields.contains(.category))
    }

    @Test func theWireDecodesTheKnownCategoryCodes() throws {
        for (raw, expected) in [("parking", ExpenseCategory.parking),
                                ("toll", .toll),
                                ("insurance", .insurance),
                                ("tax", .tax),
                                ("fine", .fine),
                                ("accessory", .accessory),
                                ("parts", .parts),
                                ("wash", .other("wash")),
                                ("other", .other(""))] {
            let json = #"{"fields":{"category":{"value":"\#(raw)","confidence":0.7}},"pipeline":"cloud-fallback v1"}"#
            let extraction = try GatewayExtraction.decode(Data(json.utf8))
            #expect(extraction.category?.value == expected,
                    "the code '\(raw)' must decode to its expense category")
        }
    }

    @Test func aBlankUntouchedAmountIsFillableButATypedOneIsNot() {
        let extraction = answer(total: Decimal(string: "12.40")!)

        let blank = GatewaySuggestionPolicy.fillableFields(
            answer: extraction,
            snapshot: GatewaySuggestionSnapshot())
        #expect(blank.contains(.total),
                "a blank, untouched amount may be filled by the cloud reading")

        let typed = GatewaySuggestionPolicy.fillableFields(
            answer: extraction,
            snapshot: GatewaySuggestionSnapshot(touched: [.total]))
        #expect(!typed.contains(.total),
                "a typed amount is the user's own - the cloud reading must never overwrite it")

        let resolved = GatewaySuggestionPolicy.fillableFields(
            answer: extraction,
            snapshot: GatewaySuggestionSnapshot(onDeviceResolved: [.total]))
        #expect(!resolved.contains(.total),
                "the on-device result has first claim (F4); the gateway never fights it")
    }

    @Test func aCategoryIsOfferedOnlyWhenTheAnswerCarriedOne() {
        let withCategory = answer(category: .parking)
        #expect(withCategory.providedFields.contains(.category))

        let withoutCategory = answer(total: Decimal(string: "12.40")!)
        #expect(!withoutCategory.providedFields.contains(.category))
    }
}
