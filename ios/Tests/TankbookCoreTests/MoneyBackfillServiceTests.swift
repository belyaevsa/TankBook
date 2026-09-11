import Foundation
import Testing
@testable import TankbookCore

// P5.2a - the money backfill service (hard rule 3, docs/SCHEMA.md -> Money
// conversion semantics, docs/SYNC.md S8), the manual-rate override path
// (hard rule 13, F9), the rate-cache persistence and the derived pending
// count. All tests use the real in-memory GRDB repository.

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
            name: "Volvo V60", make: nil, model: nil, year: 2021, plate: nil,
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

private func makeCharge(vehicleId: UUID, date: Date, money: Money) -> ChargeSession {
    ChargeSession(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                  vehicleId: vehicleId, date: date, odometer: 2000, money: money,
                  note: nil, attachments: [], provenance: .manual, conflict: .none,
                  purchaseGroupId: nil, energyKWh: 43.2, unitPrice: nil,
                  chargeType: .dcPublic, provider: "Ionity", tariffId: nil,
                  durationMin: nil, socStartPct: nil, socEndPct: nil, extraction: nil)
}

private func makeService(vehicleId: UUID, date: Date, money: Money) -> ServiceRecord {
    ServiceRecord(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
                  vehicleId: vehicleId, date: date, odometer: 3000, money: money,
                  note: nil, attachments: [], provenance: .manual, conflict: .none,
                  purchaseGroupId: nil, vendor: "Bosch", items: [], usedParts: [],
                  tireSetId: nil)
}

private func makeExpense(vehicleId: UUID, date: Date, money: Money) -> Expense {
    Expense(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: vehicleId, date: date, odometer: nil, money: money,
            note: nil, attachments: [], provenance: .manual, conflict: .none,
            purchaseGroupId: nil, category: .insurance, title: "Insurance",
            recurrence: nil, installedInServiceId: nil)
}

private func pendingMoney(currency: CurrencyCode, amount: String) -> Money {
    Money(amount: decimal(amount), currency: currency, homeCurrency: .eur)
}

private func eurMoney(_ amount: String) -> Money {
    Money(amount: decimal(amount), currency: .eur, homeCurrency: .eur)
}

/// A `RateFetcher` that returns a fixed pack, so `refreshAndBackfill` (PJ.8)
/// can be driven end to end without a live feed - the exact shape a UI-test
/// stub transport produces after decode.
private final class PackRateFetcher: RateFetcher, @unchecked Sendable {
    private let rates: [ExchangeRate]
    init(rates: [ExchangeRate]) { self.rates = rates }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        rates
    }
}

// MARK: - rateDate is the entry date, never today (F9)

@Test func backfillRateDateIsTheEntrysDayNotToday() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    // The entry is dated well in the past - NOT today - which is the whole
    // point: with a today-dated entry this test would pass even if the code
    // wrongly stamped the fetch/today date (the exact F9 defect).
    let entryDay = day(2024, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                     money: pendingMoney(currency: .pln, amount: "289.50")))

    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)
    let result = try MoneyBackfillService(store: store).backfill(repo)

    #expect(result.filledCount == 1)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.homeAmount == decimal("67.79"))
    #expect(read.money?.rateDate == entryDay, "rateDate must be the entry date")
    #expect(read.money?.rateDate != day(2026, 8, 27), "rateDate must never be today")
}

// MARK: - Never convert at today's rate (hard rule 3)

