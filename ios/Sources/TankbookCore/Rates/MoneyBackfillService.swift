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
                guard let money = entry.money, money.isRatePending else { continue }
                guard let snapshot = store.snapshot(original: money.currency,
                                                    home: money.homeCurrency,
                                                    on: entry.date) else {
                    stillPending += 1
                    continue
                }
                let converted = money.converted(using: snapshot)
                guard converted.hasSnapshot else {
                    stillPending += 1
                    continue
                }
                try Self.persist(entry, with: converted, in: repository)
                filled += 1
            }
        }
        return Result(filledCount: filled, stillPendingCount: stillPending)
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
