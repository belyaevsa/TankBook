import Foundation
import Testing
@testable import TankbookCore

// RV.151 - the rate lookup can cross the EUR base (docs/SCHEMA.md -> Exchange
// rates). Every rate fetch asks for the pack `base: .eur`, so the cache holds
// `(EUR -> X)` rows. A car whose home currency is neither EUR nor the entry's
// - a USD-home car with a RUB or PLN entry, the owner's configuration - needs
// `(USD, RUB)`, which is neither present nor invertible, so before this change
// its rows stayed rate-pending through every drain. The fix derives the cross
// rate from two same-day legs of the pack the lookup already has:
// `original per home = (base, original) / (base, home)`. Direct first, inverse
// second, derived third. All tests run on macOS with a fixed UTC calendar.

// MARK: - Test calendar + helpers

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

private func store(seed: [ExchangeRate]) -> RateStore {
    RateStore(seed: seed, calendar: utcCalendar)
}

private func row(_ base: CurrencyCode, _ quote: CurrencyCode, _ date: Date,
                 _ rate: String, source: RateSource = .ecb) -> ExchangeRate {
    ExchangeRate(base: base, quote: quote, date: date, rate: decimal(rate), source: source)
}

// MARK: - The row's whole point: a third-currency pair crosses the EUR base

/// A USD-home car with a RUB entry on a day whose pack holds `(EUR, USD)` and
/// `(EUR, RUB)`: neither the direct `(USD, RUB)` row nor its inverse
/// `(RUB, USD)` exists, yet both legs price against the pack's EUR base, so
/// the lookup can cross it:
///
///     RUB per USD = (EUR, RUB) / (EUR, USD)   (= 100 / 1.25 = 80)
///
/// Both legs read from the ENTRY's day. The converted AMOUNT is asserted, not
/// merely the snapshot: an inverted cross rate (1.25 / 100) would be non-nil,
/// plausible and wrong (homeAmount 640 000, not 100.00).
@Test func aNonEurCarResolvesAThirdCurrencyPairThroughTheEURBase() {
    let date = day(2026, 8, 21)
    let store = store(seed: [
        row(.eur, .usd, date, "1.25"),
        row(.eur, .rub, date, "100", source: .cis)
    ])

    let snapshot = store.snapshot(original: .rub, home: .usd, on: date)
    #expect(snapshot?.rate == decimal("80"), "100 / 1.25 = 80 RUB per USD")
    // The source is the (base, original) leg's publisher: RUB is CIS-priced,
    // never ECB (ECB does not publish RUB), so the derived pair labels CIS -
    // the attribution the direct path gives a RUB row on a EUR-home car.
    #expect(snapshot?.source == .cis)
    #expect(snapshot?.rateDate == date)

    let money = Money(amount: decimal("8000"), currency: .rub, homeCurrency: .usd)
    let converted = store.convert(money, on: date)
    #expect(converted.homeAmount == decimal("100.00"),
            "8000 / 80 = 100.00 USD, got \(String(describing: converted.homeAmount))")
    #expect(converted.rate == decimal("80"))
    #expect(converted.rateDate == date, "rateDate is the entry's day, never today")
}

/// Deriving the pair in both directions from the same pack gives reciprocal
/// rates: `RUB->USD` is `100 / 1.25 = 80`, `USD->RUB` is `1.25 / 100 =
/// 0.0125 = 1 / 80`. A derivation that mis-ordered the division (yielding
/// `1/80` for RUB->USD) or read a leg from another day fails on the VALUE.
@Test func derivedCrossRatesRoundTripReciprocally() {
    let date = day(2026, 8, 21)
    let store = store(seed: [
        row(.eur, .usd, date, "1.25"),
        row(.eur, .rub, date, "100")
    ])

    let rubPerUsd = store.snapshot(original: .rub, home: .usd, on: date)
    let usdPerRub = store.snapshot(original: .usd, home: .rub, on: date)

    #expect(rubPerUsd?.rate == decimal("80"))
    #expect(usdPerRub?.rate == decimal("0.0125"))
    #expect(usdPerRub?.rate == decimal("1") / decimal("80"),
            "deriving both directions gives reciprocal rates")
}

