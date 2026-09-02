import Foundation
import os

// MARK: - P2.5 rate cache + seed pack (docs/SCHEMA.md -> Exchange rates)

// Money is always a pair (hard rule 3): the original amount plus its conversion
// into the vehicle's home currency with a rate snapshot. This store supplies
// the rate for that snapshot. It is deliberately NOT synced and never touches
// the network itself: a bundled seed pack answers day-one offline lookups, a
// cache of fetched `ExchangeRate` rows answers later ones, and a miss is not an
// error - the entry saves rate-pending (F9) and backfills later, fill-blanks-
// only (docs/SCHEMA.md -> Money conversion semantics).

/// Fetches a bulk range of exchange-rate rows from the backend's public
/// `/rates/pack` endpoint (docs/SCHEMA.md -> Exchange rates). Injected as a
/// protocol with a test double, exactly as `ConfigStore` does its fetcher; the
/// real HTTP client lands with the sync work, never here.
public protocol RateFetcher: Sendable {
    func fetchPack(from: Date, to: Date, base: CurrencyCode) async throws -> [ExchangeRate]
}

/// The local rate cache. Keyed `(date, base, quote)` after `docs/SCHEMA.md`'s
/// `ExchangeRate`; lookups are exact-day (the backend carries weekends/holidays
/// forward into per-date rows, so the client never extrapolates). `rateDate`
/// on a produced snapshot is the ENTRY's day - never "today" - so a fill-up
/// dated last month converts at last month's rate and re-opening it next year
/// yields the identical number.
public final class RateStore: @unchecked Sendable {
    public typealias Clock = @Sendable () -> Date

    private struct State {
        var rates: [ExchangeRate]
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let fetcher: (any RateFetcher)?
    private let clock: Clock
    private let calendar: Calendar
    private let powerState: any PowerStateProvider

    /// Builds a store over `seed` rows. `calendar` determines what "the entry's
    /// day" means when matching a `Date` to a rate row's day; injectable so
    /// tests are deterministic. `fetcher` is optional - absent until the sync
    /// work supplies a real one; `clock` supplies "today" for `refresh()` only.
    /// `powerState` is the injected Low Power Mode state (docs/SYNC.md) that
    /// `refresh()` defers on - never `ProcessInfo` read inline.
    public init(seed: [ExchangeRate], fetcher: (any RateFetcher)? = nil,
                clock: @escaping Clock = { Date() },
                calendar: Calendar = .current,
                powerState: any PowerStateProvider = ProcessInfoPowerState()) {
        self.fetcher = fetcher
        self.clock = clock
        self.calendar = calendar
        self.powerState = powerState
        self.lock = OSAllocatedUnfairLock(initialState: State(rates: seed.map {
            $0.normalizedDay(in: calendar)
        }))
    }

    /// The snapshot for converting `original` into `home` on the day `date`
    /// falls on. The rate is ORIGINAL per HOME (`homeAmount = amount / rate`,
    /// docs/SCHEMA.md). A same-currency pair returns nil - it is already
    /// snapshotted at rate 1 by `Money`. A pair not in the cache returns nil:
    /// a miss, never an error.
    public func snapshot(original: CurrencyCode, home: CurrencyCode, on date: Date) -> RateSnapshot? {
        guard original != home else { return nil }
        let day = calendar.startOfDay(for: date)
        let rates = lock.withLock { $0.rates }

        if let row = rates.first(where: {
            $0.base == home && $0.quote == original && calendar.startOfDay(for: $0.date) == day
        }) {
            return RateSnapshot(rate: row.rate, rateDate: day, source: row.source)
        }
        // The inverse direction (base=original, quote=home) is the same pair:
        // home-per-original inverts to original-per-home.
        if let row = rates.first(where: {
            $0.base == original && $0.quote == home && calendar.startOfDay(for: $0.date) == day
        }), row.rate != 0 {
            return RateSnapshot(rate: Decimal(1) / row.rate, rateDate: day, source: row.source)
        }
        return nil
    }

    /// Converts a money pair on the entry's date. Fill-blanks-only: `Money`
    /// already guarantees an existing snapshot is never recomputed, so this is
    /// safe to call on every save and during backfill.
    public func convert(_ money: Money, on date: Date) -> Money {
        guard let snapshot = snapshot(original: money.currency, home: money.homeCurrency, on: date) else {
            return money
        }
        return money.converted(using: snapshot)
    }

