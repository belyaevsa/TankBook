import Foundation

/// The distance unit boundary.
///
/// Stored odometers (`FillUp.odometer`, `Vehicle.initialOdometer`) are already in
/// the vehicle's display unit (docs/SCHEMA.md), but `Vehicle.paceLimitKmPerDay`
/// and the derived per-kilometre rates are kilometres regardless of that unit.
/// These functions are the only places a kilometre figure crosses into the
/// vehicle's display unit and back. The factor is the one Home and Trends used
/// for their per-distance rates; it lives here so no surface carries a copy.
public enum DistanceMath {
    /// One mile in kilometres (exact, 1959 international yard and pound
    /// agreement).
    public static let kilometresPerMile = 1.609344

    /// A display-unit distance ("932" mi) as kilometres.
    public static func kilometres(fromDisplay value: Double, unit: DistanceUnit) -> Double {
        unit == .mi ? value * kilometresPerMile : value
    }

    /// A kilometre distance as the vehicle's display unit (1500 km -> 932.06 mi).
    public static func display(fromKilometres value: Double, unit: DistanceUnit) -> Double {
        unit == .mi ? value / kilometresPerMile : value
    }

    /// A rate stated per display distance unit from one stated per kilometre:
    /// cost per mile = cost per kilometre x km/mi, because a mile is longer and
    /// therefore carries more cost. This is the inverse direction of
    /// `display(fromKilometres:)`.
    public static func perDisplayUnit(fromPerKilometre value: Double, unit: DistanceUnit) -> Double {
        unit == .mi ? value * kilometresPerMile : value
    }
}