/// RV.88, found by an orchestrator mutation that PASSED: adding a "fall back to
/// today's rate when the entry's own day has none" made every row convert, the
/// pending count go to zero and the month totals fill in - and **all 1529 tests
/// stayed green**. Hard rule 3's central promise ("`rateDate` = entry date,
/// never today") was documented and unenforced for the case that matters: an
/// old entry whose day the rate archive cannot serve.
///
/// The existing coverage seeds a rate FOR the entry's day, so it cannot see the
/// fallback. This seeds only a recent rate and asserts the old row stays
/// pending - a wrong number that looks right is the failure mode here, because
/// nobody can tell a 2015 fill converted at a 2026 rate by looking at it.
@Test func anEntryWhoseOwnDayHasNoRateStaysPending_NeverTodaysRate() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let oldDay = day(2015, 6, 4)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: oldDay,
                                     money: pendingMoney(currency: .pln, amount: "289.50")))

    // The archive holds a rate for TODAY and nothing for 2015 - the real shape
    // of an ECB-backed store with a rolling window (RV.50, RV.88's own limit).
    // Today's date is deliberate: a "fall back to today" defect reads from the
    // same wall clock this fixture writes to, so seeding any other day would
    // let the defect pass for the wrong reason (the first version of this test
    // seeded 2026-09-05 and did exactly that).
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: Date(),
                     rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)

    let result = try MoneyBackfillService(store: store).backfill(repo)

    #expect(result.filledCount == 0, "a rate the archive cannot serve must not be substituted")
    #expect(result.stillPendingCount == 1, "the row stays pending and counted, never silently zeroed")
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.isRatePending == true, "still pending")
    #expect(read.money?.rateDate == nil, "no snapshot may be written from another day's rate")
    #expect(read.money?.homeAmount == nil, "no home amount may be invented")
}

// MARK: - Never recompute a written snapshot

@Test func backfillNeverRecomputesAWrittenSnapshot() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    // The entry already carries a snapshot written at 4.2706.
    let existing = pendingMoney(currency: .pln, amount: "289.50")
        .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: existing))

    // The cache holds a DIFFERENT rate for that pair and day. A test whose
    // second rate equals the first would pass even under a recompute defect.
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("3.0"), source: .cis)
    ], calendar: utcCalendar)
    let result = try MoneyBackfillService(store: store).backfill(repo)

    #expect(result.filledCount == 0)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money == existing, "the written snapshot must be byte-identical after a pass")
}

// MARK: - Manual rate replaces a feed snapshot and survives backfill

@Test func manualRateReplacesAFeedSnapshot() {
    let entryDay = day(2024, 3, 12)
    let feed = pendingMoney(currency: .pln, amount: "289.50")
        .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
    #expect(feed.homeAmount == decimal("67.79"))
    #expect(feed.rateSource == .ecb)

    // A manual rate is the user's decision: it REPLACES the feed snapshot.
    let manual = feed.applyingManualRate(decimal("4.0"), on: entryDay)
    #expect(manual.homeAmount == decimal("72.38")) // 289.50 / 4.0 rounded
    #expect(manual.rate == decimal("4.0"))
    #expect(manual.rateDate == entryDay)
    #expect(manual.rateSource == .manual)
}

@Test func manualRateSurvivesASubsequentBackfillPass() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    let feed = pendingMoney(currency: .pln, amount: "289.50")
        .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
    let manual = feed.applyingManualRate(decimal("4.0"), on: entryDay)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: manual))

    // The feed still holds 4.2706 for that pair and day; a backfill pass must
    // leave the user's manual value untouched (hard rule 13).
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)
    let result = try MoneyBackfillService(store: store).backfill(repo)

    #expect(result.filledCount == 0)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.rate == decimal("4.0"))
    #expect(read.money?.rateSource == .manual)
    #expect(read.money?.homeAmount == decimal("72.38"))
}

// MARK: - The filled snapshot is marked dirty so it syncs (S8)

@Test func backfillMarksTheRecordDirty() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    let fill = makeFillUp(vehicleId: vehicle.id, date: entryDay,
                          money: pendingMoney(currency: .pln, amount: "289.50"))
    // The entry was already synced; backfilling must re-mark it dirty.
    try repo.upsertFillUp(fill, syncState: .synced(scn: 42))

    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)
    let result = try MoneyBackfillService(store: store).backfill(repo)
    #expect(result.filledCount == 1)

    let dirty = try repo.fetchDirtyRows()
    #expect(dirty.contains { $0.entityType == "fillUp" && $0.id == fill.id },
            "the filled snapshot must be queued for sync (S8)")
}

