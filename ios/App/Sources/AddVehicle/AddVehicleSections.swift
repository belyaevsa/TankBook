import SwiftUI
import TankbookCore

// The Add-car-only sections. The identity card and the catalog suggestion list
// both screens share live in Shared (VehicleFormControls.swift and
// VehicleCatalogSuggestionsArea.swift); this file keeps the offline hint for
// the Add-car-only catalog state (RV.137 moved the suggestion list itself into
// Shared so Vehicle detail offers the same rows without a second suggester).

// MARK: - Catalog area (error-state 3: offline hint, else suggestions)

/// Below the identity card: either the offline hint or the live suggestion
/// list. The hint is a Hint (docs/ERRORS.md -> Add car, row 3) - nothing is
/// blocked, "continue manually" is the next step.
///
/// `showsSuggestions` is DECOUPLED from focus (RV.67): it is a pure function
/// of the field text and whether that text was just accepted from a suggestion
/// (`ModelSuggestionGate`), never of which field is first responder. Gating the
/// list on `focus == .makeModel` made it unmount the moment a scroll gesture
/// dismissed the keyboard (`.scrollDismissesKeyboard(.immediately)` clears
/// `@FocusState`) - the exact gesture a user needs to reach the lower rows of a
/// five-row match. The list now stays mounted while the text reads as a query,
/// and unmounts on apply, on clear, or when the field is edited back onto a new
/// query.
struct AddVehicleCatalogArea: View {
    @Binding var form: AddVehicleFormState
    let showsSuggestions: Bool
    let entries: [VehicleCatalogEntry]
    let unavailable: Bool
    let units: Vehicle.Units
    let onApply: (CatalogPrefill) -> Void

    @ViewBuilder
    var body: some View {
        if unavailable {
            hintRow
        } else if showsSuggestions {
            suggestionsList
        }
    }

    private var hintRow: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Suggestions unavailable offline – you can fill tank size later in Garage.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("addVehicleCatalogHint")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var suggestionsList: some View {
        VehicleCatalogSuggestionsArea(query: form.makeModel,
                                      entries: entries,
                                      units: units,
                                      idPrefix: "addVehicle",
                                      onApply: onApply)
    }
}
