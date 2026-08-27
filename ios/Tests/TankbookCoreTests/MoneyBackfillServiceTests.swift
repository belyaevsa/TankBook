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
                  tireSetId: nil, proposedReminderId: nil)
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
    let before = ConsumptionEngine.costPerKm(entries: entriesBefore, asOf: asOf)
    #expect(before != nil)
    // 100 EUR over 1000 km - the pending PLN entry is skipped before backfill.
    #expect(abs(before! - 0.1) < 0.000_1)

    let entryDay = asOf.addingTimeInterval(-3 * 86_400)
    let store = RateStore(seed: [
        ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb)
    ], calendar: utcCalendar)
    _ = try MoneyBackfillService(store: store).backfill(repo)

    let entriesAfter = try repo.liveEntries(forVehicle: vehicle.id)
    let after = ConsumptionEngine.costPerKm(entries: entriesAfter, asOf: asOf)
    // 289.50 / 4.2706 = 67.79, computed here INDEPENDENTLY of the production
    // expression: (100 + 67.79) / 1000.
    let expected = (100.0 + 67.79) / 1000.0
    #expect(abs(after! - expected) < 0.000_1)
    #expect(after! != before!, "backfill must change the derived all-in cost/km")
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
    // The home-currency sum equals the sum of the three converted home amounts,
    // written out literally - never re-derived with the production reduce.
    #expect(stats.monthSpend == decimal("60"))
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
