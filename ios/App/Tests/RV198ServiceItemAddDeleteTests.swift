import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.198 - a service's line items can be ADDED and DELETED on Edit entry, not
/// only corrected.
///
/// PJ.23 made the items editable but edit-only; the product owner asked for the
/// two missing operations the same evening. The write path
/// (`EditEntryView.writeNonFill`) is app code, so these tests drive an in-memory
/// repository and read the stored row back - a dropped or shifted field is data
/// loss, not a form diff.
///
/// The load-bearing test here is
/// `testDeletingAnItemDoesNotShiftTheDeletedItemsFieldsOntoTheSurvivor`: before
/// RV.198 the save preserved each item's `partNumber`/`lifetime`/cost snapshot
/// from the item at the SAME ARRAY POSITION. That was harmless while no row could
/// be removed; once a delete shifts the survivors left, it hands a surviving row
/// a deleted neighbour's fields. The draft now preserves from the item it was
/// loaded from (`draft.original`), by identity.
///
/// Oracle for every field list: docs/SCHEMA.md -> ServiceItem (title, category,
/// cost, partNumber, lifetime) plus ServiceRecord's `usedParts`/`tireSetId`.
@MainActor
final class RV198ServiceItemAddDeleteTests: XCTestCase {

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

    private func service(vehicle: Vehicle, items: [ServiceItem],
                         usedParts: [UUID] = [], tireSetId: UUID? = nil) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: items, usedParts: usedParts,
            tireSetId: tireSetId, proposedReminderId: nil)
    }

    private func eur(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    // MARK: - L1: an added item reaches the stored record, every field

    /// Adding an item and saving stores it with title, category, cost,
    /// `partNumber` and `lifetime`, and leaves the record's existing items
    /// byte-identical. Oracle: docs/SCHEMA.md -> ServiceItem's field list.
    func testAddingAnItemAndSavingStoresEveryFieldAndLeavesTheExistingItemsUntouched() throws {
        let (repository, vehicle) = try makeVehicle()
        let existing = ServiceItem(title: "Oil service", category: .oil,
                                   cost: eur("89.00"), partNumber: "MANN W 712/75",
                                   lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        let original = service(vehicle: vehicle, items: [existing])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.addServiceItem()
        form.items[form.items.count - 1].title = "Cabin filter"
        form.items[form.items.count - 1].category = .filters
        form.items[form.items.count - 1].cost = "34.50"
        form.items[form.items.count - 1].partNumber = "MAHLE LA 123"
        form.items[form.items.count - 1].lifetime = ServiceItem.Lifetime(km: nil, months: 24)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.count, 2, "the added row must be stored beside the existing one")
        XCTAssertEqual(stored.items[0], existing, "the existing item must be untouched")
        let added = stored.items[1]
        XCTAssertEqual(added.title, "Cabin filter")
        XCTAssertEqual(added.category, .filters)
        XCTAssertEqual(added.cost, eur("34.50"))
        XCTAssertEqual(added.partNumber, "MAHLE LA 123")
        XCTAssertEqual(added.lifetime, ServiceItem.Lifetime(km: nil, months: 24))
    }

    // MARK: - L1: a delete removes exactly one row and preserves its neighbours

    /// Deleting the middle of three items leaves the other two untouched,
    /// including the `partNumber` and `lifetime` the edit screen never shows.
    /// The survivor is deliberately field-poor and the deleted row field-rich,
    /// with a foreign-currency snapshot: a positional preserve would shift all
    /// three onto the survivor. Oracle: docs/SCHEMA.md -> ServiceItem.
    func testDeletingAnItemRemovesExactlyThatOneAndKeepsTheSurvivorsOwnFields() throws {
        let (repository, vehicle) = try makeVehicle()
        let first = ServiceItem(title: "Oil service", category: .oil,
                                cost: eur("89.00"), partNumber: "P1",
                                lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        let deleted = ServiceItem(
            title: "Brake fluid", category: .brakes,
            cost: Money(amount: 100, currency: .pln, homeCurrency: .eur)
                .converted(using: RateSnapshot(rate: Decimal(string: "4.27")!,
                                               rateDate: Date(timeIntervalSince1970: 1_750_000_000),
                                               source: .ecb)),
            partNumber: "P2", lifetime: ServiceItem.Lifetime(km: 20_000, months: 24))
        let survivor = ServiceItem(title: "Brake pads", category: .brakes,
                                   cost: eur("59.00"))
        let original = service(vehicle: vehicle, items: [first, deleted, survivor])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.removeServiceItem(id: try XCTUnwrap(form.items.first { $0.title == "Brake fluid" }).id)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.count, 2, "exactly the deleted row is gone")
        XCTAssertEqual(stored.items[0], first, "the row before the delete is untouched")
        XCTAssertEqual(stored.items[1].title, survivor.title)
        XCTAssertNil(stored.items[1].partNumber,
                     "the survivor must keep its own (absent) partNumber, not the deleted row's")
        XCTAssertNil(stored.items[1].lifetime,
                     "the survivor must keep its own (absent) lifetime, not the deleted row's")
        XCTAssertEqual(stored.items[1].cost, survivor.cost,
                       "the survivor must keep its own cost pair, not the deleted row's PLN snapshot")
    }

    /// The named positional bug, isolated: the deleted row is first and carries
    /// a `partNumber`/`lifetime`; the survivor carries neither. Before RV.198
    /// the save indexed the originals by position, so the survivor inherited the
    /// deleted row's fields. Oracle: docs/SCHEMA.md -> ServiceItem.
    func testDeletingAnItemDoesNotShiftTheDeletedItemsFieldsOntoTheSurvivor() throws {
        let (repository, vehicle) = try makeVehicle()
        let deleted = ServiceItem(title: "Oil service", category: .oil,
                                  cost: eur("89.00"), partNumber: "MANN W 712/75",
                                  lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        let survivor = ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        let original = service(vehicle: vehicle, items: [deleted, survivor])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.removeServiceItem(id: try XCTUnwrap(form.items.first).id)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items, [survivor],
                       "the survivor must not inherit the deleted row's partNumber or lifetime")
    }

    // MARK: - L1: the dirty check sees an add and a delete

    /// Adding an item makes the form dirty, so the RV.31 discard guard and the
    /// save button both see it. A swipe-back must not lose it (hard rule 8).
    func testAddingAnItemMarksTheFormDirty() throws {
        let (_, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00"))
        ])
        let pristine = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        var form = pristine
        form.addServiceItem()
        XCTAssertNotEqual(form, pristine, "an added item must read as an unsaved edit")
    }

    /// Deleting an item makes the form dirty, so the discard guard and the save
    /// button both see it (hard rule 8).
    func testDeletingAnItemMarksTheFormDirty() throws {
        let (_, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00")),
            ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        ])
        let pristine = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        var form = pristine
        form.removeServiceItem(id: try XCTUnwrap(form.items.first).id)
        XCTAssertNotEqual(form, pristine, "a deleted item must read as an unsaved edit")
    }

    // MARK: - L1: the empty-list decision, asserted directly

    /// Deleting the last item is LEGAL: a service may be a vendor + a lump-sum
    /// Amount with no itemised lines, and the record already round-trips an
    /// empty item list. The delete leaves `money`, `usedParts` and `tireSetId`
    /// untouched - only the items move.
    func testDeletingTheLastItemStoresAnEmptyListAndLeavesTheRecordIntact() throws {
        let (repository, vehicle) = try makeVehicle()
        let partID = UUID.v7()
        let setID = UUID.v7()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00"))
        ], usedParts: [partID], tireSetId: setID)
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.removeServiceItem(id: try XCTUnwrap(form.items.first).id)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertTrue(stored.items.isEmpty, "an empty item list is legal and must store empty")
        XCTAssertEqual(stored.money, original.money, "deleting an item must not touch the Amount")
        XCTAssertEqual(stored.usedParts, [partID])
        XCTAssertEqual(stored.tireSetId, setID)
    }

    // MARK: - L1: the links survive a delete of an unrelated item

    /// `usedParts` (Expense ids) and `tireSetId` (a TireSet id) do not point at
    /// ServiceItems, so deleting an item cannot orphan them. Oracle:
    /// docs/SCHEMA.md -> ServiceRecord.usedParts / tireSetId.
    func testUsedPartsAndTireSetIdSurviveDeletingAnUnrelatedItem() throws {
        let (repository, vehicle) = try makeVehicle()
        let partID = UUID.v7()
        let setID = UUID.v7()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: eur("89.00")),
            ServiceItem(title: "Brake pads", category: .brakes, cost: eur("59.00"))
        ], usedParts: [partID], tireSetId: setID)
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.removeServiceItem(id: try XCTUnwrap(form.items.first).id)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.map(\.title), ["Brake pads"])
        XCTAssertEqual(stored.usedParts, [partID], "the part link must survive an item delete")
        XCTAssertEqual(stored.tireSetId, setID, "the mounted tire set must survive an item delete")
    }
}
