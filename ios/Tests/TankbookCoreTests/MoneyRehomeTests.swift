import Foundation
import os
import Testing
@testable import TankbookCore

// RV.140 - the re-home pass a home-currency change runs (docs/SCHEMA.md ->
// Money): when a car's home currency changes in the Garage, its rate-pending
// entries adopt the new home currency. An entry whose original currency now
// EQUALS the new home is snapshotted at rate 1 by `Money.init` - no rate, no
// fetch; one whose currency still differs stays rate-pending, now asking for a
// rate into the new home. An entry already carrying a snapshot is never
// rewritten (hard rule 3). All tests use the real in-memory GRDB repository.

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

private func makeRepository() throws -> TankbookRepository {
    TankbookRepository(database: try TankbookDatabase.inMemory())
}

private func makeVehicle() -> Vehicle {
    Vehicle(id: UUID.v7(), createdAt: day(2026, 1, 1), updatedAt: day(2026, 1, 1), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
}

private func makeFillUp(vehicleId: UUID, date: Date, odometer: Int = 1000,
                        money: Money) -> FillUp {
    FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
           vehicleId: vehicleId, date: date, odometer: odometer,
           money: money, note: nil, attachments: [], provenance: .manual, conflict: .none,
           purchaseGroupId: nil, volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
           fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
           crossCheck: .notApplicable, extraction: nil)
}

/// A `RateFetcher` that records every requested range and would answer anything
/// - the no-fetch assertion's witness: a re-home pass must never call it.
private final class RecordingRateFetcher: RateFetcher, @unchecked Sendable {
    private struct State { var ranges: [(from: Date, to: Date)] = [] }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { state in state.ranges.append((from, to)) }
        return RatePack(rates: [])
    }
}

@Suite("RV.140: a home-currency change re-homes pending entries only")
struct RehomeTests {
    private func makeUSDFill(vehicleId: UUID, date: Date, odometer: Int, amount: String) -> FillUp {
        makeFillUp(vehicleId: vehicleId, date: date, odometer: odometer,
                   money: Money(amount: decimal(amount), currency: .usd, homeCurrency: .eur))
    }

