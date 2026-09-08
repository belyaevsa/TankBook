import Foundation
import os
import Testing
@testable import TankbookCore

// The edit-time re-home (`Money.edited`, docs/SCHEMA.md -> Money): when the
// user edits an entry's amount or currency, the pair is re-pended (hard rule
// 3) and re-homed to the vehicle's CURRENT home currency - not the one
// stamped on the row when it was written. An imported Volvo whose Garage home
// is now USD must not have a RUB edit converted into the EUR the import used.
// A no-touch edit leaves a snapshotted pair byte-identical; a same-currency
// edit resolves at rate 1 with no fetch; a still-foreign edit stays pending,
// asking for a rate into the new home. All tests use the real in-memory GRDB
// repository.

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

private func makeVehicle(homeCurrency: CurrencyCode) -> Vehicle {
    Vehicle(id: UUID.v7(), createdAt: day(2026, 1, 1), updatedAt: day(2026, 1, 1), deletedAt: nil,
            name: "Volvo V60", make: nil, model: nil, year: 2015, plate: nil,
            powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
            batteryCapacityKWh: nil, homeCurrency: homeCurrency,
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

/// A `RateFetcher` that records every request and answers nothing - the
/// no-fetch assertion's witness: the edit-time resolve must never call it.
private final class RecordingRateFetcher: RateFetcher, @unchecked Sendable {
    private struct State { var ranges: [(from: Date, to: Date)] = [] }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        lock.withLock { state in state.ranges.append((from, to)) }
        return []
    }
}

@Suite("RV.144: an entry edit re-homes to the car's CURRENT home currency")
struct MoneyEditRehomeTests {

    /// The owner's row, before the backfill ran: a fill paid in a currency
    /// that is no longer the car's, carrying the home currency stamped when the
    /// import wrote it (EUR). The car's Garage home is now USD. Editing the
    /// currency to RUB must end with `homeCurrency == .usd`, never the stale
    /// EUR - the row is about the second field.
    @Test func aCurrencyEditReHomesToTheCarsCurrentHomeCurrency() throws {
        let original = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("1.08"), rateDate: day(2026, 8, 1), source: .ecb))
        #expect(original.homeCurrency == .eur)

        let edited = Money.edited(original: original, amount: decimal("2101.75"),
                                  currency: .rub, homeCurrency: .usd)

        let money = try #require(edited)
        #expect(money.homeCurrency == .usd,
                "the edited pair must home to the car's CURRENT currency, got \(money.homeCurrency.rawValue)")
        #expect(money.currency == .rub)
        #expect(money.amount == decimal("2101.75"))
        #expect(money.isRatePending,
                "a changed-currency edit re-pends: the old EUR conversion no longer describes the row")
        #expect(money.homeAmount == nil, "no snapshot may survive a currency change")
        #expect(money.rate == nil)
    }

    /// The pending shape of the same row: the import left it waiting on a rate
    /// (RV.140's owner evidence), the user edits the currency, and the pending
    /// pair must now ask for a rate into the NEW home.
    @Test func aPendingRowEditReHomesToTheCarsCurrentHomeCurrency() throws {
        let original = Money(amount: decimal("1942.50"), currency: .usd, homeCurrency: .eur)
        #expect(original.isRatePending)

        let edited = Money.edited(original: original, amount: decimal("1942.50"),
                                  currency: .rub, homeCurrency: .usd)

        let money = try #require(edited)
        #expect(money.homeCurrency == .usd)
        #expect(money.currency == .rub)
        #expect(money.isRatePending)
    }

    /// The same edit where the edited currency EQUALS the car's home currency:
    /// the pair is snapshotted at rate 1 - no rate is needed at all, so nothing
    /// may ever fetch for it.
    @Test func anEditToTheCarsHomeCurrencySnapshotsAtRateOne() throws {
        let original = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: day(2026, 8, 1), source: .ecb))
        #expect(original.homeCurrency == .eur)

        let edited = Money.edited(original: original, amount: decimal("289.50"),
                                  currency: .usd, homeCurrency: .usd)

        let money = try #require(edited)
        #expect(!money.isRatePending, "a same-currency edit resolves at commit, never waits")
        #expect(money.homeCurrency == .usd)
        #expect(money.currency == .usd)
        #expect(money.homeAmount == decimal("289.50"), "rate 1: the home amount is the amount as paid")
        #expect(money.rate == Decimal(1))
        #expect(money.homeAmount != original.homeAmount,
                "the stale EUR conversion must be gone, not silently kept")
    }

    /// The no-fetch half of the same-currency claim, through the repository:
    /// an entry carrying the edited (rate-1, snapshotted) pair needs no rate,
    /// so a scoped backfill over it must make no request and leave it filled.
    @Test func sameCurrencyEditNeedsNoFetchAtCommit() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle(homeCurrency: .usd)
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2026, 8, 20)
        let original = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
        let edited = try #require(Money.edited(original: original, amount: decimal("289.50"),
                                               currency: .usd, homeCurrency: .usd))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: edited))

        let fetcher = RecordingRateFetcher()
        let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .backfill(repo, limitedTo: try repo.liveFillUps(forVehicle: vehicle.id))

        #expect(result.filledCount == 0, "nothing is pending to fill")
        #expect(result.stillPendingCount == 0, "the edited row already resolved at rate 1")
        #expect(fetcher.ranges.isEmpty,
                "a rate-1 row needs no rate: the commit resolve must never fetch")
        let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
        #expect(read.money?.isRatePending == false)
        #expect(read.money?.homeCurrency == .usd)
    }

    /// Hard rule 3: an edit that touches neither amount nor currency leaves a
    /// snapshotted pair byte-identical - the EUR conversion stays, because it
    /// was true when it was recorded and a note edit must not restate it.
    @Test func anEditThatTouchesNoMoneyFactLeavesASnapshottedPairByteIdentical() {
        let original = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: day(2026, 8, 1), source: .ecb))

        let edited = Money.edited(original: original, amount: original.amount,
                                  currency: original.currency, homeCurrency: .usd)

        #expect(edited == original,
                "a no-touch edit must return the pair byte-identical, whatever the vehicle home is now")
        #expect(edited?.homeCurrency == .eur)
        #expect(edited?.hasSnapshot == true)
    }

    /// A foreign edit whose rate the cache does not hold stays rate-pending,
    /// is COUNTED by the scoped pass, and is now asking for a rate into the NEW
    /// home currency - the S8 backfill that later fills it converts into USD,
    /// never back into the stale EUR.
    @Test func foreignEditWithNoCachedRateStaysPendingIntoTheNewHome() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle(homeCurrency: .usd)
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2015, 6, 4)
        let original = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)
        let edited = try #require(Money.edited(original: original, amount: decimal("2101.75"),
                                               currency: .rub, homeCurrency: .usd))
        #expect(edited.isRatePending)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: edited))

        // The cache holds RUB->EUR only (the stale direction). A resolve that
        // still looked at the old home would fill the row - this one must not.
        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .rub, date: entryDay, rate: decimal("73.0"), source: .ecb)
        ], calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .backfill(repo, limitedTo: try repo.liveFillUps(forVehicle: vehicle.id))

        #expect(result.filledCount == 0, "a rate into the old home is not the rate the row now asks for")
        #expect(result.stillPendingCount == 1, "the miss is counted, never silent-dropped")

        let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
        #expect(read.money?.isRatePending == true)
        #expect(read.money?.homeCurrency == .usd,
                "a still-foreign edit asks for a rate into the NEW home, never the stale EUR")
        #expect(read.money?.homeAmount == nil, "a miss must never invent a home amount")
        #expect(read.money?.amount == decimal("2101.75"))
    }

    /// The same foreign edit, with the rate for its OWN day in the cache: the
    /// scoped resolve fills it into the NEW home at that day's rate - never
    /// today's (hard rule 3) and never the stale EUR.
    @Test func foreignEditWithACachedRateResolvesIntoTheNewHomeAtTheEntrysOwnDay() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle(homeCurrency: .usd)
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2026, 8, 20)
        let original = Money(amount: decimal("2101.75"), currency: .usd, homeCurrency: .eur)
        let edited = try #require(Money.edited(original: original, amount: decimal("2101.75"),
                                               currency: .rub, homeCurrency: .usd))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: edited))

        let today = utcCalendar.startOfDay(for: Date())
        let store = RateStore(seed: [
            // Original-per-home: RUB per USD on the entry's own day.
            ExchangeRate(base: .usd, quote: .rub, date: entryDay, rate: decimal("80.0"), source: .ecb),
            // Today's very different rate: a wrong-date resolve would use it.
            ExchangeRate(base: .usd, quote: .rub, date: today, rate: decimal("200.0"), source: .ecb),
            // The stale direction - a resolve into EUR would silently succeed.
            ExchangeRate(base: .eur, quote: .rub, date: entryDay, rate: decimal("73.0"), source: .ecb)
        ], calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .backfill(repo, limitedTo: try repo.liveFillUps(forVehicle: vehicle.id))

        #expect(result.filledCount == 1)
        #expect(result.stillPendingCount == 0)

        let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
        let money = try #require(read.money)
        #expect(money.homeCurrency == .usd)
        #expect(money.homeAmount == decimal("26.27"),
                "2101.75 / 80.0 at the entry's own day -> 26.27 USD; today's 200.0 would give 10.51")
        #expect(money.rateDate == entryDay, "rateDate is the entry date, never today")
    }

    /// An edit that changes the AMOUNT alone on a snapshotted foreign row also
    /// re-homes and re-pends: the old snapshot described the old amount, and
    /// the pair must ask for a rate into the current home for the new one.
    @Test func anAmountEditRePendsAndReHomesASnapshottedForeignRow() throws {
        let original = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: day(2026, 8, 1), source: .ecb))

        let edited = Money.edited(original: original, amount: decimal("250.00"),
                                  currency: .pln, homeCurrency: .usd)

        let money = try #require(edited)
        #expect(money.amount == decimal("250.00"))
        #expect(money.homeCurrency == .usd, "an amount edit re-homes too")
        #expect(money.isRatePending, "the amount edit cleared the stale snapshot")
        #expect(money.homeAmount == nil)
    }
}
