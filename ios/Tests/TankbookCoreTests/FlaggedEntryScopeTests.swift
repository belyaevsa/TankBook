import Foundation
import Testing
@testable import TankbookCore

// RV.66 (2026-09-05) - pins the account-wide / car-scoped asymmetry deliberately.
//
// The account-wide flagged signal (`flaggedEntryCount`) is the number of LIVE
// records carrying a `ConflictState` across every entry table and EVERY vehicle
// (`Repository+FlaggedEntries.swift` - the SQL has no vehicle predicate), while
// Home's rows - the surface where a conflict badge can actually appear - are the
// SELECTED vehicle's alone (`liveEntries(forVehicle:)`). A conflict on car B
// therefore leaves car A's Home looking clean while the account-wide dot
// insists something is wrong.
//
// These tests pin BOTH halves so a later change cannot silently "fix" the
// symptom by making the count car-scoped: `flaggedEntryCount` MUST stay
// account-wide, and `liveEntries(forVehicle:)` MUST stay car-scoped. The
// routing fix (the sync chip body reaching the account-wide list) is the
// response to that asymmetry; narrowing the count to the selected car would be
// hiding the problem, which hard rule 8 forbids.

private let timestamp = Date(timeIntervalSince1970: 1_752_000_000)

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle(id: UUID = UUID.v7(), name: String) -> Vehicle {
    Vehicle(
        id: id, createdAt: timestamp, updatedAt: timestamp, deletedAt: nil,
        name: name, make: nil, model: nil, year: 2021, plate: nil,
        powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
        batteryCapacityKWh: nil, homeCurrency: .eur,
        units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                              energy: .kWhPer100),
        photo: nil, archived: false, paceLimitKmPerDay: 1500,
        initialOdometer: 118_000)
}

private func makeFill(vehicleId: UUID, odometer: Int, daysAgo: Int,
                      conflict: ConflictState = .none) -> FillUp {
    let date = timestamp.addingTimeInterval(-Double(daysAgo) * 86_400)
    return FillUp(
        id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
        vehicleId: vehicleId, date: date, odometer: odometer,
        money: Money(amount: Decimal(string: "71.02")!, currency: .eur,
                     homeCurrency: .eur),
        note: nil, attachments: [], provenance: .manual, conflict: conflict,
        purchaseGroupId: nil, volumeL: 42.3,
        unitPrice: Decimal(string: "1.679")!, fuelKind: .petrol95,
        fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
        crossCheck: .notApplicable, extraction: nil)
}

private func flaggedOrder() -> ConflictState {
    .flagged(kind: .order, detectedAt: timestamp)
}

@Suite("Flagged-entry count is account-wide, Home rows are car-scoped (RV.66)")
struct FlaggedEntryScopeTests {

    /// A conflict on the NON-selected car counts account-wide while that car's
    /// rows are the only ones carrying the badge - the exact RV.66 asymmetry.
    @Test("a conflict on one car counts while the other car's rows are clean")
    func flagOnSecondCarCountsAccountWide() throws {
        let repository = try makeRepository()
        let carA = makeVehicle(name: "Volvo V60")
        let carB = makeVehicle(name: "Golf GTI")
        try repository.upsertVehicle(carA)
        try repository.upsertVehicle(carB)
        try repository.upsertFillUp(makeFill(vehicleId: carA.id, odometer: 120_000, daysAgo: 5))
        try repository.upsertFillUp(makeFill(vehicleId: carB.id, odometer: 88_000, daysAgo: 60))
        try repository.upsertFillUp(makeFill(vehicleId: carB.id, odometer: 87_500, daysAgo: 2,
                                             conflict: flaggedOrder()))

        // Account-wide: the flagged count sees car B's conflict.
        #expect(try repository.flaggedEntryCount() == 1,
                "the count is account-wide: car B's flag must count")

        // Car-scoped: car A's rows (the selected car in the RV.66 scenario) are
        // clean, so Home renders no badge - and car B's rows carry the flag.
        let carARows = try repository.liveEntries(forVehicle: carA.id)
        #expect(carARows.count == 1)
        #expect(carARows.allSatisfy { $0.conflict == .none },
                "the selected car's rows must stay clean - Home never shows other cars' conflicts")
        let carBRows = try repository.liveEntries(forVehicle: carB.id)
        #expect(carBRows.count == 2)
        #expect(carBRows.contains { $0.conflict != .none },
                "the flag must live on the flagged car's own rows")
    }

    /// The count grows across BOTH cars - a later change that narrowed the SQL
    /// to one vehicle would drop car A's flag and fail here.
    @Test("a second flag on the other car raises the account-wide count")
    func countSpansVehicles() throws {
        let repository = try makeRepository()
        let carA = makeVehicle(name: "Volvo V60")
        let carB = makeVehicle(name: "Golf GTI")
        try repository.upsertVehicle(carA)
        try repository.upsertVehicle(carB)
        try repository.upsertFillUp(makeFill(vehicleId: carA.id, odometer: 120_000, daysAgo: 5,
                                             conflict: flaggedOrder()))
        try repository.upsertFillUp(makeFill(vehicleId: carB.id, odometer: 87_500, daysAgo: 2,
                                             conflict: flaggedOrder()))
        try repository.upsertFillUp(makeFill(vehicleId: carB.id, odometer: 88_000, daysAgo: 60))

        #expect(try repository.flaggedEntryCount() == 2,
                "flags on two different vehicles must both count")
    }

    /// The count counts LIVE rows only (deletedAt IS NULL), across every entry
    /// table - the tombstone rule behind "the badge survives being ignored"
    /// (hard rule 8) until the user resolves the flag.
    @Test("a tombstoned flag leaves the count")
    func deletedFlagLeavesTheCount() throws {
        let repository = try makeRepository()
        let car = makeVehicle(name: "Volvo V60")
        try repository.upsertVehicle(car)
        let flagged = makeFill(vehicleId: car.id, odometer: 87_500, daysAgo: 2,
                               conflict: flaggedOrder())
        try repository.upsertFillUp(flagged)
        #expect(try repository.flaggedEntryCount() == 1)

        try repository.softDeleteFillUp(id: flagged.id)
        #expect(try repository.flaggedEntryCount() == 0,
                "a deleted entry must leave the derived count - nothing ghost-counts")
    }
}
