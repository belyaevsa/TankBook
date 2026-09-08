import Foundation
import Testing
@testable import TankbookCore

// RV.133: the "Needs a look" row's swipe Delete. The L4 layer proves the
// gesture and the one confirmation; these L1 assertions prove what the delete
// MUST do to the store - because a swipe path can most easily reach the wrong
// delete by accident. The named trap is a delete that hard-deletes: the row
// vanishes, a naive "it disappeared" test passes, and hard rule 8 (nothing
// lost silently, the 30-day undo) is broken. So these tests assert the
// tombstone lands in the Recently deleted list (`deletedEntries()`), that the
// entry is GONE from the live log and the derived flagged count, and that
// `restoreEntry` - the Recently deleted screen's Restore - brings it back
// live and still flagged.

private let day: TimeInterval = 86_400
private let epoch = Date(timeIntervalSince1970: 1_752_000_000)

/// The swipe's delete path for a FUEL row calls `softDeleteFillUp` - the
/// repository function `FlaggedEntriesView.performDelete` dispatches to by the
/// row's kind. This is the exact L1 seam the swipe's tombstone must satisfy.
@Test("swipe-deleting a flagged fuel entry tombstones it into Recently deleted and Restore brings it back flagged")
func softDeletingAFlaggedFillLandsItInRecentlyDeletedAndRestoresItFlagged() throws {
    let repo = try makeSyncRepository()
    let vehicle = makeSyncVehicle()
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    let earlier = makeSyncFillUp(vehicleId: vehicle.id, date: epoch, odometer: 150_000)
    var gapped = makeSyncFillUp(vehicleId: vehicle.id, date: epoch + 6 * 365 * day,
                                odometer: 82_000)
    gapped.conflict = .flagged(kind: .order, detectedAt: gapped.createdAt)
    try repo.upsertFillUp(earlier, syncState: .synced(scn: 2))
    try repo.upsertFillUp(gapped, syncState: .synced(scn: 3))
    #expect(try repo.flaggedEntryCount() == 1)

    // The swipe Delete: the per-kind soft delete the fuel row dispatches to.
    try repo.softDeleteFillUp(id: gapped.id)

    // It is tombstoned, not hard-deleted: the Recently deleted screen lists it.
    let deleted = try repo.deletedEntries()
    #expect(deleted.map(\.id).contains(gapped.id),
            "a swipe-deleted flagged entry must appear in Recently deleted (hard rule 8)")
    // The live log and the derived flagged count no longer see it - the row
    // leaves the "Needs a look" list.
    let liveIDs = try repo.liveEntries(forVehicle: vehicle.id).map(\.id)
    #expect(!liveIDs.contains(gapped.id))
    #expect(try repo.flaggedEntryCount() == 0,
            "the tombstoned entry must stop counting as flagged (hard rule 2)")
    #expect(try repo.liveFillUps(forVehicle: vehicle.id).count == 1,
            "the other live fill must be untouched")

    // Restore - the Recently deleted screen's own path - brings it back, still
    // flagged: it belongs in the list again, because the conflict is derived
    // from the entry and the tombstone cleared nothing but the tombstone.
    #expect(try repo.restoreEntry(id: gapped.id))
    let restored = try repo.liveFillUps(forVehicle: vehicle.id)
        .first { $0.id == gapped.id }
    #expect(restored != nil)
    #expect(restored?.conflict == .flagged(kind: .order, detectedAt: gapped.createdAt),
            "a restored flagged entry must need a look again - Restore is not an accept")
    #expect(try repo.flaggedEntryCount() == 1)
    #expect(try repo.deletedEntries().isEmpty)
}

/// The same tombstone contract holds for the non-fill kinds a swipe row can
/// carry (the row's kind resolves the table; the 30-day window is per table).
/// A charge's Restore must not resurrect a different entry.
@Test("swipe-deleting a flagged charge tombstones it and Restore brings it back, not a fill")
func softDeletingAFlaggedChargeAlsoLandsInRecentlyDeleted() throws {
    let repo = try makeSyncRepository()
    let vehicle = makeSyncVehicle()
    try repo.upsertVehicle(vehicle, syncState: .synced(scn: 1))

    let charge = ChargeSession(
        id: UUID.v7(), createdAt: epoch, updatedAt: epoch, deletedAt: nil,
        vehicleId: vehicle.id, date: epoch + day, odometer: 121_200,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .flagged(kind: .pace, detectedAt: epoch), purchaseGroupId: nil,
        energyKWh: 24, unitPrice: nil, chargeType: .dcPublic,
        provider: "Ionity", tariffId: nil, durationMin: 31,
        socStartPct: 18, socEndPct: 82, extraction: nil)
    let fill = makeSyncFillUp(vehicleId: vehicle.id, date: epoch, odometer: 118_000)
    try repo.upsertChargeSession(charge, syncState: .synced(scn: 2))
    try repo.upsertFillUp(fill, syncState: .synced(scn: 3))
    #expect(try repo.flaggedEntryCount() == 1)

    try repo.softDeleteChargeSession(id: charge.id)

    #expect(try repo.deletedEntries().map(\.id) == [charge.id],
            "only the charge is tombstoned; the live fill is untouched")
    #expect(try repo.flaggedEntryCount() == 0)
    #expect(try repo.liveChargeSessions(forVehicle: vehicle.id).isEmpty)

    #expect(try repo.restoreEntry(id: charge.id))
    let restoredCharge = try repo.liveChargeSessions(forVehicle: vehicle.id).first
    #expect(restoredCharge != nil)
    #expect(restoredCharge?.conflict == .flagged(kind: .pace, detectedAt: epoch))
    #expect(try repo.deletedEntries().isEmpty)
}