// MARK: - Idempotence

@Test func backfillIsIdempotent() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                     money: pendingMoney(currency: .pln, amount: "289.50")))
    try repo.upsertExpense(makeExpense(vehicleId: vehicle.id, date: entryDay,
                                       money: pendingMoney(currency: .usd, amount: "100")))

    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb),
        ExchangeRate(base: .eur, quote: .usd, date: entryDay, rate: decimal("1.1"), source: .ecb),
    ], calendar: utcCalendar)
    let service = MoneyBackfillService(store: store)

    let first = try service.backfill(repo)
    #expect(first.filledCount == 2)

    let fillsBefore = try repo.liveFillUps(forVehicle: vehicle.id)
    let expensesBefore = try repo.liveExpenses(forVehicle: vehicle.id)

    let second = try service.backfill(repo)
    #expect(second.filledCount == 0, "a second pass must fill nothing")
    #expect(second.stillPendingCount == 0)

    let fillsAfter = try repo.liveFillUps(forVehicle: vehicle.id)
    let expensesAfter = try repo.liveExpenses(forVehicle: vehicle.id)
    #expect(fillsBefore == fillsAfter, "the second pass must change nothing")
    #expect(expensesBefore == expensesAfter, "the second pass must change nothing")
}

// MARK: - All four entry types

@Test func backfillCoversAllFourEntryTypes() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                     money: pendingMoney(currency: .pln, amount: "400")))
    try repo.upsertChargeSession(makeCharge(vehicleId: vehicle.id, date: entryDay,
                                            money: pendingMoney(currency: .pln, amount: "200")))
    try repo.upsertServiceRecord(makeService(vehicleId: vehicle.id, date: entryDay,
                                             money: pendingMoney(currency: .pln, amount: "100")))
    try repo.upsertExpense(makeExpense(vehicleId: vehicle.id, date: entryDay,
                                       money: pendingMoney(currency: .pln, amount: "50")))

    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.0"), source: .ecb)
    ], calendar: utcCalendar)
    let result = try MoneyBackfillService(store: store).backfill(repo)

    #expect(result.filledCount == 4)
    #expect(try repo.liveFillUps(forVehicle: vehicle.id).first?.money?.homeAmount == decimal("100"))
    #expect(try repo.liveChargeSessions(forVehicle: vehicle.id).first?.money?.homeAmount == decimal("50"))
    #expect(try repo.liveServiceRecords(forVehicle: vehicle.id).first?.money?.homeAmount == decimal("25"))
    #expect(try repo.liveExpenses(forVehicle: vehicle.id).first?.money?.homeAmount == decimal("12.50"))
}

// MARK: - Derived stats follow (hard rule 2)

/// RV.147 rewrote the pre-backfill half of this contract: the old test asserted
/// costPerKm = 0.1 with the pending PLN row SKIPPED (summed as nothing) - the
/// exact defect RV.147 removes. A window holding a rate-pending row has NO
/// exact cost-per-km: a partial numerator over the complete 1000 km span would
/// be low by an unknown amount while looking plausible (docs/SCHEMA.md ->
/// COST/KM). The figure is absent until the backfill lands and the window's
/// money is exact.
@Test func derivedCostPerKmFollowsBackfill() throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let asOf = day(2026, 8, 20)
    // One converted EUR entry and one pending PLN entry, spanning 1000 km.
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-5 * 86_400),
                                     odometer: 1000, money: eurMoney("100")))
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-3 * 86_400),
                                     odometer: 2000, money: pendingMoney(currency: .pln, amount: "289.50")))

    let entriesBefore = try repo.liveEntries(forVehicle: vehicle.id)
    let before = ConsumptionEngine.costPerKm(entries: entriesBefore, asOf: asOf,
                                             homeCurrency: .eur)
    #expect(before == nil,
            "before backfill the window holds a rate-pending row - no exact cost/km exists (was the RV.147 defect)")

    let entryDay = asOf.addingTimeInterval(-3 * 86_400)
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)
    _ = try MoneyBackfillService(store: store).backfill(repo)

    let entriesAfter = try repo.liveEntries(forVehicle: vehicle.id)
    let after = ConsumptionEngine.costPerKm(entries: entriesAfter, asOf: asOf,
                                            homeCurrency: .eur)
    // 289.50 / 4.2706 = 67.79, computed here INDEPENDENTLY of the production
    // expression: (100 + 67.79) / 1000.
    #expect(after?.amount == decimal("167.79"),
            "once the rate lands the figure's amount is the exact converted sum, to the cent")
    let expected = (100.0 + 67.79) / 1000.0
    #expect(abs((after?.perKm ?? 0) - expected) < 0.000_1)
    #expect(after != before, "backfill must make the absent figure appear")
}

