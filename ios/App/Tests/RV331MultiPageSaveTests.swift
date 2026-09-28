import TankbookCore
import UIKit
import XCTest
@testable import Tankbook

/// RV.331: several pages added in one edit are all written, in order, each
/// appended to the entry; a page added to an entry that already has recorded
/// values never replaces them; and a lost page costs only itself.
@MainActor
final class RV331MultiPageSaveTests: XCTestCase {

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

    private func photo() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120)).image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }

    private func fillUp(vehicle: Vehicle, extraction: ExtractionMeta?) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .receiptScan, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: extraction)
    }

    func testEveryHeldPageIsAppendedInOrderAndTheRecordedValuesStay() throws {
        let (repository, vehicle) = try makeVehicle()
        let recorded = ExtractionMeta(fields: [:], pipeline: "the first photo's")
        let fill = fillUp(vehicle: vehicle, extraction: recorded)
        let pages = [HeldReceiptPhoto(image: photo(), ocrLines: [], extraction: FuelExtraction(liters: 1)),
                     HeldReceiptPhoto(image: photo(), ocrLines: [], extraction: FuelExtraction(liters: 2))]
        let saved = ScannedSaveValues(total: fill.money?.amount, volumeL: fill.volumeL,
                                      unitPrice: fill.unitPrice, currency: fill.money?.currency,
                                      fuelKind: fill.fuelKind, date: fill.date)

        let (toSave, outcomes) = EditEntryView.attachHeldReceiptsToFill(
            fill, saved: saved, heldPhotos: pages, repository: repository)

        XCTAssertEqual(outcomes.count, 2)
        XCTAssertEqual(toSave.attachments, outcomes.flatMap(\.sharedIDs),
                       "both pages are appended, in the order they were added")
        XCTAssertEqual(toSave.attachments.count, 2)
        XCTAssertEqual(toSave.extraction?.pipeline, "the first photo's",
                       "a page added later never replaces the entry's recorded values")
    }

    func testALostPageCostsOnlyItself() throws {
        let (repository, vehicle) = try makeVehicle()
        let now = Date()
        let service = ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: "Tireman", items: [], usedParts: [], tireSetId: nil)
        try repository.upsertServiceRecord(service)
        let form = EditEntryView.pristineNonFillForm(for: service, vehicle: vehicle)
        let pages = [HeldReceiptPhoto(image: photo(), ocrLines: [], extraction: nil),
                     HeldReceiptPhoto(image: UIImage(), ocrLines: [], extraction: nil),
                     HeldReceiptPhoto(image: photo(), ocrLines: [], extraction: nil)]

        let outcomes = try EditEntryView.writeNonFillWithHeldReceipts(
            service, vehicle: vehicle, form: form, otherEntries: [],
            heldPhotos: pages, repository: repository)

        XCTAssertEqual(outcomes.map(\.lostPhoto), [false, true, false])
        let stored = try XCTUnwrap(try repository.liveEntries(forVehicle: vehicle.id)
            .first { $0.id == service.id })
        XCTAssertEqual(stored.attachments.count, 2, "the two pages that landed are kept")
    }
}
