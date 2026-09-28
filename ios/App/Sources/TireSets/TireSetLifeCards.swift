import SwiftUI
import TankbookCore

// MARK: - The tires' properties

/// The tires' own properties on the set form (docs/SCHEMA.md -> TireSet): make,
/// model, size, DOT week, treadwear and the new tread depth. Every field is
/// optional and stays the user's to change (hard rule 13). Same card metrics,
/// eyebrow and underline as the name card beside it.
struct TireSetSpecsCard: View {
    @Binding var form: TireSetFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tires")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
            HStack(alignment: .top, spacing: 12) {
                TireField(label: "Make", placeholder: "Nokian", text: $form.make,
                          identifier: "tireSetMakeField")
                TireField(label: "Model", placeholder: "Hakkapeliitta 10", text: $form.model,
                          identifier: "tireSetModelField")
            }
            HStack(alignment: .top, spacing: 12) {
                TireField(label: "Size", placeholder: "205/55 R16", text: $form.size,
                          identifier: "tireSetSizeField")
                TireField(label: "DOT week", placeholder: "3624", text: $form.productionWeek,
                          identifier: "tireSetDotField", keyboard: .numberPad, digits: true)
            }
            HStack(alignment: .top, spacing: 12) {
                TireField(label: "Treadwear", placeholder: "400", text: $form.treadwear,
                          identifier: "tireSetTreadwearField", keyboard: .numberPad, digits: true,
                          warn: form.readiness == .treadwearInvalid)
                TireField(label: "New tread, mm", placeholder: "9", text: $form.newTreadDepth,
                          identifier: "tireSetNewTreadField", keyboard: .decimalPad, digits: true,
                          warn: form.readiness == .treadDepthInvalid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .formCard()
    }
}

/// One labelled tire field: the eyebrow over an underlined text field. Digits
/// render in DIN (hard rule 6).
struct TireField: View {
    let label: LocalizedStringKey
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let identifier: String
    var keyboard: UIKeyboardType = .default
    var digits = false
    var warn = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(warn ? Theme.Palette.warn : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TextField(placeholder, text: $text)
                .font(digits ? .custom(AppFonts.dinAlternateBold, size: 16).monospacedDigit() : .subheadline)
                .foregroundStyle(Theme.Palette.ink)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .focused($focused)
                .fieldUnderline(isFocused: focused, warn: warn)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The history

/// The set's life (docs/JOURNEYS.md J7b): one row per stint, oldest first, with
/// its period, its distance, the running total and the condition read at the
/// swap. Derived from the swap records on every load, never stored (hard rule
/// 2). Each row's reading stays editable (hard rule 13).
struct TireSetHistoryCard: View {
    let stints: [TireMileage.Stint]
    let distanceUnit: DistanceUnit
    let onEditReading: (TireMileage.Stint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
                .padding(.bottom, 8)
            if stints.isEmpty {
                Text("No swaps logged yet – log a tire swap in Service to start the history.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tireSetHistoryEmpty")
            } else {
                ForEach(Array(stints.reversed().enumerated()), id: \.element.mountRecordId) { index, stint in
                    if index > 0 { Divider().overlay(Theme.Palette.hairline) }
                    TireStintRow(stint: stint, distanceUnit: distanceUnit,
                                 onEditReading: { onEditReading(stint) })
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .formCard()
        .accessibilityIdentifier("tireSetHistory")
    }
}

private struct TireStintRow: View {
    let stint: TireMileage.Stint
    let distanceUnit: DistanceUnit
    let onEditReading: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(TireStintFormat.period(stint))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if stint.isOnCar {
                    Text("On the car")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("tireStintOnCar")
                }
                Spacer(minLength: 4)
                Text(TireSetRowFormat.mileageText(km: stint.km, distanceUnit: distanceUnit))
                    .font(.custom(AppFonts.dinAlternateBold, size: 16).monospacedDigit())
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("tireStintDistance")
            }
            if let total = TireStintFormat.total(stint, distanceUnit: distanceUnit) {
                Text(total)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("tireStintTotal")
            }
            Button(action: onEditReading) {
                HStack(spacing: 6) {
                    Image(systemName: "ruler")
                        .font(.caption2)
                    Text(TireStintFormat.reading(stint.reading) ?? L10n.localize("Add a condition reading"))
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(stint.reading == nil ? Theme.Palette.action : Theme.Palette.inkSoft)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tireStintReading")
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tireStintRow")
    }
}

// MARK: - The condition reading

/// The two fields of a swap's condition reading: the tread depth measured and a
/// note on wear or damage. Shared by the swap form and the history's edit
/// sheet, so both doors write the same shape.
struct TireReadingFields: View {
    @Binding var depth: String
    @Binding var note: String
    var depthInvalid = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TireField(label: "Tread depth, mm", placeholder: "6.5", text: $depth,
                      identifier: "tireReadingDepthField", keyboard: .decimalPad, digits: true,
                      warn: depthInvalid)
            TireField(label: "Condition", placeholder: "Even wear, no damage", text: $note,
                      identifier: "tireReadingNoteField")
        }
    }
}

/// Edits the reading of one stint after its swap was saved (hard rule 13). It
/// writes only the swap record's reading - its items, links and odometer stay.
struct TireReadingSheet: View {
    let stint: TireMileage.Stint
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var depth = ""
    @State private var note = ""
    @State private var didLoad = false

    private var parsed: TireMeasure.Parsed<TireReading> { TireReading.from(depth: depth, note: note) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(TireStintFormat.period(stint))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    TireReadingFields(depth: $depth, note: $note, depthInvalid: parsed == .invalid)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .formCard()
                    if parsed == .invalid {
                        Text("Tread depth is in mm, like 8.5")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .accessibilityIdentifier("tireReadingHint")
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.top, 8)
            }
            .background(Theme.Palette.midnight)
            .navigationTitle("Condition reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsed == .invalid)
                        .accessibilityIdentifier("tireReadingSaveButton")
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            depth = TireMeasure.depthText(stint.reading?.treadDepthMm)
            note = stint.reading?.note ?? ""
        }
    }

    private func save() {
        guard parsed != .invalid else { return }
        do {
            try AppStore.repository().setTireReading(parsed.value, onSwap: stint.mountRecordId)
            onSaved()
            dismiss()
        } catch {
            AppLog.error(operation: "tireReading.save", category: .ui, error: error)
        }
    }
}

extension TireMileage.Stint: @retroactive Identifiable {
    public var id: UUID { mountRecordId }
}
