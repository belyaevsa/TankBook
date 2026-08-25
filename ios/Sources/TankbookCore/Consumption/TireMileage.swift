import Foundation

/// Derived tire-set mileage (docs/SCHEMA.md, TireSet: "km on this set is
/// DERIVED"). The same shape of problem as the segment engine
/// (`ConsumptionEngine.segments(for:)`): spans between anchors, computed on
/// read, with the unknowable cases excluded rather than guessed (hard rule 2 -
/// stats are derived, never stored).
///
/// A tire set's mileage is the sum of the odometer spans during which it was
/// mounted. `ServiceRecord.tireSetId` marks a mounting; the next record that
/// mounts a different set ends the span (docs/JOURNEYS.md J7b: "each seasonal
/// swap ... marks which set went on"). An open span - the set is on the car
/// right now - runs to the latest known odometer.
public enum TireMileage {

    /// The derived mileage in kilometres, or `nil` when the set has no usable
    /// span (never mounted, or every span is missing a bounding odometer).
    /// `nil` - not zero - is the honest answer the UI renders as "–": zero is a
    /// claim, and it is false.
    ///
    /// - Parameters:
    ///   - setID: the tire set whose mileage is wanted.
    ///   - records: the vehicle's service records (tombstoned rows are ignored).
    ///   - latestOdometer: the latest known odometer across ALL of the vehicle's
    ///     entries (fills, charges, services, plus `initialOdometer`) - the open
    ///     span runs to it.
    public static func mileage(for setID: UUID,
                               records: [ServiceRecord],
                               latestOdometer: Int?) -> Int? {
        // Only a record carrying `tireSetId` is a swap; a tombstoned record
        // never belonged to the car's life. Order by (date, createdAt, id) - the
        // same tiebreak the Log's union uses.
        let swaps = records
            .filter { $0.deletedAt == nil && $0.tireSetId != nil }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        var total = 0
        var hasUsableSpan = false
        var mountedSet: UUID?
        var mountOdometer: Int?

        for swap in swaps {
            // This swap closes the span of the set that was mounted before it:
            // the odometer span [mountOdometer, swap.odometer] belongs to it.
            // A span whose bounding odometer is missing (either end), or whose
            // end does not exceed its start, is excluded - never estimated.
            if mountedSet == setID,
               let start = mountOdometer,
               let end = swap.odometer,
               end > start {
                total += end - start
                hasUsableSpan = true
            }
            mountedSet = swap.tireSetId
            mountOdometer = swap.odometer
        }

        // The set still on the car (the last swap mounted it) has an open span
        // running to the latest known odometer.
        if mountedSet == setID,
           let start = mountOdometer,
           let latest = latestOdometer,
           latest > start {
            total += latest - start
            hasUsableSpan = true
        }

        return hasUsableSpan ? total : nil
    }
}
