import Foundation
import GRDB

// RV.37: delete and replace a receipt. Split out of Repository.swift to keep
// that file under the linter's file-length limit - the same reason
// Repository+RecentlyDeleted exists.
//
// An entry references its attachments by id (`attachments: [AttachmentID]`), so
// deleting a receipt is TWO writes that must agree: tombstone the attachment
// record AND unlink the id from the entry. Both happen in one write transaction
// here; a half-applied delete would leave the entry pointing at a tombstone,
// which the viewer would then fail to open (docs/ERRORS.md -> Edit entry).
//
// The attachment record is a synced entity with a tombstone and the 30-day undo
// window exactly like any other (hard rule 8): the tombstone removes the
// *reference*, and blob reclamation is a separate concern that stays out of
// scope. Because attachments are content-addressed and shared (a mixed receipt's
// fill-up and expenses reference the SAME attachment id - `sharedAttachmentIDs`),
// the tombstone is only written once NO other live entry still references the
// id - deleting from one entry must never silently blank a sibling's receipt.

extension TankbookRepository {
    /// Tombstones the attachment and unlinks it from its entry, in one write
    /// transaction. The tombstone is written only when no other live entry still
    /// references the id (a shared attachment survives in its other entries).
    public func deleteAttachment(id: UUID, from entry: any Entry, at date: Date = Date()) throws {
        try database.write { db in
            let stamp = date.timeIntervalSinceReferenceDate
            try unlinkAttachment(id, in: entry, at: stamp, in: db)
            if try referencingEntryCount(attachmentID: id, in: db) == 0 {
                try tombstone(table: TankbookSchema.attachment, id: id, at: stamp, in: db)
            }
        }
    }

    /// Replace is a new attachment plus a tombstone for the old one, never an
    /// in-place mutation (the 30-day undo has nothing to restore otherwise).
    /// The new row is upserted, the entry relinked (old id out, new id in), and
    /// the old row tombstoned - all in one transaction. The old row stays live
    /// when another entry still references it.
    public func replaceAttachment(oldID: UUID, with newAttachment: Attachment,
                                  in entry: any Entry, at date: Date = Date()) throws {
        try database.write { db in
            let stamp = date.timeIntervalSinceReferenceDate
            var row = AttachmentRow(attachment: newAttachment, syncState: .dirty)
            row.syncScn = try preservingScn(.dirty, table: TankbookSchema.attachment,
                                            id: newAttachment.id, in: db)
            try row.save(db)
            try relinkAttachment(oldID: oldID, newID: newAttachment.id, in: entry, at: stamp, in: db)
            if try referencingEntryCount(attachmentID: oldID, in: db) == 0 {
                try tombstone(table: TankbookSchema.attachment, id: oldID, at: stamp, in: db)
            }
        }
    }

    /// Writes an entry back to its type's table with a fresh `updatedAt`,
    /// marked dirty so the sync queue pushes the attachment-list change.
    private func writeEntry(_ entry: any Entry, at stamp: TimeInterval, in db: Database) throws {
        var updated = entry
        updated.updatedAt = Date(timeIntervalSinceReferenceDate: stamp)
        switch updated {
        case let fill as FillUp:
            var row = FillUpRow(fillUp: fill, syncState: .dirty)
            row.syncScn = try preservingScn(.dirty, table: TankbookSchema.fillUp, id: fill.id, in: db)
            try row.save(db)
        case let charge as ChargeSession:
            var row = ChargeSessionRow(chargeSession: charge, syncState: .dirty)
            row.syncScn = try preservingScn(.dirty, table: TankbookSchema.chargeSession,
                                            id: charge.id, in: db)
            try row.save(db)
        case let service as ServiceRecord:
            var row = ServiceRecordRow(service: service, syncState: .dirty)
            row.syncScn = try preservingScn(.dirty, table: TankbookSchema.serviceRecord,
                                            id: service.id, in: db)
            try row.save(db)
        case let expense as Expense:
            var row = ExpenseRow(expense: expense, syncState: .dirty)
            row.syncScn = try preservingScn(.dirty, table: TankbookSchema.expense,
                                            id: expense.id, in: db)
            try row.save(db)
        default:
            break
        }
    }

    /// Removes the attachment id from the entry's list and writes the entry back.
    private func unlinkAttachment(_ id: UUID, in entry: any Entry,
                                  at stamp: TimeInterval, in db: Database) throws {
        var updated = entry
        updated.attachments.removeAll { $0 == id }
        try writeEntry(updated, at: stamp, in: db)
    }

    /// Swaps the old id for the new one in the entry's list and writes it back.
    private func relinkAttachment(oldID: UUID, newID: UUID, in entry: any Entry,
                                  at stamp: TimeInterval, in db: Database) throws {
        var updated = entry
        updated.attachments.removeAll { $0 == oldID }
        updated.attachments.append(newID)
        try writeEntry(updated, at: stamp, in: db)
    }

    /// Live entries (of any type) that still reference the attachment id. Zero
    /// means the tombstone can proceed without orphaning another entry's
    /// receipt. The `attachments` column is a JSON array of UUID strings; a full
    /// UUID string is never a substring of a different UUID string, so the
    /// `LIKE` containment check is exact.
    private func referencingEntryCount(attachmentID: UUID, in db: Database) throws -> Int {
        let needle = attachmentID.uuidString
        var total = 0
        for table in TankbookSchema.entryTables {
            let referenced = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM \(table)
                WHERE deletedAt IS NULL AND attachments LIKE '%' || ? || '%'
                """, arguments: [needle]) ?? 0
            total += referenced
        }
        return total
    }
}
