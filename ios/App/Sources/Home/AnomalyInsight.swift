import Foundation
import TankbookCore

/// The app-side derivation seam for the anomaly engine (P6.1b, docs/JOURNEYS.md
/// J9). It builds the segments exactly as `HomeStats` does - the S2 single-count
/// invariant: an unresolved duplicate pair's excluded member never reaches the
/// engine, so the anomaly can never disagree with the headline about what
/// counts - and asks `AnomalyEngine.detect`. The view does no arithmetic of its
/// own; every number it renders is the engine's (hard rule 2, and the reason
/// `rollingValue`/`baselineValue`/`magnitude`/both windows are handed to the
/// card whole rather than recomputed).
///
/// The engine's abstention is part of the contract: `nil` means "stays quiet"
/// (insufficient history, seasonal rise that last year matched, an
/// already-recovering drift, or a dismissed cause). Silence is the common case
/// by design (docs/SCHEMA.md -> ANOMALY: "a detector that fires often is the
/// failure mode").
enum AnomalyInsight {

    /// The vehicle's counting fills and its segments, derived once and shared by
    /// `detect` and `monthlyCostDelta` so no caller builds segments a second way
    /// (docs/JOURNEYS.md J9 - the card and the engine cannot disagree about what
    /// counts). `usesEV` decides both which segments and which price source
    /// apply: an EV is priced per kWh on its charges, a fuel car per litre on
    /// its fills.
    private struct Prepared {
        let countingFills: [FillUp]
        let countingCharges: [ChargeSession]
        let segments: [Segment]
        let usesEV: Bool
    }

    private static func prepare(vehicle: Vehicle,
                                entries: [any Entry],
                                duplicateResolutions: Set<DuplicateDetector.PairKey>) -> Prepared {
        let fills = entries.compactMap { $0 as? FillUp }
        let pairs = DuplicateDetector.pairs(in: fills, resolved: duplicateResolutions)
        let excludedIDs = Set(pairs.map(\.excludedID))
        let countingFills = fills.filter { !excludedIDs.contains($0.id) }
        let countingCharges = entries.compactMap { $0 as? ChargeSession }
        let evSegments = ConsumptionEngine.evSegments(for: countingCharges)
        let usesEV = vehicle.powertrain == .ev || !evSegments.isEmpty
        let segments = usesEV
            ? evSegments
            : ConsumptionEngine.segments(for: countingFills, tankCapacityL: vehicle.tankCapacityL)
        return Prepared(countingFills: countingFills, countingCharges: countingCharges,
                        segments: segments, usesEV: usesEV)
    }

    static func detect(vehicle: Vehicle,
                       entries: [any Entry],
                       duplicateResolutions: Set<DuplicateDetector.PairKey>,
                       dismissals: Set<AnomalyDismissal>,
                       asOf: Date = Date(),
                       calendar: Calendar = .current) -> ConsumptionAnomaly? {
        let prepared = prepare(vehicle: vehicle, entries: entries,
                               duplicateResolutions: duplicateResolutions)
        return AnomalyEngine.detect(segments: prepared.segments, asOf: asOf,
                                    dismissals: dismissals, calendar: calendar)
    }

    /// What the anomaly's drift costs per month at the user's own most recent
    /// price (docs/VISION.md -> "What we will not tell a driver"): the
    /// money reading a private owner actually has. `nil` when no counting
    /// entry in the rolling window carries a price expressible in home currency
    /// (hard rule 3) or the drift has nothing to cost - the card then shows no
    /// money line rather than a zero.
    static func monthlyCostDelta(vehicle: Vehicle,
                                 entries: [any Entry],
                                 duplicateResolutions: Set<DuplicateDetector.PairKey>,
                                 anomaly: ConsumptionAnomaly) -> (amount: Decimal, currency: CurrencyCode)? {
        let prepared = prepare(vehicle: vehicle, entries: entries,
                               duplicateResolutions: duplicateResolutions)
        let priced: [any Entry] = prepared.usesEV
            ? prepared.countingCharges as [any Entry]
            : prepared.countingFills as [any Entry]
        guard let figure = HomeStats.unitPrice(in: priced,
                                               vehicleHome: vehicle.homeCurrency,
                                               from: anomaly.rollingWindow.start,
                                               through: anomaly.rollingWindow.end)
        else { return nil }
        guard let amount = AnomalyEngine.monthlyCostDelta(anomaly: anomaly,
                                                          segments: prepared.segments,
                                                          unitPrice: figure.amount)
        else { return nil }
        return (amount, figure.currency)
    }
}
