import SwiftUI
import TankbookCore

// MARK: - Identity card (Name / Make · model · year / Plate)

/// The three-row identity card plus the empty-name warn
/// (docs/ERRORS.md -> Add car, row 1: "Name empty on save").
struct AddVehicleIdentityCard: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?

    var body: some View {
        VStack(spacing: 0) {
            nameRow
            CardDivider()
            makeModelRow
            CardDivider()
            plateRow
        }
        .formCard()
    }

    private var nameRow: some View {
        VStack(spacing: 0) {
            FieldRow("Name") {
                TextField("", text: $form.name)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .name)
                    .fieldUnderline(isFocused: focus == .name, warn: form.showNameWarning)
                    .accessibilityIdentifier("addVehicleNameField")
            }
            if form.showNameWarning {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.warn)
                    Text("Give the car any name – you can change it later.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("addVehicleNameWarning")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.cardPadding)
                .padding(.bottom, 10)
            }
        }
    }

    private var makeModelRow: some View {
        FieldRow("Make · model · year") {
            TextField("", text: $form.makeModel)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: .makeModel)
                .accessibilityIdentifier("addVehicleMakeModelField")
                .onChange(of: form.makeModel) { _, newValue in
                    let parsed = MakeModelParser.parse(newValue)
                    form.make = parsed.make
                    form.model = parsed.model
                    form.year = parsed.year
                }
        }
    }

    private var plateRow: some View {
        FieldRow("Plate") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("", text: $form.plate)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .plate)
                    .accessibilityIdentifier("addVehiclePlateField")
                Text("Optional")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
    }
}

// MARK: - Catalog area (error-state 3: offline hint, else suggestions)

/// Below the identity card: either the offline hint or the live suggestion
/// list. The hint is a Hint (docs/ERRORS.md -> Add car, row 3) - nothing is
/// blocked, "continue manually" is the next step.
struct AddVehicleCatalogArea: View {
    @Binding var form: AddVehicleFormState
    @FocusState.Binding var focus: AddVehicleFocus?
    let entries: [VehicleCatalogEntry]
    let unavailable: Bool
    let units: Vehicle.Units
    let onApply: (CatalogPrefill) -> Void

    @ViewBuilder
    var body: some View {
        if unavailable {
            hintRow
        } else if focus == .makeModel, !form.makeModel.isEmpty {
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
