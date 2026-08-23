import Foundation
import Testing
@testable import TankbookCore

// MARK: - P1.7: Recently deleted - the storage half the screen depends on.

// Every test runs THROUGH the real store (an in-memory GRDB repository), never
// against hand-built fixture arrays. The restore-to-stats test uses the golden
// D1 series and the real `ConsumptionEngine` recompute, exactly as
// EditRecalculationTests does, so the headline assertions are the documented
// 6.9 -> something -> 6.9 cycle.

private enum UTC {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private let goldenAsOf = UTC.day(2026, 8, 23)

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle(vehicleID: UUID) -> Vehicle {
    Vehicle(
        id: vehicleID, createdAt: goldenAsOf, updatedAt: goldenAsOf, deletedAt: nil,
        name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
        plate: nil, powertrain: .ice, fuelKinds: [.petrol95],
        tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 114_000)
}

private struct FillSpec {
    let date: Date
    let odometer: Int
    let litres: Double
}

private func makeFill(id: UUID = UUID.v7(), vehicleID: UUID, _ spec: FillSpec) -> FillUp {
    FillUp(
        id: id, createdAt: spec.date, updatedAt: spec.date, deletedAt: nil,
        vehicleId: vehicleID, date: spec.date, odometer: spec.odometer,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil,
        volumeL: spec.litres, unitPrice: nil,
        fuelKind: .petrol95, fuelGrade: nil, isFull: true,
        tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

/// The golden D1 series (commuter, full tank every two weeks) - the headline
/// on `goldenAsOf` is the documented 6.9.
private let d1Specs: [FillSpec] = [
    FillSpec(date: UTC.day(2026, 5, 17), odometer: 114_980, litres: 45.9),
    FillSpec(date: UTC.day(2026, 5, 31), odometer: 115_622, litres: 44.6),
    FillSpec(date: UTC.day(2026, 6, 14), odometer: 116_281, litres: 46.8),
    FillSpec(date: UTC.day(2026, 6, 28), odometer: 116_904, litres: 43.1),
    FillSpec(date: UTC.day(2026, 7, 12), odometer: 117_561, litres: 45.5),
    FillSpec(date: UTC.day(2026, 7, 26), odometer: 118_207, litres: 44.2),
    FillSpec(date: UTC.day(2026, 8, 9), odometer: 118_843, litres: 43.9),
    FillSpec(date: UTC.day(2026, 8, 22), odometer: 119_486, litres: 42.3)
]

private func seedD1(_ repository: TankbookRepository, vehicleID: UUID) throws -> [FillUp] {
    let fills = d1Specs.map { makeFill(vehicleID: vehicleID, $0) }
    for fill in fills {
        try repository.upsertFillUp(fill)
    }
    return fills
}

private func headline(_ repository: TankbookRepository, vehicle: Vehicle,
                      asOf: Date = goldenAsOf) throws -> Headline? {
    let fills = try repository.liveFillUps(forVehicle: vehicle.id)
    let segments = ConsumptionEngine.recompute(fills: fills, tankCapacityL: vehicle.tankCapacityL)
    return ConsumptionEngine.headline(segments: segments, asOf: asOf)
}

// MARK: - Restore returns the entry to statistics (hard rule 8, executable)

@Test func restoreEntryReturnsHeadlineToExactlyItsPriorValue() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    try repository.upsertVehicle(vehicle)
    let fills = try seedD1(repository, vehicleID: vehicleID)

    let before = try headline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(before) == 6.9)

    // Delete the 07-12 fill through the repository: the headline must move.
    let target = fills.first { $0.date == UTC.day(2026, 7, 12) }!.id
    try repository.softDeleteFillUp(id: target)
    let whileDeleted = try headline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(whileDeleted) != 6.9)

    // The tombstone is on the Recently deleted screen's list...
    let deleted = try repository.deletedEntries()
    #expect(deleted.map(\.id).contains(target))
    #expect(try repository.liveEntries(forVehicle: vehicleID).map(\.id).contains(target) == false)

    // ...and restore brings it back: the stats return EXACTLY. This is the
    // screen's own restore path (`restoreEntry`), not the fill-specific one.
    let restored = try repository.restoreEntry(id: target)
    #expect(restored)
    let after = try headline(repository, vehicle: vehicle)
    #expect(ConsumptionDelta.displayedValue(after) == 6.9)
    #expect(!ConsumptionDelta.hasChanged(before: before, after: after))
    #expect(try repository.deletedEntries().isEmpty)
}

@Test func restoreEntryReturnsFalseForUnknownID() throws {
    let repository = try makeRepository()
    #expect(try repository.restoreEntry(id: UUID.v7()) == false)
}