// MARK: - Pending count is real

@Test func pendingRateCountIsTheNumberOfExcludedEntries() {
    let vehicle = makeVehicle()
    let asOf = day(2026, 8, 20)
    // Distinct dates so the S2 duplicate heuristic (same vehicle + within 30
    // minutes + volume within 5%) never flags two of these as one fill.
    let entries: [any Entry] = [
        makeFillUp(vehicleId: vehicle.id, date: asOf,
                   money: pendingMoney(currency: .pln, amount: "289.50")),
        makeFillUp(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-86_400),
                   money: pendingMoney(currency: .usd, amount: "100")),
        makeFillUp(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-2 * 86_400),
                   money: eurMoney("10")),
        makeFillUp(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-3 * 86_400),
                   money: eurMoney("20")),
        makeExpense(vehicleId: vehicle.id, date: asOf.addingTimeInterval(-4 * 86_400),
                    money: eurMoney("30")),
    ]

    let stats = HomeStats(vehicle: vehicle, entries: entries, asOf: asOf, calendar: utcCalendar)

    #expect(stats.pendingRateCount == 2)
    // The month is genuinely partial: two rows are still rate-pending, so the
    // honest figure is the known 60 sum MARKED with the pending count - never a
    // bare total that reads as complete (RV.112).
    #expect(stats.monthSpend == LogStream.MonthTotal.partial(amount: decimal("60"),
                                                             currency: .eur,
                                                             pendingCount: 2))
}

// MARK: - Rate-cache persistence + prune (docs/SCHEMA.md -> Exchange rates)

@Test func persistedCacheSurvivesARelaunch() throws {
    let directory = NSTemporaryDirectory()
    let path = directory + "tankbook-rates-\(UUID().uuidString).sqlite"
    defer {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    let entryDay = day(2026, 8, 21)
    let first = TankbookRepository(database: try TankbookDatabase(path: path))
    try first.upsertExchangeRates([
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb),
        ExchangeRate(base: .eur, quote: .usd, date: entryDay, rate: decimal("1.1"), source: .ecb),
    ])

    // Reopen the same file as a fresh repository - the relaunch path.
    let reopened = TankbookRepository(database: try TankbookDatabase(path: path))
    let rows = try reopened.exchangeRates()
    #expect(rows.count == 2)

    let store = RateStore(seed: rows, calendar: utcCalendar)
    let converted = store.convert(pendingMoney(currency: .pln, amount: "289.50"), on: entryDay)
    #expect(converted.homeAmount == decimal("67.79"))
}

@Test func pruneDropsOldRowsAndKeepsRecent() throws {
    let repo = try makeRepository()
    let now = day(2026, 8, 27)
    let old = now.addingTimeInterval(-3 * 365 * 86_400)   // ~3 years ago
    let recent = now.addingTimeInterval(-1 * 86_400)      // yesterday

    try repo.upsertExchangeRates([
        ExchangeRate(base: .eur, quote: .pln, date: old, rate: decimal("4.0"), source: .ecb),
        ExchangeRate(base: .eur, quote: .pln, date: recent, rate: decimal("4.2"), source: .ecb),
    ])

    let cutoff = now.addingTimeInterval(-2 * 365 * 86_400) // ~2 years rolling
    try repo.pruneExchangeRates(olderThan: cutoff)

    let rows = try repo.exchangeRates()
    #expect(rows.count == 1)
    #expect(rows.first?.rate == decimal("4.2"))
    #expect(rows.first?.date == recent)
}

