import Foundation
import Testing
@testable import TankbookCore

/// The `.parts` Expense -> TireSet link (docs/SCHEMA.md -> TireSet, docs/JOURNEYS.md
/// J7b "a tire purchase becomes a TireSet"). The pure decision in
/// `TireSetPurchase` plus the persistence round trip that proves the link is by
/// id, not by the expense's words.
@Suite struct TireSetPurchaseTests {

    private func makeVehicle() -> Vehicle {
        let timestamp = Date(timeIntervalSince1970: 1_752_000_000)
        return Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
    }

    private func makeExpense(vehicleId: UUID, category: ExpenseCategory,
                             title: String) -> Expense {
        let now = Date(timeIntervalSince1970: 1_752_000_000)
        return Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicleId, date: now, odometer: nil,
            money: Money(amount: Decimal(520), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: category, title: title,
            recurrence: nil, installedInServiceId: nil)
    }

    // MARK: - The link is written

    /// Oracle: `SCHEMA.md` -> TireSet `purchaseExpenseId` is "the
    /// Expense(.parts) that bought them". A `.parts` expense becomes a set whose
    /// name is the expense's words and whose purchase link is the expense's id.
    @Test func partsExpenseBecomesALinkedSet() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .parts,
                                  title: "Winter Nokian")

        let set = TireSetPurchase.makeSet(for: expense, existing: [])

        #expect(set != nil)
        #expect(set?.purchaseExpenseId == expense.id,
                "the purchase link is the deliverable, not the button")
        #expect(set?.name == "Winter Nokian")
        #expect(set?.vehicleId == vehicle.id)
        #expect(set?.deletedAt == nil)
    }

    /// Only `.parts` buys a set: every other category is a cost with no object
    /// to mount, so it makes none (docs/SCHEMA.md -> Expense.category).
    @Test func nonPartsExpenseMakesNoSet() {
        let vehicle = makeVehicle()
        for category: ExpenseCategory in [.insurance, .tax, .parking, .toll,
                                          .fine, .accessory, .other("wash")] {
            let expense = makeExpense(vehicleId: vehicle.id, category: category,
                                      title: "Cost")
            #expect(TireSetPurchase.makeSet(for: expense, existing: []) == nil,
                    "\(category) is not a tire purchase")
        }
    }

    @Test func aBlankTitleCannotNameASet() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .parts, title: "   ")
        #expect(TireSetPurchase.makeSet(for: expense, existing: []) == nil,
                "a set with no name violates TireSetDraft's own invariant")
    }

    // MARK: - Written once

    /// The second "make this a tire set" on the same expense does NOT mint a
    /// second set; it resolves to the one already linked.
    @Test func aSecondMakeDoesNotMintASecondSet() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .parts,
                                  title: "Winter Nokian")
        let first = TireSetPurchase.makeSet(for: expense, existing: [])
        #expect(first != nil)

        let second = TireSetPurchase.makeSet(for: expense, existing: [first!])

        #expect(second == nil, "one purchase, one set")
        #expect(TireSetPurchase.linkedSet(forExpense: expense.id, in: [first!]) == first)
    }

    /// A tombstoned set does not block re-making one from the same purchase -
    /// archiving is put-away, not a permanent claim on the expense (hard rule 8).
    @Test func anArchivedSetDoesNotBlockARemake() {
        let vehicle = makeVehicle()
        let expense = makeExpense(vehicleId: vehicle.id, category: .parts,
                                  title: "Winter Nokian")
        var archived = TireSetPurchase.makeSet(for: expense, existing: [])!
        archived.deletedAt = Date()

        #expect(TireSetPurchase.makeSet(for: expense, existing: [archived]) != nil)
    }

    // MARK: - The link survives an edit

    /// The L1 the defect named: the set still carries `purchaseExpenseId` after
    /// the expense is edited. The link is an id, never derived from the title,
    /// so renaming the expense does not orphan the set.
    @Test func theLinkSurvivesAnExpenseEdit() throws {
        let repository = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = makeVehicle()
        try repository.upsertVehicle(vehicle)
        let expense = makeExpense(vehicleId: vehicle.id, category: .parts,
                                  title: "Winter Nokian")
        try repository.upsertExpense(expense)
        let set = TireSetPurchase.makeSet(for: expense, existing: [])!
        try repository.upsertTireSet(set)

        var edited = expense
        edited.title = "Winter tyres (renamed)"
        edited.updatedAt = Date(timeIntervalSince1970: 1_752_000_100)
        try repository.upsertExpense(edited)

        let readBack = try repository.liveTireSets(forVehicle: vehicle.id)
        #expect(readBack.count == 1)
        #expect(readBack[0].purchaseExpenseId == expense.id,
                "the purchase link is by id - editing the expense must not drop it")
    }
}
