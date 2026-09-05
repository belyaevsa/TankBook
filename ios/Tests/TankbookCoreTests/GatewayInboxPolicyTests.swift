import Foundation
import Testing
@testable import TankbookCore

// RV.38 - the inbox decision (docs/JOURNEYS.md F4, amended); RV.45 the per-field
// ask (amended 2026-09-04). A late gateway answer no longer silently rewrites a
// saved entry; it lands in the inbox as a suggestion, and "leave it as it is" is
// the default. RV.45 replaced the blank-fields-only merge with a PER-FIELD one:
// the card lists every field the receipt read that differs from or fills what
// the user saved, and the user ticks per field what to take. This suite pins the
// decisions in core - what makes an item, what is offered, and what the per-field
// merge changes - so the inbox view and the sheet cannot disagree about the
// boundary. The model is `SyncSurfaceTests`: pin WHICH state, never "a thing
// happened".

@Suite("Gateway inbox policy (RV.38, RV.45)")
struct GatewayInboxPolicyTests {

    private static func answer() -> GatewayExtraction {
        GatewayExtraction(
            total: .init(value: Decimal(string: "99.99")!, confidence: 0.92),
            volume: .init(value: 55.00, confidence: 0.90),
            unitPrice: .init(value: Decimal(string: "1.500")!, confidence: 0.88),
            date: .init(value: "17.08.2026", confidence: 0.80),
            fuelKind: .init(value: .diesel, confidence: 0.70),
            currency: .init(value: .rub, confidence: 0.60),
            pipeline: "test"
        )
    }

    /// A saved fill-up as the typed path writes one: total + litres typed, price
    /// set, fuel kind petrol95, home currency eur.
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

    /// Asserts `merged` equals `original` with ONLY the change in `apply` made -
    /// every other field byte-identical (the RV.45 trap: a merge that overwrote
    /// everything would pass "the target changed" and fail here). `updatedAt` and
    /// `crossCheck` are legitimately recomputed by the merge, so they are copied
    /// from the result rather than asserted against the original.
    private func assertOnlyTickedFieldsChanged(
        merged: FillUp, original: FillUp, apply: (inout FillUp) -> Void
    ) {
        var expected = original
        apply(&expected)
        expected.updatedAt = merged.updatedAt
        expected.crossCheck = merged.crossCheck
        #expect(merged == expected)
    }

    // MARK: - What is offered (the decision set)

