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

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        let result = lock.withLock { $0 }
        return RatePack(rates: try result.get())
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

// MARK: - The window the refresh actually asks the server for

/// Records the range `RateStore.refresh` requests, so the client's window can be
/// checked against the server's cap.
private final class RangeRecordingFetcher: RateFetcher, @unchecked Sendable {
    let lock = OSAllocatedUnfairLock(initialState: (from: Date?.none, to: Date?.none))

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { $0 = (from, to) }
        return RatePack(rates: [])
    }
}

/// The server rejects a span wider than `Rates:MaxPackDays` with a 400, and its
/// comparison is inclusive: `to - from + 1 > maxDays`.
///
/// This existed as a real production failure before it existed as a test. The
/// client asked for TWO YEARS while the server capped at 400 days, so every
/// refresh 400'd - seen on the first device build, five in one session. Neither
/// suite could catch it: the client tests use a `RateFetcher` double that accepts
/// any range, and the server tests choose their own. Both sides were tested; the
/// contract between them was not, which is exactly where this class of bug lives.
private let serverMaxPackDays = 400

@Test func refreshRequestsAWindowTheServerWillAccept() async {
    let fetcher = RangeRecordingFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)

    await store.refresh()

    let (from, to) = fetcher.lock.withLock { $0 }
    let start = try! #require(from)
    let end = try! #require(to)

    let inclusiveDays = utcCalendar.dateComponents([.day], from: start, to: end).day! + 1
    #expect(inclusiveDays <= serverMaxPackDays,
            "the client asks for \(inclusiveDays) days; the server rejects anything over \(serverMaxPackDays)")
    // Not merely "small enough": asking for far less than the cap would silently
    // shrink the history available for backfilling older entries.
    #expect(inclusiveDays == serverMaxPackDays)
}

// MARK: - RV.88 fetchSpan: demand-driven fetch over an arbitrary span

/// Records every `fetchPack` range a caller asks for, so a multi-chunk span can
/// be asserted against the server's 400-day cap.
private final class MultiRangeRecordingFetcher: RateFetcher, @unchecked Sendable {
    private struct State {
        var ranges: [(from: Date, to: Date)] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let rows: [ExchangeRate]

    init(rows: [ExchangeRate] = []) { self.rows = rows }

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { state in
            state.ranges.append((from, to))
        }
        return RatePack(rates: rows)
    }
}

/// A multi-year import asks `fetchSpan` for dates far older than the rolling
/// 400-day refresh window. The server rejects a single wider request with a
/// 400 (`Rates:MaxPackDays`), so the span must be requested in consecutive
/// <= 400-day chunks that together cover the whole span - never one oversized
/// request, never a silently truncated tail.
@Test func fetchSpanChunksAWideSpanUnderTheServerCap() async {
    // A 319-day span fits ONE chunk (2015-01-01 .. 2015-11-15).
    let single = MultiRangeRecordingFetcher()
    let singleStore = RateStore(seed: [], fetcher: single, calendar: utcCalendar)
    _ = await singleStore.fetchSpan(from: day(2015, 1, 1), to: day(2015, 11, 15))
    #expect(single.ranges.count == 1, "a sub-400-day span is one request, got \(single.ranges.count)")

    // A ~1095-day span needs three consecutive chunks.
    let fetcher = MultiRangeRecordingFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, sleep: { _ in })
    _ = await store.fetchSpan(from: day(2015, 1, 1), to: day(2017, 12, 31))

    let ranges = fetcher.ranges
    #expect(ranges.count == 3, "a ~1095-day span is three chunks, got \(ranges.count)")

    // Every request is within the server's cap (inclusive days <= 400).
    for (from, to) in ranges {
        let inclusiveDays = utcCalendar.dateComponents([.day], from: from, to: to).day! + 1
        #expect(inclusiveDays <= serverMaxPackDays,
                "each chunk must fit the server's \(serverMaxPackDays)-day cap, asked for \(inclusiveDays)")
    }

    // The chunks are contiguous and cover the whole span (no gap, no overlap
    // beyond the shared boundary, nothing dropped at either end).
    let sorted = ranges.sorted { $0.from < $1.from }
    #expect(sorted.first?.from == day(2015, 1, 1))
    #expect(sorted.last?.to == day(2017, 12, 31))
    for pair in zip(sorted, sorted.dropFirst()) {
        let nextAfterChunk = utcCalendar.date(byAdding: .day, value: 1, to: pair.0.to) ?? pair.1.from
        #expect(nextAfterChunk == pair.1.from,
                "chunks must be contiguous: \(pair.0.to) must be followed by \(pair.1.from)")
    }
}

/// A fetched span actually lands in the cache and converts an entry dated in
/// it - the reason the import drain asks in the first place.
@Test func fetchSpanMergedRowsAnswerLookupsInTheSpan() async {
    let date = day(2015, 3, 12)
    let fetcher = MultiRangeRecordingFetcher(rows: [
        row(.eur, .usd, date, "1.10"),
    ])
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar)
    let money = Money(amount: decimal("110"), currency: .usd, homeCurrency: .eur)
    #expect(store.convert(money, on: date).homeAmount == nil, "before the fetch nothing answers")

    _ = await store.fetchSpan(from: day(2015, 1, 1), to: day(2015, 12, 31))

    let converted = store.convert(money, on: date)
    #expect(converted.homeAmount == decimal("100.00"))
    #expect(converted.rateDate == date)
}

