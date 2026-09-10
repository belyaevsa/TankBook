import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.199 - a service's total and its line items must agree, or say why they do
/// not.
///
/// The decision the row records: the edit screen's Amount stays INDEPENDENTLY
/// editable (an invoice's grand total legitimately differs from its lines -
/// tax, a discount, an un-itemised line; hard rule 4's truth for fuel, hard
/// rule 13 for a user's value), and the screen STATES the line sum beside it
/// whenever the two disagree. The sum is computed by the ONE shared function
/// the create screen's header also uses, so the two doors cannot drift
/// ([RV.169]'s complaint). This suite pins the sum, the independent Amount, the
/// mismatch in both directions, and the mixed-currency refusal.
///
/// Oracle for every figure: the items' own exact `Decimal` costs
/// (docs/SCHEMA.md -> Money, ServiceItem) - never a `Double`.
@MainActor
final class RV199ServiceLineSumTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixtures

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_579)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    private func eur(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    private func usd(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .usd, homeCurrency: .eur)
    }

    private func service(vehicle: Vehicle, money: Money, items: [ServiceItem]) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: money, note: nil, attachments: [], provenance: .manual,
            conflict: .none, purchaseGroupId: nil, vendor: nil, items: items,
            usedParts: [], tireSetId: nil, proposedReminderId: nil)
    }

    /// A create-path draft: a fresh typed row (no stored original), whose cost
    /// the save path would place in the vehicle's home currency.
    private func typedDraft(_ cost: String) -> ServiceEntryItemDraft {
        ServiceEntryItemDraft(title: "Item", category: .other(""), cost: cost)
    }

    // MARK: - L1: the sum reflects an added item (the mutation's target)

    /// Add a line and the sum grows by exactly that line's `Decimal` cost. The
    /// oracle is the items' own exact costs, summed - not a `Double`, and not a
    /// presence check: the mutation `dropLast()` (ignore the newest item) must
    /// turn this red.
    func testLineSumReflectsAnAddedItem() {
        var form = EditEntryNonFillForm()
        form.currency = .eur
        form.addServiceItem()
        form.items[0].cost = "89.00"

        let first = Decimal(string: "89.00")!
        XCTAssertEqual(form.lineSum(homeCurrency: .eur).summedAmount, first)

        form.addServiceItem()
        form.items[1].cost = "59.00"

        let oracle = Decimal(string: "89.00")! + Decimal(string: "59.00")!
        XCTAssertEqual(oracle, Decimal(string: "148.00")!)
        XCTAssertEqual(form.lineSum(homeCurrency: .eur).summedAmount, oracle,
                       "the sum must include the newest item, exactly")
    }

    // MARK: - L1: the stored Amount is unchanged by an item edit (hard rule 13)

    /// Editing a line item must not rewrite the record's `money`. The form's
    /// Amount string is untouched, and the save writes the stored pair
    /// byte-identical - the half a careless "derive the total" implementation
    /// gets wrong. The fixture's total deliberately differs from its lines.
    func testEditingAnItemDoesNotChangeTheStoredAmount() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, money: eur("160.00"), items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00")),
            ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        let loadedAmount = form.amount
        form.items[0].cost = "99.00"

        XCTAssertEqual(form.amount, loadedAmount,
                       "editing a line must not move the Amount field")

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.money, original.money,
                       "the stored Amount is the user's value and must survive an item edit")
        XCTAssertEqual(stored.items[0].cost, eur("99.00"),
                       "the edited line itself must be written")
    }

    // MARK: - L1: the mismatch state, both directions

    /// The mismatch appears when the Amount and the line sum differ and is
    /// absent when they agree - asserted in BOTH directions, so half the rule
    /// cannot pass untested. A currency difference alone is a disagreement even
    /// when the digits match.
    func testMismatchAppearsWhenTheyDifferAndIsAbsentWhenTheyAgree() {
        var form = EditEntryNonFillForm()
        form.currency = .eur
        form.amount = "148.00"
        form.addServiceItem()
        form.items[0].cost = "89.00"
        form.addServiceItem()
        form.items[1].cost = "59.00"

        XCTAssertFalse(form.lineSumDiffersFromAmount(homeCurrency: .eur),
                       "148.00 against 89.00 + 59.00 agrees")

        form.amount = "160.00"
        XCTAssertTrue(form.lineSumDiffersFromAmount(homeCurrency: .eur),
                      "160.00 against 148.00 differs")

        form.amount = "148.00"
        XCTAssertFalse(form.lineSumDiffersFromAmount(homeCurrency: .eur),
                       "matching the sum again must clear the mismatch")

        form.currency = .usd
        XCTAssertTrue(form.lineSumDiffersFromAmount(homeCurrency: .eur),
                      "148.00 USD against 148.00 EUR is still a disagreement")
    }

    /// With no costed item there is nothing to compare, so no mismatch is
    /// stated - the Amount is free to stand alone.
    func testNoMismatchWhenNoItemCarriesACost() {
        var form = EditEntryNonFillForm()
        form.currency = .eur
        form.amount = "50.00"
        form.addServiceItem()
        XCTAssertFalse(form.lineSumDiffersFromAmount(homeCurrency: .eur))
    }

    // MARK: - L1: a mixed-currency set states no summed total (hard rule 3)

    /// Two currencies have no common quantity, so the set is `.mixed` and
    /// `summedAmount` is nil - a renderer must state the per-currency breakdown,
    /// never a summed cross-currency figure (hard rule 3, the RV.145 rule).
    func testMixedCurrencyItemsProduceNoSummedTotal() {
        var form = EditEntryNonFillForm()
        form.currency = .eur
        form.amount = "148.00"
        form.items = [
            ServiceEntryItemDraft(from: ServiceItem(title: "Oil", category: .oil,
                                                    cost: eur("89.00"))),
            ServiceEntryItemDraft(from: ServiceItem(title: "Pads", category: .brakes,
                                                    cost: usd("59.00")))
        ]

        let sum = form.lineSum(homeCurrency: .eur)
        XCTAssertNil(sum.summedAmount,
                     "a mixed-currency set must never produce a summed total")
        guard case .mixed(let subtotals) = sum else {
            return XCTFail("expected .mixed, got \(sum)")
        }
        XCTAssertEqual(subtotals.count, 2)
        XCTAssertEqual(subtotals.first { $0.currency == .eur }?.amount, Decimal(string: "89.00"))
        XCTAssertEqual(subtotals.first { $0.currency == .usd }?.amount, Decimal(string: "59.00"))
        XCTAssertTrue(form.lineSumDiffersFromAmount(homeCurrency: .eur),
                      "no single line total can match the single Amount")
    }

    // MARK: - L1: create and edit state the SAME sum, asserted from both paths

    /// The create screen's header and the edit screen's money card must derive
    /// the same figure for the same items - the whole point of the ONE shared
    /// summation. Both directions are driven: the create `ServiceEntryFormState`
    /// and the edit form loaded through `pristineNonFillForm`.
    func testCreateAndEditProduceTheSameSumForTheSameItems() throws {
        let (_, vehicle) = try makeVehicle()
        let items = [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00")),
            ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        ]
        let original = service(vehicle: vehicle, money: eur("148.00"), items: items)

        var createForm = ServiceEntryFormState()
        createForm.items = [typedDraft("89.00"), typedDraft("59.00")]

        let editForm = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)

        let oracle = Decimal(string: "89.00")! + Decimal(string: "59.00")!
        let createSum = createForm.lineSum(homeCurrency: .eur)
        let editSum = editForm.lineSum(homeCurrency: .eur)
        XCTAssertEqual(createSum, editSum, "the two doors must state the same sum")
        XCTAssertEqual(createSum.summedAmount, oracle)
        XCTAssertEqual(editSum.summedAmount, oracle)

        // The create path's DISPLAY sum and its SAVE money come from the same
        // function too, so the header cannot promise a figure the record does
        // not store.
        let built = createForm.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        XCTAssertEqual(built.money?.amount, createSum.summedAmount,
                       "the derived header must equal the saved amount")
    }

    // MARK: - L1: an existing differing total is not rewritten on open

    /// Opening a service whose stored total differs from its lines leaves both
    /// figures as they were - the stored Amount is not derived away (hard rule
    /// 13) and the mismatch is what tells the user.
    func testOpeningADifferingServiceDoesNotRewriteTheStoredAmount() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, money: eur("160.00"), items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00")),
            ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        ])
        try repository.upsertServiceRecord(original)

        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertEqual(form.amountDecimal, Decimal(string: "160.00"))
        XCTAssertEqual(form.lineSum(homeCurrency: .eur).summedAmount, Decimal(string: "148.00"))
        XCTAssertTrue(form.lineSumDiffersFromAmount(homeCurrency: .eur))

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.money, eur("160.00"),
                       "opening the screen must not rewrite the stored total")
    }
}