// MARK: - PJ.8: the refresh -> backfill product trigger (S8)

/// A pending entry plus a stub fetcher is filled after `refresh()` - the whole
/// point of PJ.8. No launch flag, no debug hook: the refresh merges the stub's
/// pack and the backfill fills the entry from it.
@Test func refreshAndBackfillFillsAPendingEntry() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                     money: pendingMoney(currency: .pln, amount: "289.50")))

    let store = RateStore(seed: [], fetcher: PackRateFetcher(rates: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ]), calendar: utcCalendar)
    let result = try await MoneyBackfillService(store: store).refreshAndBackfill(repo)

    #expect(result?.filledCount == 1)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.homeAmount == decimal("67.79"))
}

/// An entry whose snapshot came from a MANUAL rate is left alone by the
/// refresh-triggered backfill (hard rule 13: once a user sets a value it is
/// theirs permanently). The feed still holds a different rate for the same day.
@Test func refreshAndBackfillLeavesAManualSnapshotAlone() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    let manual = pendingMoney(currency: .pln, amount: "289.50")
        .applyingManualRate(decimal("4.0"), on: entryDay)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay, money: manual))

    let store = RateStore(seed: [], fetcher: PackRateFetcher(rates: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ]), calendar: utcCalendar)
    let result = try await MoneyBackfillService(store: store).refreshAndBackfill(repo)

    #expect(result?.filledCount == 0)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.rate == decimal("4.0"))
    #expect(read.money?.rateSource == .manual)
    #expect(read.money?.homeAmount == decimal("72.38"))
}

/// The filled amount uses the ENTRY's date, never today's (hard rule 3, F9).
/// Two different rates are seeded - the entry's day and the real current day -
/// and the VALUE is asserted, not merely that it is non-nil: converting at
/// today's rate would give 289.50 / 3.0 = 96.50, not 67.79.
@Test func refreshAndBackfillUsesTheEntryDateNotToday() async throws {
    let repo = try makeRepository()
    let vehicle = makeVehicle()
    try repo.upsertVehicle(vehicle)

    let entryDay = day(2024, 3, 12)
    try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                     money: pendingMoney(currency: .pln, amount: "289.50")))

    let today = utcCalendar.startOfDay(for: Date())
    let store = RateStore(seed: [], fetcher: PackRateFetcher(rates: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb),
        ExchangeRate(base: .eur, quote: .pln, date: today, rate: decimal("3.0"), source: .ecb)
    ]), calendar: utcCalendar)
    let result = try await MoneyBackfillService(store: store).refreshAndBackfill(repo)

    #expect(result?.filledCount == 1)
    let read = try repo.liveFillUps(forVehicle: vehicle.id).first!
    #expect(read.money?.homeAmount == decimal("67.79"),
            "must convert at the entry's date rate (4.2706), never today's (3.0 -> 96.50)")
    #expect(read.money?.rateDate == entryDay)
}

// MARK: - RV.88 the import commit + scoped backfill (the drain's core half)

/// The import path writes foreign rows rate-pending - the correct half of the
/// story (hard rule 3: `rateDate` is the ENTRY date). This suite pins the other
/// half: the backfill that resolves exactly those rows, scoped to the ones the
/// import just wrote, at each row's OWN `rateDate` - never today's. A mutation
/// that resolves at today's date must fail on the VALUE, not merely a count.
@Suite("RV.88 import rows drain (scoped backfill)")
struct ImportDrainBackfillTests {