@Test func deletedEntriesListsEveryEntryTypeNewestDeletionFirst() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    try repository.upsertVehicle(makeVehicle(vehicleID: vehicleID))

    let fill = makeFill(vehicleID: vehicleID,
                        FillSpec(date: UTC.day(2026, 8, 20), odometer: 119_000, litres: 42.0))
    let expense = Expense(
        id: UUID.v7(), createdAt: UTC.day(2026, 8, 20), updatedAt: UTC.day(2026, 8, 20),
        deletedAt: nil, vehicleId: vehicleID, date: UTC.day(2026, 8, 20), odometer: nil,
        money: nil, note: nil, attachments: [], provenance: .manual,
        conflict: .none, purchaseGroupId: nil, category: .other("car wash"),
        title: "Car wash", recurrence: nil, installedInServiceId: nil)
    try repository.upsertFillUp(fill)
    try repository.upsertExpense(expense)

    try repository.softDeleteFillUp(id: fill.id, at: UTC.day(2026, 8, 21))
    try repository.softDeleteExpense(id: expense.id, at: UTC.day(2026, 8, 22))

    let deleted = try repository.deletedEntries()
    #expect(deleted.count == 2)
    // Newest deletion first (Aug 22 expense, then Aug 21 fill).
    #expect(deleted.first?.entry.id == expense.id)
    #expect(deleted.last?.entry.id == fill.id)
    #expect(deleted.first?.deletedAt == UTC.day(2026, 8, 22))
    #expect(deleted.contains { $0.entry is FillUp })
    #expect(deleted.contains { $0.entry is Expense })
}

// MARK: - Purge honours the grace period (both sides of the boundary)

@Test func purgeHonoursGracePeriodAt29And31Days() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    try repository.upsertVehicle(makeVehicle(vehicleID: vehicleID))

    // Two fills, two tombstone ages: 29 days (inside the window) and 31 days
    // (outside it). The default purge cutoff is exactly 30 days ago.
    let inside = makeFill(id: UUID.v7(), vehicleID: vehicleID,
                          FillSpec(date: UTC.day(2026, 8, 1), odometer: 119_000, litres: 42.0))
    let outside = makeFill(id: UUID.v7(), vehicleID: vehicleID,
                           FillSpec(date: UTC.day(2026, 8, 1), odometer: 119_100, litres: 40.0))
    try repository.upsertFillUp(inside)
    try repository.upsertFillUp(outside)

    let now = Date()
    try repository.softDeleteFillUp(id: inside.id, at: now.addingTimeInterval(-29 * 86_400))
    try repository.softDeleteFillUp(id: outside.id, at: now.addingTimeInterval(-31 * 86_400))

    try repository.purgeTombstones()

    // 29 days survives, 31 days is gone - BOTH sides asserted, not one.
    let deleted = try repository.deletedEntries()
    #expect(deleted.map(\.id) == [inside.id])
    #expect(try repository.rowCount(in: TankbookSchema.fillUp) == 1)
    #expect(try repository.liveFillUps(forVehicle: vehicleID).isEmpty)
}

// MARK: - Purge is idempotent

@Test func purgeTombstonesIsIdempotent() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    try repository.upsertVehicle(makeVehicle(vehicleID: vehicleID))

    let old = makeFill(id: UUID.v7(), vehicleID: vehicleID,
                       FillSpec(date: UTC.day(2026, 8, 1), odometer: 119_000, litres: 42.0))
    let fresh = makeFill(id: UUID.v7(), vehicleID: vehicleID,
                         FillSpec(date: UTC.day(2026, 8, 1), odometer: 119_100, litres: 40.0))
    try repository.upsertFillUp(old)
    try repository.upsertFillUp(fresh)
    let now = Date()
    try repository.softDeleteFillUp(id: old.id, at: now.addingTimeInterval(-40 * 86_400))
    try repository.softDeleteFillUp(id: fresh.id, at: now)

    try repository.purgeTombstones()
    let afterFirst = (deleted: try repository.deletedEntries(),
                      count: try repository.rowCount(in: TankbookSchema.fillUp))

    // Second run changes nothing - a purge is a set of DELETE statements whose
    // first execution already removed everything it could.
    try repository.purgeTombstones()
    let afterSecond = (deleted: try repository.deletedEntries(),
                       count: try repository.rowCount(in: TankbookSchema.fillUp))

    #expect(afterFirst.deleted.map(\.id) == afterSecond.deleted.map(\.id))
    #expect(afterFirst.count == afterSecond.count)
    #expect(afterFirst.count == 1)   // the fresh tombstone is still inside the window
    #expect(afterFirst.deleted.map(\.id) == [fresh.id])
}

// MARK: - Purge is a real deletion, not a hide (the backup-export consequence)

