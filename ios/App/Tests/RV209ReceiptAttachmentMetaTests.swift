import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.209 L1 - the two receipt `Attachment` row builders agree on the account of
/// what the scan read, and their one documented difference is pinned.
///
/// `writeReceiptPhoto` (the save-side builder, `ManualFillUpReceiptSave.swift`)
/// and `ReceiptAttachmentWriter.write` (the out-of-save builder,
/// `ReceiptAttachSupport.swift`) both call `VehiclePhotoStore.save` and both
/// build the row, but they build `extractionMeta` differently:
/// `extraction?.assignmentOnly` against `ScannedSavePlanner.assignment(from:)`.
/// The save-side builder is handed the save plan's full `ExtractionMeta`, so it
/// keeps the plan's provenance (crop rects, `userCorrected`, a QR-resolved
/// total); the out-of-save builder has only a raw `FuelExtraction`. The
/// documented decision (in the code at both sites) is that this difference is
/// deliberate and limited to provenance: the value-bearing account the
/// recognised page reads is identical for the same parse.
///
/// The tests drive BOTH real builders with the same `FuelExtraction` and compare
/// the stored/returned `ExtractionMeta`, so a divergent value account fails
/// here. The second test pins the documented provenance difference.
///
/// Lives in the app-target test bundle because the builders are app code over
/// UIKit (`VehiclePhotoStore`, the attachments path); the SwiftPM core tests run
/// on macOS where that path does not exist.
@MainActor
final class RV209ReceiptAttachmentMetaTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeRepository() throws -> TankbookRepository {
        try TankbookRepository(database: TankbookDatabase.inMemory())
    }

    private func extraction() -> FuelExtraction {
        FuelExtraction(liters: 42.30, unitPrice: Decimal(string: "1.679")!,
                       total: Decimal(string: "71.02")!, currency: .eur,
                       fuelKind: .petrol95, date: "17.08.2026",
                       stationName: "Circle K Sikupilli")
    }

    /// The `saved` values that make the plan's `userCorrected` all-false: the
    /// user left every proposal as it was.
    private func unchangedSaved(_ extraction: FuelExtraction) -> ScannedSaveValues {
        ScannedSaveValues(total: extraction.total, volumeL: extraction.liters,
                          unitPrice: extraction.unitPrice, currency: extraction.currency,
                          fuelKind: extraction.fuelKind,
                          date: extraction.date.flatMap { ConfirmDate.parse($0) },
                          stationName: extraction.stationName)
    }

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

    // MARK: - The same extraction through both doors

    /// The row's acceptance: the same `FuelExtraction` through the save builder
    /// and the out-of-save builder produces the SAME `extractionMeta`. Oracle:
    /// the two stored metas compared directly. Both builders are driven for
    /// real - the save builder through `writeReceiptPhoto`, the out-of-save
    /// builder through `ReceiptAttachmentWriter.write`.
    func testTheSameExtractionThroughBothBuildersYieldsTheSameStoredAssignment() throws {
        let repository = try makeRepository()
        let image = photoImage()
        let extraction = extraction()

        let outOfSave = try ReceiptAttachmentWriter.write(
            id: UUID.v7(), image: image, ocrLines: [], extraction: extraction)

        let plan = ScannedSavePlanner.plan(
            extraction: extraction,
            declaredProvenance: .manual,
            hasPhoto: true,
            saved: unchangedSaved(extraction))
        let id = try XCTUnwrap(plan.attachmentID)
        try writeReceiptPhoto(id: id, source: ConfirmPrefill(extraction: extraction,
                                                             sourceImage: image),
                              extraction: plan.extraction, repository: repository)
        let saveSide = try XCTUnwrap(repository.liveAttachments().first { $0.id == id })

        XCTAssertEqual(saveSide.extractionMeta, outOfSave.extractionMeta,
                       "the same extraction through both builders must record the same assignment")
        XCTAssertNotNil(saveSide.extractionMeta,
                        "a parse that resolved fields must store an assignment, not nil")

        for attachment in try repository.liveAttachments() { removeAttachmentFile(attachment) }
    }

    /// The documented difference, pinned: the save builder keeps the plan's
    /// provenance - the crop rect and the `userCorrected` comparison against the
    /// saved values - while the out-of-save builder, which has only a
    /// `FuelExtraction`, records the same value with default provenance. The
    /// value itself still agrees, so the recognised page cannot show two
    /// accounts of what was read.
    func testTheSaveBuilderCarriesProvenanceTheOutOfSaveBuilderCannot() throws {
        let repository = try makeRepository()
        let image = photoImage()
        let extraction = extraction()

        let outOfSave = try ReceiptAttachmentWriter.write(
            id: UUID.v7(), image: image, ocrLines: [], extraction: extraction)

        // The user corrected the total, and the plan carries the crop rect the
        // save-side builder alone can know.
        let corrected = ScannedSaveValues(total: Decimal(string: "70.00")!,
                                          volumeL: extraction.liters,
                                          unitPrice: extraction.unitPrice,
                                          currency: extraction.currency,
                                          fuelKind: extraction.fuelKind,
                                          date: extraction.date.flatMap { ConfirmDate.parse($0) },
                                          stationName: extraction.stationName)
        let crop = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1)
        let plan = ScannedSavePlanner.plan(
            extraction: extraction,
            cropRects: [.total: crop],
            declaredProvenance: .manual,
            hasPhoto: true,
            saved: corrected)
        let id = try XCTUnwrap(plan.attachmentID)
        try writeReceiptPhoto(id: id, source: ConfirmPrefill(extraction: extraction,
                                                             sourceImage: image),
                              extraction: plan.extraction, repository: repository)
        let saveSide = try XCTUnwrap(repository.liveAttachments().first { $0.id == id })

        let saveTotal = try XCTUnwrap(saveSide.extractionMeta?.fields[.total])
        let outTotal = try XCTUnwrap(outOfSave.extractionMeta?.fields[.total])
        XCTAssertEqual(saveTotal.value, outTotal.value,
                       "the value account must agree even where the provenance differs")
        XCTAssertEqual(saveTotal.cropRect, crop,
                       "the save builder keeps the plan's crop rect")
        XCTAssertNil(outTotal.cropRect,
                     "the out-of-save builder has no crop rect to record")
        XCTAssertTrue(saveTotal.userCorrected,
                      "the save builder compares against the values the user saved")
        XCTAssertFalse(outTotal.userCorrected,
                       "the out-of-save builder has no saved values to compare against")

        for attachment in try repository.liveAttachments() { removeAttachmentFile(attachment) }
    }
}
