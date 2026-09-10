import SwiftUI
import TankbookCore

/// Which field of the non-fill edit form holds focus (drives the whole-row
/// tap-to-focus of RV.47 and the odometer's format-on-blur).
enum EditEntryNonFillFocus: Hashable {
    case amount, energy, provider, vendor, title, odometer
}

/// The edit form for the three non-FillUp entry types (docs/SCHEMA.md, Entry):
/// a charge, a service record or an expense. Compact editable rows - amount +
/// currency chips (the lifted `CurrencyChipRow`), the type's own headline field,
/// date, odometer and note. Every value is a default input, never a fact
/// (hard rule 13).
struct EditEntryNonFillView: View {
    @Binding var form: EditEntryNonFillForm
    let entry: any Entry
    let vehicle: Vehicle
    /// The complete, ordered currency offer for the edited entry's car
    /// (docs/SCHEMA.md -> Currency offer).
    let offer: [CurrencyCode]
    let attachments: [Attachment]
    @Binding var showDatePicker: Bool
    let syncOverwrite: SyncOverwrite?
    let onRestore: () -> Void
    let pendingBlobIDs: Set<UUID>
    let onAttachmentChanged: (FuelExtraction?) -> Void

    @FocusState private var nonFillFocus: EditEntryNonFillFocus?

