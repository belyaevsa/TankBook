import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// PJ.28 L1 - a scanned Expense saves with its receipt photo attached, a manual
/// one never requires one, and a failed photo write never loses the expense.
/// The row's whole defect was silent data loss: the Expense-mode shutter read
/// the receipt and then threw the photograph away (`ExpenseEntryView` wrote
/// `attachments: []`). These tests pin the persistence contract of the save -
/// the `Attachment` row AND its file must both exist (either alone can pass
/// while the receipt is unreachable), the printed date must ride on
/// `extractedTimestamp`, and a write failure must leave the expense savable.
///
/// Lives in the app-target test bundle because the receipt write is app code
/// over UIKit (`VehiclePhotoStore`, `ReceiptAttachmentWriter`); the SwiftPM
/// core tests run on macOS where the app's Application Support attachments path
/// does not exist. Each test builds its own in-memory repository; the file
/// bytes land in the real attachments directory (as a fill-up's would) and are
/// removed after.
@MainActor
final class PJ28ExpenseReceiptTests: XCTestCase {

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

    /// The Expense the sheet's save writes (the same construction, reproduced
    /// so the persistence contract is pinned against the row, not against the
    /// view's private `save()` which no unit test can drive).
    private func makeExpense(vehicleId: UUID, attachments: [AttachmentID],
                             provenance: Provenance) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
            vehicleId: vehicleId, date: Date(), odometer: nil,
            money: Money(amount: Decimal(string: "71.02")!, currency: .eur,
                         homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: provenance,
            conflict: .none, purchaseGroupId: nil, category: .parts,
            title: "Wiper blades", recurrence: nil, installedInServiceId: nil)
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

    private func capture(extraction: FuelExtraction, image: UIImage = UIImage()) -> ExpenseScanCapture {
        ExpenseScanCapture(image: image, extraction: extraction,
                           ocrLines: [OCRLine(text: "WIPER BLADES 71.02")])
    }

    private func savedExpense(_ repository: TankbookRepository,
                              vehicleId: UUID) throws -> Expense? {
        try repository.liveExpenses(forVehicle: vehicleId).first
    }

