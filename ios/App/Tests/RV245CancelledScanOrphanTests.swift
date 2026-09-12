import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.245 - a service scan stages its invoice pages at scan START (RV.243), so
/// a read that never finishes cannot lose them. The other half of that trade:
/// a sheet dismissed WITHOUT a save leaves those rows and files with no owning
/// record, and the server-side orphan sweep (P4.3) never reaches the device.
///
/// The cleanup is one call - `ServiceEntryView.discardStagedPages` - that the
/// sheet's single dismissal path (`onDisappear`, shared by the X, the
/// swipe-down and the discard prompt's Discard) invokes unless a save set
/// `didSave`. These tests drive that call against the real repository and the
/// real attachment file store, so the oracle is the stored row plus the file on
/// disk, never the in-memory page array alone.
@MainActor
final class RV245CancelledScanOrphanTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixtures

    private func photoImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120))
        return renderer.image { context in
            UIColor.systemGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }

    private func fileExists(_ attachment: Attachment) throws -> Bool {
        let directory = try VehiclePhotoStore.attachmentsDirectory()
        return FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(attachment.file.relativePath).path)
    }

    private func makeVehicle(_ repository: TankbookRepository) throws -> Vehicle {
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV245 Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return vehicle
    }

    // MARK: - Cancel

    /// L1, fails before this row: a staged scan that is cancelled must take its
    /// page rows and files with it. The row count is asserted as a delta, so a
    /// page another test left behind cannot make this pass or fail by accident.
    func testCancellingAStagedScanRemovesItsPageRowsAndFiles() throws {
        let repository = try AppStore.repository()
        let before = try repository.liveAttachments().count

        let staged = ServiceInvoiceScanner.stagePages(images: [photoImage()])
        XCTAssertEqual(staged.count, 1, "the scan must persist its page before the read")
        XCTAssertEqual(try repository.liveAttachments().count, before + 1)
        let attachment = try XCTUnwrap(staged.first?.attachment)
        XCTAssertTrue(try fileExists(attachment), "the staged page's file must exist on disk")

        ServiceEntryView.discardStagedPages(staged,
                                            pendingPrefill: nil,
                                            session: ServiceInvoiceSession(),
                                            repository: repository)

        XCTAssertEqual(try repository.liveAttachments().count, before,
                       "a cancelled scan must leave no page rows")
        XCTAssertFalse(try fileExists(attachment),
                       "a cancelled scan must leave no page file")
    }

    /// L1: the pages a SAVED record owns survive another scan's cancel. The
    /// cancel removes only the pages it is handed - a saved record's pages are
    /// not in that set, so the delete cannot reach them.
    func testASavedRecordsPagesSurviveASecondScansCancel() throws {
        let repository = try AppStore.repository()
        let vehicle = try makeVehicle(repository)

        let savedPages = ServiceInvoiceScanner.stagePages(images: [photoImage()])
        XCTAssertEqual(savedPages.count, 1)
        let item = ServiceItem.make(
            title: "Oil service", category: .oil,
            cost: Money(amount: Decimal(string: "89.00")!, currency: .eur, homeCurrency: .eur))
        let record = ServiceEntryDraft(
            vendor: "Bosch Service", items: [item], date: Date(), odometer: 118_930,
            attachments: savedPages.map(\.attachment.id), provenance: .receiptScan)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        try repository.upsertServiceRecord(record)

        let cancelled = ServiceInvoiceScanner.stagePages(images: [photoImage()])
        ServiceEntryView.discardStagedPages(cancelled,
                                            pendingPrefill: nil,
                                            session: ServiceInvoiceSession(),
                                            repository: repository)

        let savedAttachment = try XCTUnwrap(savedPages.first?.attachment)
        XCTAssertNotNil(try repository.liveAttachments().first { $0.id == savedAttachment.id },
                        "a saved record's page must survive another scan's cancel")
        XCTAssertTrue(try fileExists(savedAttachment),
                      "a saved record's page file must survive another scan's cancel")
        let saved = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.attachments, [savedAttachment.id])
    }

    /// RV.245: the sheet's one dismissal path owns the cleanup and a save
    /// disarms it. A source scan is the only check that sees the wiring - the
    /// behavioural tests above prove the cleanup works, not that the view calls
    /// it, and the X / swipe-down / Discard all funnel through `onDisappear`.
    func testTheDismissalPathCallsTheCleanupAndASaveDisarmsIt() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // App/Tests
            .deletingLastPathComponent() // App
            .deletingLastPathComponent() // ios
            .appendingPathComponent("App/Sources/ServiceEntry/ServiceEntryView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains(".onDisappear"),
                      "the sheet's single dismissal path must be onDisappear")
        XCTAssertTrue(source.contains("Self.discardStagedPages(pages,"),
                      "the dismissal path must call the one cleanup")
        XCTAssertTrue(source.contains("guard !didSave"),
                      "a save must disarm the cleanup")
        XCTAssertTrue(source.contains("didSave = true"),
                      "the save path must set didSave")
    }
}