    /// Merges fetched rows into the cache. Same-key rows replace (a corrected
    /// pack wins); a corrected pack never rewrites a `Money` snapshot, which
    /// lives on the entry and is immutable (docs/SCHEMA.md, hard rule 3).
    public func merge(_ rates: [ExchangeRate]) {
        lock.withLock { state in
            for row in rates {
                let normalized = row.normalizedDay(in: calendar)
                if let index = state.rates.firstIndex(where: {
                    $0.base == normalized.base && $0.quote == normalized.quote && $0.date == normalized.date
                }) {
                    state.rates[index] = normalized
                } else {
                    state.rates.append(normalized)
                }
            }
        }
    }

    /// Every row currently cached, normalized to the start of its day. Used to
    /// persist the cache so a relaunch can rebuild the store from disk - the
    /// cache itself is never synced (docs/SCHEMA.md -> Exchange rates); only
    /// the `Money` snapshots inside entries travel (S8).
    public func allRates() -> [ExchangeRate] {
        lock.withLock { $0.rates }
    }

    /// How many days of rates one `/rates/pack` refresh asks for, INCLUSIVE of
    /// both ends.
    ///
    /// It must not exceed the server's `Rates:MaxPackDays` (400,
    /// `docs/API.md` -> Exchange rates), which rejects a wider span with a 400.
    /// This asked for **two years** until 2026-09-02 and therefore failed on
    /// every single refresh - seen in production on the first device build,
    /// five 400s in one session, and never caught because the client tests use
    /// a `RateFetcher` double and the server tests choose their own ranges. Both
    /// sides were tested; the contract between them was not.
    ///
    /// The server's comparison is `to - from + 1 > maxDays`, so 400 inclusive
    /// days is accepted and 401 is not - hence the `- 1` at the call site.
    /// A miss is not an error (F9): entries save rate-pending and backfill
    /// later, so a shorter window costs a backfill, never a wrong number.
    static let packWindowDays = 400

    /// Fetches a rolling `packWindowDays` pack (base EUR) when a fetcher is present;
    /// otherwise a no-op. A fetch failure is silent - a miss is not an error
    /// (docs/SCHEMA.md -> Exchange rates, F9).
    ///
    /// Returns `true` when the refresh was not deferred, `false` when Low Power
    /// Mode postponed it (or there is no fetcher). The refresh is opportunistic
    /// work (docs/SYNC.md -> Low Power Mode table), so the trigger defaults to
    /// `.background`; a user-initiated fetch would pass `.userInitiated`.
    @discardableResult
    public func refresh(trigger: PowerWorkTrigger = .background) async -> Bool {
        guard let fetcher else { return false }
        // P6.8: the rate pack refresh defers while the mode is on. Nothing is
        // lost - a miss is not an error (F9): entries save rate-pending and
        // backfill later, fill-blanks-only.
        if LowPowerPolicy.defers(work: .ratePackRefresh, trigger: trigger,
                                 lowPowerMode: powerState.isLowPowerModeEnabled) {
            return false
        }
        let now = clock()
        let from = calendar.date(byAdding: .day, value: -(Self.packWindowDays - 1), to: now) ?? now
        do {
            let rates = try await fetcher.fetchPack(from: from, to: now, base: .eur)
            merge(rates)
        } catch {
            return true
        }
        return true
    }
}

private extension ExchangeRate {
    /// Normalizes a row's `date` to the start of its day, so cache keys compare
    /// as calendar days regardless of the time component a seed or fetch gave.
    func normalizedDay(in calendar: Calendar) -> ExchangeRate {
        ExchangeRate(base: base, quote: quote, date: calendar.startOfDay(for: date),
                     rate: rate, source: source)
    }
}

// MARK: - Bundled seed pack

/// The seed pack envelope: a version plus rows. `rate` is a JSON STRING (an
/// exact `Decimal`, never a `Double` - docs/SCHEMA.md types money as Decimal),
/// and `date` is `YYYY-MM-DD` - both decoded into domain types here.
struct ExchangeRateSeed: Codable {
    let packVersion: Int
    let rates: [Row]

    struct Row: Codable {
        let date: String
        let base: String
        let quote: String
        let rate: String
        let source: String
    }
}

/// Errors from loading a seed pack. A malformed pack is rejected WHOLE - the
/// same discipline as the vehicle catalog (docs/SYNC.md -> Reference data).
public enum RateError: Error, Equatable {
    case bundleMissing
    case invalidDate(String)
    case invalidCurrency(String)
    case invalidRate(String)
}

/// Loads the bundled seed pack (docs/SCHEMA.md -> Exchange rates: the pack that
/// ships in the app so day-one offline capture still converts common pairs).
public enum RateSeedStore {
    public static let bundledResourceName = "Rates.seed"
    public static let bundledExtension = "json"