    private func attachmentFileExists(_ attachment: Attachment) throws -> Bool {
        let directory = try VehiclePhotoStore.attachmentsDirectory()
        return FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(attachment.file.relativePath).path)
    }

    private func removeAttachmentFile(_ attachment: Attachment) {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(attachment.file.relativePath))
    }

    // MARK: - The scanned save keeps its receipt

    /// The row's whole point, at the persistence level: the Expense the save
    /// writes references the attachment id, the `Attachment` row exists, and
    /// the file the row points at exists on disk. Asserting only `attachments`
    /// (or only the row) would pass while the receipt is unreachable.
    func testScannedExpenseSavesWithItsReceiptAttachedAndReachable() throws {
        let (repository, vehicle) = try makeVehicle()
        let scan = capture(extraction: FuelExtraction(total: Decimal(string: "71.02")!,
                                                      currency: .eur,
                                                      date: "17.08.2026"),
                           image: photoImage())

        let id = try ExpenseReceiptWrite.write(scan: scan, repository: repository)
        let expense = makeExpense(vehicleId: vehicle.id, attachments: [id],
                                  provenance: .receiptScan)
        try repository.upsertExpense(expense)

        let saved = try XCTUnwrap(try savedExpense(repository, vehicleId: vehicle.id))
        XCTAssertEqual(saved.attachments, [id],
                       "the saved Expense must carry the receipt's attachment id")
        XCTAssertEqual(saved.provenance, .receiptScan,
                       "a scan is never a .manual arrival (docs/SCHEMA.md)")

        let attachments = try repository.liveAttachments()
        XCTAssertEqual(attachments.count, 1, "exactly one Attachment row must exist")
        let attachment = try XCTUnwrap(attachments.first)
        XCTAssertEqual(attachment.id, id)
        XCTAssertEqual(attachment.kind, .photo)
        XCTAssertFalse(attachment.file.relativePath.isEmpty,
                       "the Attachment row must name its file")
        XCTAssertTrue(try attachmentFileExists(attachment),
                      "the file the Attachment row references must exist on disk")
        defer { removeAttachmentFile(attachment) }

        XCTAssertEqual(attachment.ocrText, "WIPER BLADES 71.02",
                       "the raw OCR text rides the attachment for re-parsing (RV.48)")
    }

    /// The printed date is ground truth for the timeline priority rule
    /// (docs/SCHEMA.md -> PRIORITY): when the extraction read one it lands on
    /// `extractedTimestamp`, exactly as it does on a fill-up's receipt.
    func testExtractedTimestampIsCarriedWhenTheExtractionReadADate() throws {
        let (repository, _) = try makeVehicle()
        let scan = capture(extraction: FuelExtraction(total: Decimal(string: "71.02")!,
                                                      currency: .eur,
                                                      date: "17.08.2026"),
                           image: photoImage())

        let id = try ExpenseReceiptWrite.write(scan: scan, repository: repository)
        let attachment = try XCTUnwrap(try repository.liveAttachments().first)
        defer { removeAttachmentFile(attachment) }

        XCTAssertEqual(id, attachment.id)
        XCTAssertEqual(attachment.extractedTimestamp, ConfirmDate.parse("17.08.2026"),
                       "the receipt's printed date must ride on extractedTimestamp")
    }

    /// No readable date on the receipt -> a nil `extractedTimestamp`, never an
    /// invented one (hard rule 13: a blank is an honest absence).
    func testNoReadableDateLeavesExtractedTimestampNil() throws {
        let (repository, _) = try makeVehicle()
        let scan = capture(extraction: FuelExtraction(total: Decimal(string: "71.02")!,
                                                      currency: .eur),
                           image: photoImage())

        _ = try ExpenseReceiptWrite.write(scan: scan, repository: repository)
        let attachment = try XCTUnwrap(try repository.liveAttachments().first)
        defer { removeAttachmentFile(attachment) }

        XCTAssertNil(attachment.extractedTimestamp)
    }

    // MARK: - The typed door stays a peer

    /// A manual expense with no scan still saves - no attachment, no error
    /// (hard rule 15: the photo is a head start, never a requirement). The
    /// typed save never calls the receipt write, so no `Attachment` row can
    /// appear beside it.
    func testManualExpenseWithNoScanSavesWithoutAttachmentAndWithoutError() throws {
        let (repository, vehicle) = try makeVehicle()

        let expense = makeExpense(vehicleId: vehicle.id, attachments: [],
                                  provenance: .manual)
        XCTAssertNoThrow(try repository.upsertExpense(expense),
                         "a typed expense must save without any attachment work")

        let saved = try XCTUnwrap(try savedExpense(repository, vehicleId: vehicle.id))
        XCTAssertTrue(saved.attachments.isEmpty,
                      "a typed expense must carry no attachment id")
        XCTAssertEqual(saved.provenance, .manual)
        XCTAssertTrue(try repository.liveAttachments().isEmpty,
                      "a typed save must not leave an orphan Attachment row")
    }

    // MARK: - The capture is one-shot

    /// PJ.28's vacuous trap: a second open of the form must not re-attach a
    /// stale photo. The session's consume clears the staged capture, so the
    /// second read returns nil - the same one-shot discipline the pre-fill
    /// values follow (RV.62).
    func testTheCaptureIsConsumedSoASecondOpenAttachesNothing() {
        let session = ExpenseEntrySession()
        session.pendingCapture = capture(extraction: FuelExtraction(total: Decimal(string: "12.40")!,
                                                                    currency: .eur,
                                                                    date: "09.08.2026"))

        let first = session.consumePendingCapture()
        XCTAssertNotNil(first, "the staged capture must be delivered once")
        XCTAssertNil(session.pendingCapture, "consuming must clear the staged capture")
        XCTAssertNil(session.consumePendingCapture(),
                     "a second open of the form must not re-attach a stale photo")
    }

    // MARK: - A failed write loses neither the expense nor the silence

    /// A photo that cannot be encoded throws from the write seam BEFORE
    /// anything is persisted - no half-written `Attachment` row, no orphan
    /// file - and the expense still saves without it. The toast's copy names
    /// what happened and the next step (hard rules 7 and 8).
    func testAFailedImageWriteStillSavesTheExpenseAndNamesItsNextStep() throws {
        let (repository, vehicle) = try makeVehicle()
        // An empty UIImage has no CGImage, so `jpegData` returns nil and the
        // write fails exactly as a disk-full or unencodable frame would.
        let scan = capture(extraction: FuelExtraction(total: Decimal(string: "71.02")!,
                                                      currency: .eur,
                                                      date: "17.08.2026"))

        XCTAssertThrowsError(try ExpenseReceiptWrite.write(scan: scan,
                                                           repository: repository),
                             "an unencodable photo must throw, never silently pass")
        XCTAssertTrue(try repository.liveAttachments().isEmpty,
                      "a failed write must not leave a half-written Attachment row")

        // The save's degrade branch: the expense still goes to disk, without
        // the photo and without an error.
        let expense = makeExpense(vehicleId: vehicle.id, attachments: [],
                                  provenance: .receiptScan)
        XCTAssertNoThrow(try repository.upsertExpense(expense))
        let saved = try XCTUnwrap(try savedExpense(repository, vehicleId: vehicle.id))
        XCTAssertTrue(saved.attachments.isEmpty,
                      "the expense must save even though its photo could not")
        XCTAssertTrue(try repository.liveAttachments().isEmpty)

        // The surfaced message names what happened AND the next step - a toast
        // that only reported the loss would fail hard rule 7.
        let message = L10n.receiptNotSavedMessage
        XCTAssertTrue(message.contains("saved without it"),
                      "the message must say the entry was saved: \(message)")
        XCTAssertTrue(message.contains("Free up space"),
                      "the message must name its next step: \(message)")
    }
}
