import SwiftUI
import TankbookCore

/// The Reminder form's cards (P3.4), split out so `ReminderFormView` stays
/// small and each card owns one concern - the same shape as ServiceEntry's
/// sections. All fields edit the shared `ReminderFormState`; the due card is
/// where the no-due-field invariant (docs/SCHEMA.md) surfaces as a warn that
/// names its next step (hard rule 7).

/// The eyebrow label the form's cards share ("TITLE", "DATE", "ODOMETER").
func reminderEyebrow(_ label: LocalizedStringKey) -> some View {
    Text(label)
        .font(.caption2)
        .textCase(.uppercase)
        .tracking(1.0)
        .foregroundStyle(Theme.Palette.inkSoft)
}

// MARK: - Car

/// The form's FIRST card (design/screens/ReminderForm.dc.html) and the one the
/// merged list exists for (docs/SCREENMAP.md -> "the car as its first field"):
/// a reminder is about a car, so the field is offered explicitly rather than
/// guessed. The merged list opens it with nothing chosen (Save inert until one
/// is picked); a car's own list opens it with that car chosen, still
/// changeable (hard rule 13 - a default input, never a fact). Car names are
/// user text: each chip keeps its intrinsic width and the flow wraps whole
/// chips, so a long Russian name is never truncated.
struct ReminderFormCarCard: View {
    let vehicles: [Vehicle]
    let selectedVehicleID: UUID?
    let onSelect: (UUID) -> Void
    /// The "nothing is picked for you" caption explains a CREATE's opener (the
    /// merged list vs a car's own screen). An edit's car comes from the
    /// reminder itself, so the caption would only mislead there.
    let showsCaption: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                reminderEyebrow("Car")
                Spacer(minLength: 8)
                if selectedVehicleID == nil {
                    Text("Pick one")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("reminderFormCarRequiredHint")
                }
            }
            CarChipFlow(spacing: 6, rowSpacing: 6) {
                ForEach(vehicles, id: \.id) { vehicle in
                    chip(vehicle)
                }
            }
            if showsCaption {
                Text("Nothing is picked for you here – from a car's own screen yours is pre-chosen, still changeable.")
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .formCard()
    }

    private func chip(_ vehicle: Vehicle) -> some View {
        let selected = vehicle.id == selectedVehicleID
        return Button {
            onSelect(vehicle.id)
        } label: {
            Text(vehicle.name)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reminderFormCar_\(vehicle.name)")
    }
}

/// Packs the car chips at their intrinsic widths, left-to-right, wrapping a
/// chip onto the next row only when it genuinely does not fit - the same
/// behaviour the fuel card's trailing flow delivers, leading-aligned for a
/// form's left-edge label. A chip is never compressed, so a car name (user
/// text) cannot be truncated by the layout.
private struct CarChipFlow: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(of: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height }
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? (rows.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let rows = rows(of: subviews, maxWidth: proposal.width ?? bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let gap = row.indices.isEmpty ? 0 : spacing
            if maxWidth.isFinite, !row.indices.isEmpty,
               row.width + gap + size.width > maxWidth {
                result.append(row)
                row = Row()
            }
            let nextGap = row.indices.isEmpty ? 0 : spacing
            row.indices.append(index)
            row.width += nextGap + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { result.append(row) }
        return result
    }
}

// MARK: - Title

/// The title field card. The empty-title warn uses the same amber underline
/// mechanism as every other form field in the app.
struct ReminderFormTitleCard: View {
    @Binding var form: ReminderFormState
    @FocusState.Binding var focus: ReminderFormFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            reminderEyebrow("Title")
            TextField("", text: $form.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: .title)
                .fieldUnderline(isFocused: focus == .title,
                                warn: form.readiness == .titleMissing)
                .accessibilityIdentifier("reminderFormTitleField")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .formCard()
    }
}

// MARK: - Category

