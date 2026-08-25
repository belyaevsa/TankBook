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
}