    private var distanceUnit: DistanceUnit { vehicle.units.distance }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if !attachments.isEmpty {
                    EditEntryRows.receiptCard(attachments: attachments, entry: entry,
                                              pendingBlobIDs: pendingBlobIDs,
                                              onAttachmentChanged: onAttachmentChanged)
                }
                typeCard
                moneyCard
                ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
                odometerRow
                EditEntryRows.noteRow(text: $form.note, identifier: "editEntryNonFillNoteField")
                if let syncOverwrite {
                    EditEntryRows.changedBySyncRow(deviceName: syncOverwrite.deviceName,
                                                   replacedAt: syncOverwrite.replacedAt,
                                                   onRestore: onRestore)
                }
                // No consumption footnote here. "Edits recalculate consumption
                // for this and the next fill-up" is a FILL-UP's promise: a
                // service, an expense or a charge moves no consumption segment
                // (docs/SCHEMA.md - only FillUp changes trigger a recompute),
                // and saying otherwise on an expense told the user their
                // parking receipt would move their L/100km.
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var typeCard: some View {
        switch entry {
        case let charge as ChargeSession:
            VStack(spacing: 0) {
                // RV.47: whole row (label + gap) focuses the field.
                FocusableFieldRow("Energy", $nonFillFocus, equals: .energy,
                                  rowIdentifier: "editEntryEnergyRow") {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        TextField("0", text: $form.energyKWh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.custom(AppFonts.dinAlternateBold, size: 24))
                            .foregroundStyle(Theme.Palette.ink)
                            .focused($nonFillFocus, equals: .energy)
                            .accessibilityIdentifier("editEntryEnergyField")
                            .numericInput($form.energyKWh, kind: .decimal)
                        Text(L10n.kWh)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                CardDivider()
                FocusableFieldRow("Provider", $nonFillFocus, equals: .provider,
                                  rowIdentifier: "editEntryProviderRow") {
                    TextField(charge.provider ?? L10n.localize("Provider"), text: $form.provider)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($nonFillFocus, equals: .provider)
                        .accessibilityIdentifier("editEntryProviderField")
                }
            }
            .formCard()
        case let service as ServiceRecord:
            VStack(spacing: 9) {
                FocusableFieldRow("Vendor", $nonFillFocus, equals: .vendor,
                                  rowIdentifier: "editEntryVendorRow") {
                    TextField(service.vendor ?? L10n.localize("Vendor"), text: $form.vendor)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($nonFillFocus, equals: .vendor)
                        .accessibilityIdentifier("editEntryVendorField")
                }
                .formCard()
                ForEach($form.items) { $item in
                    EditEntryServiceItemRow(item: $item)
                }
            }
        case let expense as Expense:
            VStack(spacing: 0) {
                FocusableFieldRow("Title", $nonFillFocus, equals: .title,
                                  rowIdentifier: "editEntryTitleRow") {
                    TextField(expense.title, text: $form.title)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($nonFillFocus, equals: .title)
                        .accessibilityIdentifier("editEntryTitleField")
                }
                CardDivider()
                categoryRow(current: expense.category)
            }
            .formCard()
        default:
            EmptyView()
        }
    }

    /// What KIND of expense this is - insurance, parking, a fine. It is what
    /// the Log row falls back to when the expense has no title, and for an
    /// imported row it is the importer's GUESS from the source file's kind
    /// column, so a screen that shows the title without it lets the user edit
    /// the name of a thing whose type they cannot see or correct (hard rule 13).
    ///
    /// `current` is offered alongside the standard cases so an expense already
    /// carrying a custom `.other("...")` keeps it in the list rather than being
    /// silently re-typed by opening the menu.
    private func categoryRow(current: ExpenseCategory) -> some View {
        HStack(spacing: 8) {
            Text("Category")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 8)
            Menu {
                ForEach(Self.categoryOptions(including: current), id: \.self) { category in
                    Button {
                        form.category = category
                    } label: {
                        Text(L10n.expenseCategoryLabel(category))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(L10n.expenseCategoryLabel(form.category))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .accessibilityIdentifier("editEntryCategoryMenu")
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
    }

    /// The offered categories: the entry flow's own list, plus the entry's
    /// stored category when that is a custom one the list does not carry.
    static func categoryOptions(including current: ExpenseCategory) -> [ExpenseCategory] {
        let standard = ExpenseCategory.entryCases
        guard !standard.contains(current) else { return standard }
        return [current] + standard
    }

    private var moneyCard: some View {
        VStack(spacing: 0) {
            FocusableFieldRow("Amount", $nonFillFocus, equals: .amount,
                              rowIdentifier: "editEntryAmountRow") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TextField("0.00", text: $form.amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.custom(AppFonts.dinAlternateBold, size: 24))
                        .foregroundStyle(Theme.Palette.ink)
                        .focused($nonFillFocus, equals: .amount)
                        .accessibilityIdentifier("editEntryAmountField")
                        .numericInput($form.amount, kind: .decimal)
                    Text(AddVehicleSupport.moneySymbol(for: form.currency))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            CardDivider()
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Currency")
                CurrencyChipRow(currency: $form.currency,
                                offer: offer,
                                lowConfidence: false)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 6)
        }
        .formCard()
    }

    private var odometerRow: some View {
        FocusableFieldRow("Odometer", $nonFillFocus, equals: .odometer,
                          rowIdentifier: "editEntryOdometerRow") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($nonFillFocus, equals: .odometer)
                    .accessibilityIdentifier("editEntryOdometerField")
                    .numericInput($form.odometer, kind: .integer)
                    .onChange(of: nonFillFocus) { oldValue, newValue in
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
        }
        .formCard()
    }
}

/// One stored service line item made editable: its title, its category and its
/// cost (docs/SCHEMA.md, ServiceItem). It reuses `ServiceEntryItemDraft` with the
/// create screen so the two paths cannot drift. `partNumber` and `lifetime` are
/// not shown here (PJ.22/PJ.26 own their editors) but ride through the draft
/// untouched - dropping either on save would be data loss.
///
/// Edit-only by design: this row edits the items the record already has and
/// never adds or deletes one. The row's acceptance is that promoting a category
/// loses nothing; add/delete would drag in the create screen's save gate and
/// empty-item rules, a larger surface than the row asks for.
struct EditEntryServiceItemRow: View {
    @Binding var item: ServiceEntryItemDraft

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                TextField("Item name", text: $item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("editEntryServiceItemTitle")
                TextField("", text: $item.cost)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 15))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: 96)
                    .accessibilityIdentifier("editEntryServiceItemCost")
                    .numericInput($item.cost, kind: .decimal)
            }
            HStack {
                categoryMenu
                Spacer(minLength: 8)
            }
            if item.category.otherText != nil {
                TextField("Category name", text: otherTextBinding)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("editEntryServiceItemOtherCategory")
            }
        }
        .padding(13)
        .formCard()
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
        .accessibilityIdentifier("editEntryServiceItemCategory")
    }

    /// The `.other` free text, read and written through the category. For an
    /// imported item this is the source file's kind text, so the user can see
    /// and correct what the importer guessed (hard rule 13).
    private var otherTextBinding: Binding<String> {
        Binding(
            get: { item.category.otherText ?? "" },
            set: { item.category = .other($0) }
        )
    }
}
