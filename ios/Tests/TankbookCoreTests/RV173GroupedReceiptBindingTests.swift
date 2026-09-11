import Foundation
import Testing
@testable import TankbookCore

/// RV.173: a grouped save's attachment binding is all-or-nothing. The one
/// shared receipt-photo write returns an outcome (RV.149); the accepted
/// `Expense` rows must consume that outcome rather than the plan's intended id,
/// so a `.lost` write leaves the fill-up AND its expense siblings unattached -
/// no row points at an id that resolves to nothing (hard rule 8). These are the
/// stored-row oracles: every row is written to a repository and read back, so
/// the assertion is about what is on disk, never about a value in flight.
@Suite("RV.173: a grouped save's attachment binding is all-or-nothing")
struct RV173GroupedReceiptBindingTests {

    private func decimal(_ string: String) -> Decimal {
        Decimal(string: string)!
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

    private func makeVehicle(_ repository: TankbookRepository) throws -> Vehicle {
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
        return vehicle
    }

    private func scannedPlan() -> ScannedSavePlan {
        ScannedSavePlanner.plan(
            extraction: FuelExtraction(liters: 42.30, unitPrice: decimal("1.679"),
                                       total: decimal("71.02"), currency: .eur, fuelKind: .petrol95),
            hasPhoto: true,
            saved: ScannedSaveValues(total: decimal("71.02"), volumeL: 42.30,
                                     unitPrice: decimal("1.679"), currency: .eur,
                                     fuelKind: .petrol95))
    }

    /// Writes the fill-up with the SAME effective ids the expenses get, exactly
    /// as the view does, then returns every live entry for the car.
    @discardableResult
    private func writeGroup(_ repository: TankbookRepository, vehicle: Vehicle,
                            group: ReceiptGroupPlan, scanned: ScannedSavePlan,
                            effectiveAttachments: [AttachmentID]) throws -> [any Entry] {
        let now = Date()
        let fillUp = FillUp(
            id: UUID.v7(), createdAt: now, updatedAt: now, deletedAt: nil,
            vehicleId: vehicle.id, date: now, odometer: 118_930,
            money: Money(amount: decimal("71.02"), currency: .eur, homeCurrency: .eur),
            note: nil, attachments: effectiveAttachments, provenance: .receiptScan,
            conflict: .none, purchaseGroupId: group.purchaseGroupId, volumeL: 42.30,
            unitPrice: decimal("1.679"), fuelKind: .petrol95, fuelGrade: nil,
            isFull: false, tankLevelAfterPct: nil, stationId: nil,
            crossCheck: .verified, extraction: nil)
        try repository.upsertFillUp(fillUp)
        let rows = scanned.binding(effectiveAttachments.first)
            .expenses(from: group, vehicleId: vehicle.id, date: now, createdAt: now) { amount in
                Money(amount: amount, currency: .eur, homeCurrency: .eur)
            }
        for row in rows { try repository.upsertExpense(row) }
        return try repository.liveEntries(forVehicle: vehicle.id)
    }

    private func assertNoDanglingReference(_ stored: [any Entry],
                                           liveAttachments: Set<UUID>) {
        let dangling = stored.flatMap(\.attachments).filter { !liveAttachments.contains($0) }
        #expect(dangling.isEmpty,
                "no stored row may reference an attachment that does not exist: \(dangling)")
    }

    @Test("a lost photo writes no stored row referencing a missing attachment")
    func lostPhotoStoresNoDanglingID() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = try makeVehicle(repository)
        let group = try #require(groupPlan())
        let scanned = scannedPlan()
        #expect(scanned.attachmentID != nil, "the plan still intends a photo")

        // The photo write threw (RV.149 `.lost`): the effective list is empty.
        let stored = try writeGroup(repository, vehicle: vehicle, group: group,
                                    scanned: scanned, effectiveAttachments: [])
        let live = Set(try repository.liveAttachments().map(\.id))
        #expect(live.isEmpty, "a failed write leaves no Attachment row")
        assertNoDanglingReference(stored, liveAttachments: live)
        #expect(stored.allSatisfy { $0.attachments.isEmpty },
                "the fill-up and every expense sibling agree: none carries the lost id")
    }

    @Test("a written photo binds every stored row to the one live attachment")
    func writtenPhotoBindsEveryStoredRow() throws {
        let repository = try TankbookRepository(database: TankbookDatabase.inMemory())
        let vehicle = try makeVehicle(repository)
        let group = try #require(groupPlan())
        let scanned = scannedPlan()
        let id = try #require(scanned.attachmentID)
        let now = Date()
        try repository.upsertAttachment(
            Attachment(id: id, createdAt: now, updatedAt: now, deletedAt: nil,
                       kind: .photo,
                       file: LocalFileRef(sha256: String(repeating: "a", count: 64),
                                          relativePath: "\(id.uuidString).jpg"),
                       extractedTimestamp: nil, ocrText: nil, thumbnailBase64: nil,
                       extractionMeta: nil))

        let stored = try writeGroup(repository, vehicle: vehicle, group: group,
                                    scanned: scanned, effectiveAttachments: [id])
        let live = Set(try repository.liveAttachments().map(\.id))
        assertNoDanglingReference(stored, liveAttachments: live)
        #expect(stored.count == 3, "one fill-up + two accepted expenses")
        #expect(stored.allSatisfy { $0.attachments == [id] },
                "every member of the group shares the ONE live receipt")
        #expect(stored.allSatisfy { $0.purchaseGroupId == group.purchaseGroupId },
                "the group identity is untouched by a successful write")
    }
}
