import Foundation

/// A derived consumption segment: the distance and fuel between two consecutive
/// full fills (docs/SCHEMA.md, Derived: consumption -> SEGMENT). Never stored -
/// recomputed for a vehicle whenever any FillUp in range changes. The same shape
/// backs EV consumption, where `litres` carries kWh.
public struct Segment: Equatable, Sendable {
    /// The date of the closing fill - the segment's right edge.
    public let closes: Date
    /// Distance driven between opening and closing odometer, in km.
    public let km: Double
    /// Fuel volume between opening and closing fills, in litres (kWh for EV).
    public let litres: Double
    /// Distance-weighted consumption: litres / km x 100 (L/100km or kWh/100km).
    public let per100: Double
    /// The full fill that opened the segment.
    public let openingFillID: UUID
    /// The full fill that closed the segment.
    public let closingFillID: UUID

    public init(closes: Date, km: Double, litres: Double,
                openingFillID: UUID, closingFillID: UUID) {
        self.closes = closes
        self.km = km
        self.litres = litres
        self.per100 = km > 0 ? litres / km * 100 : 0
        self.openingFillID = openingFillID
        self.closingFillID = closingFillID
    }
}
