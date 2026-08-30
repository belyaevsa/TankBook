import Testing
import Foundation
@testable import TankbookCore

/// PJ.48 the blank-fields-only attach merge (docs/ERRORS.md -> Edit entry, the
/// two new rows). The guarantee in pure form: a receipt attached to a TYPED
/// entry may offer pre-fills for fields the entry left BLANK only. A typed
/// value is a fact and is never overwritten (hard rule 13); an OCR reading that
/// disagrees with a typed value produces no suggestion and no amber - the typed
/// value wins silently and the photo is kept either way (ERRORS.md:126).
@Suite struct ReceiptAttachMergeTests {

    private func decimal(_ string: String) -> Decimal { Decimal(string: string)! }

    /// A fully typed fill: money, volume, unit price, fuel kind and date all
    /// recorded - the shape of every fill the app's own save path writes.
    private func typedFill(unitPrice: Decimal? = Decimal(string: "1.679"),
                           money: Money? = Money(amount: Decimal(string: "71.02")!,
                                                 currency: .eur, homeCurrency: .eur)) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: UUID.v7(), date: now, odometer: 119_486,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, volumeL: 42.30,
            unitPrice: unitPrice, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    /// An OCR result that disagrees with every typed value, plus a couple of
    /// extra fields the entry did not record (a fiscal date and a fuel kind).
    private func disagreeingExtraction() -> FuelExtraction {
        FuelExtraction(liters: 30.00, unitPrice: decimal("2.000"),
                       total: decimal("60.00"), currency: .pln, fuelKind: .diesel,
                       date: "17.08.2026")
    }

    // MARK: - The load-bearing case: a fully typed entry is never overwritten

    @Test func fullyTypedEntryYieldsNoSuggestionsEvenWhenOcrDisagrees() {
        // Every typed field is a fact. The OCR reading every one of them
        // differently must produce NOTHING to pre-fill - no total, no currency,
        // no unit price - so the typed values stay byte-identical and no amber
        // is raised against them (ERRORS.md:126).
        let entry = typedFill()
        let ocr = disagreeingExtraction()
        #expect(ReceiptAttachMerge.suggestions(entry: entry, extraction: ocr).isEmpty)
    }

    @Test func aTypedFieldIsNotSuggestedEvenWhenTheOcrAgrees() {
        // "Blank" decides, never "agreement": a field the entry already holds is
        // not blank, so the merge never returns it - agreeing OCR included. The
        // suggestion is for fields the user still has to fill, not a
        // re-assertion of what they typed.
        let entry = typedFill()
        let agreeing = FuelExtraction(liters: 42.30, unitPrice: decimal("1.679"),
                                      total: decimal("71.02"), currency: .eur,
                                      fuelKind: .petrol95)
        #expect(ReceiptAttachMerge.suggestions(entry: entry, extraction: agreeing).isEmpty)
    }

    // MARK: - Blank fields ARE offered (dimmed by the view, never applied silently)

    @Test func blankMoneyYieldsTotalAndCurrencySuggestions() {
        // A fill with no money recorded (the corporate-fill shape - docs/SCHEMA.md
        // -> FillUp: money is optional) left total and currency blank: the OCR
        // may suggest both. The view renders each dimmed until tapped.
        let entry = typedFill(money: nil)
        let suggestions = ReceiptAttachMerge.suggestions(
            entry: entry, extraction: disagreeingExtraction())
        #expect(suggestions.contains(.total))
        #expect(suggestions.contains(.currency))
        // The unit price IS typed here, so even though the OCR read a different
        // one, it must not be suggested.
        #expect(!suggestions.contains(.unitPrice))
    }

    @Test func blankUnitPriceYieldsAUnitPriceSuggestion() {
        // A fill imported without a price left unitPrice blank; the OCR may
        // suggest it. Money is present, so total and currency stay untouched
        // whatever the OCR read.
        let entry = typedFill(unitPrice: nil)
        let suggestions = ReceiptAttachMerge.suggestions(
            entry: entry, extraction: disagreeingExtraction())
        #expect(suggestions.contains(.unitPrice))
        #expect(!suggestions.contains(.total))
        #expect(!suggestions.contains(.currency))
    }

    @Test func aBlankFieldIsOnlySuggestedWhenTheOcrResolvedIt() {
        // A blank money field is offered a total/currency only when the OCR
        // actually read one - a suggestion is a value, never a promise.
        let entry = typedFill(money: nil)
        let noMoneyFields = FuelExtraction(liters: 30.00, unitPrice: decimal("2.000"))
        #expect(ReceiptAttachMerge.suggestions(entry: entry, extraction: noMoneyFields).isEmpty)
    }

    // MARK: - Non-optional fields are never "blank"

    @Test func volumeFuelKindAndDateAreNeverSuggested() {
        // volumeL, fuelKind and date are non-optional on FillUp: a typed entry
        // always records them, so the merge never treats them as blank - the
        // OCR's own readings of them are dropped even on a blank-money fill.
        let entry = typedFill(money: nil)
        let suggestions = ReceiptAttachMerge.suggestions(
            entry: entry, extraction: disagreeingExtraction())
        #expect(!suggestions.contains(.volume))
        #expect(!suggestions.contains(.fuelKind))
        #expect(!suggestions.contains(.date))
    }
}
