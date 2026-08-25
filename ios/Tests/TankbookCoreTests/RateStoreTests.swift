import Foundation
import os
import Testing
@testable import TankbookCore

// P2.5 foreign-currency tests: the rate store, the seed pack, the detection
// rule and the money invariants they uphold (docs/SCHEMA.md -> Money and
// Exchange rates; docs/JOURNEYS.md F9). All run on macOS with no simulator
// (docs/TESTING.md, L1) and use a fixed UTC calendar so "the entry's day" is
// deterministic.

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

// MARK: - 1. Pending-rate save

@Test func foreignFillUpWithNoRateSavesRatePending() {
    let store = store(seed: [])
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let saved = store.convert(money, on: day(2026, 8, 21))

    // A miss is not an error: the original amount is exact, the home amount
    // is absent, and the entry is complete enough to save (F9).
    #expect(saved.amount == decimal("289.50"))
    #expect(saved.currency == .pln)
    #expect(saved.homeAmount == nil)
    #expect(saved.isRatePending)
    #expect(saved.rate == nil)
    #expect(saved.rateDate == nil)
}

// MARK: - 2. rateDate is the entry date, not today

@Test func rateDateIsTheEntryDateNotToday() {
    let early = day(2026, 8, 1)
    let late = day(2026, 8, 15)
    let store = store(seed: [
        row(.eur, .pln, early, "4.2"),
        row(.eur, .pln, late, "4.5")
    ])
    let money = Money(amount: decimal("100"), currency: .pln, homeCurrency: .eur)

    let convertedEarly = store.convert(money, on: early)
    #expect(convertedEarly.rate == decimal("4.2"))
    #expect(convertedEarly.rateDate == early)
    #expect(convertedEarly.homeAmount == decimal("23.81"))

    let convertedLate = store.convert(money, on: late)
    #expect(convertedLate.rate == decimal("4.5"))
    #expect(convertedLate.rateDate == late)

    // A fill-up dated last month converts at last month's rate; re-opening it
    // next year must produce the identical number - and never "today"'s rate.
    #expect(convertedEarly.rateDate != Date())
}

@Test func lookupUsesTheEntrysDayWhenItCarriesATimeComponent() {
    let date = day(2026, 8, 1)
    let store = store(seed: [row(.eur, .pln, date, "4.2")])
    let money = Money(amount: decimal("100"), currency: .pln, homeCurrency: .eur)

    // 17:12 on Aug 1 still resolves to Aug 1's rate.
    let withTime = utcCalendar.date(byAdding: DateComponents(hour: 17, minute: 12), to: date)!
    let converted = store.convert(money, on: withTime)
    #expect(converted.rate == decimal("4.2"))
    #expect(utcCalendar.isDate(converted.rateDate!, inSameDayAs: date))
}

// MARK: - 3. Snapshots are immutable

@Test func backfillFillsBlanksAndNeverOverwritesAnExistingSnapshot() {
    let date = day(2026, 8, 1)
    let store = store(seed: [])
    let pending = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)

    // No rate yet: the entry is rate-pending.
    let before = store.convert(pending, on: date)
    #expect(before.homeAmount == nil)

    // The rate arrives; backfill fills the blank.
    store.merge([row(.eur, .pln, date, "4.2706")])
    let filled = store.convert(pending, on: date)
    #expect(filled.homeAmount == decimal("67.79"))
    #expect(filled.rate == decimal("4.2706"))

    // A corrected feed arrives with a DIFFERENT rate; the snapshot is untouched.
    store.merge([row(.eur, .pln, date, "4.5")])
    let reBackfilled = store.convert(filled, on: date)
    #expect(reBackfilled.homeAmount == decimal("67.79"))
    #expect(reBackfilled.rate == decimal("4.2706"))
}

// MARK: - 4. Determinism

@Test func convertingTheSameEntryTwiceIsDeterministic() {
    let date = day(2026, 8, 21)
    let store = store(seed: [row(.eur, .pln, date, "4.2706")])
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)

    let first = store.convert(money, on: date)
    let second = store.convert(money, on: date)

    // The conversion is a pure function of (amount, currency, rate, date): the
    // same entry converts to the byte-identical snapshot every time - same
    // home amount, same rate, same rateDate. (`JSONEncoder` key ORDER is not
    // canonical on this OS, so the value equality - which is what a re-opened
    // entry must reproduce - is asserted, not the JSON spelling.)
    #expect(first == second)
    #expect(first.homeAmount == decimal("67.79"))
    #expect(second.homeAmount == decimal("67.79"))
    #expect(first.rate == decimal("4.2706"))
    #expect(first.rateDate == second.rateDate)
    #expect(first.rateDate == date)
}

// MARK: - 5. Seed pack (no network, no cache)

@Test func bundledSeedPackConvertsACommonPairWithNoNetwork() throws {
    let seed = try RateSeedStore.bundledSeed(calendar: utcCalendar)
    #expect(!seed.isEmpty)
    let store = RateStore(seed: seed, calendar: utcCalendar)

    // The artboard's worked example: 289.50 PLN on 2026-08-21 converts at the
    // seed's 4.2706 to 67.79 EUR - with no fetcher, no cache and no network.
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let converted = store.convert(money, on: day(2026, 8, 21))
    #expect(converted.homeAmount == decimal("67.79"))
    #expect(converted.rate == decimal("4.2706"))
    #expect(converted.rateSource == .ecb)
}

