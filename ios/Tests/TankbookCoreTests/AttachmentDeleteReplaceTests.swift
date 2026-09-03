import Foundation
import Testing
@testable import TankbookCore

// RV.37: delete and replace a receipt. The load-bearing guarantees live in core
// so they are pinned without a device (the P3.7 lesson):
// - delete tombstones the attachment (recoverable for the 30-day window, hard
//   rule 8) AND unlinks it from the entry, in one transaction;
// - a shared attachment (a mixed receipt's fill-up and expenses reference the
//   SAME id) is unlinked from the deleting entry but NOT tombstoned, so its
//   other entries keep their receipt;
// - replace is a new attachment plus a tombstone for the old one, and touches
//   no other field of the entry (hard rule 13 - the swap never overwrites a
//   value the user confirmed).

@Suite struct AttachmentDeleteReplaceTests {

    private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

    private func makeRepository() throws -> TankbookRepository {
        TankbookRepository(database: try TankbookDatabase.inMemory())
    }

    private func makeVehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            name: "Volvo V60", make: "Volvo", model: "V60", year: 2021,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                 energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500)
    }

    private func makeFillUp(vehicleId: UUID, attachments: [AttachmentID],
                            money: Money? = Money(amount: Decimal(string: "71.02")!,
                                                  currency: .eur, homeCurrency: .eur),
                            unitPrice: Decimal? = Decimal(string: "1.679")!) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            vehicleId: vehicleId, date: timestamp, odometer: 119_486,
            money: money, note: "fill note", attachments: attachments,
            provenance: .receiptScan, conflict: .none, purchaseGroupId: nil,
            volumeL: 42.30, unitPrice: unitPrice, fuelKind: .petrol95, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private func makeExpense(vehicleId: UUID, attachments: [AttachmentID]) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
            vehicleId: vehicleId, date: timestamp, odometer: nil,
            money: Money(amount: Decimal(string: "8.00")!, currency: .eur, homeCurrency: .eur),
            note: nil, attachments: attachments, provenance: .manual,
            conflict: .none, purchaseGroupId: nil, category: .other("wash"),
            title: "Car wash", recurrence: nil, installedInServiceId: nil)
    }

    // MARK: - Delete

    @Test func deleteUnlinksTheEntryAndTombstonesTheAttachment() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let attachment = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(attachment)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id,
                                         attachments: [attachment.id]))

        try repo.deleteAttachment(id: attachment.id,
                                  from: try repo.liveFillUps(forVehicle: vehicle.id)[0])

        // Unlinked: the entry no longer references the id.
        #expect(try repo.liveFillUps(forVehicle: vehicle.id)[0].attachments.isEmpty)
        // Tombstoned, not hard-deleted: the record survives the 30-day window.
        #expect(try repo.liveAttachments().isEmpty)
        #expect(try repo.rowCount(in: TankbookSchema.attachment) == 1)
        // Recoverable: restoring clears the tombstone.
        try repo.restoreAttachment(id: attachment.id)
        #expect(try repo.liveAttachments().map(\.id) == [attachment.id])
    }

    @Test func deleteLeavesTheEntrysOtherFieldsByteIdentical() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let attachment = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(attachment)
        let fill = makeFillUp(vehicleId: vehicle.id, attachments: [attachment.id])
        try repo.upsertFillUp(fill)

        try repo.deleteAttachment(id: attachment.id, from: fill)

        let after = try repo.liveFillUps(forVehicle: vehicle.id)[0]
        #expect(after.money == fill.money)
        #expect(after.unitPrice == fill.unitPrice)
        #expect(after.volumeL == fill.volumeL)
        #expect(after.odometer == fill.odometer)
        #expect(after.note == fill.note)
    }

    @Test func deleteFromOneEntryKeepsASharedAttachmentLive() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let attachment = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(attachment)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id,
                                         attachments: [attachment.id]))
        try repo.upsertExpense(makeExpense(vehicleId: vehicle.id,
                                           attachments: [attachment.id]))

        try repo.deleteAttachment(id: attachment.id,
                                  from: try repo.liveFillUps(forVehicle: vehicle.id)[0])

        // The fill is unlinked, the expense still references the id, so the
        // attachment is NOT tombstoned - deleting one entry's receipt must never
        // blank a sibling's.
        #expect(try repo.liveFillUps(forVehicle: vehicle.id)[0].attachments.isEmpty)
        #expect(try repo.liveExpenses(forVehicle: vehicle.id)[0].attachments == [attachment.id])
        #expect(try repo.liveAttachments().map(\.id) == [attachment.id])
    }

    // MARK: - Replace

    @Test func replaceLinksTheNewAttachmentAndTombstonesTheOldOne() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let old = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(old)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, attachments: [old.id]))

        let new = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.replaceAttachment(oldID: old.id, with: new,
                                   in: try repo.liveFillUps(forVehicle: vehicle.id)[0])

        #expect(try repo.liveFillUps(forVehicle: vehicle.id)[0].attachments == [new.id])
        #expect(try repo.liveAttachments().map(\.id) == [new.id])
        #expect(try repo.rowCount(in: TankbookSchema.attachment) == 2)
        // The old one is a tombstone, not gone: replace is never an in-place
        // mutation, so the 30-day undo has something to restore.
        try repo.restoreAttachment(id: old.id)
        #expect(try repo.liveAttachments().map(\.id).sorted()
            == [old.id, new.id].sorted())
    }

    @Test func replaceTouchesNoOtherFieldOfTheEntry() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let old = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(old)
        let fill = makeFillUp(vehicleId: vehicle.id, attachments: [old.id])
        try repo.upsertFillUp(fill)

        let new = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.replaceAttachment(oldID: old.id, with: new, in: fill)

        let after = try repo.liveFillUps(forVehicle: vehicle.id)[0]
        #expect(after.money == fill.money)
        #expect(after.unitPrice == fill.unitPrice)
        #expect(after.volumeL == fill.volumeL)
        #expect(after.odometer == fill.odometer)
        #expect(after.note == fill.note)
        #expect(after.attachments == [new.id])
    }

    @Test func replaceKeepsASharedOldAttachmentLive() throws {
        let repo = try makeRepository()
        try repo.upsertVehicle(makeVehicle())
        let vehicle = try repo.liveVehicles()[0]
        let old = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.upsertAttachment(old)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, attachments: [old.id]))
        try repo.upsertExpense(makeExpense(vehicleId: vehicle.id, attachments: [old.id]))

        let new = makeSyncAttachment(sha256: UUID().uuidString)
        try repo.replaceAttachment(oldID: old.id, with: new,
                                   in: try repo.liveFillUps(forVehicle: vehicle.id)[0])

        // The fill now references the new attachment; the expense still
        // references the old one, so the old row is NOT tombstoned.
        #expect(try repo.liveFillUps(forVehicle: vehicle.id)[0].attachments == [new.id])
        #expect(try repo.liveExpenses(forVehicle: vehicle.id)[0].attachments == [old.id])
        #expect(try repo.liveAttachments().map(\.id).sorted()
            == [old.id, new.id].sorted())
    }
}
