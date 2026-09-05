import Foundation

// MARK: - P2.7 the pump-photo accuracy gate
//
// Pump-photo mode ships only when the pump corpus clears its accuracy gate in
// the L5 harness (docs/VISION.md, docs/PHASES.md -> P2 exit gate), and the gate
// IS the check (docs/TASKS.md P2.7). The gate is a property of the build's own
// measured accuracy, never a runtime opinion: the numbers below are what the
// harness scored when this build was cut, and a remote config document may only
// turn the flag DOWN while they are below the threshold - never up. The
// reasoning is the same as docs/CONFIG.md -> "Config can never disable a
// security control": a document must not be able to defeat an accuracy gate any
// more than it can defeat a security control.
//
// B1 (2026-09-04) re-scoped the gate. The old `measuredHits / measuredTotal >=
// 0.95` was a recall average over a denominator that mixed three different
// things: the three numeric fields (the hard 178 cells), a near-free `currency`
// marker lookup (66), and `fuelKind` (17) which a pump parser must never
// produce. Recall inverts hard rule 13 - a correct `nil` scores as a miss and a
// confident-wrong value scores as a hit - and on the two idle pumps
// (`pump-016`/`017`, ground truth `0.00`) recall actively rewarded logging a
// zero-litre fill, the exact bug hard rule 15 forbids. The gate is now
// **precision on the committed numeric fields plus a coverage floor**: commit
// only what is uniquely pinned, and ship when committed-value precision is at
// or above ~99% AND coverage clears the floor. The *meaning* changed, not just
// the number: "never a wrong fill-up" is a precision property, not a recall
// average.

/// The pump-photo accuracy gate. The measured values are the raw field score
/// the harness reported when this build was cut, and the Vision-gated ratchet
/// test asserts they match the live corpus score - so the constants cannot
/// drift from reality without a failing test.
public enum PumpPhotoGate {
    /// Numeric cells the parser committed to a correct value at build time
    /// (the precision numerator), over the 178 numeric cells (liters,
    /// unitPrice, total - blanks skipped). `fuelKind` is never scored for a
    /// pump (the spec forbids inferring it) and `currency` is reported
    /// separately, never in the gate.
    public static let measuredCommittedCorrect: Int = 31

    /// Numeric cells the parser committed to at build time (the coverage
    /// numerator). A cell it abstained on - a correct refusal or an honest
    /// miss - is not committed.
    public static let measuredCommitted: Int = 31

    /// Numeric cells the parser resolved correctly at build time (recall, kept
    /// for legibility - the gate no longer runs on it).
    public static let measuredNumericHits: Int = 31

    /// The numeric cells the pump corpus scores (B1): 178. Not 66 x 3: blank
    /// numeric cells stay skipped (glare on a total, the two idle pumps have no
    /// meaningful unit price, and pump-021/022/023 show a grade price BOARD
    /// rather than the transaction's unit price), and `fuelKind` is never
    /// asserted for a pump at all.
    public static let measuredNumericTotal: Int = 178

    /// The precision threshold (B1): committed-value precision at or above this
    /// ships. ~99% is the analyses' convergence - a mode that pre-fills a wrong
    /// digit on one fill in a hundred is the wrong side of hard rule 13, and
    /// the whole point of the gate is that the factor-of-ten volume error is
    /// invisible on the Confirm screen.
    public static let precisionThreshold: Double = 0.99

    /// The coverage floor (B1): the fraction of the 178 numeric cells the
    /// parser must commit to. This is a product decision, not a derived number.
    /// 0.60 is the recommendation: it is reachable by the deterministic ladder
    /// on the OCR text that already exists (the analyses put the ladder at
    /// ~62%), and it is the floor below which "pre-fills three fills out of
    /// five" stops being a head start worth offering (hard rule 15). A higher
    /// floor (the analyses floated 0.85) presumes the crop work or a trained
    /// model, neither of which is warranted before the free win is measured.
    public static let coverageFloor: Double = 0.60

    /// The measured committed-value precision as a fraction in 0...1.
    public static var measuredPrecision: Double {
        measuredCommitted > 0 ? Double(measuredCommittedCorrect) / Double(measuredCommitted) : 0
    }

    /// The measured numeric coverage as a fraction in 0...1.
    public static var measuredCoverage: Double {
        measuredNumericTotal > 0 ? Double(measuredCommitted) / Double(measuredNumericTotal) : 0
    }

    /// Whether this build may offer pump-photo mode. The gate, not the remote
    /// flag, is the deciding input: `ConfigStore.isEnabled(.pumpPhoto)` is false
    /// regardless of rollout while this is false.
    public static var allowsPumpPhoto: Bool {
        measuredPrecision >= precisionThreshold && measuredCoverage >= coverageFloor
    }

    /// The gate as a check: nil when a flag state is consistent with the build's
    /// measured precision and coverage, else a violation naming the
    /// inconsistency. P2.7's deliverable is the test that calls this with the
    /// real numbers - a flag turned on while precision is below the threshold or
    /// coverage below the floor is a violation, a flag left off is never one.
    public static func violation(flagEnabled: Bool, precision: Double, coverage: Double) -> String? {
        guard flagEnabled else { return nil }
        if precision < precisionThreshold {
            return "pumpPhoto is enabled but committed-value precision \(precision) is below "
                + "the ship gate \(precisionThreshold)"
        }
        if coverage < coverageFloor {
            return "pumpPhoto is enabled but numeric coverage \(coverage) is below the floor \(coverageFloor)"
        }
        return nil
    }
}

// MARK: - The pump capture path, honestly degraded

/// Decides what a pump capture produces, once at capture time
/// (docs/TASKS.md P2.7 -> "The capture path, honestly degraded").
///
/// The decision is passed the already-resolved flag state (the caller owns
/// whether that is `PumpPhotoGate.allowsPumpPhoto`, or a `ConfigStore`'s
/// `isEnabled(.pumpPhoto)` once config is wired into the app), so this type
/// stays a pure function of that input.
public enum PumpPhotoCapture {
    /// Off: nil - the ordinary manual form, pre-filled with nothing and with no
    /// message. The feature is simply not offered (hard rule 15): a pump
    /// capture degrades to "correct a couple of fields", never to a dead end or
    /// an error state.
    ///
    /// On: the extraction, which the Confirm sheet treats as default input the
    /// user edits (hard rule 13). A pump volume in particular must stay visible
    /// and editable - the Confirm sheet dims an unconfirmed value to 60% opacity
    /// and never writes one the user has not seen, because the factor-of-ten
    /// ambiguity (Spike/ReceiptSpike/fixtures/pump/README.md) is otherwise
    /// invisible on a Confirm screen and corrupts consumption silently.
    public static func prefill(pumpPhotoEnabled: Bool, extraction: FuelExtraction?) -> FuelExtraction? {
        guard pumpPhotoEnabled else { return nil }
        return extraction
    }
}