    /// The row's whole point, both halves in one test: a car whose home
    /// currency changes EUR -> USD re-homes its rate-pending USD entries, and
    /// an entry already carrying a snapshot is left BYTE-IDENTICAL - a fix that
    /// rewrites history fails here.
    @Test func rehomeRewritesPendingEntriesAndLeavesSnapshottedOnesByteIdentical() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2024, 3, 12)
        // A snapshotted PLN row: converted to EUR at its own day when home was
        // EUR - history that was true when recorded and must survive the change.
        let snapshotted = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
        let snapshottedFill = makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                         odometer: 100_000, money: snapshotted)
        try repo.upsertFillUp(snapshottedFill, syncState: .synced(scn: 42))
        // The owner's imported rows: USD, still waiting on a rate.
        let pendingA = makeUSDFill(vehicleId: vehicle.id, date: entryDay,
                                   odometer: 100_500, amount: "110.00")
        let pendingB = makeUSDFill(vehicleId: vehicle.id, date: entryDay,
                                   odometer: 101_000, amount: "132.00")
        try repo.upsertFillUp(pendingA)
        try repo.upsertFillUp(pendingB)
        // The snapshot's state BEFORE the change - the "byte-identical" claim
        // is only asserted against this moment, never against a re-read.
        let snapshotBefore = try repo.liveFillUps(forVehicle: vehicle.id)
            .first { $0.id == snapshottedFill.id }?.money

        // No rate cache, no fetcher seeded with anything: the re-home must not
        // need them - same-currency money converts by identity.
        let store = RateStore(seed: [], fetcher: RecordingRateFetcher(), calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .rehome(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 2, "both pending USD rows resolve at rate 1")
        #expect(result.stillPendingCount == 0)

        let read = try repo.liveFillUps(forVehicle: vehicle.id)
        let afterSnapshot = read.first { $0.id == snapshottedFill.id }?.money
        #expect(afterSnapshot == snapshotBefore,
                "a snapshotted entry must be byte-identical after a home-currency change")
        #expect(afterSnapshot?.homeCurrency == .eur,
                "the snapshot keeps its original home currency, never re-stated in the new one")
        #expect(afterSnapshot?.hasSnapshot == true)

        for fill in read where fill.id == pendingA.id || fill.id == pendingB.id {
            let money = try #require(fill.money)
            #expect(!money.isRatePending, "a same-currency row is no longer pending")
            #expect(money.homeCurrency == .usd, "the row's home follows the vehicle's new home")
            #expect(money.currency == .usd)
            #expect(money.homeAmount == money.amount, "same-currency rows convert at rate 1")
            #expect(money.rate == Decimal(1))
        }

        // The re-homed rows are queued dirty so they travel to other devices
        // (docs/SYNC.md S8/S9); the untouched snapshot is not.
        let dirty = try repo.fetchDirtyRows()
        #expect(dirty.contains { $0.entityType == "fillUp" && $0.id == pendingA.id })
        #expect(dirty.contains { $0.entityType == "fillUp" && $0.id == pendingB.id })
        #expect(!dirty.contains { $0.id == snapshottedFill.id },
                "an untouched snapshot must not be re-queued for sync")
    }

    /// The owner's case needs NO network: 381 same-currency rows resolve at
    /// rate 1 with a fetcher that would record (and fail on) any request.
    @Test func rehomeToSameCurrencySnapshotsAtRateOneWithNoFetch() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        for (index, odometer) in [100_000, 100_500, 101_000, 101_500].enumerated() {
            try repo.upsertFillUp(makeUSDFill(vehicleId: vehicle.id,
                                              date: day(2024, 3, 12 + index),
                                              odometer: odometer, amount: "110.00"))
        }

        let fetcher = RecordingRateFetcher()
        let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .rehome(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 4)
        #expect(result.stillPendingCount == 0)
        #expect(fetcher.ranges.isEmpty,
                "same-currency rows need no rate: a re-home must never fetch")
        let rows = try repo.liveFillUps(forVehicle: vehicle.id)
        #expect(rows.allSatisfy { $0.money?.homeCurrency == .usd })
        #expect(rows.allSatisfy { $0.money?.isRatePending == false })
        #expect(rows.allSatisfy { $0.money?.homeAmount == $0.money?.amount })
    }

    /// A genuinely mixed history is legitimate and survives: a snapshotted EUR
    /// row keeps its EUR snapshot, a pending USD row resolves at rate 1, and a
    /// pending PLN row is re-homed - still pending, but now asking for a rate
    /// into the NEW home currency (USD), never the old EUR.
    @Test func mixedHistoryKeepsSnapshottedRowsInTheirOriginalHomeCurrency() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2024, 3, 12)
        let snapshotted = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
        let snapshottedFill = makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                         odometer: 100_000, money: snapshotted)
        try repo.upsertFillUp(snapshottedFill)
        let pendingUSD = makeUSDFill(vehicleId: vehicle.id, date: entryDay,
                                     odometer: 100_500, amount: "110.00")
        let pendingPLN = makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                    odometer: 101_000,
                                    money: Money(amount: decimal("200.00"), currency: .pln,
                                                 homeCurrency: .eur))
        try repo.upsertFillUp(pendingUSD)
        try repo.upsertFillUp(pendingPLN)
        let snapshotBefore = try repo.liveFillUps(forVehicle: vehicle.id)
            .first { $0.id == snapshottedFill.id }?.money

        let store = RateStore(seed: [], fetcher: RecordingRateFetcher(), calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .rehome(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 1, "only the USD row resolves at rate 1")
        #expect(result.stillPendingCount == 1, "the PLN row is re-homed and stays counted")

        let read = try repo.liveFillUps(forVehicle: vehicle.id)
        let snapshotAfter = try #require(read.first { $0.id == snapshottedFill.id }?.money)
        #expect(snapshotAfter == snapshotBefore, "the snapshotted row is byte-identical")
        #expect(snapshotAfter == snapshotted)
        #expect(snapshotAfter.homeCurrency == .eur)
        #expect(snapshotAfter.homeAmount == decimal("67.79"))

        let plnAfter = try #require(read.first { $0.id == pendingPLN.id }?.money)
        #expect(plnAfter.isRatePending)
        #expect(plnAfter.homeCurrency == .usd,
                "a still-foreign row asks for a rate into the NEW home, never the old EUR")
        #expect(plnAfter.currency == .pln)
        #expect(plnAfter.homeAmount == nil)

        let usdAfter = try #require(read.first { $0.id == pendingUSD.id }?.money)
        #expect(!usdAfter.isRatePending)
        #expect(usdAfter.homeAmount == decimal("110.00"))
        #expect(usdAfter.rate == Decimal(1))
    }
}
