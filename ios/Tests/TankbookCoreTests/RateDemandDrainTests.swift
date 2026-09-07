import Foundation
import os
import Testing
@testable import TankbookCore

// RV.111 - the demand drain a "Check for rates" tap runs (docs/SYNC.md S8,
// docs/ERRORS.md -> Home). An imported entry is written rate-pending on purpose
// (hard rule 3: `rateDate` is the ENTRY date, and a 2015 rate is not on the
// device at import time). The rolling launch pass only refreshes the last
// `packWindowDays` days, so a row dated years back is never asked for again by
// any automatic path - the drain must ask over the span the pending rows
// actually cover. All tests use the real in-memory GRDB repository and run on
// macOS (docs/TESTING.md, L1); the fetchers echo or refuse requested spans so a
// wrong span cannot fill the row.

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

private func makeFillUp(vehicleId: UUID, date: Date, odometer: Int,
                        currency: CurrencyCode, amount: String) -> FillUp {
    FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
           vehicleId: vehicleId, date: date, odometer: odometer,
           money: Money(amount: decimal(amount), currency: currency, homeCurrency: .eur),
           note: nil, attachments: [], provenance: .import(source: "mfm"), conflict: .none,
           purchaseGroupId: nil, volumeL: 45, unitPrice: nil, fuelKind: .petrol95,
           fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
           crossCheck: .notApplicable, extraction: nil)
}

/// A `RateFetcher` that answers each requested span with a rate row for EVERY
/// date in it (the core shape of the `-stubRatesEcho` UI seam). If the drain
/// asked the rolling pack instead of the pending rows' own dates, no rate for
/// an old date would ever come back and the row would stay pending - so an
/// echo fetcher is what proves the retry asked for the right span.
private final class EchoSpanRateFetcher: RateFetcher, @unchecked Sendable {
    private struct State {
        var ranges: [(from: Date, to: Date)] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        lock.withLock { state in state.ranges.append((from, to)) }
        var rows: [ExchangeRate] = []
        var cursor = utcCalendar.startOfDay(for: from)
        let last = utcCalendar.startOfDay(for: to)
        while cursor <= last, rows.count < 800 {
            rows.append(ExchangeRate(base: base, quote: .usd, date: cursor,
                                     rate: decimal("1.10"), source: .ecb))
            rows.append(ExchangeRate(base: base, quote: .pln, date: cursor,
                                     rate: decimal("4.2706"), source: .ecb))
            guard let next = utcCalendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return rows
    }
}

/// A `RateFetcher` that records every requested range and answers an EMPTY pack
/// - the provider was reached and has no row for those dates (the genuine dead
/// end), the shape `-stubRatesMissThenHit`'s first request produces.
private final class EmptyPackRecordingFetcher: RateFetcher, @unchecked Sendable {
    private struct State {
        var ranges: [(from: Date, to: Date)] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        lock.withLock { state in state.ranges.append((from, to)) }
        return []
    }
}

/// A `RateFetcher` whose fetch always fails - the offline transport shape.
private final class FailingRateFetcher: RateFetcher, @unchecked Sendable {
    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - The row's whole point: a pending row older than the window is asked for

@MainActor @Test func demandDrainAsksOutsideTheRollingWindowAndFillsWhenTheAnswerArrives() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    // Years back - deliberately OUTSIDE `RateStore.packWindowDays`, which is the
    // case RV.106's ~100-day import never hit and this row exists for. A test
    // dated inside the window passes against today's rolling-only code.
    let oldDay = day(2015, 6, 4)
    #expect(utcCalendar.startOfDay(for: oldDay) < RateStore.rollingPackFrom(now: Date()),
            "the fixture must predate the rolling pack window or the test is vacuous")
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: oldDay, odometer: 100_000,
                                     currency: .pln, amount: "289.50"))

    let fetcher = EchoSpanRateFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
    let outcome = try #require(await MoneyBackfillService(store: store).demandDrain(repo))

    #expect(outcome.filledCount == 1)
    #expect(outcome.stillPendingCount == 0)
    #expect(outcome.reachedProvider)
    // The span asked for had to reach the 2015 date: the echo fetcher only
    // answers the requested range, so the fill proves the demand asked the
    // pending row's own date, never the rolling pack.
    #expect(fetcher.ranges.contains { $0.from <= oldDay && $0.to >= oldDay },
            "the drain must ask over the pending row's date, got \(fetcher.ranges)")

    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.homeAmount == decimal("67.79"))
    #expect(read.money?.rateDate == utcCalendar.startOfDay(for: oldDay),
            "rateDate must be the entry date, never today (hard rule 3)")
}

// MARK: - A date the provider cannot serve stays pending and counted, never today's rate

