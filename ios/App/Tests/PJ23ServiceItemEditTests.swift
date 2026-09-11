import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.23 (SERVICE half) - Edit entry must show and edit a service's LINE ITEMS,
/// not just its Vendor.
///
/// The row's acceptance, verbatim: `.other("x") -> .oil` keeps title, cost,
/// attachments, links. `ServiceCategory.other(String)` is the schema's escape
/// hatch for an unknown category, and J7 promises it is promoted later without
/// data loss - so the promotion test asserts EVERY `ServiceItem` field
/// (docs/SCHEMA.md: title, category, cost, partNumber, lifetime), not the two
/// the edit changes. An imported service gets its items from the source file's
/// kind column - the importer's guess - so hard rule 13 requires them editable
/// "at the moment it is offered and again afterwards".
///
/// Lives in the app-target test bundle because the write path
/// (`EditEntryView.writeNonFill`) is app code; it drives an in-memory
/// repository and reads the stored row back, so a dropped field is caught as
/// data loss rather than as a diff in a form.
@MainActor
final class PJ23ServiceItemEditTests: XCTestCase {

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
                         attachments: [AttachmentID] = [],
                         usedParts: [UUID] = []) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: items, usedParts: usedParts,
            tireSetId: nil)
    }

    // MARK: - The form loads the stored items

    /// A service's items are loaded as editable defaults (hard rule 13). Before
    /// PJ.23 the form carried none at all, so an imported service opened to a
    /// Vendor field and nothing else.
    func testTheFormLoadsTheStoredItems() throws {
        let (_, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Замена масла", category: .other("масло"),
                        cost: Money(amount: 89, currency: .eur, homeCurrency: .eur),
                        partNumber: "MANN W 712/75",
                        lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        ])

        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertEqual(form.items.count, 1)
        XCTAssertEqual(form.items.first?.title, "Замена масла")
        XCTAssertEqual(form.items.first?.category, .other("масло"))
        XCTAssertEqual(form.items.first?.cost, "89.00")
        XCTAssertEqual(form.items.first?.partNumber, "MANN W 712/75")
        XCTAssertEqual(form.items.first?.lifetime, ServiceItem.Lifetime(km: 15_000, months: 12))
    }

    // MARK: - L1: the row's own acceptance

    /// The acceptance sentence: `.other("x") -> .oil` keeps title, cost,
    /// attachments and links. Oracle: docs/SCHEMA.md -> ServiceItem's field
    /// list - assert every field, not the two that changed.
    func testPromotingACategoryKeepsEveryItemFieldAndTheRecordsLinks() throws {
        let (repository, vehicle) = try makeVehicle()
        let attachmentID = UUID.v7()
        let partID = UUID.v7()
        let original = service(
            vehicle: vehicle,
            items: [ServiceItem(title: "Замена масла", category: .other("масло"),
                                cost: Money(amount: 89, currency: .eur, homeCurrency: .eur),
                                partNumber: "MANN W 712/75",
                                lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))],
            attachments: [attachmentID], usedParts: [partID])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.items[0].category = .oil
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        let item = try XCTUnwrap(stored.items.first)
        XCTAssertEqual(item.title, "Замена масла", "the promotion must keep the title")
        XCTAssertEqual(item.category, .oil, "the promotion must change the category")
        XCTAssertEqual(item.cost, original.items[0].cost, "the promotion must keep the cost pair")
        XCTAssertEqual(item.partNumber, "MANN W 712/75", "partNumber must survive the save")
        XCTAssertEqual(item.lifetime, ServiceItem.Lifetime(km: 15_000, months: 12),
                       "lifetime must survive the save (PJ.22/PJ.26 depend on it)")
        XCTAssertEqual(stored.attachments, [attachmentID], "the record keeps its attachments")
        XCTAssertEqual(stored.usedParts, [partID], "the record keeps its links")
    }

    // MARK: - L1: the edit reaches the stored record (the named mutation target)

    /// An edited item title must reach the stored `ServiceRecord`. On the code
    /// before PJ.23 `saveNonFill`'s service arm wrote only `vendor`, so this
    /// fails there - deleting the `service.items = ...` assignment reproduces
    /// that state exactly.
    func testAnEditedItemTitleReachesTheStoredServiceRecord() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil,
                        cost: Money(amount: 89, currency: .eur, homeCurrency: .eur))
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.items[0].title = "Oil service and filter"
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.title, "Oil service and filter",
                       "the edited title must reach the stored ServiceRecord")
    }

    // MARK: - L1: the discard baseline sees the items (the RV.195 twin)

    /// Changing an item makes the form dirty, so the discard guard and the save
    /// button both see it. A field the save writes but the dirty check ignores
    /// would lose the edit on a swipe-back (hard rule 8). The baseline loads
    /// fresh synthetic ids, so equality must ignore them - otherwise the screen
    /// opens already dirty.
    func testChangingAnItemMarksTheFormDirty() throws {
        let (_, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil,
                        cost: Money(amount: 89, currency: .eur, homeCurrency: .eur))
        ])
        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertEqual(form, EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle),
                       "two loads of the same untouched record must compare equal")

        form.items[0].title = "Oil service and filter"
        XCTAssertNotEqual(form, EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle),
                          "a changed item must read as an unsaved edit")
    }

    // MARK: - L1: a service with no items

    /// A service with no items renders without crashing and saves unchanged -
    /// nothing is invented for an empty list, and no phantom row is written.
    func testAServiceWithNoItemsLoadsAndSavesUnchanged() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [])
        try repository.upsertServiceRecord(original)

        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertTrue(form.items.isEmpty)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertTrue(stored.items.isEmpty)
        XCTAssertNil(stored.vendor)
    }

    // MARK: - L1: the cost pair is not restated on a no-touch save

    /// An untouched foreign-currency cost keeps its snapshot byte-identical
    /// (hard rule 3): editing the title must not re-convert a written rate. The
    /// draft holds the amount as text, so this pins that the conversion is
    /// preserved rather than rebuilt from the typed digits.
    func testAnUntouchedForeignCostKeepsItsSnapshot() throws {
        let (repository, vehicle) = try makeVehicle()
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        let cost = Money(amount: 100, currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: Decimal(string: "4.27")!,
                                           rateDate: day, source: .ecb))
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: cost)
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.items[0].title = "Oil service and filter"
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.cost, cost,
                       "a no-touch foreign cost must keep its rate snapshot (hard rule 3)")
    }
}