    /// An import-derived USD fill, built the way `ImportConverter.makeFill`
    /// builds one: foreign money with no snapshot.
    private func importedUSDFill(vehicleId: UUID, date: Date,
                                 odometer: Int, amount: String) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: vehicleId, date: date, odometer: odometer,
               money: Money(amount: decimal(amount), currency: .usd, homeCurrency: .eur),
               note: nil, attachments: [], provenance: .import(source: "mfm"),
               conflict: .none, purchaseGroupId: nil, volumeL: 45, unitPrice: nil,
               fuelKind: .diesel, fuelGrade: nil, isFull: true,
               tankLevelAfterPct: 100, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    @Test func commitLeavesForeignRowsPendingAndScopedBackfillFillsEachAtItsOwnRateDate() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        // Two USD fills on different days, each needing a DIFFERENT historical
        // rate. Today also carries a rate, different from both - so a backfill
        // that wrongly used today's date produces a wrong VALUE (and a wrong
        // rateDate), not merely a wrong count.
        let dayA = day(2015, 3, 12)
        let dayB = day(2015, 6, 30)
        let fills = [
            importedUSDFill(vehicleId: vehicle.id, date: dayA, odometer: 100_000, amount: "110"),
            importedUSDFill(vehicleId: vehicle.id, date: dayB, odometer: 100_500, amount: "132"),
        ]
        try repo.commitImportFills(fills, source: "mfm")

