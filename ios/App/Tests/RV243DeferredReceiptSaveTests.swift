import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.243 - a deferred expense or service read that lands after the save must
/// not cost the user the photograph or the invoice pages. RV.215 made both reads
/// deferrable and, in doing so, left the photo attached only when the read
/// finished before the save: a save that beat the read saved the entry with no
/// `attachments` and the captured image was gone (hard rule 8).
///
/// These tests drive the REAL sessions and the REAL save seam. The photograph
/// (or page) is staged the moment the scan starts, so a save that beats the read
/// still writes it; the late read then only offers its values through the inbox.
/// The oracle is the stored row plus the file on disk - asserting the inbox item
/// alone is the row's named vacuous trap, because an item can exist while the
/// photo does not.
@MainActor
final class RV243DeferredReceiptSaveTests: XCTestCase {

    /// A one-shot async gate, so a test can hold the read open while it saves and
    /// then release it - deterministic, no timing race.
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { self.continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: AppInbox.storageKey)
    }

    // MARK: - Fixtures

    private func makeVehicle() throws -> (TankbookRepository, Vehicle) {
        let repository = try AppStore.repository()
        let now = Date()
        let vehicle = Vehicle(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            name: "RV243 Volvo", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

    /// A tiny renderable frame - a captured photo's stand-in. Has a `CGImage`,
    /// so `jpegData` succeeds and the write completes.
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

    private func removeAttachmentFile(_ attachment: Attachment) {
        guard let directory = try? VehiclePhotoStore.attachmentsDirectory() else { return }
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(attachment.file.relativePath))
    }

    private func expenseOutcome(category: ExpenseCategory) -> ExpenseScanOutcome {
        let capture = ExpenseScanCapture(image: UIImage(), extraction: FuelExtraction(),
                                         ocrLines: [])
        return ExpenseScanOutcome(
            prefill: ExpensePrefill(),
            preset: category,
            capture: capture,
            recognition: ExpenseRecognition(
                category: .init(value: category, confidence: 0.8)))
    }

    private func serviceOutcome(vendor: String) -> ServiceScanOutcome {
        ServiceScanOutcome(
            prefill: ServiceEntryPrefill(),
            recognition: ServiceRecognition(vendor: .init(value: vendor, confidence: 0.9)))
    }

    // MARK: - Expense

    /// L1, fails before this row: the save happens while the read is still in
    /// flight. The staged photograph must be on disk and referenced by the saved
    /// expense, and the completed read must still reach the inbox with its
    /// values.
    func testAnExpenseSavedWhileItsReadIsPendingKeepsItsPhotoAndTheLateReadReachesTheInbox() async throws {
        let (repository, vehicle) = try makeVehicle()
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ExpenseEntrySession()
        let gate = Gate()

        // The scan starts: the photograph is staged before the read resolves.
        session.start(
            image: photoImage(),
            work: { await gate.wait(); return self.expenseOutcome(category: .parking) },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.expense(outcome.recognition), entryID: entryID)
            })

        // The save that beats the read: the load consumes the staged capture,
        // and the save writes it - the read has resolved nothing yet.
        let capture = try XCTUnwrap(
            session.consumePendingCapture(),
            "the staged photograph must be available to a save that beats the read")
        var form = ExpenseEntryFormState()
        form.category = .parts
        form.amount = "71.02"
        let amount = try XCTUnwrap(form.amountDecimal)
        let (expense, photoWriteFailed) = try ExpenseEntryView.writeExpense(
            form: form, vehicle: vehicle, amount: amount, scan: capture,
            repository: repository)
        XCTAssertFalse(photoWriteFailed, "a renderable frame must write, not report a loss")
        session.markSaved(entryID: expense.id)

        // The read lands late.
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        let saved = try XCTUnwrap(repository.liveExpenses(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.attachments.count, 1,
                       "an expense saved before its read must still carry its receipt")
        let attachment = try XCTUnwrap(
            repository.liveAttachments().first { $0.id == saved.attachments.first },
            "the referenced attachment must be a live row")
        XCTAssertTrue(try fileExists(attachment),
                      "the receipt file must exist on disk, not only the row")
        XCTAssertTrue(inbox.hasItem(for: expense.id),
                      "the late read must still offer its values through the inbox")
        removeAttachmentFile(attachment)
    }

    // MARK: - Service

    /// L1, the same contract one entry kind over: a multi-page invoice saved
    /// before its read lands must keep every page on disk and on the record, and
    /// the late read must still reach the inbox.
    func testAServiceSavedWhileItsReadIsPendingKeepsItsPagesAndTheLateReadReachesTheInbox() async throws {
        let (repository, vehicle) = try makeVehicle()
        let inbox = AppInbox(noteEntryChanged: {})
        let session = ServiceInvoiceSession()
        let gate = Gate()

        // The scan starts: the pages are persisted before the read runs.
        let staged = ServiceInvoiceScanner.stagePages(images: [photoImage()])
        XCTAssertEqual(staged.count, 1, "the scan must persist its page before the read")
        session.start(
            stagedPages: staged,
            work: { await gate.wait(); return self.serviceOutcome(vendor: "New Garage") },
            onAnswer: { _ in XCTFail("a read after the save must not fill the form") },
            onSavedAnswer: { outcome, entryID in
                inbox.recordLateGatewayAnswer(.service(outcome.recognition), entryID: entryID)
            })

        // The load applies the staged prefill; the save happens before the read.
        let stagedPrefill = try XCTUnwrap(session.pendingPrefill,
                                          "the staged pages must be available to the load")
        var form = ServiceEntryFormState()
        form.apply(stagedPrefill)
        form.items = [ServiceEntryItemDraft(title: "Oil service", category: .oil, cost: "89.00")]
        let record = form.draft(vehicle: vehicle)
            .build(vehicleId: vehicle.id, homeCurrency: vehicle.homeCurrency)
        try repository.upsertServiceRecord(record)
        session.markSaved(entryID: record.id)

        // The read lands late.
        gate.open()
        try await Task.sleep(for: .milliseconds(80))

        let saved = try XCTUnwrap(repository.liveServiceRecords(forVehicle: vehicle.id).first)
        XCTAssertEqual(saved.attachments, staged.map(\.attachment.id),
                       "a service saved before its read must still carry its invoice pages")
        for id in saved.attachments {
            let attachment = try XCTUnwrap(
                repository.liveAttachments().first { $0.id == id },
                "every referenced page must be a live attachment row")
            XCTAssertTrue(try fileExists(attachment),
                          "every invoice page file must exist on disk")
            removeAttachmentFile(attachment)
        }
        XCTAssertTrue(inbox.hasItem(for: record.id),
                      "the late read must still offer its values through the inbox")
    }
}