// MARK: - The derived path is the fallback, never the primary

/// A pack that carries the pair outright is used AS-IS. Here the direct row
/// says 85 RUB per USD while the same-day legs would derive 80 - the direct
/// path must win, to the cent (8500 / 85 = 100.00 USD, not 106.25).
@Test func aPackCarryingThePairOutrightWinsOverTheDerivation() {
    let date = day(2026, 8, 21)
    let store = store(seed: [
        row(.eur, .usd, date, "1.25"),
        row(.eur, .rub, date, "100"),
        row(.usd, .rub, date, "85")
    ])

    let money = Money(amount: decimal("8500"), currency: .rub, homeCurrency: .usd)
    let converted = store.convert(money, on: date)
    #expect(converted.rate == decimal("85"),
            "the direct row (85) must win over the derived 80")
    #expect(converted.homeAmount == decimal("100.00"), "8500 / 85 = 100.00 USD")
}

/// The inverse row wins over the derivation too, when both are possible.
@Test func anInverseRowWinsOverTheDerivation() {
    let date = day(2026, 8, 21)
    // (RUB, USD) stored at 0.01 USD per RUB inverts to 100 RUB per USD; the
    // EUR legs would derive 80. The inverse path (resolution 2) must be
    // reached before the derived one (resolution 3).
    let store = store(seed: [
        row(.eur, .usd, date, "1.25"),
        row(.eur, .rub, date, "100"),
        row(.rub, .usd, date, "0.01")
    ])

    let snapshot = store.snapshot(original: .rub, home: .usd, on: date)
    #expect(snapshot?.rate == decimal("100"),
            "the inverse row must win over the derived 80, got \(String(describing: snapshot?.rate))")
}

// MARK: - A day missing either leg stays pending (no nearby day, no today)

/// Both legs must fall on the ENTRY's day: here `(EUR, RUB)` exists on a
/// neighbouring day and on today, but not on the entry's day. A defect that
/// paired legs across days, or fell back to today's rate ([RV.88]'s defect),
/// fills this row; the row must instead stay rate-pending and counted (F9).
@Test func aDayMissingEitherLegStaysRatePending() {
    let entryDay = day(2026, 8, 21)
    let otherDay = day(2026, 8, 20)
    let store = store(seed: [
        row(.eur, .usd, entryDay, "1.25"),
        row(.eur, .rub, otherDay, "100"),
        row(.eur, .rub, utcCalendar.startOfDay(for: Date()), "90")
    ])

    let snapshot = store.snapshot(original: .rub, home: .usd, on: entryDay)
    #expect(snapshot == nil,
            "a day missing its RUB leg must stay pending, never derive from another day")
    let money = Money(amount: decimal("8000"), currency: .rub, homeCurrency: .usd)
    #expect(store.convert(money, on: entryDay).isRatePending)
}

// MARK: - L3: the owner's scenario end to end (multi-currency import, non-EUR car)

/// A USD-home car importing RUB, PLN and EUR fills drains to ZERO pending rows
/// when the EUR-base pack covers the span. This is the configuration that
/// stayed rate-pending through every drain before this change: `(USD, RUB)`
/// and `(USD, PLN)` are neither present in a EUR-based pack nor invertible
/// from it, so each row needed a lookup that could cross the EUR base. Three
/// currencies, one hit per resolution path: RUB derives (cis leg), PLN
/// derives (ecb leg), EUR resolves by inverting `(EUR, USD)` - all three paths
/// asserted in one pass, to the cent.
@Suite("RV.151 multi-currency import onto a non-EUR car")
struct MultiCurrencyNonEurCarImportTests {