@Test func purgedEntriesAreGoneFromTheBackupStream() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    try repository.upsertVehicle(makeVehicle(vehicleID: vehicleID))
    let fill = makeFill(vehicleID: vehicleID,
                        FillSpec(date: UTC.day(2026, 8, 1), odometer: 119_000, litres: 42.0))
    try repository.upsertFillUp(fill)
    try repository.softDeleteFillUp(id: fill.id, at: Date().addingTimeInterval(-40 * 86_400))

    // The backup format includes tombstones (docs/SCHEMA.md -> Backup format:
    // "exact shapes above, tombstones included"), so before the purge the
    // entry WOULD be in a backup: the physical row is still there.
    let idsBefore = try repository.database.read { try FillUpRow.fetchAll($0) }.map(\.fillUp.id)
    #expect(idsBefore == [fill.id])
    #expect(try repository.rowCount(in: TankbookSchema.fillUp) == 1)

    try repository.purgeTombstones()

    // After the purge the row is physically gone: a backup export made now
    // serializes no trace of it. A "hide" (clearing deletedAt, or flagging)
    // would fail this.
    let idsAfter = try repository.database.read { try FillUpRow.fetchAll($0) }.map(\.fillUp.id)
    #expect(idsAfter.isEmpty)
    #expect(try repository.rowCount(in: TankbookSchema.fillUp) == 0)
    #expect(try repository.deletedEntries().isEmpty)
}

// MARK: - Days-remaining countdown (the screen's point)

@Test func daysRemainingCountsDownFrom30AndNeverGoesNegative() throws {
    let now = goldenAsOf
    let day: TimeInterval = 86_400

    #expect(TombstoneCountdown.daysRemaining(deletedAt: now, now: now) == 30,
            "deleted today reads 30")
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-day), now: now) == 29)
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-3 * day), now: now) == 27)
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-27 * day), now: now) == 3)
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-29 * day), now: now) == 1)
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-30 * day), now: now) == 0)
    // Deeper than the window - the purge may not have run yet; never negative.
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(-45 * day), now: now) == 0)
    // A future-stamped tombstone (clock skew) is clamped to the grace period.
    #expect(TombstoneCountdown.daysRemaining(deletedAt: now.addingTimeInterval(day), now: now) == 30)
}

// MARK: - Deleted entries are excluded from stats while deleted

@Test func deletedEntryIsExcludedFromHomeStatsWhileTombstoned() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    let vehicle = makeVehicle(vehicleID: vehicleID)
    try repository.upsertVehicle(vehicle)
    let fills = try seedD1(repository, vehicleID: vehicleID)

    let all = try repository.liveEntries(forVehicle: vehicleID)
    let statsBefore = HomeStats(vehicle: vehicle, entries: all, asOf: goldenAsOf)
    #expect(ConsumptionDelta.displayedValue(statsBefore.headline) == 6.9)

    let target = fills.first { $0.date == UTC.day(2026, 7, 12) }!.id
    try repository.softDeleteFillUp(id: target)

    // `liveEntries` (what Home renders) excludes the tombstone, so HomeStats -
    // which is a pure function of that list - excludes it too. The whole screen
    // depends on this: a restored entry re-enters stats by becoming live again.
    let live = try repository.liveEntries(forVehicle: vehicleID)
    #expect(live.map(\.id).contains(target) == false)
    let statsWhileDeleted = HomeStats(vehicle: vehicle, entries: live, asOf: goldenAsOf)
    #expect(ConsumptionDelta.displayedValue(statsWhileDeleted.headline) != 6.9)

    try repository.restoreEntry(id: target)
    let restoredLive = try repository.liveEntries(forVehicle: vehicleID)
    let statsAfterRestore = HomeStats(vehicle: vehicle, entries: restoredLive, asOf: goldenAsOf)
    #expect(ConsumptionDelta.displayedValue(statsAfterRestore.headline) == 6.9)
}

// MARK: - "Delete all now" purges everything regardless of age

@Test func purgeAllTombstonesRemovesEveryTombstoneEvenInsideTheWindow() throws {
    let repository = try makeRepository()
    let vehicleID = UUID.v7()
    try repository.upsertVehicle(makeVehicle(vehicleID: vehicleID))

    let now = Date()
    for daysAgo in [1.0, 10.0, 29.0] {
        let fill = makeFill(id: UUID.v7(), vehicleID: vehicleID,
                            FillSpec(date: now.addingTimeInterval(-daysAgo * 86_400),
                                     odometer: 119_000, litres: 42.0))
        try repository.upsertFillUp(fill)
        try repository.softDeleteFillUp(id: fill.id, at: now.addingTimeInterval(-daysAgo * 86_400))
    }
    #expect(try repository.deletedEntries().count == 3)

    // "Delete all now" is destructive and immediate: no grace period, every
    // age goes. The vehicle itself is live, so it stays.
    try repository.purgeAllTombstones()

    #expect(try repository.deletedEntries().isEmpty)
    #expect(try repository.rowCount(in: TankbookSchema.fillUp) == 0)
    #expect(try repository.liveVehicles().count == 1)

    // And idempotent: a second "Delete all now" is a no-op.
    try repository.purgeAllTombstones()
    #expect(try repository.rowCount(in: TankbookSchema.fillUp) == 0)
}
