import Foundation

/// The car's AdBlue figures (docs/SCHEMA.md -> AdBlue): the most recent top-up
/// and the lifetime rate. Derived from the live `AdBlueFill` entries on every
/// read, never stored (hard rule 2); no fuel figure reads an `AdBlueFill`.
public struct AdBlueStats: Equatable, Sendable {
    /// The most recent top-up by the shared entry order.
    public let lastFill: AdBlueFill
    /// Litres per 1000 units of the car's odometer distance; nil until two
    /// top-ups with readings span a positive distance - never estimated.
    public let litresPer1000: Double?

    /// nil when the car has no AdBlue top-up at all, so a car that never takes
    /// AdBlue shows nothing about it.
    public static func compute(entries: [any Entry]) -> AdBlueStats? {
        let fills = entries.compactMap { $0 as? AdBlueFill }
            .filter { $0.deletedAt == nil }
            .sorted(by: EntryOrder.ascending)
        guard let last = fills.last else { return nil }
        return AdBlueStats(lastFill: last, litresPer1000: rate(fills))
    }

    /// RATE = Σ volume of every top-up except the last ÷ (odo(last) − odo(first)),
    /// over the top-ups that carry a reading. The last top-up's litres refill
    /// what the distance since the previous one used, so the first top-up's
    /// litres are the ones the window does not measure - the same reasoning as
    /// fuel's lifetime figure, here without a full-tank flag.
    static func rate(_ ordered: [AdBlueFill]) -> Double? {
        let read = ordered.filter { $0.odometer != nil }
        guard read.count >= 2, let first = read.first?.odometer, let last = read.last?.odometer,
              last > first else { return nil }
        let litres = read.dropFirst().reduce(0) { $0 + $1.volumeL }
        return litres / Double(last - first) * 1000
    }
}
