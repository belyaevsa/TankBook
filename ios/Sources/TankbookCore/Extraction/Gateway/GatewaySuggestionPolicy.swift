import Foundation

// MARK: - P6.3 the late-answer rule (docs/API.md -> "The device's side of
// /extract", rule 3; docs/EXTRACTION.md -> "the gateway cross-checks and
// suggests, it never trusts").
//
// A late answer - the budget expired, the request kept running, the answer
// arrived after the user had already moved on - is bound by hard rule 13 and
// by F4:
//
// - it may fill **only fields that are still blank and untouched**, and it
//   renders as a suggestion the user can reject;
// - it may **never** overwrite a field the user has typed in or confirmed;
// - once the entry is **saved, nothing arrives at all**.
//
// "Blank" means the on-device pipeline left the field unresolved: the on-device
// result was already on screen when the gateway started, so it has first claim
// and a gateway answer must never fight it. "Touched" means the user has
// engaged the field since the pre-fill; engagement is permanent.

/// What the form already holds and has done, at the moment a gateway answer
/// arrives - the input the policy decides over.
public struct GatewaySuggestionSnapshot: Sendable, Equatable {
    /// The fields the user has engaged since the on-device pre-fill (tapped,
    /// typed, or picked). Once engaged, a field is the user's own: no late
    /// answer may overwrite it (hard rule 13).
    public var touched: Set<FieldRef>
    /// The fields the on-device pipeline resolved. A resolved field is not
    /// blank - the on-device result was already on screen (F4), and the
    /// gateway never fights the parser for a field the parser already holds.
    public var onDeviceResolved: Set<FieldRef>
    /// The entry was saved. A saved entry is corrected by its owner alone
    /// (F4): nothing arrives after save.
    public var saved: Bool

    public init(touched: Set<FieldRef> = [], onDeviceResolved: Set<FieldRef> = [], saved: Bool = false) {
        self.touched = touched
        self.onDeviceResolved = onDeviceResolved
        self.saved = saved
    }
}

/// The single place the fill-blanks-only rule lives, so the Confirm sheet and
/// the tests cannot disagree about where the boundary is.
public enum GatewaySuggestionPolicy {

    /// The subset of a gateway answer that may fill the form: fields that are
    /// still blank AND untouched, on an unsaved entry. Empty when the entry is
    /// saved - the hard F4 stop.
    public static func fillableFields(
        answer: GatewayExtraction,
        snapshot: GatewaySuggestionSnapshot
    ) -> Set<FieldRef> {
        guard !snapshot.saved else { return [] }
        return answer.providedFields.filter { ref in
            !snapshot.onDeviceResolved.contains(ref) && !snapshot.touched.contains(ref)
        }
    }

    /// The boolean form of the rule, per field. Kept as its own function so a
    /// single field's treatment is directly assertable.
    public static func mayFill(
        ref: FieldRef,
        onDeviceResolved: Bool,
        touched: Bool,
        saved: Bool
    ) -> Bool {
        guard !saved, !onDeviceResolved, !touched else { return false }
        return true
    }
}
