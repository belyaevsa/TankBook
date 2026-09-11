import Foundation
import UIKit
import XCTest
import TankbookCore
@testable import Tankbook

/// RV.173 L1: on a grouped save - one slip that produces a fill-up plus
/// accepted expenses - a failed receipt-photo write must leave the WHOLE group
/// unattached. RV.149 fixed the fill-up; its expense siblings from the same slip
/// kept the plan's shared id and pointed at an `Attachment` that was never
/// written (the dangling id nobody saw until a viewer tried to open it). The
/// oracle here is the stored rows: every `attachmentID` on every written row
/// resolves to a live `Attachment`, or is absent. The write itself is forced to
/// fail the same way RV.149 does it - an empty `UIImage` has no `CGImage`, so
/// `jpegData` returns nil exactly as a disk-full or unencodable frame would.
///
/// Lives in the app-target test bundle because the receipt write is app code
/// over UIKit (`VehiclePhotoStore`, the attachments path); the SwiftPM core
/// tests run on macOS where that path does not exist. The pure all-or-nothing
/// shape is pinned in core (`RV173GroupedReceiptBindingTests`).
@MainActor
final class RV173GroupedReceiptSaveTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Fixtures

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
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
            initialOdometer: 118_930)
        try repository.upsertVehicle(vehicle)
        return (repository, vehicle)
    }

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
            saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                     unitPrice: decimal("1.679"), currency: .eur,
                                     fuelKind: .petrol95,
                                     date: ConfirmDate.parse("17.08.2026")))
    }

    private func groupPlan() -> ReceiptGroupPlan? {
        let detection = MixedReceiptDetection.mixed(
            lines: [
                ReceiptLineItem(title: "Мойка кузова", amount: decimal("8.00"),
                                category: .parking, isCarRelated: true),
                ReceiptLineItem(title: "Кофе американо", amount: decimal("4.80"),
                                category: .other("coffee"), isCarRelated: false)
            ],
            fuelLine: decimal("71.02"), grandTotal: decimal("83.82"))
        return ReceiptGroupPlanner.plan(detection: detection,
                                        fillUpAmount: decimal("71.02"),
                                        acceptedLineIDs: Set(detection.lines.map(\.id)))
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

    /// The view's grouped write, reduced to the repository seam: the fill-up and
    /// every accepted expense are built with the SAME effective attachment list
    /// the shared write produced. Returns every live entry for the car.
    @discardableResult
    private func writeGroup(_ repository: TankbookRepository, vehicle: Vehicle,
                            scanned: ScannedSavePlan, group: ReceiptGroupPlan,
                            outcome: ReceiptWriteOutcome) throws -> [any Entry] {
        let now = Date()
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: ConfirmDate.parse("17.08.2026")!,
            odometer: 118_930,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: outcome.sharedIDs, provenance: .receiptScan,
            conflict: .none, purchaseGroupId: group.purchaseGroupId, volumeL: 42.30,
            unitPrice: decimal("1.679"), fuelKind: .petrol95, fuelGrade: nil,
            isFull: false, tankLevelAfterPct: nil, stationId: nil,
            crossCheck: .verified, extraction: scanned.extraction)
        try repository.upsertFillUp(fillUp)
        let rows = scanned.binding(outcome.sharedID)
            .expenses(from: group, vehicleId: vehicle.id, date: now, createdAt: now) { amount in
                Money(amount: amount, currency: .eur, homeCurrency: .eur)
            }
        for row in rows { try repository.upsertExpense(row) }
        return try repository.liveEntries(forVehicle: vehicle.id)
    }

    // MARK: - A lost photo leaves no row pointing at nothing

    /// The row's whole defect at the seam the save runs: the real photo write
    /// throws, and the accepted expense siblings must follow the fill-up's empty
    /// attachment list. The oracle is the stored rows, not the values in flight.
    func testLostPhotoLeavesTheWholeGroupUnattached() throws {
        let (repository, vehicle) = try makeVehicle()
        // An empty UIImage has no CGImage, so `jpegData` returns nil and the
        // write fails exactly as a disk-full or unencodable frame would.
        let prefill = prefill(image: UIImage())
        let scanned = scannedPlan(prefill: prefill)
        let id = try XCTUnwrap(scanned.attachmentID)
        let group = try XCTUnwrap(groupPlan())

        let outcome = attemptReceiptPhotoWrite(scanned: scanned, source: prefill,
                                               repository: repository)
        XCTAssertEqual(outcome, .lost(id),
                       "the forced write failure must surface as .lost")

        let stored = try writeGroup(repository, vehicle: vehicle, scanned: scanned,
                                    group: group, outcome: outcome)
        XCTAssertEqual(stored.count, 3, "one fill-up + two accepted expenses")
        let live = Set(try repository.liveAttachments().map(\.id))
        XCTAssertTrue(live.isEmpty, "a failed write leaves no Attachment row")
        let dangling = stored.flatMap(\.attachments).filter { !live.contains($0) }
        XCTAssertTrue(dangling.isEmpty,
                      "no stored row may reference a missing attachment: \(dangling)")
        XCTAssertTrue(stored.allSatisfy { $0.attachments.isEmpty },
                      "the fill-up and every expense sibling agree: none carries the lost id")
        XCTAssertTrue(stored.allSatisfy { $0.purchaseGroupId == group.purchaseGroupId },
                      "the group identity survives the lost photo")
    }

    // MARK: - A written photo keeps the whole group bound to one receipt

    /// The happy path is untouched: a renderable frame writes, and the fill-up
    /// and every expense reference the ONE live attachment with the group id
    /// intact. Clearing the ids on success would break the shared-receipt
    /// invariant; this is the half that must not move.
    func testWrittenPhotoBindsEveryRowToOneReceipt() throws {
        let (repository, vehicle) = try makeVehicle()
        let prefill = prefill(image: photoImage())
        let scanned = scannedPlan(prefill: prefill)
        let id = try XCTUnwrap(scanned.attachmentID)
        let group = try XCTUnwrap(groupPlan())

        let outcome = attemptReceiptPhotoWrite(scanned: scanned, source: prefill,
                                               repository: repository)
        XCTAssertEqual(outcome, .wrote(id))

        let stored = try writeGroup(repository, vehicle: vehicle, scanned: scanned,
                                    group: group, outcome: outcome)
        let attachments = try repository.liveAttachments()
        XCTAssertEqual(attachments.count, 1, "exactly one Attachment row")
        let live = Set(attachments.map(\.id))
        XCTAssertEqual(stored.count, 3)
        XCTAssertTrue(stored.allSatisfy { $0.attachments == [id] },
                      "every member of the group shares the ONE live receipt")
        XCTAssertTrue(stored.allSatisfy { $0.purchaseGroupId == group.purchaseGroupId })
        let dangling = stored.flatMap(\.attachments).filter { !live.contains($0) }
        XCTAssertTrue(dangling.isEmpty)
        if let attachment = attachments.first { removeAttachmentFile(attachment) }
    }

    // MARK: - The user is told once, not once per row

    /// RV.149's shared report is driven by the ONE write outcome, so a grouped
    /// save reports once however many expense rows it wrote. The toast count is
    /// the oracle: a per-row report would bump `revision` past 1.
    func testLostGroupReportsExactlyOnce() throws {
        let (repository, _) = try makeVehicle()
        let prefill = prefill(image: UIImage())
        let scanned = scannedPlan(prefill: prefill)
        let id = try XCTUnwrap(scanned.attachmentID)
        let group = try XCTUnwrap(groupPlan())
        let outcome = attemptReceiptPhotoWrite(scanned: scanned, source: prefill,
                                               repository: repository)
        XCTAssertEqual(outcome, .lost(id))

        // The group has two accepted expenses; the report is per save, not per row.
        let rows = scanned.binding(outcome.sharedID)
            .expenses(from: group, vehicleId: UUID.v7(), date: Date(), createdAt: Date()) { amount in
                Money(amount: amount, currency: .eur, homeCurrency: .eur)
            }
        XCTAssertEqual(rows.count, 2)

        let toastCenter = AppToastCenter()
        reportLostReceiptPhoto(outcome, toastCenter: toastCenter)
        XCTAssertEqual(toastCenter.revision, 1,
                       "a lost grouped photo is reported once, never once per expense row")
    }
}
