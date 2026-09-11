import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.202 - a service or an expense can be GIVEN a receipt, not only shown one.
///
/// Before this row the non-fill edit form rendered the shared receipt card only
/// when the entry already had an attachment, so an entry that arrived without a
/// photo had no "Add receipt" affordance at all (docs/ERRORS.md -> Edit entry).
/// These tests drive the EXACT repository seam `saveNonFill` performs
/// (`writeNonFillWithHeldReceipt`) with an in-memory repository and read the
/// stored row back, so "the photo was attached" means the reloaded record
/// carries the `Attachment` id - never that a button rendered.
///
/// The failure half is RV.149's rule one entry kind over: a photo write can
/// fail, and the entry must still save while the failure surfaces as `.lost` -
/// the flag the save reports through `reportLostReceiptPhoto` after the entry is
/// on disk. Asserting only that the entry saved is today's (silent) behaviour
/// and is exactly the defect.
///
/// Lives in the app-target test bundle because the receipt write is app code
/// over UIKit (`VehiclePhotoStore`, the attachments path); the SwiftPM core
/// tests run on macOS where that path does not exist.
@MainActor
final class RV202NonFillReceiptAttachTests: XCTestCase {

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

    private func service(vehicle: Vehicle) -> ServiceRecord {
        let now = Date()
        return ServiceRecord(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 119_486,
            money: Money(amount: Decimal(string: "148.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, vendor: nil, items: [
                ServiceItem(title: "Oil service", category: .oil,
                            cost: Money(amount: Decimal(string: "89.00")!,
                                        currency: .eur, homeCurrency: .eur))
            ], usedParts: [], tireSetId: nil)
    }

    private func expense(vehicle: Vehicle) -> Expense {
        let now = Date()
        return Expense(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: nil,
            money: Money(amount: Decimal(string: "12.40")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .parts, title: "Oil filter")
    }

    /// A tiny renderable frame - the attached photo's stand-in. Has a `CGImage`,
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

    // MARK: - A service keeps the receipt it is given

    /// The row's whole point: attaching to a service persists the photo and the
    /// entry still carries it after a reload. Oracle: the stored `Attachment`
    /// id on the reloaded `ServiceRecord`, plus the live `Attachment` row it
    /// points at. This fails today - the non-fill save wrote no attachment.
    func testAttachingAReceiptToAServicePersistsThePhotoAndTheEntryKeepsItAfterReload() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle)
        try repository.upsertServiceRecord(original)
        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        let held = HeldReceiptPhoto(image: photoImage(), ocrLines: [], extraction: nil)

        let outcome = try EditEntryView.writeNonFillWithHeldReceipt(
            original, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: held, repository: repository)

        XCTAssertFalse(outcome.lostPhoto, "a renderable frame must write, not report a loss")
        let id = try XCTUnwrap(outcome.sharedIDs.first,
                               "the save must reference the attachment it wrote")
        let reloaded = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(reloaded.attachments, [id],
                       "the reloaded service must carry the attached receipt")
        let attachment = try XCTUnwrap(repository.liveAttachments().first { $0.id == id },
                                       "the id the service references must be a live Attachment row")
        XCTAssertEqual(attachment.kind, .photo)
        removeAttachmentFile(attachment)
    }

    /// RV.149's rule, one entry kind over: a service photo write that fails is
    /// REPORTED (`.lost`, the flag that drives the toast), not swallowed, and the
    /// service still saves without the photo (hard rule 1: never a blocked save;
    /// hard rule 8: never a silent drop). Oracle: `outcome.lostPhoto` plus the
    /// reloaded record's empty attachment list.
    func testAFailedServicePhotoWriteIsReportedAndTheServiceStillSaves() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = service(vehicle: vehicle)
        try repository.upsertServiceRecord(original)
        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        // An empty UIImage has no CGImage, so `jpegData` returns nil and the
        // write fails exactly as a disk-full or unencodable frame would.
        let held = HeldReceiptPhoto(image: UIImage(), ocrLines: [], extraction: nil)