@Test func bundledSeedPackHasNoDuplicateKeysAndOnlyPositiveRates() throws {
    let seed = try RateSeedStore.bundledSeed(calendar: utcCalendar)
    var keys = Set<String>()
    for rate in seed {
        #expect(rate.rate > 0)
        let key = "\(rate.date)-\(rate.base.rawValue)-\(rate.quote.rawValue)"
        #expect(!keys.contains(key), "duplicate seed key \(key)")
        keys.insert(key)
    }
}

@Test func inverseDirectionResolvesFromASingleStoredDirection() {
    let date = day(2026, 8, 1)
    // Stored EUR->PLN (base EUR, quote PLN). A PLN-home user filling EUR needs
    // the inverse: PLN per EUR = 1 / 4.2.
    let store = store(seed: [row(.eur, .pln, date, "4.2")])
    let money = Money(amount: decimal("84.00"), currency: .eur, homeCurrency: .pln)
    let converted = store.convert(money, on: date)
    #expect(converted.homeAmount != nil)
    #expect(converted.rate! == decimal("1") / decimal("4.2"))
    // 84 EUR * 4.2 PLN/EUR = 352.80 PLN (homeAmount = amount / rate, rate = PLN per EUR).
    #expect(converted.homeAmount == decimal("352.80"))
}

// MARK: - 6. Never silently convert on low confidence

@Test func lowConfidenceCurrencyIsNeverConvertedEvenWhenARateExists() {
    let date = day(2026, 8, 21)
    let store = store(seed: [row(.eur, .pln, date, "4.2706")])
    let snapshot = store.snapshot(original: .pln, home: .eur, on: date)
    #expect(snapshot != nil, "a rate exists for the pair")

    // The detector must report low confidence and NOT a conversion, so the UI
    // asks rather than guessing (a wrong currency silently converted is a
    // number the user cannot spot later).
    let state = ForeignCurrencyDetector.state(currency: .pln, homeCurrency: .eur,
                                              lowConfidence: true, snapshot: snapshot)
    #expect(state == .lowConfidence)
}

@Test func detectorStatesCoverTheForeignDecisionMatrix() {
    let snapshot = RateSnapshot(rate: decimal("4.2706"), rateDate: day(2026, 8, 21), source: .ecb)

    #expect(ForeignCurrencyDetector.state(currency: .eur, homeCurrency: .eur,
                                          lowConfidence: false, snapshot: snapshot) == .notForeign)
    #expect(ForeignCurrencyDetector.state(currency: .pln, homeCurrency: .eur,
                                          lowConfidence: true, snapshot: snapshot) == .lowConfidence)
    #expect(ForeignCurrencyDetector.state(currency: .pln, homeCurrency: .eur,
                                          lowConfidence: false, snapshot: nil) == .ratePending)
    #expect(ForeignCurrencyDetector.state(currency: .pln, homeCurrency: .eur,
                                          lowConfidence: false, snapshot: snapshot) == .converted(snapshot))
}

// MARK: - 7. Decimal, not Double

@Test func decimalRateAndAmountRoundTripExactly() {
    // A rate like 4.3287 and an amount like 289.50 must survive the conversion
    // as exact Decimal arithmetic - never a Double in the path.
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
    let converted = money.converted(using: RateSnapshot(rate: decimal("4.3287"),
                                                        rateDate: day(2026, 8, 21),
                                                        source: .ecb))
    #expect(converted.homeAmount == decimal("66.88"))
    #expect(converted.rate == decimal("4.3287"))
}

// MARK: - Fetcher protocol (test double)

private final class StubRateFetcher: RateFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: Result<[ExchangeRate], any Error>.success([]))

    func set(result: Result<[ExchangeRate], any Error>) {
        lock.withLock { $0 = result }
    }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate] {
        let result = lock.withLock { $0 }
        return try result.get()
    }
}

@Test func refreshMergesFetchedRatesAndBackfillsAPendingEntry() async {
    let date = day(2026, 8, 1)
    let fetcher = StubRateFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
    let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)

    #expect(store.convert(money, on: date).homeAmount == nil)

    fetcher.set(result: .success([row(.eur, .pln, date, "4.2706")]))
    await store.refresh()

    let filled = store.convert(money, on: date)
    #expect(filled.homeAmount == decimal("67.79"))
}

@Test func refreshFailureIsSilentAndLeavesTheStoreUsable() async {
    let date = day(2026, 8, 1)
    struct FetchError: Error {}
    let fetcher = StubRateFetcher()
    fetcher.set(result: .failure(FetchError()))
    let store = RateStore(seed: [row(.eur, .pln, date, "4.2")], fetcher: fetcher, calendar: utcCalendar)

    await store.refresh()

    // The seed still answers; a failed fetch is a non-event (F3/F9).
    let money = Money(amount: decimal("100"), currency: .pln, homeCurrency: .eur)
    #expect(store.convert(money, on: date).homeAmount == decimal("23.81"))
}

// MARK: - Seed pack decoding

@Test func malformedSeedPackIsRejectedWhole() {
    let bad = """
        {"packVersion": 1, "rates": [{"date": "2026-08-21", "base": "EUR",
          "quote": "PLN", "rate": "not-a-number", "source": "ecb"}]}
        """
    #expect(throws: RateError.self) {
        _ = try RateSeedStore.decode(data: Data(bad.utf8), calendar: utcCalendar)
    }
}

@Test func seedDecodeRejectsAnInvalidCurrencyCode() {
    let bad = """
        {"packVersion": 1, "rates": [{"date": "2026-08-21", "base": "EUR",
          "quote": "XX", "rate": "4.2", "source": "ecb"}]}
        """
    #expect(throws: RateError.self) {
        _ = try RateSeedStore.decode(data: Data(bad.utf8), calendar: utcCalendar)
    }
}