/// `fetchSpan` offline is a non-event (F9): a transport failure must not throw
/// to the caller - the drain is best-effort and everything after an import must
/// survive without a connection (hard rule 1).
@Test func fetchSpanFailureIsSilent() async {
    struct FetchError: Error {}
    let fetcher = StubRateFetcher()
    fetcher.set(result: .failure(FetchError()))
    let store = RateStore(seed: [row(.eur, .usd, day(2015, 3, 12), "1.10")],
                          fetcher: fetcher, calendar: utcCalendar)

    let attempted = await store.fetchSpan(from: day(2015, 1, 1), to: day(2015, 12, 31))

    #expect(attempted == false, "a failed fetch reports no merge")
    // The seed still answers; the failed fetch changed nothing.
    let money = Money(amount: decimal("110"), currency: .usd, homeCurrency: .eur)
    #expect(store.convert(money, on: day(2015, 3, 12)).homeAmount == decimal("100.00"))
}

// MARK: - RV.158: the span walk is floor-bounded, paced and single-flight

/// Records every requested range and states a coverage floor on every answer -
/// the server shape the walk must read to stop asking for dead span.
private final class FloorStatingFetcher: RateFetcher, @unchecked Sendable {
    private struct State { var ranges: [(from: Date, to: Date)] = [] }
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let floor: Date

    init(floor: Date) { self.floor = floor }

    var ranges: [(from: Date, to: Date)] { lock.withLock { $0.ranges } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { $0.ranges.append((from, to)) }
        return RatePack(rates: [], coverageFloor: floor)
    }
}

/// A span fetch held open until `release()`, so "a walk is on the wire" is a
/// deterministic state rather than a timing accident.
private actor SpanGate {
    private var started = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signalStarted() { started = true }
    var hasStarted: Bool { started }

    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private final class GatedSpanFetcher: RateFetcher, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private let gate: SpanGate

    init(gate: SpanGate) { self.gate = gate }

    var fetchCount: Int { lock.withLock { $0 } }

    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> RatePack {
        lock.withLock { $0 += 1 }
        await gate.signalStarted()
        await gate.wait()
        return RatePack(rates: [])
    }
}

/// Counts the pacing pauses a walk takes, so "paced" is asserted without a
/// wall-clock measurement.
private actor SleepRecorder {
    private(set) var count = 0
    func record(_: Duration) { count += 1 }
}

/// The server states the oldest date it can serve; the walk must not spend a
/// request on each 400-day slice below it. Removing the floor early-exit makes
/// the second request 2011-02-05..2012-03-10 and turns this red.
@Test func fetchSpanStopsAtTheServerCoverageFloor() async {
    let floor = day(2020, 1, 1)
    let fetcher = FloorStatingFetcher(floor: floor)
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, sleep: { _ in })

    _ = await store.fetchSpan(from: day(2010, 1, 1), to: day(2025, 12, 31), base: .eur)

    let ranges = fetcher.ranges
    #expect(!ranges.isEmpty)
    // The first answer states the floor; every request after it must target the
    // covered span, never another 400-day slice of dead history.
    #expect(ranges.first!.to < floor, "the probe chunk predates the stated floor")
    #expect(ranges.dropFirst().allSatisfy { $0.to >= floor },
            "no post-probe request may target a date before the floor, got \(ranges)")
    // The floor narrows the start; it never truncates the top of the span.
    #expect(ranges.last?.to == day(2025, 12, 31))
}

/// An empty answer inside coverage is a legitimate gap: the next chunk still
/// runs. Stopping on the first empty chunk would silently truncate a span whose
/// only miss is a weekend or holiday.
@Test func anEmptyChunkInsideCoverageDoesNotAbortTheWalk() async {
    let fetcher = MultiRangeRecordingFetcher()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, sleep: { _ in })

    _ = await store.fetchSpan(from: day(2015, 1, 1), to: day(2017, 12, 31))

    #expect(fetcher.ranges.count == 3,
            "an all-empty covered span is still three chunks, got \(fetcher.ranges.count)")
    #expect(fetcher.ranges.last?.to == day(2017, 12, 31),
            "the walk must reach the top of the span, not stop at the first empty chunk")
}

/// Chunks are separated by the injected pause: three chunks means two pauses.
@Test func fetchSpanPacesItsChunks() async {
    let fetcher = MultiRangeRecordingFetcher()
    let sleeper = SleepRecorder()
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar,
                          sleep: { await sleeper.record($0) })

    _ = await store.fetchSpan(from: day(2015, 1, 1), to: day(2017, 12, 31))

    #expect(fetcher.ranges.count == 3)
    #expect(await sleeper.count == 2, "three chunks means two between-chunk pauses")
}

/// A second `fetchSpan` for the same base while one is on the wire joins it and
/// issues no request of its own - the burst the device log shows is one walk,
/// not two racing ones.
@Test func aSecondFetchSpanForTheSameBaseJoinsTheInFlightOne() async throws {
    let gate = SpanGate()
    let fetcher = GatedSpanFetcher(gate: gate)
    let store = RateStore(seed: [], fetcher: fetcher, calendar: utcCalendar, sleep: { _ in })

    let first = Task { await store.fetchSpan(from: day(2015, 1, 1), to: day(2015, 12, 31), base: .eur) }
    while await !gate.hasStarted { try await Task.sleep(for: .milliseconds(1)) }
    #expect(fetcher.fetchCount == 1)

    let second = Task { await store.fetchSpan(from: day(2015, 1, 1), to: day(2015, 12, 31), base: .eur) }
    try? await Task.sleep(for: .milliseconds(20))
    #expect(fetcher.fetchCount == 1, "a second span for the same base must join the in-flight walk")

    await gate.release()
    _ = await first.value
    _ = await second.value
    #expect(fetcher.fetchCount == 1, "the joined walk issued no second request")
}
