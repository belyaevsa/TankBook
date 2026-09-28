import Foundation
import Testing
@testable import TankbookCore

/// P3.3 TireSetDraft rules (docs/SCHEMA.md -> TireSet). The create/rename form
/// in pure form: a blank name refuses to save and names its next step; the
/// rename path keeps the set's identity and purchase link intact.
@Suite struct TireSetDraftTests {

    private static let vehicleId = UUID.v7()
    private static let setID = UUID.v7()

    @Test func aBlankNameIsNotReadyToSave() {
        #expect(TireSetDraft(name: "").readiness == .nameMissing)
        #expect(TireSetDraft(name: "   ").readiness == .nameMissing)
        #expect(TireSetDraft(name: "\n\t").readiness == .nameMissing)
    }

    @Test func aNonBlankNameIsReady() {
        #expect(TireSetDraft(name: "Winter Nokian").readiness == .ready)
    }

    @Test func buildProducesANewSetWithTheNameAndNoPurchaseLink() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let set = TireSetDraft(name: "Summer Michelin").build(vehicleId: Self.vehicleId, now: now)

        #expect(set.vehicleId == Self.vehicleId)
        #expect(set.name == "Summer Michelin")
        #expect(set.purchaseExpenseId == nil)
        #expect(set.createdAt == now)
        #expect(set.deletedAt == nil)
    }

    @Test func appliedRenamesInPlaceAndKeepsIdentityAndPurchaseLink() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let expenseID = UUID.v7()
        var existing = TireSet(
            id: Self.setID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: Self.vehicleId, name: "Winter Nokian", purchaseExpenseId: expenseID)

        let renamed = TireSetDraft(name: "Winter Continental").applied(to: existing,
                                                                       now: now.addingTimeInterval(1))

        #expect(renamed.id == Self.setID)
        #expect(renamed.name == "Winter Continental")
        #expect(renamed.purchaseExpenseId == expenseID,
                "a rename must never drop the P3.2 purchase link")
        #expect(renamed.createdAt == now)
        #expect(renamed.updatedAt == now.addingTimeInterval(1))
        #expect(renamed.deletedAt == nil)
    }

    // MARK: - The tires' properties

    @Test func thePropertiesSaveTrimmedAndParsed() {
        let set = TireSetDraft(name: "Winter", make: " Nokian ", model: "Hakkapeliitta 10",
                               size: "205/55 R16", productionWeek: "3624",
                               treadwear: "400", newTreadDepth: "9,5").build(vehicleId: Self.vehicleId)
        #expect(set.make == "Nokian")
        #expect(set.model == "Hakkapeliitta 10")
        #expect(set.size == "205/55 R16")
        #expect(set.productionWeek == "3624")
        #expect(set.treadwear == 400)
        #expect(set.newTreadDepthMm == 9.5, "a comma decimal is the Russian keyboard's, and it parses")
    }

    @Test func blankPropertiesAreNotGivenAndClearingOneClearsIt() {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        let existing = TireSet(
            id: Self.setID, createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: Self.vehicleId, name: "Winter", purchaseExpenseId: nil,
            make: "Nokian", treadwear: 400, newTreadDepthMm: 9)
        let cleared = TireSetDraft(name: "Winter").applied(to: existing, now: now)
        #expect(cleared.make == nil && cleared.treadwear == nil && cleared.newTreadDepthMm == nil)
        #expect(TireSetDraft(name: "Winter").readiness == .ready)
    }

    @Test func aTypedNumberThatDoesNotParseRefusesRatherThanDropping() {
        #expect(TireSetDraft(name: "Winter", treadwear: "four hundred").readiness == .treadwearInvalid)
        #expect(TireSetDraft(name: "Winter", treadwear: "0").readiness == .treadwearInvalid)
        #expect(TireSetDraft(name: "Winter", newTreadDepth: "9..5").readiness == .treadDepthInvalid)
        #expect(TireSetDraft(name: "Winter", newTreadDepth: "45").readiness == .treadDepthInvalid)
        // The name still comes first: it is the one thing a set cannot lack.
        #expect(TireSetDraft(name: "", treadwear: "x").readiness == .nameMissing)
    }

    // MARK: - The swap's condition reading

    @Test func aReadingIsBlankUntilSomethingIsTypedAndRefusesABadDepth() {
        #expect(TireReading.from(depth: "", note: "  ") == .blank)
        #expect(TireReading.from(depth: "6,5", note: "") == .value(TireReading(treadDepthMm: 6.5, note: nil)))
        #expect(TireReading.from(depth: "", note: " even wear ")
                == .value(TireReading(treadDepthMm: nil, note: "even wear")))
        #expect(TireReading.from(depth: "deep", note: "even wear") == .invalid)
    }

    @Test func aServiceRecordCarriesTheReadingOnlyWhenItMountsASet() {
        let reading = TireReading(treadDepthMm: 6.5)
        let date = Date(timeIntervalSince1970: 1_752_000_000)
        let swap = ServiceEntryDraft(items: [], date: date, odometer: 41_000, tireSetId: Self.setID,
                                     tireReading: reading).build(vehicleId: Self.vehicleId, homeCurrency: .eur)
        #expect(swap.tireReading == reading)
        let service = ServiceEntryDraft(items: [], date: date, odometer: 41_000,
                                        tireReading: reading).build(vehicleId: Self.vehicleId, homeCurrency: .eur)
        #expect(service.tireReading == nil)
    }
}