    @Test("a differing answer offers every differing field, each as .differs")
    func differingAnswerOffersEachField() {
        let offers = GatewayInboxPolicy.offers(extraction: Self.answer(), entry: Self.savedEntry())
        #expect(Set(offers.map(\.field)) == [.date, .fuelKind, .volume, .unitPrice, .total, .currency])
        #expect(offers.allSatisfy { $0.disposition == .differs },
                "against a fully-set entry every discrepancy replaces a value")
    }

    @Test("a blank price is offered as .fillsBlank, not .differs")
    func blankFieldIsAFillNotAReplace() {
        let offers = GatewayInboxPolicy.offers(extraction: Self.answer(), entry: Self.savedEntryBlankPrice())
        let price = offers.first { $0.field == .unitPrice }
        #expect(price?.disposition == .fillsBlank)
    }

    @Test("a field the receipt did not read is not offered")
    func unreadFieldIsNotOffered() {
        let extraction = GatewayExtraction(
            volume: .init(value: 55.00, confidence: 0.9),
            pipeline: "test")
        let offers = GatewayInboxPolicy.offers(extraction: extraction, entry: Self.savedEntry())
        #expect(Set(offers.map(\.field)) == [.volume])
        #expect(!offers.contains { $0.field == .date },
                "an unread date is absence, never a decision")
    }

    @Test("a field that matches is not offered as a choice at all")
    func matchingFieldIsNotOffered() {
        var entry = Self.savedEntry()
        let agreeing = GatewayExtraction(
            total: .init(value: entry.money!.amount, confidence: 0.9),
            volume: .init(value: entry.volumeL, confidence: 0.9),
            unitPrice: .init(value: entry.unitPrice!, confidence: 0.9),
            fuelKind: .init(value: entry.fuelKind, confidence: 0.9),
            currency: .init(value: entry.money!.currency, confidence: 0.9),
            pipeline: "test")
        _ = entry
        #expect(GatewayInboxPolicy.offers(extraction: agreeing, entry: Self.savedEntry()).isEmpty,
                "agreement is not a decision")
    }

    // MARK: - What makes an item

    @Test("a differing answer is an offer even when nothing is blank")
    func differingAnswerIsOffered() {
        #expect(GatewayInboxPolicy.shouldOffer(extraction: Self.answer(), entry: Self.savedEntry()))
    }

    @Test("a blank field is an offer even when the rest agrees")
    func blankFieldIsOffered() {
        let blank = Self.savedEntryBlankPrice()
        let extraction = GatewayExtraction(
            unitPrice: .init(value: Decimal(string: "1.500")!, confidence: 0.9),
            pipeline: "test")
        #expect(GatewayInboxPolicy.shouldOffer(extraction: extraction, entry: blank))
    }

    @Test("an answer that agrees and fills nothing is not an offer")
    func agreeingAnswerIsNotOffered() {
        let agreeing = GatewayExtraction(
            total: .init(value: Self.savedEntry().money!.amount, confidence: 0.9),
            volume: .init(value: Self.savedEntry().volumeL, confidence: 0.9),
            unitPrice: .init(value: Self.savedEntry().unitPrice!, confidence: 0.9),
            fuelKind: .init(value: Self.savedEntry().fuelKind, confidence: 0.9),
            currency: .init(value: Self.savedEntry().money!.currency, confidence: 0.9),
            pipeline: "test")
        #expect(!GatewayInboxPolicy.shouldOffer(extraction: agreeing, entry: Self.savedEntry()))
    }

    // MARK: - The per-field merge

    @Test("taking a blank field fills it and touches nothing else")
    func mergeFillsBlankOnly() {
        let blank = Self.savedEntryBlankPrice()
        let merged = GatewayInboxPolicy.merged(entry: blank, extraction: Self.answer(), taking: [.unitPrice])
        #expect(merged.unitPrice == Decimal(string: "1.500")!,
                "the blank price fills from the receipt")
        assertOnlyTickedFieldsChanged(merged: merged, original: blank) { $0.unitPrice = Decimal(string: "1.500")! }
    }

    @Test("taking a differing field replaces exactly that field")
    func mergeReplacesDifferingFieldOnly() {
        let original = Self.savedEntry()
        let merged = GatewayInboxPolicy.merged(entry: original, extraction: Self.answer(), taking: [.volume])
        #expect(merged.volumeL == 55.00, "the receipt's volume replaces the typed one")
        assertOnlyTickedFieldsChanged(merged: merged, original: original) { $0.volumeL = 55.00 }
    }

    @Test("taking several fields replaces each and nothing else")
    func mergeReplacesTickedFieldsOnly() {
        let original = Self.savedEntry()
        let merged = GatewayInboxPolicy.merged(
            entry: original, extraction: Self.answer(), taking: [.volume, .fuelKind, .total])
        #expect(merged.volumeL == 55.00)
        #expect(merged.fuelKind == .diesel)
        #expect(merged.money?.amount == Decimal(string: "99.99")!)
        assertOnlyTickedFieldsChanged(merged: merged, original: original) {
            $0.volumeL = 55.00
            $0.fuelKind = .diesel
            $0.money = original.money!.replacingAmount(Decimal(string: "99.99")!)
        }
    }

    @Test("taking nothing leaves the entry byte-identical")
    func mergeTakingNothingIsByteIdentical() {
        let original = Self.savedEntry()
        let merged = GatewayInboxPolicy.merged(entry: original, extraction: Self.answer(), taking: [])
        #expect(merged == original,
                "no tick means no change - updatedAt included, not just the data fields")
    }

    @Test("taking a ticked blank and a ticked differing field applies both")
    func mergeBlankAndDifferTogether() {
        let blank = Self.savedEntryBlankPrice()
        let merged = GatewayInboxPolicy.merged(
            entry: blank, extraction: Self.answer(), taking: [.unitPrice, .volume])
        #expect(merged.unitPrice == Decimal(string: "1.500")!)
        #expect(merged.volumeL == 55.00)
        assertOnlyTickedFieldsChanged(merged: merged, original: blank) {
            $0.unitPrice = Decimal(string: "1.500")!
            $0.volumeL = 55.00
        }
    }

    @Test("a ticked field the receipt did not read is a no-op")
    func mergeIgnoresUnreadField() {
        let original = Self.savedEntry()
        let volumeOnly = GatewayExtraction(volume: .init(value: 55.00, confidence: 0.9), pipeline: "test")
        let merged = GatewayInboxPolicy.merged(entry: original, extraction: volumeOnly, taking: [.volume, .date])
        #expect(merged.volumeL == 55.00, "the read field applies")
        assertOnlyTickedFieldsChanged(merged: merged, original: original) { $0.volumeL = 55.00 }
        #expect(merged.date == original.date, "an unread date ticked is not invented")
    }

    // MARK: - RV.64 which action is loud (the recommendation follows the ticks)

    @Test("zero ticks: leave-as-is is the recommended action")
    func zeroTicksRecommendsLeaveAsIs() {
        #expect(GatewayInboxPolicy.recommendedAction(tickedCount: 0) == .leaveAsIs,
                "nothing is decided yet, so leave-as-is stays the loud default (hard rule 13)")
    }

    @Test("one tick: the update becomes the recommended action")
    func oneTickRecommendsUpdate() {
        #expect(GatewayInboxPolicy.recommendedAction(tickedCount: 1) == .update,
                "a ticked field IS the user deciding - the update takes the loud treatment")
    }

    @Test("every further tick keeps the update recommended")
    func manyTicksKeepTheUpdateRecommended() {
        #expect(GatewayInboxPolicy.recommendedAction(tickedCount: 5) == .update,
                "two ticks are not less of a decision than one")
    }

    @Test("unticking the last field returns the recommendation to leave-as-is")
    func untickingTheLastFieldReturnsTheRecommendation() {
        #expect(GatewayInboxPolicy.recommendedAction(tickedCount: 1) == .update)
        #expect(GatewayInboxPolicy.recommendedAction(tickedCount: 0) == .leaveAsIs,
                "the state is symmetric - the last untick is the empty state again")
    }

    // MARK: - Clearing is the resolution's job, not the policy's

    @Test("the policy offers and fills but never clears - resolution clears")
    func policyDoesNotClear() {
        let blank = Self.savedEntryBlankPrice()
        let merged = GatewayInboxPolicy.merged(entry: blank, extraction: Self.answer(), taking: [.unitPrice])
        #expect(merged.unitPrice != nil)
    }
}
