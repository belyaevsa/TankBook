import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.204 L1 - the two entry kinds on Edit entry must obey ONE contract when a
/// photo write fails: the save the user asked for lands, the photo failure is
/// reported after it, and no entry is ever blocked. Before this row the fill-up
/// edit path blocked and warned in place (`attachFailedWarn`, the entry
/// unchanged - PJ.48's contract) while the non-fill path degraded (RV.202, the
/// entry saves without the photo - RV.149's contract). Same screen, same
/// gesture, same failure, two behaviours.
///
/// The tests drive the EXACT seams the two saves run
/// (`EditEntryView.attachHeldReceiptToFill` and
/// `EditEntryView.writeNonFillWithHeldReceipt`) with an in-memory repository and
/// read the stored rows back. The cross-kind assertion is the row's acceptance:
/// the two outcomes must be equal, so the pair cannot drift again.
///
/// Lives in the app-target test bundle because the receipt write is app code
/// over UIKit (`VehiclePhotoStore`, the attachments path); the SwiftPM core
/// tests run on macOS where that path does not exist.
@MainActor
final class RV204ReceiptDegradeParityTests: XCTestCase {

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

    private func fillUp(vehicle: Vehicle, attachments: [AttachmentID] = []) -> FillUp {
        let now = Date()
        return FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual, conflict: .none,
            purchaseGroupId: nil, volumeL: 42.30, unitPrice: Decimal(string: "1.679")!,
            fuelKind: .petrol95, fuelGrade: nil, isFull: true, tankLevelAfterPct: 100,
            stationId: nil, crossCheck: .verified, extraction: nil)
    }

    private func service(vehicle: Vehicle, attachments: [AttachmentID] = []) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: [
                ServiceItem(title: "Oil service", category: .oil,
                            cost: Money(amount: Decimal(string: "89.00")!,
                                        currency: .eur, homeCurrency: .eur))
            ], usedParts: [], tireSetId: nil)
    }

    /// A renderable frame: has a `CGImage`, so `jpegData` succeeds and the write
    /// lands.
    private func photoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
        return renderer.image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }

    private func saved(_ fill: FillUp) -> ScannedSaveValues {
        ScannedSaveValues(total: fill.money?.amount, volumeL: fill.volumeL,
                          unitPrice: fill.unitPrice, currency: fill.money?.currency,
                          fuelKind: fill.fuelKind, date: fill.date)
    }

    private func removeAttachmentFile(_ attachment: Attachment) {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(attachment.file.relativePath))
    }

    // MARK: - The same failure, the same outcome

    /// The row's whole point: an unencodable frame on EITHER entry kind yields
    /// `.lost` and the entry still saves without the photo. Oracle: the two
    /// outcomes compared to each other and the reloaded rows' empty attachment
    /// lists.
    func testAFailedPhotoWriteDegradesIdenticallyOnBothEntryKinds() throws {
        let (repository, vehicle) = try makeVehicle()
        let fill = fillUp(vehicle: vehicle)
        try repository.upsertFillUp(fill)
        let heldFill = HeldReceiptPhoto(image: UIImage(), ocrLines: [], extraction: nil)

        let (toSave, fillOutcome) = EditEntryView.attachHeldReceiptToFill(
            fill, saved: saved(fill), heldPhoto: heldFill, repository: repository)
        try repository.upsertFillUp(toSave)

        let record = service(vehicle: vehicle)
        try repository.upsertServiceRecord(record)
        let form = EditEntryView.pristineNonFillForm(for: record, vehicle: vehicle)
        let heldService = HeldReceiptPhoto(image: UIImage(), ocrLines: [], extraction: nil)
        let serviceOutcome = try EditEntryView.writeNonFillWithHeldReceipt(
            record, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: heldService, repository: repository)

        XCTAssertTrue(fillOutcome.lostPhoto,
                      "the fill-up edit must degrade, not block (RV.204)")
        XCTAssertTrue(serviceOutcome.lostPhoto)
        XCTAssertEqual(fillOutcome.sharedIDs, serviceOutcome.sharedIDs,
                       "both entry kinds must reference the SAME (empty) attachment list")
        XCTAssertTrue(try repository.liveAttachments().isEmpty,
                      "a failed write must not leave a half-written Attachment row")
        XCTAssertTrue(try XCTUnwrap(repository.liveFillUps(forVehicle: vehicle.id).first)
            .attachments.isEmpty,
                      "the fill-up must save without the photo it could not keep")
        XCTAssertTrue(try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
            .attachments.isEmpty,
                      "the service must save without the photo it could not keep")
    }

    /// The happy side: a renderable frame writes on both kinds, and the new id
    /// is APPENDED to the entry's existing list (RV.204's sibling decision),
    /// never a replace. Oracle: the stored list equals the pre-existing id plus
    /// the written one.
    func testAWrittenPhotoIsAppendedOnBothEntryKinds() throws {
        let (repository, vehicle) = try makeVehicle()
        let existingFillID = UUID.v7()
        let fill = fillUp(vehicle: vehicle, attachments: [existingFillID])
        try repository.upsertFillUp(fill)
        let heldFill = HeldReceiptPhoto(image: photoImage(), ocrLines: [], extraction: nil)

        let (toSave, fillOutcome) = EditEntryView.attachHeldReceiptToFill(
            fill, saved: saved(fill), heldPhoto: heldFill, repository: repository)
        try repository.upsertFillUp(toSave)

        let existingServiceID = UUID.v7()
        let record = service(vehicle: vehicle, attachments: [existingServiceID])
        try repository.upsertServiceRecord(record)
        let form = EditEntryView.pristineNonFillForm(for: record, vehicle: vehicle)
        let heldService = HeldReceiptPhoto(image: photoImage(), ocrLines: [], extraction: nil)
        let serviceOutcome = try EditEntryView.writeNonFillWithHeldReceipt(
            record, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: heldService, repository: repository)

        let fillID = try XCTUnwrap(fillOutcome.sharedIDs.first)
        let serviceID = try XCTUnwrap(serviceOutcome.sharedIDs.first)
        XCTAssertEqual(try XCTUnwrap(repository.liveFillUps(forVehicle: vehicle.id).first)
            .attachments, [existingFillID, fillID],
                       "a landed photo must be appended, never replace the existing list")
        XCTAssertEqual(try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
            .attachments, [existingServiceID, serviceID],
                       "a landed photo must be appended, never replace the existing list")

        for attachment in try repository.liveAttachments() {
            removeAttachmentFile(attachment)
        }
    }

    /// A typed fill-up edit with no held photo is a no-op on the receipt half:
    /// `.nothingToWrite`, the entry's own attachments untouched (hard rule 15 -
    /// the typed door is a peer, not a lesser one).
    func testNoHeldPhotoLeavesTheFillUpUntouched() throws {
        let (repository, vehicle) = try makeVehicle()
        let existing = UUID.v7()
        let fill = fillUp(vehicle: vehicle, attachments: [existing])
        try repository.upsertFillUp(fill)

        let (toSave, outcome) = EditEntryView.attachHeldReceiptToFill(
            fill, saved: saved(fill), heldPhoto: nil, repository: repository)

        XCTAssertEqual(outcome, .nothingToWrite)
        XCTAssertEqual(toSave.attachments, [existing])
        XCTAssertTrue(try repository.liveAttachments().isEmpty)
    }
}
