import Foundation
import TankbookCore

/// Everything the tire-set form collects, plus the save decision. The raw
/// strings live here; the decision - whether the draft may save and why - lives
/// in the pure `TireSetDraft` so the view, its L1 tests and the L4 tests all
/// share one gate. The same two-layer pattern as `ServiceEntryFormState` ->
/// `ServiceEntryDraft`.
struct TireSetFormState: Equatable {
    var name = ""
    var make = ""
    var model = ""
    var size = ""
    var productionWeek = ""
    var treadwear = ""
    var newTreadDepth = ""

    /// The values the form opened with, for the discard guard.
    var initial = TireSetDraft(name: "")

    var draft: TireSetDraft {
        TireSetDraft(name: name, make: make, model: model, size: size,
                     productionWeek: productionWeek, treadwear: treadwear,
                     newTreadDepth: newTreadDepth)
    }

    var readiness: TireSetDraft.SaveReadiness { draft.readiness }

    /// The disabled-save hint's next step (hard rule 7), derived from the same
    /// readiness the gate uses.
    var saveHint: String? {
        switch readiness {
        case .ready: nil
        case .nameMissing: L10n.localize("Add a name to save")
        case .treadwearInvalid: L10n.localize("Treadwear is a whole number, like 400")
        case .treadDepthInvalid: L10n.localize("Tread depth is in mm, like 8.5")
        }
    }

    /// Populates the form from an existing set for the edit path. Every value
    /// lands as a user-editable default (hard rule 13).
    static func from(tireSet: TireSet) -> TireSetFormState {
        var state = TireSetFormState()
        state.name = tireSet.name
        state.make = tireSet.make ?? ""
        state.model = tireSet.model ?? ""
        state.size = tireSet.size ?? ""
        state.productionWeek = tireSet.productionWeek ?? ""
        state.treadwear = tireSet.treadwear.map(String.init) ?? ""
        state.newTreadDepth = TireMeasure.depthText(tireSet.newTreadDepthMm)
        state.initial = state.draft
        return state
    }

    /// Real edits only (the back-navigation discard guard).
    func hasEdits() -> Bool {
        draft != initial
    }
}
