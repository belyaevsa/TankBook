import Foundation

// MARK: - P2.7 the pump-photo accuracy gate
//
// Pump-photo mode ships only when the pump corpus scores >=95% in the L5
// accuracy harness (docs/VISION.md, docs/PHASES.md -> P2 exit gate), and the
// gate IS the check (docs/TASKS.md P2.7). The gate is a property of the
// build's own measured accuracy, never a runtime opinion: the numbers below are
// what the Spike harness scored when this build was cut, and a remote config
// document may only turn the flag DOWN while they are below the threshold -
// never up. The reasoning is the same as docs/CONFIG.md -> "Config can never
// disable a security control": a document must not be able to defeat an
// accuracy gate any more than it can defeat a security control.

/// The pump-photo accuracy gate. `measuredHits` / `measuredTotal` are the raw
/// field score the Spike harness (`cd Spike/ReceiptSpike && swift run
/// ReceiptSpike fixtures/pump`) reported when this build was cut, and the
/// Vision-gated ratchet test asserts they match the live corpus score - so the
/// constant cannot drift from reality without a failing test.
public enum PumpPhotoGate {
    /// Pump fields resolved by the parser at build time. 21 today, over 84 -
    /// the pump corpus scores 25.0% across twenty-three pumps from six
    /// manufacturers (Spike/ReceiptSpike/fixtures/pump/README.md). The jump
    /// from 2/61 came in P6.14, and it is NOT a parser improvement: the gate
    /// began scoring `currency`, and the extractor's marker-word detector
    /// (РУБ/€/EUR/...) already reads 19 of the 23 displays. The three numeric
    /// fields are still 2/61 - pump extraction remains the hard problem, and
    /// 25.0% is still noise against a 95% gate, which is why the mode still
    /// ships off.
    ///
    /// 2026-08-30: pump-030 (Tokheim, Zolotaya Seredina, Tver) added 5 scored
    /// fields and 1 hit - 25/111 -> 26/116, 22.5% -> 22.4%. A new fixture that
    /// scores 1 of 5 moves the ratio DOWN, which is the corpus working as
    /// intended: the gate tracks reality, it does not flatter it.
    public static let measuredHits: Int = 32

    /// Pump fields scored at build time. Not 23 x 3: the blank numeric cells
    /// stay skipped (glare on a total, the two idle pumps have no meaningful
    /// unit price, and pump-021/022/023 show a grade price BOARD rather than
    /// the transaction's unit price), and `fuelKind` is never asserted for a
    /// pump at all. The 23 currency cells are what raised 61 -> 84.
    public static let measuredTotal: Int = 171

    /// The ship threshold (docs/VISION.md, docs/PHASES.md -> P2 exit gate).
    public static let threshold: Double = 0.95

    /// The measured field accuracy as a fraction in 0...1.
    public static var measuredAccuracy: Double {
        measuredTotal > 0 ? Double(measuredHits) / Double(measuredTotal) : 0
    }

    /// Whether this build may offer pump-photo mode. The gate, not the remote
    /// flag, is the deciding input: `ConfigStore.isEnabled(.pumpPhoto)` is false
    /// regardless of rollout while this is false.
    public static var allowsPumpPhoto: Bool { measuredAccuracy >= threshold }

    /// The gate as a check: nil when a flag state is consistent with the build's
    /// measured accuracy, else a violation naming the inconsistency. P2.7's
    /// deliverable is the test that calls this with the real numbers - a flag
    /// turned on while the corpus is below the threshold is a violation, a flag
    /// left off is never one.
    public static func violation(flagEnabled: Bool, accuracy: Double) -> String? {
        guard flagEnabled else { return nil }
        guard accuracy >= threshold else {
            return "pumpPhoto is enabled but pump accuracy \(accuracy) is below the ship gate \(threshold)"
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
