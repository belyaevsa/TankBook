import SwiftUI
import TankbookCore

// MARK: - Category labels

/// Display labels for a line item's category. Fixed cases map to catalogue
/// keys; `.other(value)` carries free text that is runtime data, so it renders
/// through `Text(String)` - the split keeps the coalesced-String trap out
/// (see the note atop `L10n.swift`).
extension ServiceCategory {
    var fixedLabelKey: LocalizedStringKey? {
        switch self {
        case .oil: "Oil"
        case .brakes: "Brakes"
        case .tires: "Tires"
        case .battery: "Battery"
        case .filters: "Filters"
        case .inspection: "Inspection"
        case .repair: "Repair"
        case .parts: "Parts"
        case .wash: "Wash"
        case .other: nil
        }
    }

    var otherText: String? {
        if case .other(let value) = self { return value }
        return nil
    }

    /// The fixed categories the chooser offers, in a stable order.
    static let fixedCases: [ServiceCategory] = [
        .oil, .brakes, .tires, .battery, .filters, .inspection, .repair, .parts, .wash
    ]
}

/// Renders a category either as its fixed localised label or as `.other`'s free
/// text (empty -> "Other").
struct ServiceCategoryLabel: View {
    let category: ServiceCategory

    var body: some View {
        if let other = category.otherText {
            if other.isEmpty {
                Text("Other")
            } else {
                Text(other)
            }
        } else if let key = category.fixedLabelKey {
            Text(key)
        }
    }
}

// MARK: - Mode row

