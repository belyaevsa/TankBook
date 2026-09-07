import Foundation

/// Backfills rate-pending money pairs across every money-bearing entry (all
/// four `Entry` types) once a rate is available (hard rule 3,
/// docs/SCHEMA.md -> Money conversion semantics, docs/SYNC.md S8).
///
/// Fill-blanks-only: an entry whose `Money` already carries a snapshot is
/// never recomputed, and the rate is resolved on the entry's OWN date - never
/// today, never the fetch date (F9). Filled snapshots are written with the
/// ordinary `.dirty` sync state so they travel to the other devices (S8). A
/// miss is not an error: the entry stays rate-pending and is counted, never
/// surfaced.
///
/// Two call shapes: the full pass (`backfill(_:)`) sweeps the whole garage -
/// the S8 trigger after a refresh - and the scoped pass
/// (`backfill(_:limitedTo:)`) resolves exactly the entries a caller names,
/// which is what an import commit runs over its own just-written rows (RV.88:
/// the rows an import wrote must not wait on the next whole-garage sweep to
/// reach the car's currency).
public struct MoneyBackfillService {
    /// The outcome of one pass: counts only, no domain values (hard rule 12).
    public struct Result: Equatable, Sendable {
        public let filledCount: Int
        public let stillPendingCount: Int

        public init(filledCount: Int, stillPendingCount: Int) {
            self.filledCount = filledCount
            self.stillPendingCount = stillPendingCount
        }
    }

    /// The outcome of a demand drain (RV.111) - what a "Check for rates" tap
    /// actually did. Carries the same counts as `Result` plus the two facts the
    /// UI needs to stay honest about what happens next: whether the provider
    /// was reached (an offline pass proves nothing about a date) and whether
    /// the pass left a row whose date no future rolling refresh or re-ask can
    /// ever serve (the dead end, `docs/ERRORS.md` -> Home).
    public struct DemandDrainResult: Equatable, Sendable {
        public let filledCount: Int
        public let stillPendingCount: Int
        /// True when at least one span actually reached the rate service; false
        /// offline (a failed fetch is a silent non-event, hard rule 1).
        public let reachedProvider: Bool
        /// True when the pass reached the provider and a rate-pending row dated
        /// before the rolling pack window (`RateStore.packWindowDays`) is still
        /// pending. Such a date is never served by a future launch pass or a
        /// re-ask of the same date, so the only way out is a manual rate.
        public let hasUnresolvableRows: Bool

        public init(filledCount: Int, stillPendingCount: Int,
                    reachedProvider: Bool, hasUnresolvableRows: Bool) {
            self.filledCount = filledCount
            self.stillPendingCount = stillPendingCount
            self.reachedProvider = reachedProvider
            self.hasUnresolvableRows = hasUnresolvableRows
        }
    }

    private let store: RateStore

    public init(store: RateStore) {
        self.store = store
    }

    /// RV.111: the demand drain a "Check for rates" tap runs - the sibling of
    /// the import drain (`drainAfterImport`) that asks over the rows actually
    /// rate-pending, not over the rolling pack. The rolling refresh only covers
    /// the last `packWindowDays` days, so a pending row dated years back (a
    /// multi-year import committed while the rate archive was still publishing)
    /// would never be asked for again; this drain enumerates every live entry
    /// whose money is rate-pending and demands exactly the span they cover
    /// (`RateStore.fetchSpan`, chunked under the server's 400-day cap).
    ///
    /// `@MainActor` because the repository is the app's MainActor-bound GRDB
    /// writer: the drain awaits a network fetch between its reads, so it must
    /// not carry the non-Sendable repository across a nonisolated boundary.
    /// Nil when nothing is pending: an empty ask is a bug, not a no-op, so no
    /// request is made at all. Offline is a non-event: a failed fetch is silent
    /// and the backfill still fills whatever the cache already holds (hard rule
    /// 1). Each row converts at its OWN date's rate - never today's (hard rule
    /// 3) - and a row the provider cannot serve stays pending and counted.
    @MainActor
    @discardableResult
    public func demandDrain(_ repository: TankbookRepository) async -> DemandDrainResult? {
        let pending = try? Self.pendingEntries(in: repository)
        guard let pending, !pending.isEmpty else { return nil }

        // Raw dates straight to `fetchSpan`, which normalises them to the day
        // with the store's own calendar - so the span asked for matches the
        // day granularity the backfill looks rates up by, whatever the caller's
        // timezone. The upper end is extended by one day: the wire contract
        // serialises `from`/`to` in UTC (`RemoteRateFetcher.dayString`), and a
        // day's local midnight serialises to the PREVIOUS UTC date on a
        // positive-offset device, so an un-extended `to` would stop one server
        // day short of the newest pending row's date and that row would never
        // fill. One day of slack at the top covers both tz directions; a chunk
        // boundary moves by one day at worst.
        guard let from = pending.map(\.date).min(),
              let last = pending.map(\.date).max() else { return nil }
        let calendar = Calendar.current
        let to = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let reachedProvider = await store.fetchSpan(from: from, to: to, base: .eur,
                                                    trigger: .userInitiated)
        // Re-read the CURRENT rows via the whole-garage pass: the fetch above
        // awaited, so rows captured before it may be stale. Fill-blanks-only
        // over the garage is safe and fills every row the fetched span answered.
        let filled = (try? backfill(repository)) ?? Result(filledCount: 0, stillPendingCount: 0)

        let hasUnresolvableRows: Bool
        if reachedProvider, filled.stillPendingCount > 0,
           let stillPending = try? Self.pendingEntries(in: repository) {
            hasUnresolvableRows = Self.hasRowsBeforeRollingWindow(stillPending)
        } else {
            hasUnresolvableRows = false
        }
        return DemandDrainResult(filledCount: filled.filledCount,
                                 stillPendingCount: filled.stillPendingCount,
                                 reachedProvider: reachedProvider,
                                 hasUnresolvableRows: hasUnresolvableRows)
    }

