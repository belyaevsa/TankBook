import Foundation
import TankbookCore

/// Everything the tire-set name form collects, plus the save decision. The raw
/// string lives here; the decision - whether the draft may save and why - lives
/// in the pure `TireSetDraft` so the view, its L1 tests and the L4 tests all
/// share one gate. The same two-layer pattern as `ServiceEntryFormState` ->
/// `ServiceEntryDraft`.
struct TireSetFormState: Equatable {
    var name = ""
    var initialName = ""

    var draft: TireSetDraft { TireSetDraft(name: name) }

    var readiness: TireSetDraft.SaveReadiness { draft.readiness }

    /// The trimmed name, so a whitespace-only name is the same as an empty one
    /// and never persists.
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Populates the form from an existing set for the rename path. The name
    /// lands as a user-editable default (hard rule 13).
    static func from(tireSet: TireSet) -> TireSetFormState {
        var state = TireSetFormState()
        state.name = tireSet.name
        state.initialName = tireSet.name
        return state
    }

    /// Real edits only (the discard guard on the sheet): a moved name.
    func hasEdits() -> Bool {
        name != initialName
    }
}
