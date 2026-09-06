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

    private let store: RateStore

    public init(store: RateStore) {
        self.store = store
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
