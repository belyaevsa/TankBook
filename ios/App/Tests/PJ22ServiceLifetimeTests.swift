import Foundation
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.22 (SERVICE half) - the lifetime editor on a service line item and the
/// reminder it drives.
///
/// The row's acceptance: a line item's `lifetime` (km / months) is editable on
/// the Edit-entry item row, it reaches the stored `ServiceItem`, and setting or
/// changing it is what the post-save offer counts from. The core proposal logic
/// is exercised in `ReminderOfferTests`; this file drives the app write path
/// (`EditEntryView.writeNonFill`) and reads the stored row back, so a dropped
/// lifetime is caught as data loss.
///
/// Oracle: `docs/SCHEMA.md` -> `ServiceItem.lifetime`, and the record's own
/// values - never today.
@MainActor
final class PJ22ServiceLifetimeTests: XCTestCase {

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

    /// Setting a lifetime on a row with none reaches the stored item - the
    /// editor's field is the write. Oracle: the stored `ServiceItem.lifetime`.
    func testSettingALifetimeReachesTheStoredRecord() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Brake pads front", category: .brakes, cost: nil)
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertNil(form.items[0].lifetime)
        XCTAssertFalse(form.serviceLifetimeChanged)
        form.items[0].lifetime = ServiceItem.Lifetime(km: 30_000, months: 24)
        XCTAssertTrue(form.serviceLifetimeChanged,
                      "setting a lifetime is the edit the offer responds to")

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.lifetime, ServiceItem.Lifetime(km: 30_000, months: 24))
    }

    /// Clearing both halves clears the lifetime - the draft owns the value, so
    /// the stored one is not resurrected by the `original` fallback.
    func testClearingALifetimeClearsIt() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: nil,
                        partNumber: "MANN W 712/75",
                        lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        XCTAssertFalse(form.serviceLifetimeChanged, "an untouched load is not an edit")
        form.items[0].lifetime = nil
        XCTAssertTrue(form.serviceLifetimeChanged)

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)

        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertNil(stored.items.first?.lifetime, "clearing must clear, not resurrect")
        XCTAssertEqual(stored.items.first?.partNumber, "MANN W 712/75",
                       "clearing the lifetime must not drop partNumber (PJ.61 out of scope)")
    }

    /// A no-touch save does not read as a lifetime edit, so the post-save offer
    /// is not raised by an unrelated change.
    func testAnUnrelatedEditDoesNotCountAsALifetimeChange() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle, items: [
            ServiceItem(title: "Oil service", category: .oil, cost: nil,
                        lifetime: ServiceItem.Lifetime(km: 15_000, months: 12))
        ])
        try repository.upsertServiceRecord(original)

        var form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        form.vendor = "Bosch Service"
        XCTAssertFalse(form.serviceLifetimeChanged,
                       "a vendor edit is not a lifetime change")

        try EditEntryView.writeNonFill(original, vehicle: vehicle, form: form,
                                       otherEntries: [], repository: repository)
        let stored = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(stored.items.first?.lifetime, ServiceItem.Lifetime(km: 15_000, months: 12),
                       "the stored lifetime survives an unrelated edit")
    }
}