    /// Every live entry across the garage whose money is still waiting on a
    /// rate - the one walk the demand drain uses to enumerate what to ask for
    /// and to re-check what a pass left pending. The S8 backfill's own
    /// whole-garage pass fills; this walk only names the rows.
    private static func pendingEntries(in repository: TankbookRepository) throws -> [any Entry] {
        var pending: [any Entry] = []
        for vehicle in try repository.liveVehicles() {
            for entry in try repository.liveEntries(forVehicle: vehicle.id)
            where entry.money?.isRatePending == true {
                pending.append(entry)
            }
        }
        return pending
    }

    /// Whether any of the entries is rate-pending on a day the rolling pack can
    /// never cover (`RateStore.packWindowDays`): no future launch refresh asks
    /// for it and a re-ask of the same dates is answered empty, so the only way
    /// out is a manual rate (hard rule 13). Day comparison, so an entry at
    /// 17:12 still resolves against the day's row.
    private static func hasRowsBeforeRollingWindow(_ entries: [any Entry],
                                                   now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        let windowFrom = RateStore.rollingPackFrom(now: now, calendar: calendar)
        return entries.contains { entry in
            guard entry.money?.isRatePending == true else { return false }
            return calendar.startOfDay(for: entry.date) < windowFrom
        }
    }

    /// One pass over every money-bearing entry. Idempotent: a second pass fills
    /// nothing, because every entry it touched now carries a snapshot and the
    /// fill-blanks-only guard skips it.
    @discardableResult
    public func backfill(_ repository: TankbookRepository) throws -> Result {
        var filled = 0
        var stillPending = 0
        for vehicle in try repository.liveVehicles() {
            let entries = try repository.liveEntries(forVehicle: vehicle.id)
            for entry in entries {
                switch try outcome(for: entry, in: repository) {
                case .filled: filled += 1
                case .stillPending: stillPending += 1
                case .notPending: break
                }
            }
        }
        return Result(filledCount: filled, stillPendingCount: stillPending)
    }

    /// A backfill over EXACTLY the given entries - the shape the import commit
    /// needs (RV.88): a rate pack that just arrived must not spend a full pass
    /// rewriting history the user did not just import. Same semantics as the
    /// full pass, scoped: fill-blanks-only, each entry resolved on its OWN date
    /// (hard rule 3), a miss stays pending and is counted. Idempotent.
    ///
    /// `entries` must be the CURRENT rows (a caller that passes a pre-write
    /// struct could clobber a field the write changed - e.g. the commit's
    /// conflict stamp), so a caller re-reads the rows it committed before
    /// calling this.
    @discardableResult
    public func backfill(_ repository: TankbookRepository,
                         limitedTo entries: [any Entry]) throws -> Result {
        var filled = 0
        var stillPending = 0
        for entry in entries {
            switch try outcome(for: entry, in: repository) {
            case .filled: filled += 1
            case .stillPending: stillPending += 1
            case .notPending: break
            }
        }
        return Result(filledCount: filled, stillPendingCount: stillPending)
    }

    /// The per-entry fill decision, shared by the full pass and the scoped one
    /// so they can never disagree about what fills and what waits.
    private func outcome(for entry: any Entry,
                         in repository: TankbookRepository) throws -> Outcome {
        guard let money = entry.money, money.isRatePending else { return .notPending }
        guard let snapshot = store.snapshot(original: money.currency,
                                            home: money.homeCurrency,
                                            on: entry.date) else {
            return .stillPending
        }
        let converted = money.converted(using: snapshot)
        guard converted.hasSnapshot else { return .stillPending }
        try Self.persist(entry, with: converted, in: repository)
        return .filled
    }

    private enum Outcome {
        case filled
        case stillPending
        case notPending
    }

    /// The product-side trigger for S8 (docs/SYNC.md, PJ.8): refresh the rate
    /// pack, then backfill every rate-pending money pair. A rate that arrives
    /// later - fetched just now, or merged from a synced device - fills the
    /// entries that were saved rate-pending (F9), so they do not wait on the
    /// user typing a manual rate. The backfill runs even when the refresh
    /// deferred (Low Power Mode): it is a local write over whatever the cache
    /// already holds, and fill-blanks-only makes it safe to run whenever a rate
    /// might be available. Idempotent, like `backfill`.
    @discardableResult
    public func refreshAndBackfill(_ repository: TankbookRepository,
                                   trigger: PowerWorkTrigger = .background) async -> Result? {
        _ = await store.refresh(trigger: trigger)
        return try? backfill(repository)
    }

    private static func persist(_ entry: any Entry, with money: Money,
                                in repository: TankbookRepository) throws {
        switch entry {
        case var fill as FillUp:
            fill.money = money
            try repository.upsertFillUp(fill, syncState: .dirty)
        case var charge as ChargeSession:
            charge.money = money
            try repository.upsertChargeSession(charge, syncState: .dirty)
        case var service as ServiceRecord:
            service.money = money
            try repository.upsertServiceRecord(service, syncState: .dirty)
        case var expense as Expense:
            expense.money = money
            try repository.upsertExpense(expense, syncState: .dirty)
        default:
            break
        }
    }
}
