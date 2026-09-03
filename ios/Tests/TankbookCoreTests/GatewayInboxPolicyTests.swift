import Foundation
import Testing
@testable import TankbookCore

// RV.38 - the inbox decision (docs/JOURNEYS.md F4, amended): a late gateway
// answer no longer silently rewrites a saved entry; it lands in the inbox as a
// suggestion, and "leave it as it is" is the default. This suite pins the three
// decisions in core - what makes an item, what fills, and what the merge
// preserves - so the inbox view and the sheet cannot disagree about the
// boundary. The model is `SyncSurfaceTests`/`SyncChipTests`: pin WHICH state,
// never "a thing happened".

@Suite("Gateway inbox policy (RV.38)")
struct GatewayInboxPolicyTests {

    private static func answer() -> GatewayExtraction {
        GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.679")!, confidence: 0.88),
            date: .init(value: "17.08.2026", confidence: 0.80),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .rub, confidence: 0.60),
            pipeline: "test"
        )
    }

    /// A saved fill-up as the typed path writes one: total + litres typed, price
    /// derived, fuel kind defaulted to petrol95, home currency eur.
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

    /// A saved entry with a BLANK price - the one gateway field a saved fill-up
    /// can genuinely leave blank (an imported or partially-written row).
    private static func savedEntryBlankPrice() -> FillUp {
        var entry = savedEntry()
        entry.unitPrice = nil
        entry.crossCheck = .notApplicable
        return entry
    }

    // MARK: - What makes an item

    @Test("a differing answer is an offer even when nothing is blank")
    func differingAnswerIsOffered() {
        // The gateway read diesel/99.99 against a saved petrol95/71.02: the
        // difference is worth surfacing even though nothing can be auto-filled.
        #expect(GatewayInboxPolicy.shouldOffer(extraction: Self.answer(), entry: Self.savedEntry()))
    }

    @Test("a blank field is an offer even when the rest agrees")
    func blankFieldIsOffered() {
        let blank = Self.savedEntryBlankPrice()
        #expect(GatewayInboxPolicy.shouldOffer(extraction: Self.answer(), entry: blank))
    }

    @Test("an answer that agrees and fills nothing is not an offer")
    func agreeingAnswerIsNotOffered() {
        // The answer matches what the user saved exactly: no fillable field, no
        // difference - nothing to say, no inbox item.
        var entry = Self.savedEntry()
        let agreeing = GatewayExtraction(
            total: .init(value: entry.money!.amount, confidence: 0.9),
            volume: .init(value: entry.volumeL, confidence: 0.9),
            unitPrice: .init(value: entry.unitPrice!, confidence: 0.9),
            fuelKind: .init(value: entry.fuelKind, confidence: 0.9),
            currency: .init(value: entry.money!.currency, confidence: 0.9),
            pipeline: "test")
        _ = entry
        #expect(!GatewayInboxPolicy.shouldOffer(extraction: agreeing, entry: Self.savedEntry()))
    }

    // MARK: - The blank-fields-only fill set

    @Test("a nil unit price is fillable; a set one never is")
    func unitPriceFillBoundary() {
        #expect(GatewayInboxPolicy.fillableFields(
            extraction: Self.answer(), entry: Self.savedEntryBlankPrice()) == [.unitPrice])
        #expect(GatewayInboxPolicy.fillableFields(
            extraction: Self.answer(), entry: Self.savedEntry()).isEmpty,
            "a typed/derived price is the user's own - never fillable")
    }

    @Test("volume, date, fuel kind and currency are never blank on a saved fill-up")
    func nonOptionalFieldsNeverFillable() {
        let fillable = GatewayInboxPolicy.fillableFields(
            extraction: Self.answer(), entry: Self.savedEntryBlankPrice())
        #expect(!fillable.contains(.volume))
        #expect(!fillable.contains(.total))
        #expect(!fillable.contains(.date))
        #expect(!fillable.contains(.fuelKind))
        #expect(!fillable.contains(.currency))
    }

    // MARK: - The blank-fields-only merge

    @Test("the merge fills the blank price and leaves every other value byte-identical")
    func mergeFillsBlankPriceOnly() {
        let blank = Self.savedEntryBlankPrice()
        let merged = GatewayInboxPolicy.merged(entry: blank, extraction: Self.answer())

        #expect(merged.unitPrice == Decimal(string: "1.679")!,
                "the blank price fills from the receipt")
        #expect(merged.volumeL == blank.volumeL, "the typed litres are untouched")
        #expect(merged.money == blank.money, "the saved total is untouched")
        #expect(merged.fuelKind == blank.fuelKind, "the saved fuel kind is untouched")
        #expect(merged.date == blank.date, "the saved date is untouched")
        #expect(merged.id == blank.id, "the entry identity is preserved")
    }

    @Test("a value the user saved is never overwritten by an accepted re-read")
    func mergeNeverOverwritesASavedValue() {
        // The gateway says 99.99 / 55.00 / 1.679 - but the entry already holds
        // 71.02 / 42.30 / 1.679, so nothing moves.
        let original = Self.savedEntry()
        let merged = GatewayInboxPolicy.merged(entry: original, extraction: Self.answer())
        #expect(merged.volumeL == original.volumeL)
        #expect(merged.money == original.money)
        #expect(merged.unitPrice == original.unitPrice)
        #expect(merged.fuelKind == original.fuelKind)
        #expect(merged.date == original.date)
    }

    // MARK: - Clearing is the resolution's job, not the policy's

    @Test("the policy offers and fills but never clears - resolution clears")
    func policyDoesNotClear() {
        // The inbox store deletes the item on resolution; the policy only
        // decides offer/fill. Pinned so a future "clear in the policy" does not
        // resurrect a declined item.
        let blank = Self.savedEntryBlankPrice()
        let merged = GatewayInboxPolicy.merged(entry: blank, extraction: Self.answer())
        #expect(merged.unitPrice != nil)
    }
}