/// The Service / Parts / Tires / Other row (artboard).
///
/// Merged from P3.2 and P3.3, which each rewrote this row for their own half:
/// **Service and Tires are real modes** (a tire swap is a ServiceRecord
/// carrying `tireSetId`, P3.3) and **Parts and Other are forward exits** into
/// the Expense entry (P3.2, hard rule 15 - they are peer doors, not a fallback).
/// Neither agent could see the other's branch, so each left the other's chips
/// unwired; the row only works with both.
struct ServiceEntryModeRow: View {
    @Binding var mode: ServiceEntryMode
    let onParts: () -> Void
    let onOther: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            selectableChip("Service", selected: mode == .service,
                           identifier: "serviceEntryModeService") { mode = .service }
            selectableChip("Parts", selected: false,
                           identifier: "serviceEntryModeParts", action: onParts)
            selectableChip("Tires", selected: mode == .tires,
                           identifier: "serviceEntryModeTires") { mode = .tires }
            selectableChip("Other", selected: false,
                           identifier: "serviceEntryModeOther", action: onOther)
        }
    }

    private func selectableChip(_ label: LocalizedStringKey, selected: Bool,
                                identifier: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Tire set picker (P3.3)

/// The Tires mode's one decision: which set went on. Selecting a set mounts it
/// (sets `tireSetId`), which makes the odometer required (P3.1a's rule - the
/// span anchors on it). When the car has no sets yet, the card names the next
/// step (add one in the Garage) rather than blocking (hard rule 7).
struct ServiceEntryTireSetCard: View {
    let tireSets: [TireSet]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tire set")
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(Theme.Palette.inkSoft)
            if tireSets.isEmpty {
                Text("No tire sets yet – add one from Garage.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("serviceEntryTireSetEmpty")
            } else {
                Menu {
                    ForEach(tireSets, id: \.id) { set in
                        Button {
                            onSelect(set.id)
                        } label: {
                            Text(set.name)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedName ?? L10n.localize("Choose set"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.Palette.ink)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .accessibilityIdentifier("serviceEntryTireSetPicker")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .formCard()
    }

    private var selectedName: String? {
        guard let selectedID else { return nil }
        return tireSets.first { $0.id == selectedID }?.name
    }
}

// MARK: - Vendor + total header

/// The vendor field and the derived header total (artboard: "Bosch Service" /
/// "148.00 €"). The total is the sum of the item costs - derived, never stored
/// (hard rule 2).
struct ServiceEntryHeader: View {
    @Binding var vendor: String
    let totalText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("Vendor", text: $vendor)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("serviceEntryVendorField")
            Spacer(minLength: 8)
            Text(totalText)
                .font(.custom(AppFonts.dinAlternateBold, size: 24))
                .foregroundStyle(Theme.Palette.taillight)
                .accessibilityIdentifier("serviceEntryHeaderTotal")
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Date + odometer card

/// The two-column Date / Odometer card (artboard). The date defaults to today
/// and is editable; its `provenanceCaption` slot ("· invoice") stays nil until
/// P3.1b, so the scanned path can add it without relayout. The odometer is
/// pre-filled from the last known value and stays editable (hard rule 13);
/// when a km lifetime is set and the field is blank, the card warns and names
/// the next step (hard rule 7).
struct ServiceEntryDateOdometerCard: View {
    @Binding var form: ServiceEntryFormState
    @FocusState.Binding var focus: ServiceEntryFocus?
    let distanceUnit: DistanceUnit
    @Binding var showDatePicker: Bool
    let odometerRequired: Bool
    let onFillOdometer: () -> Void
    var provenanceCaption: LocalizedStringKey?

    var body: some View {
        // A `Grid` row, not an `HStack`: grid cells in one row share a height,
        // so the date card and the odometer card can never render as two
        // different boxes again. Equal widths come from each card filling its
        // cell. The two carry different amounts of text (a date and a caption
        // against a figure, a unit and a caption), which is exactly the case an
        // HStack renders ragged.
        Grid(horizontalSpacing: 7, verticalSpacing: 0) {
            GridRow {
                dateCard
                odometerCard
            }
        }
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            eyebrow("Date")
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() }
            } label: {
                // The caption sits on its OWN line, exactly as the odometer's
                // "last known" does. Inline, it pushed the year onto a second
                // line in BOTH languages ("Aug 9, · invoice" / "2026" and
                // "9 авг. · счёт" / "2026 г.") - the date card is the narrowest
                // half of a two-up row, and a date plus a caption plus a chevron
                // does not fit it in any language.
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(form.date.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                    if let provenanceCaption {
                        Text(provenanceCaption)
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("serviceEntryDateButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .formCard()
    }

    private var odometerCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            eyebrow("Odometer")
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .font(.custom(AppFonts.dinAlternateBold, size: 15))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($focus, equals: .odometer)
                    .fieldUnderline(isFocused: focus == .odometer,
                                    warn: odometerRequired && form.odometerValue == nil)
                    .accessibilityIdentifier("serviceEntryOdometerField")
                    .onChange(of: focus) { oldValue, newValue in
                        if newValue == .odometer {
                            form.odometer = OdometerFormat.ungrouped(form.odometer)
                        } else if oldValue == .odometer, let value = form.odometerValue {
                            form.odometer = OdometerFormat.grouped(value)
                        }
                    }
                Text(L10n.distanceUnit(distanceUnit))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            // The "last known" provenance caption sits on its own line, as the
            // ConfirmManual odometer card does - the inline artboard form is
            // where Russian ("последний известный") overflowed.
            Text("last known")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
            if odometerRequired && form.odometerValue == nil {
                warning
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .formCard()
    }

    /// The km-lifetime anchor warning (docs/ERRORS.md -> Service & expenses):
    /// the message names what the odometer is needed for, and "Fill" is the
    /// next step - the pre-filled value is one tap away.
    private var warning: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warn)
                Text("Odometer is needed to schedule the next service.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.warn)
                    .accessibilityIdentifier("serviceEntryOdometerWarning")
            }
            Button("Fill") { onFillOdometer() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.headlight)
                .accessibilityIdentifier("serviceEntryOdometerFillButton")
        }
        .padding(.top, 2)
    }

    private func eyebrow(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.caption2)
            .textCase(.uppercase)
            .tracking(1.0)
            .foregroundStyle(Theme.Palette.inkSoft)
    }
}

// MARK: - Line item

/// One line item: a title, a category chooser (the `ServiceCategory` cases plus
/// `.other` free text), and an exact cost. The cost string is the user's own
/// digits; the header total derives from it. Delete is an explicit affordance,
/// never hidden behind a swipe.
struct ServiceEntryItemCard: View {
    @Binding var item: ServiceEntryItemDraft
    let onDelete: () -> Void

    /// A scanned row renders dimmed until the user edits it (hard rule 13: the
    /// scanned value is a default input, never read-only). Editing any field
    /// lifts the dim; the shared DESIGN.md 60% opacity keeps it consistent with
    /// the confirm sheet's treatment.
    private var isDimmed: Bool { item.scanned }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                TextField("Item name", text: $item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .opacity(isDimmed ? ConfirmConfidenceGate.dimmedOpacity : 1)
                    .accessibilityIdentifier("serviceEntryItemTitle")
                TextField("", text: $item.cost)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 15))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: 96)
                    .opacity(isDimmed ? ConfirmConfidenceGate.dimmedOpacity : 1)
                    .accessibilityIdentifier("serviceEntryItemCost")
            }
            HStack {
                categoryMenu
                    .opacity(isDimmed ? ConfirmConfidenceGate.dimmedOpacity : 1)
                Spacer(minLength: 8)
                deleteButton
            }
            if item.category.otherText != nil {
                TextField("Category name", text: otherTextBinding)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("serviceEntryItemOtherCategory")
            }
        }
        .padding(13)
        .formCard()
        .onChange(of: item.title) { _, _ in confirm() }
        .onChange(of: item.cost) { _, _ in confirm() }
        .onChange(of: item.category) { _, _ in confirm() }
    }

    /// Editing a scanned row is its confirmation: the dim lifts and the value
    /// is the user's own from now on.
    private func confirm() {
        if item.scanned { item.scanned = false }
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(ServiceCategory.fixedCases, id: \.self) { category in
                Button {
                    item.category = category
                } label: {
                    ServiceCategoryLabel(category: category)
                }
            }
            Button {
                item.category = .other(item.category.otherText ?? "")
            } label: {
                Text("Other")
            }
        } label: {
            HStack(spacing: 4) {
                ServiceCategoryLabel(category: item.category)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
        }
        .accessibilityIdentifier("serviceEntryItemCategory")
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete line item")
        .accessibilityIdentifier("serviceEntryItemDelete")
    }

    /// The `.other` free text, read and written through the category. The text
    /// survives a persistence round-trip (the category-promotion path in J7
    /// depends on it).
    private var otherTextBinding: Binding<String> {
        Binding(
            get: { item.category.otherText ?? "" },
            set: { item.category = .other($0) }
        )
    }
}

// MARK: - Add line item

/// The dashed "Add line item" affordance (artboard). Always reachable - the
/// manual path is a peer of the scanned one, never a fallback (hard rule 15).
struct ServiceEntryAddItemButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                Text("Add line item")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("serviceEntryAddItemButton")
    }
}

// MARK: - Note

/// The note field (artboard). A free-text note, always optional.
struct ServiceEntryNoteRow: View {
    @Binding var note: String

    var body: some View {
        TextField("Note", text: $note)
            .font(.subheadline)
            .foregroundStyle(Theme.Palette.ink)
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            .formCard()
            .accessibilityIdentifier("serviceEntryNoteField")
    }
}