        let outcome = try EditEntryView.writeNonFillWithHeldReceipt(
            original, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: held, repository: repository)

        XCTAssertTrue(outcome.lostPhoto,
                      "a photo-write failure must surface the report flag, never a silent []")
        XCTAssertTrue(outcome.sharedIDs.isEmpty,
                      "a lost photo must reference no attachment id")
        let liveAttachments = try repository.liveAttachments()
        XCTAssertTrue(liveAttachments.isEmpty,
                      "a failed write must not leave a half-written Attachment row")
        let reloaded = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertTrue(reloaded.attachments.isEmpty,
                      "the service must save without the photo it could not keep")
    }

    // MARK: - An expense shares the screen, so it shares the behaviour

    /// The same persistence contract for an Expense: the two kinds share the
    /// non-fill form and must share the attach behaviour. Oracle: the stored
    /// `Attachment` id on the reloaded `Expense`.
    func testAttachingAReceiptToAnExpensePersistsThePhotoAndTheEntryKeepsItAfterReload() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = expense(vehicle: vehicle)
        try repository.upsertExpense(original)
        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        let held = HeldReceiptPhoto(image: photoImage(), ocrLines: [], extraction: nil)

        let outcome = try EditEntryView.writeNonFillWithHeldReceipt(
            original, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: held, repository: repository)

        XCTAssertFalse(outcome.lostPhoto)
        let id = try XCTUnwrap(outcome.sharedIDs.first)
        let reloaded = try XCTUnwrap(repository.liveExpenses(forVehicle: vehicle.id).first)
        XCTAssertEqual(reloaded.attachments, [id],
                       "the reloaded expense must carry the attached receipt")
        if let attachment = try repository.liveAttachments().first(where: { $0.id == id }) {
            removeAttachmentFile(attachment)
        }
    }

    /// The failure half for an Expense, exactly as for a service.
    func testAFailedExpensePhotoWriteIsReportedAndTheExpenseStillSaves() throws {
        let (repository, vehicle) = try makeVehicle()
        let original = expense(vehicle: vehicle)
        try repository.upsertExpense(original)
        let form = EditEntryView.pristineNonFillForm(for: original, vehicle: vehicle)
        let held = HeldReceiptPhoto(image: UIImage(), ocrLines: [], extraction: nil)

        let outcome = try EditEntryView.writeNonFillWithHeldReceipt(
            original, vehicle: vehicle, form: form, otherEntries: [],
            heldPhoto: held, repository: repository)

        XCTAssertTrue(outcome.lostPhoto)
        let liveAttachments = try repository.liveAttachments()
        XCTAssertTrue(liveAttachments.isEmpty)
        let reloaded = try XCTUnwrap(repository.liveExpenses(forVehicle: vehicle.id).first)
        XCTAssertTrue(reloaded.attachments.isEmpty)
    }

    // MARK: - The affordance is wired to the shared card (RV.11)

    /// The persistence tests above drive the write seam directly; this guard
    /// pins the other half of the row - the non-fill form must offer the "Add
    /// receipt" affordance and hang the camera/Photos chooser off the CARD, the
    /// same branch the fill-up form uses (RV.11). It is a source scan so it
    /// fails if a later edit drops the wiring, which is precisely the defect
    /// this row fixes; the flow itself is proven at L4.
    func testTheNonFillReceiptCardWiresTheAddAffordanceAndChooser() throws {
        let source = try String(contentsOf: Self.nonFillViewSource, encoding: .utf8)
        XCTAssertTrue(source.contains("onAddReceipt: onAddReceipt"),
                      "the non-fill receipt card must pass onAddReceipt, or no 'Add receipt' shows")
        XCTAssertTrue(source.contains(".receiptAttachSource("),
                      "the chooser must hang off the card, not the screen (RV.11)")
    }

    private static var nonFillViewSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TankbookTests
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/EditEntry/EditEntryNonFillView.swift")
    }
}