@MainActor @Test func demandDrainLeavesAGenuinelyMissingDatePendingAndCounted() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let oldDay = day(2015, 6, 4)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: oldDay, odometer: 100_000,
                                     currency: .pln, amount: "289.50"))

    // The store holds a rate for TODAY and nothing for 2015; the fetcher
    // answers empty - the provider reached, no row for that date. A defect that
    // "resolves" the row at today's rate would fill it from the seed below.
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: Date(), rate: decimal("4.2706"), source: .ecb)
    ], fetcher: EmptyPackRecordingFetcher(), calendar: utcCalendar)
    let outcome = try #require(await MoneyBackfillService(store: store).demandDrain(repo))

    #expect(outcome.filledCount == 0)
    #expect(outcome.stillPendingCount == 1, "the row stays pending and counted")
    #expect(outcome.reachedProvider)
    #expect(outcome.hasUnresolvableRows,
            "a reached pass that leaves a pre-window date pending is the dead end")

    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.isRatePending == true, "still pending")
    #expect(read.money?.homeAmount == nil, "no home amount may be written from today's rate")
    #expect(read.money?.rateDate == nil, "no snapshot may be written at another day's rate")
}

// MARK: - The bound: a decade-long pending span is chunked, not one request

@MainActor @Test func demandDrainChunksADecadeLongPendingSpanUnderTheServerCap() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let first = day(2010, 1, 1)
    let last = day(2019, 12, 31)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: first, odometer: 10_000,
                                     currency: .usd, amount: "110"))
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: last, odometer: 200_000,
                                     currency: .usd, amount: "132"))

    let fetcher = EmptyPackRecordingFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
    _ = await MoneyBackfillService(store: store).demandDrain(repo)

    // A specific number, not "more than one": the drain extends the span one
    // day past the newest date (RV.111's UTC-wire guard), so 2010-01-01 through
    // 2020-01-01 - 3653 inclusive days at 400 per chunk - is ten consecutive
    // requests.
    let requestedTo = utcCalendar.date(byAdding: .day, value: 1, to: last) ?? last
    let inclusiveDays = utcCalendar.dateComponents([.day], from: first, to: requestedTo).day! + 1
    let expected = (inclusiveDays + RateStore.packWindowDays - 1) / RateStore.packWindowDays
    let ranges = fetcher.ranges
    #expect(ranges.count == expected,
            "a \(inclusiveDays)-day span is \(expected) chunks, got \(ranges.count)")
    #expect(ranges.count == 10)
    for (from, to) in ranges {
        let chunkDays = utcCalendar.dateComponents([.day], from: from, to: to).day! + 1
        #expect(chunkDays <= RateStore.packWindowDays,
                "each chunk must fit the server's \(RateStore.packWindowDays)-day cap")
    }
    let sorted = ranges.sorted { $0.from < $1.from }
    #expect(sorted.first?.from == first, "the chunks start at the oldest pending date")
    #expect(sorted.last?.to == requestedTo, "the chunks reach a day past the newest pending date")
}

// MARK: - No pending rows means no request at all

@MainActor @Test func demandDrainMakesNoRequestWhenNothingIsPending() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)
    // A fully converted history: every row already carries its home amount, so
    // there is nothing to ask for.
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: day(2026, 8, 1),
                                     odometer: 100_000, currency: .eur, amount: "70.56"))

    let fetcher = EmptyPackRecordingFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
    let outcome = await MoneyBackfillService(store: store).demandDrain(repo)

    #expect(outcome == nil, "no pending rows must yield no demand pass")
    #expect(fetcher.ranges.isEmpty, "no pending rows must mean no request at all")
}

// MARK: - Offline: the fetch fails silently and the backfill still fills from cache

@MainActor @Test func demandDrainOfflineIsSilentAndFillsFromTheCache() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let oldDay = day(2015, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: oldDay, odometer: 100_000,
                                     currency: .pln, amount: "289.50"))

    // The cache already holds the rate for the pending row's day (fetched on an
    // earlier launch); the demand fetch now fails - a non-event (hard rule 1).
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: oldDay, rate: decimal("4.2706"), source: .ecb)
    ], fetcher: FailingRateFetcher(), calendar: utcCalendar)
    let outcome = try #require(await MoneyBackfillService(store: store).demandDrain(repo))

    #expect(!outcome.reachedProvider, "a failed fetch is not a reached provider")
    #expect(outcome.filledCount == 1, "the backfill still fills whatever the cache holds")
    #expect(outcome.stillPendingCount == 0)
    #expect(!outcome.hasUnresolvableRows,
            "an offline pass proves nothing about a date, so it is not a dead end")

    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.homeAmount == decimal("67.79"))
    #expect(read.money?.rateDate == utcCalendar.startOfDay(for: oldDay))
}

// MARK: - A within-window miss is NOT the dead end

@MainActor @Test func demandDrainDoesNotDeadEndARowTheRollingPassWillStillReach() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    // RV.106's shape: a pending row INSIDE the rolling window whose rate the
    // server had not published at import time. The demand comes back empty now,
    // but a later launch's rolling pass re-asks the date - so it must not be
    // labelled unresolvable.
    let today = utcCalendar.startOfDay(for: Date())
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: today, odometer: 120_000,
                                     currency: .pln, amount: "289.50"))

    let store = RateStore(seed: [], fetcher: EmptyPackRecordingFetcher(), calendar: utcCalendar)
    let outcome = try #require(await MoneyBackfillService(store: store).demandDrain(repo))

    #expect(outcome.stillPendingCount == 1)
    #expect(outcome.reachedProvider)
    #expect(!outcome.hasUnresolvableRows,
            "a within-window miss may still resolve on a later launch pass")
}
