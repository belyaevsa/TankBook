import SwiftUI
import TankbookCore

// MARK: - Shared catalog suggestion list (RV.137)

/// The live catalog suggestion list under the "Make · model · year" row,
/// shared by Add car and Vehicle detail. One implementation of "which bundled
/// catalog rows match the field text" - a second one would be exactly the
/// duplication RV.129 names. Choosing a row calls `onApply` with the entry's
/// `CatalogPrefill`; what a pick means is the caller's decision, never this
/// view's (Add car fills the whole form, Vehicle detail fills only the
/// make/model/year text - the permanence decision in VehicleDetailView's
/// header, where nothing stores a catalogue id for a later pack to rewrite).
///
/// Visibility is a caller concern too: `showsSuggestions` is decided up the
/// tree by `ModelSuggestionGate` + the offline state (RV.67), never by this
/// view or by focus. The offline hint is Add-car-only copy and stays in
/// `AddVehicleCatalogArea`; a bundled catalogue cannot be offline for the edit
/// screen, so there is no hint to render there.
struct VehicleCatalogSuggestionsArea: View {
    /// The field's current text; empty or whitespace yields no rows.
    let query: String
    let entries: [VehicleCatalogEntry]
    /// The units the row's tank/battery subtitle should read in - the vehicle's
    /// own per-car units on the edit screen, the locale's on Add car.
    let units: Vehicle.Units
    /// Prefix for `*Suggestion_<index>` accessibility identifiers, so a UI test
    /// on one screen never matches the other screen's rows.
    let idPrefix: String
    let onApply: (CatalogPrefill) -> Void

    var body: some View {
        let suggestions = CatalogSuggester(entries: entries)
            .suggestions(for: query, limit: 5)
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
                        // A year is not a quantity: interpolated into a SwiftUI
                        // `Text` it picks up locale grouping ("2,011–" in EN,
                        // "2 011–" in RU), so it is built verbatim (RV.69).
                        if let end = suggestion.entry.yearsEnd {
                            Text(verbatim: "\(suggestion.entry.yearsStart)–\(end)")
                        } else {
                            Text(verbatim: "\(suggestion.entry.yearsStart)–")
                        }
                        if let tank = suggestion.entry.tankCapacityL {
                            let tankText = AddVehicleSupport.tankCapacityText(litres: tank, unit: units.volume)
                            Text("· \(tankText) \(L10n.volumeUnit(units.volume))")
                        }
                        if let battery = suggestion.entry.batteryCapacityKWh {
                            let batteryText = AddVehicleSupport.capacityText(battery)
                            Text("· \(batteryText) \(L10n.kWh)")
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
        .accessibilityIdentifier("\(idPrefix)Suggestion_\(index)")
    }
}
