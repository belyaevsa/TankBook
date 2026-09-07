import Foundation
import GRDB

// RV.104: the two user actions over a timeline flag's acceptance. Both are
// ordinary entry writes that mark the row dirty - the acceptance is a domain
// fact that rides the record's payload to the next device (docs/SCHEMA.md ->
// Validation -> Acceptance). This layer adds no verdict of its own: `acceptFlag`
// records the user's decision and clears the derived flag; `undoFlagAcceptance`
// removes the decision and lets the timeline validator re-derive the conflict
// from the entries alone - an accepted entry is still flaggable again (hard
// rule 8).

extension TankbookRepository {

    /// Records the user's acceptance of a flagged entry: `conflict` becomes
    /// `.none` and a `FlagAcceptance` is stored for the entry's CURRENT facts
    /// (odometer + date - the keying rule). Returns false when the id names no
    /// live flagged entry. Per entry, deliberate: there is deliberately no bulk
    /// "accept everything the import flagged" - the whole point of the signal
    /// is that a real problem is worth one tap.
    public func acceptFlag(id: UUID, reason: String?, now: Date = Date()) throws -> Bool {
        guard let entry = try liveEntry(id: id),
              case .flagged(let kind, _) = entry.conflict else { return false }
        var accepted = entry
        accepted.conflict = .none
        accepted.flagAcceptance = FlagAcceptance(
            kind: kind,
            acceptedOdometer: accepted.odometer,
            acceptedDate: accepted.date,
            reason: Self.cleanedReason(reason),
            acceptedAt: now)
        accepted.updatedAt = now
        try upsert(accepted)
        return true
    }

    /// Removes an acceptance and re-derives the conflict from the entries alone
    /// (a re-validation runs against the vehicle's live timeline, so an entry
    /// whose facts still break it is flagged again immediately). Returns false
    /// when the id names no live accepted entry.
    public func undoFlagAcceptance(id: UUID, now: Date = Date()) throws -> Bool {
        guard let entry = try liveEntry(id: id),
              entry.flagAcceptance != nil else { return false }
        var reverted = entry
        reverted.flagAcceptance = nil
        reverted.updatedAt = now
        try upsert(reverted)
        _ = try revalidateTimeline(vehicleIds: [reverted.vehicleId])
        return true
    }

    /// A live entry by id across every entry table, or nil. Used by the accept /
    /// undo actions, which receive ids from account-wide surfaces (the flagged
    /// list) that may name an entry on any car.
    public func liveEntry(id: UUID) throws -> (any Entry)? {
        try database.read { db in
            if let row = try FillUpRow.fetchOne(db, key: id.uuidString),
               row.fillUp.deletedAt == nil { return row.fillUp }
            if let row = try ChargeSessionRow.fetchOne(db, key: id.uuidString),
               row.chargeSession.deletedAt == nil { return row.chargeSession }
            if let row = try ServiceRecordRow.fetchOne(db, key: id.uuidString),
               row.service.deletedAt == nil { return row.service }
            if let row = try ExpenseRow.fetchOne(db, key: id.uuidString),
               row.expense.deletedAt == nil { return row.expense }
            return nil
        }
    }

    // MARK: Private

    private func upsert(_ entry: any Entry) throws {
        switch entry {
        case let fill as FillUp: try upsertFillUp(fill)
        case let charge as ChargeSession: try upsertChargeSession(charge)
        case let service as ServiceRecord: try upsertServiceRecord(service)
        case let expense as Expense: try upsertExpense(expense)
        default: break
        }
    }

    private static func cleanedReason(_ reason: String?) -> String? {
        guard let reason else { return nil }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
