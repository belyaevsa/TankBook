import Foundation
import Testing
@testable import TankbookCore

// RV.152 - the two answers to a home-currency change (docs/SCHEMA.md -> Money,
// docs/ERRORS.md -> Vehicle detail). "Convert the log" restates every entry's
// derived half from its immutable receipt at the entry's OWN date (hard rule 3,
// never today); "Keep the entries as they are" is RV.140's re-home, which
// touches only rate-pending rows and leaves snapshots byte-identical. The
// prompt's pending count comes from `conversionPlan`, which shares the same
// date-scoped lookup the convert uses.

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

private func makeFillUp(vehicleId: UUID, date: Date, odometer: Int,
                        money: Money) -> FillUp {
    FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
           vehicleId: vehicleId, date: date, odometer: odometer,
           money: money, note: nil, attachments: [], provenance: .manual, conflict: .none,
           purchaseGroupId: nil, volumeL: 42.3, unitPrice: nil, fuelKind: .petrol95,
           fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
           crossCheck: .notApplicable, extraction: nil)
}

private func eurSnapshotted(_ amount: String) -> Money {
    Money(amount: decimal(amount), currency: .eur, homeCurrency: .eur)
}

@Suite("RV.152: convert the log at the entry's own date")
struct ConvertLogTests {

    /// The row's whole point: a snapshotted row is re-derived from its
    /// IMMUTABLE receipt at its OWN date - never today's rate. Today carries a
    /// deliberately different pair of rates, so a "use today" defect fails on
    /// the resulting `homeAmount` AND `rate`, not on a count.
    @Test func convertRestatesFromTheReceiptAtTheEntrysOwnDate() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2024, 3, 12)
        let snapshotted = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                         odometer: 100_000, money: snapshotted))

        let today = utcCalendar.startOfDay(for: Date())
        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .pln, date: entryDay, rate: decimal("4.2706"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: entryDay, rate: decimal("1.08107664"), source: .ecb),
            ExchangeRate(base: .eur, quote: .pln, date: today, rate: decimal("3.0"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: today, rate: decimal("2.0"), source: .ecb)
        ], calendar: utcCalendar)

        let result = try MoneyBackfillService(store: store)
            .convertLog(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 1)
        #expect(result.stillPendingCount == 0)

        let read = try #require(try repo.liveFillUps(forVehicle: vehicle.id).first)
        let money = try #require(read.money)

        // Oracle: the seeded pack's rates for the entry's own day, never the
        // hardcoded expected value and never today's.
        let expectedRate = decimal("4.2706") / decimal("1.08107664")
        let expectedHome = (decimal("289.50") / expectedRate).rounded(decimalPlaces: 2)

        #expect(money.homeCurrency == .usd, "the derived half follows the new home")
        #expect(money.rate == expectedRate, "the rate must come from the entry's own date")
        #expect(money.homeAmount == expectedHome)
        #expect(money.rateDate == entryDay, "rateDate is the entry date, never today")
        // The receipt itself is untouched, byte for byte.
        #expect(money.amount == decimal("289.50"))
        #expect(money.currency == .pln)
        // Today's rate would give 289.50 / (3.0 / 2.0) = 193.00 - the mutation's tell.
        #expect(money.homeAmount != decimal("193.00"),
                "a today's-rate convert must not be reachable")
    }

    /// A partial convert is the expected case, never an error: a row whose date
    /// the pack cannot serve stays rate-pending and counted, the rest convert.
    @Test func convertLeavesRowsWithNoRatePendingAndCountsThem() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let servedDay = day(2026, 8, 10)
        let unservedDay = day(2026, 9, 5)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: servedDay,
                                         odometer: 100_000, money: eurSnapshotted("70.00")))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: unservedDay,
                                         odometer: 100_500, money: eurSnapshotted("72.00")))

        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .usd, date: servedDay, rate: decimal("1.10"), source: .ecb)
        ], calendar: utcCalendar)

        let result = try MoneyBackfillService(store: store)
            .convertLog(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 1)
        #expect(result.stillPendingCount == 1, "an unresolvable row is counted, never dropped")

        let rows = try repo.liveFillUps(forVehicle: vehicle.id).sorted { $0.date < $1.date }
        #expect(rows[0].money?.homeCurrency == .usd)
        #expect(rows[0].money?.isRatePending == false)
        #expect(rows[0].money?.amount == decimal("70.00"), "the receipt survives a convert")
        #expect(rows[1].money?.isRatePending == true, "the unserved date stays pending")
        #expect(rows[1].money?.homeCurrency == .usd)
        #expect(rows[1].money?.homeAmount == nil, "an unresolvable row is never zeroed")
        #expect(rows[1].money?.amount == decimal("72.00"))
        #expect(rows[1].money?.currency == .eur)
    }

    /// The prompt's count is `conversionPlan`; its oracle is the SAME lookup the
    /// convert uses (`store.snapshot`), so the prompt and the convert can never
    /// disagree about what a date's rate is. The fixture mixes served and
    /// unserved dates so the test cannot pass vacuously.
    @Test func conversionPlanCountsPendingRowsThroughTheSharedLookup() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let servedA = day(2026, 8, 10)
        let servedB = day(2026, 8, 11)
        let unserved = day(2026, 9, 5)
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: servedA,
                                         odometer: 100_000, money: eurSnapshotted("70.00")))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: servedB,
                                         odometer: 100_500, money: eurSnapshotted("71.00")))
        try repo.upsertFillUp(makeFillUp(vehicleId: vehicle.id, date: unserved,
                                         odometer: 101_000, money: eurSnapshotted("72.00")))

        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .usd, date: servedA, rate: decimal("1.10"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: servedB, rate: decimal("1.10"), source: .ecb)
        ], calendar: utcCalendar)
        let service = MoneyBackfillService(store: store)

        let plan = try service.conversionPlan(repo, vehicleID: vehicle.id, to: .usd)

        // The oracle: each entry resolved through the same `store.snapshot` the
        // convert calls, never a second count written here.
        let entries = try repo.liveEntries(forVehicle: vehicle.id)
        var expectedPending = 0
        var expectedConverted = 0
        for entry in entries {
            guard let money = entry.money else { continue }
            if money.currency == .usd {
                expectedConverted += 1
            } else if store.snapshot(original: money.currency, home: .usd, on: entry.date) == nil {
                expectedPending += 1
            } else {
                expectedConverted += 1
            }
        }
        #expect(plan.stillPendingCount == expectedPending)
        #expect(plan.filledCount == expectedConverted)
        #expect(expectedPending == 1, "the fixture must contain an unserved date")
        #expect(expectedConverted == 2, "the fixture must contain served dates")
    }
}

