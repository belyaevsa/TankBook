import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.149 L1 - a fill-up's receipt photo can fail to save and the user is never
/// told. The expense path (PJ.28) already reports that failure with a toast;
/// the fill-up path logged and dropped the photo silently (docs/ERRORS.md ->
/// Confirm, RV.149). These tests pin the degraded-save contract at the seam the
/// save actually runs (`attemptReceiptPhotoWrite`): a photo-write failure must
/// surface as `.lost` - the flag that drives the report - and must leave the
/// fill-up saveable without the photo (hard rule 1: the save never blocks, and
/// hard rule 8: nothing is lost silently). The toast itself is the L4 check;
/// asserting only that the entry saved is today's behaviour and the whole defect.
///
/// Lives in the app-target test bundle because the receipt write is app code
/// over UIKit (`VehiclePhotoStore`, the attachments path); the SwiftPM core
/// tests run on macOS where that path does not exist.
@MainActor
final class RV149FillUpReceiptSaveTests: XCTestCase {

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
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// The resolved scan the Confirm sheet would show for `-seedConfirmPrefill`:
    /// liters + price, the total deriving, with the photo a save would write.
    private func prefill(image: UIImage) -> ConfirmPrefill {
        ConfirmPrefill(
            extraction: FuelExtraction(liters: 42.30, unitPrice: 1.679,
                                       currency: .eur, fuelKind: .petrol95,
                                       date: "17.08.2026"),
            sourceImage: image)
    }

    private func scannedPlan(prefill: ConfirmPrefill) -> ScannedSavePlan {
        ScannedSavePlanner.plan(
            extraction: prefill.extraction,
            declaredProvenance: .receiptScan,
            hasPhoto: prefill.sourceImage != nil,
            saved: ScannedSaveValues(total: Decimal(string: "71.02")!,
                                     volumeL: 42.30,
                                     unitPrice: Decimal(string: "1.679")!,
                                     currency: .eur, fuelKind: .petrol95,
                                     date: ConfirmDate.parse("17.08.2026")))
    }

    /// A tiny renderable frame - a scanned photo's stand-in. Has a `CGImage`,
    /// so `jpegData` succeeds and the photo write completes.
    private func photoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
        return renderer.image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }

    private func removeAttachmentFile(_ attachment: Attachment) {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(attachment.file.relativePath))
    }

    // MARK: - A lost photo never loses the fill-up, and never the silence

    /// The row's whole defect at the seam the save runs: when the photo cannot
    /// be written (an unencodable frame throws exactly as a storage failure
    /// would), `attemptReceiptPhotoWrite` reports `.lost` - the flag that makes
    /// the save tell the user - and no half-written `Attachment` row or file is
    /// left behind. The oracle is the expense path's shipped behaviour at
    /// `ExpenseEntryView.save()`: the entry lands, `attachments` is empty, and
    /// the report fires (L4 asserts the toast itself).
    func testLostPhotoSurfacesTheReportFlagAndTheFillUpStillSaves() throws {
        let (repository, vehicle) = try makeVehicle()
        // An empty UIImage has no CGImage, so `jpegData` returns nil and the
        // write fails exactly as a disk-full or unencodable frame would.
        let prefill = prefill(image: UIImage())
        let plan = scannedPlan(prefill: prefill)
        let id = try XCTUnwrap(plan.attachmentID,
                               "a scanned save with a photo must plan a shared attachment id")

        let outcome = attemptReceiptPhotoWrite(scanned: plan, source: prefill,
                                               repository: repository)

        XCTAssertEqual(outcome, .lost(id),
                       "a photo-write failure must surface as .lost, never as a silent []")
        XCTAssertTrue(outcome.lostPhoto,
                      "the report flag must be set so the save tells the user")
        XCTAssertTrue(outcome.sharedIDs.isEmpty,
                      "a lost photo must reference no attachment id")

        XCTAssertTrue(try repository.liveAttachments().isEmpty,
                      "a failed write must not leave a half-written Attachment row")

        // The save's degrade branch (the view writes the same shape): the
        // fill-up still goes to disk, without the photo and without an error.
        let now = Date()
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: ConfirmDate.parse("17.08.2026")!,
            odometer: 118_930,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur,
                         homeCurrency: .eur),
            note: nil, attachments: outcome.sharedIDs, provenance: .receiptScan,
            conflict: .none, purchaseGroupId: nil, volumeL: 42.30,
            unitPrice: Decimal(string: "1.679"), fuelKind: .petrol95, fuelGrade: nil,
            isFull: false, tankLevelAfterPct: nil, stationId: nil,
            crossCheck: .verified, extraction: plan.extraction)
        XCTAssertNoThrow(try repository.upsertFillUp(fillUp),
                         "the fill-up must save even though its photo could not")
        let saved = try XCTUnwrap(try repository.liveEntries(forVehicle: vehicle.id).first)
        XCTAssertTrue(saved.attachments.isEmpty,
                      "the saved fill-up must carry no attachment id")
        XCTAssertTrue(try repository.liveAttachments().isEmpty)
    }

    // MARK: - A written photo keeps the fill-up's receipt reachable

    /// The happy side of the same seam: a renderable frame writes, the outcome
    /// is `.wrote(id)`, and the `Attachment` row AND its file both exist - the
    /// receipt a scanned fill-up promises is actually reachable, never a
    /// dangling id (the PJ.2 guarantee, pinned from the fill-up's own seam).
    func testWrittenPhotoOutcomeReferencesAReachableReceipt() throws {
        let (repository, _) = try makeVehicle()
        let prefill = prefill(image: photoImage())
        let plan = scannedPlan(prefill: prefill)
        let id = try XCTUnwrap(plan.attachmentID)

        let outcome = attemptReceiptPhotoWrite(scanned: plan, source: prefill,
                                               repository: repository)

        XCTAssertEqual(outcome, .wrote(id))
        XCTAssertFalse(outcome.lostPhoto)
        XCTAssertEqual(outcome.sharedIDs, [id],
                       "a written photo must be the id the fill-up references")

        let attachments = try repository.liveAttachments()
        XCTAssertEqual(attachments.count, 1, "exactly one Attachment row must exist")
        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(attachment.id, id)
        let directory = try VehiclePhotoStore.attachmentsDirectory()
        let fileExists = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(attachment.file.relativePath).path)
        XCTAssertTrue(fileExists, "the file the Attachment row references must exist on disk")
        removeAttachmentFile(attachment)
    }

    /// The typed path has no photo to write and nothing to report: `.nothingToWrite`,
    /// no flag, no attachment (hard rule 15 - the typed door is a peer).
    func testTypedPathHasNothingToWriteAndNothingToReport() throws {
        let (repository, _) = try makeVehicle()
        let prefill = ConfirmPrefill(extraction: nil)
        let plan = ScannedSavePlanner.plan(
            extraction: nil,
            hasPhoto: false,
            saved: ScannedSaveValues(total: Decimal(string: "71.02")!,
                                     volumeL: 42.30,
                                     unitPrice: Decimal(string: "1.679")!,
                                     currency: .eur, fuelKind: .petrol95,
                                     date: ConfirmDate.parse("17.08.2026")))
        XCTAssertNil(plan.attachmentID)

        let outcome = attemptReceiptPhotoWrite(scanned: plan, source: prefill,
                                               repository: repository)

        XCTAssertEqual(outcome, .nothingToWrite)
        XCTAssertFalse(outcome.lostPhoto)
        XCTAssertTrue(outcome.sharedIDs.isEmpty)
        XCTAssertTrue(try repository.liveAttachments().isEmpty,
                      "a typed save must not leave an orphan Attachment row")
    }
}