/// The category chip grid. Every offered category is a fixed case - `.other`
/// free text is an invoice-line concept, not a reminder category (docs/SCHEMA.md).
struct ReminderFormCategoryCard: View {
    @Binding var form: ReminderFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            reminderEyebrow("Category")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6, alignment: .leading)],
                      alignment: .leading, spacing: 6) {
                ForEach(ReminderCategory.formCases, id: \.self) { category in
                    chip(category)
                }
            }
        }
        .padding(13)
        .formCard()
    }

    private func chip(_ category: ReminderCategory) -> some View {
        let selected = form.category == category
        return Button {
            form.category = category
        } label: {
            ReminderCategoryLabel(category: category)
                .font(.footnote.weight(selected ? .bold : .semibold))
                .foregroundStyle(selected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.Palette.taillight.opacity(0.14) : Theme.Palette.dash))
                .overlay(Capsule().stroke(selected ? Theme.Palette.taillight : Theme.Palette.hairline,
                                          lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminderFormCategory_\(category.rawLabel)")
    }
}

// MARK: - Due

/// The date + odometer card, where the "neither due field" rule lives: each
/// field is optional on its own, but a reminder with neither is not a reminder
/// (docs/SCHEMA.md), and Save refuses with the warn below naming the next step.
struct ReminderFormDueCard: View {
    @Binding var form: ReminderFormState
    @FocusState.Binding var focus: ReminderFormFocus?
    let distanceUnit: DistanceUnit
    @Binding var showDatePicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            dateRow
            CardDivider()
            odometerRow
            if form.readiness == .noDueField {
                noDueWarning
            }
        }
        .formCard()
    }

    private var dateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            reminderEyebrow("Date")
            Spacer(minLength: 8)
            if form.hasDueDate {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(form.dueDate.formatted(.dateTime.month(.abbreviated).day().year()))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.Palette.ink)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminderFormDateButton")
                Button {
                    form.hasDueDate = false
                    showDatePicker = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Remove date")
                .accessibilityIdentifier("reminderFormClearDateButton")
            } else {
                Button {
                    form.hasDueDate = true
                    showDatePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                        Text("Add date")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Palette.action)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reminderFormAddDateButton")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    private var odometerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            reminderEyebrow("Odometer")
            Spacer(minLength: 8)
            TextField("", text: $form.dueOdometer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(Theme.Palette.ink)
                .focused($focus, equals: .odometer)
                .fieldUnderline(isFocused: focus == .odometer,
                                warn: form.readiness == .noDueField)
                .accessibilityIdentifier("reminderFormOdometerField")
                .numericInput($form.dueOdometer, kind: .integer)
                .onChange(of: focus) { oldValue, newValue in
                    if newValue == .odometer {
                        form.dueOdometer = OdometerFormat.ungrouped(form.dueOdometer)
                    } else if oldValue == .odometer, let value = form.odometerValue {
                        form.dueOdometer = OdometerFormat.grouped(value)
                    }
                }
            Text(L10n.distanceUnit(distanceUnit))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            if !form.dueOdometer.isEmpty {
                Button {
                    form.dueOdometer = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Remove odometer")
                .accessibilityIdentifier("reminderFormClearOdometerButton")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    /// The no-due-field warn (docs/ERRORS.md -> Reminders, hard rule 7): names
    /// the condition AND the next step - the two rows above it.
    private var noDueWarning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn)
            Text("A reminder needs a date or an odometer – set one to save.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.warn)
                .accessibilityIdentifier("reminderFormNoDueWarning")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.bottom, 10)
    }
}

// MARK: - Recurrence

/// The "Repeat every" card: months and kilometres, each optional. A zero in
/// either is a no-op (ReminderDraft treats it as unset).
struct ReminderFormRecurrenceCard: View {
    @Binding var form: ReminderFormState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reminderEyebrow("Repeat every")
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 4)
            recurrenceRow(label: "Months", unit: L10n.localize("months"),
                          text: $form.recurrenceEveryMonths,
                          identifier: "reminderFormMonthsField")
            CardDivider()
            recurrenceRow(label: "Kilometres", unit: L10n.localize("km"),
                          text: $form.recurrenceEveryKm,
                          identifier: "reminderFormKmField")
        }
        .formCard()
    }

    private func recurrenceRow(label: LocalizedStringKey, unit: String,
                               text: Binding<String>, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 15))
                .foregroundStyle(Theme.Palette.ink)
                .frame(maxWidth: 90)
                .accessibilityIdentifier(identifier)
                .numericInput(text, kind: .integer)
            Text(unit)
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }
}
