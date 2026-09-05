import SwiftUI
import TankbookCore

// The Add-car-only sections. The identity card both screens share lives in
// Shared/VehicleFormControls.swift (lifted in P1.12); this file keeps the
// catalog suggestions area, which only Add car has.

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
        let suggestions = CatalogSuggester(entries: entries)
            .suggestions(for: form.makeModel, limit: 5)
        return Group {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                        suggestionRow(suggestion, index: index)
                        if index < suggestions.count - 1 { CardDivider() }
                    }
                }
                .formCard()
            }
        }
    }

    private func suggestionRow(_ suggestion: CatalogSuggestion, index: Int) -> some View {
        Button {
            onApply(suggestion.entry.prefill())
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    HStack(spacing: 6) {
                        if let end = suggestion.entry.yearsEnd {
                            Text("\(suggestion.entry.yearsStart)–\(end)")
                        } else {
                            Text("\(suggestion.entry.yearsStart)–")
                        }
                        if let tank = suggestion.entry.tankCapacityL {
                            Text("· \(AddVehicleSupport.capacityText(tank)) \(L10n.volumeUnit(units.volume))")
                        }
                        if let battery = suggestion.entry.batteryCapacityKWh {
                            Text("· \(AddVehicleSupport.capacityText(battery)) \(L10n.kWh)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Theme.Palette.taillight)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("addVehicleSuggestion_\(index)")
    }
}
