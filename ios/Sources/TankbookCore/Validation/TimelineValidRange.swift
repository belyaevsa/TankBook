import Foundation

/// The values one field of an entry may hold without flagging, given its
/// date-neighbours (docs/SCHEMA.md -> Validation -> Valid range, RV.117a).
///
/// This is derived, never stored (hard rule 2), and it is computed by
/// `TimelineValidator` in the same pass that produces the flags, from the same
/// neighbour walk and the same `paceLimitKmPerDay` - so a value inside the range
/// is never flagged and a value outside always is.
///
/// - `.none`: the neighbourhood itself is inconsistent - no value satisfies the
///   order and pace constraints at once (a multi-year import can produce it).
///   Saying "must be between 490 983 and 490 500" would be nonsense, so nothing
///   is claimed.
/// - `.bounded(lower:upper:)`: every value in the inclusive span satisfies both
///   checks. A `nil` end is genuinely open - that side has no neighbour bound -
///   and is never a large sentinel number: the newest entry has no `next` to
///   bound its upper end, the oldest no `previous` to bound its lower.
public enum ValidRange<Bound: Comparable & Equatable & Sendable>: Equatable, Sendable {
    case none
    case bounded(lower: Bound?, upper: Bound?)
}

/// The RV.117a intervals for one entry, returned alongside its flags. When the
/// entry carries an odometer both intervals exist: the odometer readings valid
/// for its date, and the dates valid for its odometer. Whichever of the two the
/// current value falls outside is the field the user should question - the
/// neighbourhood says so instead of only that "something" is wrong.
public struct TimelineValidRange: Equatable, Sendable {
    /// The inclusive odometer readings valid for the entry's date. `nil` bounds
    /// are open (see `ValidRange`).
    public let odometer: ValidRange<Int>
    /// The inclusive dates on which the entry's odometer is valid while it keeps
    /// the same two date-neighbours. `nil` bounds are open.
    public let dates: ValidRange<Date>

    public init(odometer: ValidRange<Int>, dates: ValidRange<Date>) {
        self.odometer = odometer
        self.dates = dates
    }
}