    public static func bundledSeed(calendar: Calendar = .current) throws -> [ExchangeRate] {
        guard let url = Bundle.module.url(forResource: bundledResourceName,
                                          withExtension: bundledExtension) else {
            throw RateError.bundleMissing
        }
        return try seed(at: url, calendar: calendar)
    }

    public static func seed(at url: URL, calendar: Calendar = .current) throws -> [ExchangeRate] {
        try decode(data: Data(contentsOf: url), calendar: calendar)
    }

    public static func decode(data: Data, calendar: Calendar = .current) throws -> [ExchangeRate] {
        let seed = try JSONDecoder().decode(ExchangeRateSeed.self, from: data)
        return try seed.rates.map { row in
            guard let date = Self.day(row.date, calendar: calendar) else {
                throw RateError.invalidDate(row.date)
            }
            guard let base = CurrencyCode(rawValue: row.base) else {
                throw RateError.invalidCurrency(row.base)
            }
            guard let quote = CurrencyCode(rawValue: row.quote) else {
                throw RateError.invalidCurrency(row.quote)
            }
            guard let rate = Decimal(string: row.rate, locale: Locale(identifier: "en_US_POSIX")),
                  rate > 0 else {
                throw RateError.invalidRate(row.rate)
            }
            let source = RateSource.wire(row.source)
            return ExchangeRate(base: base, quote: quote, date: date, rate: rate, source: source)
        }
    }

    private static func day(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

// MARK: - The foreign-currency decision (never silently convert)

/// What the confirm sheet does with a foreign currency (docs/ERRORS.md ->
/// Confirm, F9). Drives both the conversion card and the save path, so the two
/// can never disagree about whether a rate was applied.
public enum ForeignCurrencyState: Equatable, Sendable {
    /// Currency equals home: money is snapshotted at rate 1, no card shown.
    case notForeign
    /// The currency is uncertain: ask the user, NEVER convert - a wrong
    /// currency silently converted is a number the user cannot spot later.
    case lowConfidence
    /// Foreign and confident but no rate for the entry's date: save as
    /// rate-pending (original amount exact, home amount absent).
    case ratePending
    /// Foreign and confident with a rate: the conversion card shows the number.
    case converted(RateSnapshot)
}

/// The pure detection rule, L1-testable without a view. Detection comes from
/// the extraction's currency when present and from the user's chip choice
/// otherwise - never from the device locale alone (wrong for a traveller).
public enum ForeignCurrencyDetector {
    public static func state(currency: CurrencyCode,
                             homeCurrency: CurrencyCode,
                             lowConfidence: Bool,
                             snapshot: RateSnapshot?) -> ForeignCurrencyState {
        if currency == homeCurrency { return .notForeign }
        if lowConfidence { return .lowConfidence }
        guard let snapshot else { return .ratePending }
        return .converted(snapshot)
    }
}

public extension ForeignCurrencyState {
    /// Whether the conversion card renders: only the foreign states that are
    /// confident about the currency. Low confidence renders the amber prompt
    /// instead (never silently converted), and `.notForeign` renders nothing.
    var showsConversionCard: Bool {
        switch self {
        case .ratePending, .converted: return true
        case .notForeign, .lowConfidence: return false
        }
    }
}

/// The resolved foreign-currency decision for one amount: the state the UI
/// renders plus the money pair to save. The two travel together so the card and
/// the save path can never disagree about the applied rate.
public struct ForeignCurrencyConversion: Equatable, Sendable {
    public let state: ForeignCurrencyState
    public let money: Money

    public init(state: ForeignCurrencyState, money: Money) {
        self.state = state
        self.money = money
    }

    /// The converted home amount, non-nil only when the state is `.converted`.
    public var convertedAmount: Decimal? {
        guard case .converted = state else { return nil }
        return money.homeAmount
    }
}

public extension RateStore {
    /// Resolves the foreign-currency state and the resulting money pair for an
    /// amount on the entry's date. Low confidence never converts; a rate miss
    /// leaves the pair rate-pending; same currency stays snapshotted at rate 1.
    func resolve(amount: Decimal, currency: CurrencyCode, homeCurrency: CurrencyCode,
                 on date: Date, lowConfidence: Bool) -> ForeignCurrencyConversion {
        let money = Money(amount: amount, currency: currency, homeCurrency: homeCurrency)
        let snapshot = snapshot(original: currency, home: homeCurrency, on: date)
        let state = ForeignCurrencyDetector.state(currency: currency, homeCurrency: homeCurrency,
                                                  lowConfidence: lowConfidence, snapshot: snapshot)
        if case .converted(let rate) = state {
            return ForeignCurrencyConversion(state: state, money: money.converted(using: rate))
        }
        return ForeignCurrencyConversion(state: state, money: money)
    }
}