@Suite("RV.152: keep the entries as they are")
struct KeepEntriesTests {

    /// The "Keep" answer is RV.140's re-home, unchanged: a snapshotted row is
    /// byte-identical afterwards, and only the rate-pending rows adopt the new
    /// home (a same-currency row resolving at rate 1, a still-foreign row now
    /// asking for a rate into the new home).
    @Test func keepRehomesOnlyPendingRowsAndLeavesSnapshotsByteIdentical() throws {
        let repo = try makeRepository()
        let vehicle = makeVehicle()
        try repo.upsertVehicle(vehicle)

        let entryDay = day(2024, 3, 12)
        let snapshotted = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
        let snapshottedFill = makeFillUp(vehicleId: vehicle.id, date: entryDay,
                                         odometer: 100_000, money: snapshotted)
        try repo.upsertFillUp(snapshottedFill)
        let pendingUSD = makeFillUp(vehicleId: vehicle.id, date: entryDay, odometer: 100_500,
                                    money: Money(amount: decimal("110.00"), currency: .usd,
                                                 homeCurrency: .eur))
        let pendingPLN = makeFillUp(vehicleId: vehicle.id, date: entryDay, odometer: 101_000,
                                    money: Money(amount: decimal("200.00"), currency: .pln,
                                                 homeCurrency: .eur))
        try repo.upsertFillUp(pendingUSD)
        try repo.upsertFillUp(pendingPLN)
        let snapshotBefore = try repo.liveFillUps(forVehicle: vehicle.id)
            .first { $0.id == snapshottedFill.id }?.money

        let store = RateStore(seed: [], calendar: utcCalendar)
        let result = try MoneyBackfillService(store: store)
            .rehome(repo, vehicleID: vehicle.id, to: .usd)

        #expect(result.filledCount == 1, "the same-currency pending row resolves at rate 1")
        #expect(result.stillPendingCount == 1, "the foreign pending row stays counted")

        let read = try repo.liveFillUps(forVehicle: vehicle.id)
        let snapshotAfter = try #require(read.first { $0.id == snapshottedFill.id }?.money)
        #expect(snapshotAfter == snapshotBefore,
                "a snapshotted row must be byte-identical after Keep")
        #expect(snapshotAfter.homeCurrency == .eur,
                "Keep never restates a snapshot's home currency")

        let usdAfter = try #require(read.first { $0.id == pendingUSD.id }?.money)
        #expect(!usdAfter.isRatePending)
        #expect(usdAfter.homeCurrency == .usd)
        #expect(usdAfter.homeAmount == decimal("110.00"))
        #expect(usdAfter.rate == Decimal(1))

        let plnAfter = try #require(read.first { $0.id == pendingPLN.id }?.money)
        #expect(plnAfter.isRatePending)
        #expect(plnAfter.homeCurrency == .usd, "a still-foreign row asks into the NEW home")
        #expect(plnAfter.homeAmount == nil)
    }

    /// The negative claim that keeps hard rule 3 intact: neither answer ever
    /// converts at today's rate. The store holds a rate for TODAY only; the
    /// entry's own date is unserved.
    @Test func neitherAnswerEverConvertsAtTodaysRate() throws {
        let oldDay = day(2015, 6, 4)
        let today = utcCalendar.startOfDay(for: Date())
        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .pln, date: today, rate: decimal("3.0"), source: .ecb),
            ExchangeRate(base: .eur, quote: .usd, date: today, rate: decimal("2.0"), source: .ecb)
        ], calendar: utcCalendar)
        let snapshotted = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: oldDay, source: .ecb))

        // Convert: the entry's own day has no rate, so it stays pending - a
        // today's-rate convert would populate it with a wrong number.
        let convertRepo = try makeRepository()
        let convertVehicle = makeVehicle()
        try convertRepo.upsertVehicle(convertVehicle)
        try convertRepo.upsertFillUp(makeFillUp(vehicleId: convertVehicle.id, date: oldDay,
                                                odometer: 100_000, money: snapshotted))
        let convertResult = try MoneyBackfillService(store: store)
            .convertLog(convertRepo, vehicleID: convertVehicle.id, to: .usd)
        #expect(convertResult.filledCount == 0)
        #expect(convertResult.stillPendingCount == 1)
        let afterConvert = try #require(
            try convertRepo.liveFillUps(forVehicle: convertVehicle.id).first?.money)
        #expect(afterConvert.isRatePending)
        #expect(afterConvert.homeAmount == nil)
        #expect(afterConvert.rateDate == nil, "no snapshot may be written from another day's rate")

        // Keep: a snapshotted row is not touched at all, so it keeps its own
        // day's snapshot rather than being restated at today's rate.
        let keepRepo = try makeRepository()
        let keepVehicle = makeVehicle()
        try keepRepo.upsertVehicle(keepVehicle)
        try keepRepo.upsertFillUp(makeFillUp(vehicleId: keepVehicle.id, date: oldDay,
                                             odometer: 100_000, money: snapshotted))
        _ = try MoneyBackfillService(store: store)
            .rehome(keepRepo, vehicleID: keepVehicle.id, to: .usd)
        let afterKeep = try #require(
            try keepRepo.liveFillUps(forVehicle: keepVehicle.id).first?.money)
        #expect(afterKeep.homeCurrency == .eur)
        #expect(afterKeep.rateDate == oldDay)
        #expect(afterKeep.homeAmount == decimal("67.79"))
    }
}
