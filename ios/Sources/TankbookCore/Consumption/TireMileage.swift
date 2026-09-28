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
        stints(for: setID, records: records, latestOdometer: latestOdometer).last?.totalKm
    }

    /// One mounting of a set: from the swap that put it on the car to the next
    /// swap that mounted a different set, or to now while it is still on.
    public struct Stint: Equatable, Sendable {
        /// The `ServiceRecord` that mounted the set.
        public let mountRecordId: UUID
        public let mountDate: Date
        public let startOdometer: Int?
        /// The odometer that closed the stint: the next swap's, or the latest
        /// known one while the set is on the car.
        public let endOdometer: Int?
        /// The date of the swap that took the set off; nil while it is on.
        public let endDate: Date?
        public var isOnCar: Bool { endDate == nil }
        /// The distance of this stint, or nil when a bounding odometer is
        /// missing or does not exceed the start - never estimated.
        public let km: Int?
        /// The set's distance through this stint: the sum of every known stint
        /// so far, or nil while none is known.
        public let totalKm: Int?
        /// The condition read at the mounting swap.
        public let reading: TireReading?
    }

    /// The set's history, oldest first: every stint with its own distance and
    /// the running total. Derived on read from the swap records, the same
    /// ordering and exclusion rules as `mileage(for:records:latestOdometer:)`,
    /// which is this list's last running total.
    public static func stints(for setID: UUID,
                              records: [ServiceRecord],
                              latestOdometer: Int?) -> [Stint] {
        // Only a record carrying `tireSetId` is a swap; a tombstoned record
        // never belonged to the car's life. Order by the shared chronological
        // order (docs/SCHEMA.md, Entry -> ordering rule) - the same one the
        // Log and the engines read, so two same-day swaps never flip.
        let swaps = records
            .filter { $0.deletedAt == nil && $0.tireSetId != nil }
            .sorted(by: EntryOrder.ascending)

        var stints: [Stint] = []
        var total: Int?
        for (index, swap) in swaps.enumerated() where swap.tireSetId == setID {
            // The next swap ends this stint, whichever set it mounts: a repeat
            // mount of the same set starts a stint of its own.
            let next = swaps[(index + 1)...].first
            let endOdometer = next.map(\.odometer) ?? latestOdometer
            var km: Int?
            if let start = swap.odometer, let end = endOdometer, end > start {
                km = end - start
            }
            if let km { total = (total ?? 0) + km }
            stints.append(Stint(mountRecordId: swap.id, mountDate: swap.date,
                                startOdometer: swap.odometer, endOdometer: endOdometer,
                                endDate: next?.date, km: km, totalKm: total,
                                reading: swap.tireReading))
        }
        return stints
    }
}