        // The commit leaves every foreign row rate-pending (hard rule 3) -
        // the exact state the owner's import produced.
        let committed = try repo.liveFillUps(forVehicle: vehicle.id)
        #expect(committed.count == 2)
        #expect(committed.allSatisfy { $0.money?.isRatePending == true },
                "an imported foreign row must land rate-pending, never silently converted")

        let today = utcCalendar.startOfDay(for: Date())
        let store = RateStore(seed: [
            // Original-per-home: USD per EUR. 110 / 1.10 = 100.00 EUR.
            ExchangeRate(base: .eur, quote: .usd, date: dayA, rate: decimal("1.10"), source: .ecb),
            // 132 / 1.20 = 110.00 EUR.
            ExchangeRate(base: .eur, quote: .usd, date: dayB, rate: decimal("1.20"), source: .ecb),
            // Today's rate - a WRONG-date backfill would resolve at this and the
            // value assertions below fail.
            ExchangeRate(base: .eur, quote: .usd, date: today, rate: decimal("2.0"), source: .ecb),
        ], calendar: utcCalendar)

        // The drain runs the backfill over exactly the rows the import wrote.
        let result = try MoneyBackfillService(store: store).backfill(repo, limitedTo: committed)

        #expect(result.filledCount == 2)
        #expect(result.stillPendingCount == 0)

        let read = try repo.liveFillUps(forVehicle: vehicle.id).sorted { $0.date < $1.date }
        #expect(read[0].money?.homeAmount == decimal("100.00"),
                "day A must convert at A's own rate (1.10 -> 100.00 EUR), never today's (2.0 -> 55.00)")
        #expect(read[0].money?.rateDate == dayA, "rateDate must be the entry date, never today")
        #expect(read[1].money?.homeAmount == decimal("110.00"),
                "day B must convert at B's own rate (1.20 -> 110.00 EUR), never today's")
        #expect(read[1].money?.rateDate == dayB)
        #expect(read[0].money?.rateDate != today && read[1].money?.rateDate != today)
    }

    @Test func scopedBackfillLeavesUnresolvableRowsPendingAndCountsThem() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let dayA = day(2015, 3, 12)
        let dayB = day(2015, 6, 30)
        let dayC = day(2015, 9, 15)
        let fills = [
            importedUSDFill(vehicleId: vehicle.id, date: dayA, odometer: 100_000, amount: "110"),
            importedUSDFill(vehicleId: vehicle.id, date: dayB, odometer: 100_500, amount: "110"),
            importedUSDFill(vehicleId: vehicle.id, date: dayC, odometer: 101_000, amount: "110"),
        ]
        try repo.commitImportFills(fills, source: "mfm")
        let committed = try repo.liveFillUps(forVehicle: vehicle.id)

        // The service holds rates for A and B only - C's day is genuinely
        // unresolvable (the exact case a decade-old import hits).
        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .usd, date: dayA, rate: decimal("1.10"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: dayB, rate: decimal("1.10"), source: .ecb),
        ], calendar: utcCalendar)

        let result = try MoneyBackfillService(store: store).backfill(repo, limitedTo: committed)

        #expect(result.filledCount == 2)
        #expect(result.stillPendingCount == 1,
                "an unresolvable row is COUNTED, never silently dropped")

        // A row with no rate stays rate-pending: its home amount is absent,
        // never zeroed. Zeroing it would make it look resolved (and drain the
        // F9 footnote) while showing a wrong number.
        let all = try repo.liveFillUps(forVehicle: vehicle.id)
        let unresolved = all.first { $0.money?.isRatePending == true }
        #expect(unresolved != nil, "the unresolvable row must STAY pending")
        #expect(unresolved?.money?.homeAmount == nil,
                "an unresolvable row must keep its home amount absent, never a silent zero")
        #expect(unresolved?.money?.amount == decimal("110"),
                "the ORIGINAL amount must survive a miss untouched")
        let resolved = all.filter { $0.money?.isRatePending == false }
        #expect(resolved.count == 2)
    }

    @Test func scopedBackfillDoesNotTouchEntriesOutsideItsSet() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let dayA = day(2015, 3, 12)
        let dayB = day(2015, 6, 30)
        // Two pending fills committed by an import; the drain is scoped to A.
        let fillA = importedUSDFill(vehicleId: vehicle.id, date: dayA, odometer: 100_000, amount: "110")
        let fillB = importedUSDFill(vehicleId: vehicle.id, date: dayB, odometer: 100_500, amount: "110")
        try repo.commitImportFills([fillA, fillB], source: "mfm")

        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .usd, date: dayA, rate: decimal("1.10"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: dayB, rate: decimal("1.10"), source: .ecb),
        ], calendar: utcCalendar)
        let all = try repo.liveFillUps(forVehicle: vehicle.id)
        let onlyA = all.filter { $0.id == fillA.id }

        let result = try MoneyBackfillService(store: store).backfill(repo, limitedTo: onlyA)

        #expect(result.filledCount == 1, "the scoped pass fills exactly the rows it was given")
        #expect(result.stillPendingCount == 0)
        let after = try repo.liveFillUps(forVehicle: vehicle.id)
        let fillAState = after.first { $0.id == fillA.id }
        let fillBState = after.first { $0.id == fillB.id }
        #expect(fillAState?.money?.homeAmount == decimal("100.00"))
        #expect(fillBState?.money?.isRatePending == true,
                "a row the user did not just import must not be backfilled by the drain")
    }

    @Test func scopedBackfillIsIdempotent() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let dayA = day(2015, 3, 12)
        let fill = importedUSDFill(vehicleId: vehicle.id, date: dayA, odometer: 100_000, amount: "110")
        try repo.commitImportFills([fill], source: "mfm")

        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .usd, date: dayA, rate: decimal("1.10"), source: .ecb),
        ], calendar: utcCalendar)
        let service = MoneyBackfillService(store: store)

        // Each pass reads the CURRENT rows (a caller must re-read after the
        // previous pass, exactly as the drain does) - so the second pass sees
        // a filled snapshot and fills nothing.
        let first = try service.backfill(repo, limitedTo: try repo.liveFillUps(forVehicle: vehicle.id))
        #expect(first.filledCount == 1)
        let second = try service.backfill(repo, limitedTo: try repo.liveFillUps(forVehicle: vehicle.id))
        #expect(second.filledCount == 0, "a second scoped pass must fill nothing (fill-blanks-only)")
        #expect(second.stillPendingCount == 0)
    }
}
