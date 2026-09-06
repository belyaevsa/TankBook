import Foundation

/// The canonical chronological order of a vehicle's entries (docs/SCHEMA.md,
/// Entry -> ordering rule). ONE function, read by every consumer that orders
/// entries in time - the consumption engines (`ConsumptionEngine`), the log
/// stream (`LogStream`), the timeline validator (`TimelineValidator`) and the
/// repository's live union - so a recompute, a save-time check and the Log can
/// never disagree about which of two same-day fills came first.
///
/// The rule, ascending:
///
/// 1. `date` ascending - an entry that carries a real time orders by it.
/// 2. Entries sharing a timestamp (a dateless import day) order by `odometer`
///    ascending - the only travel-order fact a dateless entry carries. An
///    entry that records no odometer has no travel position and sorts first
///    among that date's ties, ordered by creation among its peers.
/// 3. Entries that STILL tie (same date, same reading - a splash fill) order by
///    `createdAt` ascending, then `id`. Both are immutable once the record is
///    stored, so a recompute over the same data always returns the same order
///    and can never reorder history. Nothing is invented: in particular no
///    time is fabricated to separate a dateless pair (hard rule 13).
public enum EntryOrder {

    /// Ascending chronological order: `lhs` sorts before `rhs`.
    public static func ascending(_ lhs: any Entry, _ rhs: any Entry) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        // Equal timestamp: the odometer is the only ordering fact the entry
        // carries. A missing reading (an expense/service recorded without one)
        // sorts before any number - treated as the smallest key - so the
        // no-odo entry is ordered by creation among itself rather than being
        // given a travel position it does not record.
        // The `(nil, nil)` case MUST be matched before `(nil, _)`, which also
        // matches it: with both nil the original fell into `return true`, so
        // `ascending(a, b)` and `ascending(b, a)` were both true - not a strict
        // weak ordering, which Swift's sort may answer with an arbitrary order
        // or a trap. Two same-day entries that both record no odometer (an
        // ordinary pair of expenses) hit exactly that.
        switch (lhs.odometer, rhs.odometer) {
        case let (lhsReading?, rhsReading?):
            if lhsReading != rhsReading { return lhsReading < rhsReading }
        case (nil, nil):
            break
        case (nil, _):
            return true
        case (_, nil):
            return false
        }
        // Equal date AND equal odometer (a splash fill): no travel fact remains.
        // Creation order is the stable tie-break - deterministic, never
        // reorders on recompute, never an invented time.
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Descending chronological order (newest first): `lhs` sorts before `rhs`.
    public static func descending(_ lhs: any Entry, _ rhs: any Entry) -> Bool {
        ascending(rhs, lhs)
    }
}
