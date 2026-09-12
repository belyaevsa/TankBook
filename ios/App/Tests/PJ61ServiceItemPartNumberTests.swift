import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.61 - the service item editor gains an editable **part number**, the one
/// `ServiceItem` field the editor could not set (docs/SCHEMA.md -> ServiceItem,
/// "enables reorder and lifetime tracking").
///
/// The write path (`EditEntryView.writeNonFill`) is app code, so these tests
/// drive an in-memory repository and read the stored row back - a dropped part
/// number is data loss, not a form diff. The reload goes through
/// `pristineNonFillForm`, the same load the edit screen opens with, so a field
/// the save writes but the load loses is caught here too.
@MainActor
final class PJ61ServiceItemPartNumberTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

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

    private func service(vehicle: Vehicle, items: [ServiceItem]) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: nil, note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: items, usedParts: [], tireSetId: nil)
    }

    /// The row's acceptance: an item edited with a part number reaches the
    /// stored `ServiceItem` and loads back into the editor. Oracle: the stored
    /// `ServiceItem.partNumber`, read through the same load the screen uses.
    func testAnEditedPartNumberRoundTripsThroughSaveAndReload() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: nil)
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertNil(form.items[0].partNumber, "a stored item with no part number loads blank")
        form.items[0].partNumber = "MAHLE LA 123"
        XCTAssertNotEqual(form, EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle),
                          "typing a part number must read as an unsaved edit (hard rule 8)")

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.partNumber, "MAHLE LA 123",
                       "the edited part number must reach the stored ServiceRecord")

        let reloaded = EditEntryView.pristineNonFillForm(for: stored, vehicle: vehicle)
        XCTAssertEqual(reloaded.items.first?.partNumber, "MAHLE LA 123",
                       "the saved part number must load back into the editor")
    }

    /// The editor owns the value: clearing it clears the stored one rather than
    /// resurrecting it from the row it was loaded from.
    func testClearingAPartNumberClearsIt() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: nil,
                        partNumber: "MANN W 712/75")
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertEqual(form.items[0].partNumber, "MANN W 712/75")
        form.items[0].partNumber = nil

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertNil(stored.items.first?.partNumber, "clearing must clear, not resurrect")
    }

    /// A no-touch save keeps the stored part number, so an unrelated edit (a
    /// vendor, a title) cannot silently drop it.
    func testAnUnrelatedEditKeepsTheStoredPartNumber() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: nil,
                        partNumber: "MANN W 712/75")
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.vendor = "Bosch Service"
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.partNumber, "MANN W 712/75",
                       "the stored part number survives an unrelated edit")
    }

    /// A delete still does not shift a neighbour's part number onto a survivor
    /// (the PJ.23/RV.198 identity rule), now that the field is editable.
    func testDeletingAnItemDoesNotShiftItsPartNumberOntoTheSurvivor() throws {
        let (repository, vehicle) = try makeVehicle()
        let deleted = ServiceItem(title: "Oil service", category: .oil, cost: nil,
                                  partNumber: "MANN W 712/75")
        let survivor = ServiceItem(title: "Brake pads", category: .brakes, cost: nil)
        let original = service(vehicle: vehicle, items: [deleted, survivor])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.removeServiceItem(id: try XCTUnwrap(form.items.first).id)
        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items, [survivor],
                       "the survivor must not inherit the deleted row's partNumber")
    }
}
