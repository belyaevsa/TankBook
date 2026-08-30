import Foundation

/// The live "+N km since last" caption state for the ConfirmManual odometer
/// (docs/VISION.md -> Fill-up log; docs/DESIGN.md -> the Pump Card). Computed
/// in core so the four states are L1-testable: a caption built inside the view
/// would only be reachable by XCUITest, which asserts behaviour and never
/// values (the P3.7 lesson). The caption is a suggestion, never a gate - an
/// implausible odometer warns in amber and the user decides (hard rule 13),
/// exactly as `TimelineValidator` flags on save without ever blocking it.
public struct OdometerDelta: Equatable, Sendable {
    /// The signed difference `typed - lastKnown` in the vehicle's distance unit.
    public let km: Int
    /// Which way the typed value moved relative to last known, and whether the
    /// implied daily pace looks wrong.
    public let state: State

    public enum State: Equatable, Sendable {
        /// Typed > last known, and the implied daily pace is within the limit.
        case forward
        /// Typed == last known: a legitimate state (no distance driven since the
        /// last entry), rendered neutral, never amber.
        case equal
        /// Typed < last known: the odometer went backwards - attention.
        case backwards
        /// Typed > last known but the implied daily rate exceeds the vehicle's
        /// `paceLimitKmPerDay` - attention.
        case pace

        /// Whether the state renders amber. Amber is attention, never alarm
        /// (hard rule 5); only backwards and an exceeded pace warrant it.
        public var isWarning: Bool {
            switch self {
            case .forward, .equal: return false
            case .backwards, .pace: return true
            }
        }
    }

    /// Evaluates the live delta. Returns nil when there is nothing to compare:
    /// no typed odometer, or no last-known value (a new car with no entries -
    /// the odometer field is blank and there is no "last" to measure against).
    ///
    /// The pace check mirrors `TimelineValidator`'s CHECK 2 (docs/SCHEMA.md):
    /// implied km/day against the last-known entry's date, flagged only when
    /// `days > 0` and the rate exceeds the limit. Without a last-known date (the
    /// value came from `Vehicle.initialOdometer`) the pace check cannot run and
    /// a positive delta stays `.forward` - the same conservative behaviour the
    /// validator has when no previous entry exists.
    public static func evaluate(typed: Int?,
                                lastKnown: Int?,
                                lastKnownDate: Date?,
                                entryDate: Date,
                                paceLimitKmPerDay: Double) -> OdometerDelta? {
        guard let typed, let lastKnown else { return nil }
        let km = typed - lastKnown
        if km < 0 {
            return OdometerDelta(km: km, state: .backwards)
        }
        if km == 0 {
            return OdometerDelta(km: 0, state: .equal)
        }
        if let lastKnownDate {
            let days = abs(entryDate.timeIntervalSince(lastKnownDate)) / 86_400
            if days > 0, Double(km) / days > paceLimitKmPerDay {
                return OdometerDelta(km: km, state: .pace)
            }
        }
        return OdometerDelta(km: km, state: .forward)
    }
}

/// The last-known odometer reference a caption is measured against: the value
/// and the date of the entry holding it. Derived in core so the pre-fill and
/// the live caption cannot disagree about what "last known" means.
public struct OdometerLastKnown: Equatable, Sendable {
    public let odometer: Int?
    public let date: Date?

    public init(odometer: Int?, date: Date?) {
        self.odometer = odometer
        self.date = date
    }

    /// The last known from a vehicle's entries: the max odometer and the date
    /// of its NEWEST occurrence (entries are ordered by date, so `.last` is the
    /// most recent fill at that reading - "when was this odometer last
    /// logged", the anchor the implied-pace check needs). A car with no
    /// odometer-carrying entries falls back to `vehicle.initialOdometer` with
    /// no date - the pace check then cannot run, the same conservative
    /// behaviour `TimelineValidator` has with no previous entry.
    public static func lastKnown(in entries: [any Entry], vehicle: Vehicle) -> OdometerLastKnown {
        let lastOdo = entries.compactMap(\.odometer).max()
        return OdometerLastKnown(odometer: lastOdo ?? vehicle.initialOdometer,
                                 date: lastOdo.flatMap { value in
                                     entries.last { $0.odometer == value }?.date
                                 })
    }
}