    private func usdHomeVehicle() -> Vehicle {
        Vehicle(id: UUID.v7(), createdAt: day(2026, 1, 1), updatedAt: day(2026, 1, 1), deletedAt: nil,
                name: "Volvo V60", make: nil, model: nil, year: 2021, plate: nil,
                powertrain: .ice, fuelKinds: [.petrol95], tankCapacityL: 71,
                batteryCapacityKWh: nil, homeCurrency: .usd,
                units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100, energy: .kWhPer100),
                photo: nil, archived: false, paceLimitKmPerDay: 1500, initialOdometer: 0)
    }

    private func importedFill(vehicleId: UUID, date: Date, odometer: Int,
                              currency: CurrencyCode, amount: String) -> FillUp {
        FillUp(id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
               vehicleId: vehicleId, date: date, odometer: odometer,
               money: Money(amount: decimal(amount), currency: currency, homeCurrency: .usd),
               note: nil, attachments: [], provenance: .import(source: "mfm"), conflict: .none,
               purchaseGroupId: nil, volumeL: 45, unitPrice: nil, fuelKind: .diesel,
               fuelGrade: nil, isFull: true, tankLevelAfterPct: 100, stationId: nil,
               crossCheck: .notApplicable, extraction: nil)
    }

    @Test func multiCurrencyImportOntoAUsdCarDrainsToZeroWhenThePackCoversTheSpan() throws {
        let repo = TankbookRepository(database: try TankbookDatabase.inMemory())
        let vehicle = usdHomeVehicle()
        try repo.upsertVehicle(vehicle)

        // The owner's mix: RUB and PLN fills on a USD-home car, plus a EUR fill
        // so the inverse path is exercised on the same car. Distinct days keep
        // each row's rate unambiguous.
        let rubDay = day(2026, 8, 21)
        let plnDay = day(2026, 8, 22)
        let eurDay = day(2026, 8, 23)
        let fills = [
            importedFill(vehicleId: vehicle.id, date: rubDay, odometer: 100_000,
                         currency: .rub, amount: "8000"),
            importedFill(vehicleId: vehicle.id, date: plnDay, odometer: 100_500,
                         currency: .pln, amount: "340"),
            importedFill(vehicleId: vehicle.id, date: eurDay, odometer: 101_000,
                         currency: .eur, amount: "100")
        ]
        try repo.commitImportFills(fills, source: "mfm")

        // Every foreign row lands rate-pending (hard rule 3) - the exact state
        // the owner's 381 rows were left in.
        let committed = try repo.liveFillUps(forVehicle: vehicle.id)
        #expect(committed.count == 3)
        #expect(committed.allSatisfy { $0.money?.isRatePending == true })

        // The EUR-base pack the import drain fetched covers the span: (EUR, USD)
        // on every day, (EUR, RUB) as cis on the RUB day, (EUR, PLN) as ecb on
        // the PLN day. No (USD, RUB) or (USD, PLN) row exists anywhere.
        let store = store(seed: [
            row(.eur, .usd, rubDay, "1.25"),
            row(.eur, .rub, rubDay, "100", source: .cis),
            row(.eur, .usd, plnDay, "1.25"),
            row(.eur, .pln, plnDay, "4.25"),
            row(.eur, .usd, eurDay, "1.25")
        ])

        let result = try MoneyBackfillService(store: store).backfill(repo, limitedTo: committed)

        #expect(result.filledCount == 3)
        #expect(result.stillPendingCount == 0,
                "the owner's scenario must leave ZERO rows pending when the pack covers the span")

        let read = try repo.liveFillUps(forVehicle: vehicle.id).sorted { $0.date < $1.date }
        // 8000 RUB at (EUR,RUB)/(EUR,USD) = 100/1.25 = 80 RUB/USD -> 100.00 USD.
        #expect(read[0].money?.homeAmount == decimal("100.00"))
        #expect(read[0].money?.rate == decimal("80"))
        #expect(read[0].money?.rateSource == .cis,
                "the derived RUB row records the original leg's publisher")
        #expect(read[0].money?.rateDate == rubDay)
        // 340 PLN at 4.25/1.25 = 3.4 PLN/USD -> 100.00 USD.
        #expect(read[1].money?.homeAmount == decimal("100.00"))
        #expect(read[1].money?.rate == decimal("3.4"))
        #expect(read[1].money?.rateSource == .ecb)
        #expect(read[1].money?.rateDate == plnDay)
        // 100 EUR inverts (EUR, USD): 1/1.25 = 0.8 EUR/USD -> 125.00 USD.
        #expect(read[2].money?.homeAmount == decimal("125.00"))
        #expect(read[2].money?.rate == decimal("0.8"))
        #expect(read[2].money?.rateDate == eurDay)
    }
}
