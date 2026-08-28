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
    static func detect(vehicle: Vehicle,
                       entries: [any Entry],
                       duplicateResolutions: Set<DuplicateDetector.PairKey>,
                       dismissals: Set<AnomalyDismissal>,
                       asOf: Date = Date(),
                       calendar: Calendar = .current) -> ConsumptionAnomaly? {
        let fills = entries.compactMap { $0 as? FillUp }
        let pairs = DuplicateDetector.pairs(in: fills, resolved: duplicateResolutions)
        let excludedIDs = Set(pairs.map(\.excludedID))
        let countingFills = fills.filter { !excludedIDs.contains($0.id) }
        let charges = entries.compactMap { $0 as? ChargeSession }
        let evSegments = ConsumptionEngine.evSegments(for: charges)
        let usesEV = vehicle.powertrain == .ev || !evSegments.isEmpty
        let segments = usesEV
            ? evSegments
            : ConsumptionEngine.segments(for: countingFills, tankCapacityL: vehicle.tankCapacityL)
        return AnomalyEngine.detect(segments: segments, asOf: asOf,
                                    dismissals: dismissals, calendar: calendar)
    }
}
