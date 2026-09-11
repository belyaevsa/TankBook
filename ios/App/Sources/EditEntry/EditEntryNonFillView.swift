import SwiftUI
import UIKit
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
    /// RV.202: the receipt a non-fill entry is being given. `attachImage` drives
    /// the pending card; `showAttachSource` is the camera/Photos chooser's
    /// binding; `onAddReceipt` opens it and `onAttachImage` runs the shared
    /// `attachReceipt` path. The chooser hangs off the card, never the screen
    /// (RV.11).
    let attachImage: UIImage?
    let attachProcessing: Bool
    @Binding var showAttachSource: Bool
    let onAddReceipt: () -> Void
    let onAttachImage: (UIImage) -> Void
    /// The tire set this `.parts` expense bought, when the link exists. Nil for
    /// every other entry kind and for an unlinked parts purchase.
    let linkedTireSet: TireSet?
    /// Creates (or opens) the set this `.parts` expense becomes.
    let onMakeTireSet: () -> Void

    @FocusState private var nonFillFocus: EditEntryNonFillFocus?

    private var distanceUnit: DistanceUnit { vehicle.units.distance }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                receiptCard
                typeCard
                if let expense = entry as? Expense, expense.category == .parts {
                    TireSetPurchaseCard(linkedSet: linkedTireSet, onMake: onMakeTireSet)
                }
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

    /// RV.202: the same three-way receipt branch the fill-up form uses. An
    /// entry that already carries a receipt shows it (view/replace/delete live
    /// in the shared card); a photo just picked but not yet saved shows the
    /// pending card; an entry with neither shows the card WITH the "Add
    /// receipt" affordance and the camera/Photos chooser. The chooser is
    /// attached to the CARD, not the screen - iOS 26 anchors a
    /// `confirmationDialog` popover to the view it is attached to (RV.11).
    @ViewBuilder
    private var receiptCard: some View {
        if !attachments.isEmpty {
            EditEntryRows.receiptCard(attachments: attachments, entry: entry,
                                      pendingBlobIDs: pendingBlobIDs,
                                      onAttachmentChanged: onAttachmentChanged)
        } else if attachImage != nil {
            EditEntryRows.pendingReceiptCard(processing: attachProcessing)
        } else {
            EditEntryRows.receiptCard(attachments: attachments, entry: entry,
                                      pendingBlobIDs: pendingBlobIDs,
                                      onAddReceipt: onAddReceipt)
                .receiptAttachSource(isPresented: $showAttachSource,
                                     title: "Add receipt") { image in
                    onAttachImage(image)
                }
        }
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
                    EditEntryServiceItemRow(item: $item) {
                        // Deleting the LAST item is legal. A workshop invoice can
                        // be vendor + a lump-sum Amount with no itemised lines,
                        // and the record already round-trips an empty item list
                        // (PJ.23's own L1 saves one unchanged). Forbidding the
                        // last delete would strand that shape behind a row the
                        // user cannot remove - the mirror of a blank row they
                        // cannot remove. [RV.187]'s bare "Service" title is the
                        // same last resort an empty record already reaches, not
                        // a new state.
                        form.removeServiceItem(id: item.id)
                    }
                }
                ServiceEntryAddItemButton(identifier: "editEntryAddServiceItemButton") {
                    form.addServiceItem()
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
            lineSumBlock
        }
        .formCard()
    }

    /// RV.199: the service's line sum beside the independently-editable Amount,
    /// with a stated mismatch when the two disagree. ATTENTION, not an error:
    /// the sum is amber and the entry always saves (hard rule 5 - amber is
    /// attention, never a gate; hard rule 13 - the Amount is the user's own).
    /// The sum comes from the SAME function the create screen's header uses
    /// (`form.lineSum(homeCurrency:)`), so the two doors cannot drift. The row
    /// renders only when an item carries a cost - with none, there is nothing
    /// to state beside the Amount.
    @ViewBuilder
    private var lineSumBlock: some View {
        if entry is ServiceRecord, let presentation = lineSumPresentation {
            CardDivider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Line items")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.inkSoft)
                    Spacer(minLength: 8)
                    Text(presentation.value)
                        .font(.custom(AppFonts.dinAlternateBold, size: 17))
                        .foregroundStyle(presentation.differs ? Theme.Palette.warn
                                                               : Theme.Palette.ink)
                        .accessibilityIdentifier("editEntryLineSumValue")
                }
                if let note = presentation.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.warn)
                        .accessibilityIdentifier("editEntryLineSumMismatch")
                }
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 8)
        }
    }

    /// The line sum as the money card states it: the exact figure under its own
    /// currency's marker, the mismatch sentence when it disagrees with the
    /// Amount, and whether it is styled as attention. `.none` (no costed item)
    /// yields nil so no empty row renders; `.mixed` states the per-currency
    /// breakdown and never a summed cross-currency total (hard rule 3).
    private struct LineSumPresentation {
        let value: String
        let note: String?
        let differs: Bool
    }

    private var lineSumPresentation: LineSumPresentation? {
        let home = vehicle.homeCurrency
        switch form.lineSum(homeCurrency: home) {
        case .none:
            return nil
        case .summed(let amount, let currency):
            let differs = form.lineSumDiffersFromAmount(homeCurrency: home)
            return LineSumPresentation(
                value: HomeFormat.entryAmount(amount,
                                              symbol: AddVehicleSupport.moneySymbol(for: currency)),
                note: differs ? L10n.localize("Differs from the amount above") : nil,
                differs: differs)
        case .mixed(let subtotals):
            return LineSumPresentation(
                value: subtotals.map {
                    HomeFormat.entryAmount($0.amount,
                                           symbol: AddVehicleSupport.moneySymbol(for: $0.currency))
                }.joined(separator: " · "),
                note: L10n.localize("Different currencies – no single total"),
                differs: true)
        }
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

/// One stored service line item made editable: its title, its category, its
/// cost and its **lifetime** (docs/SCHEMA.md, ServiceItem), plus the trash
/// affordance that removes it. It reuses `ServiceEntryItemDraft` with the create
/// screen so the two paths cannot drift. `partNumber` is still not shown here
/// (PJ.61 owns its editor) but rides through the draft untouched - dropping it
/// on save would be data loss, and a delete must not shift it onto a neighbour.
///
/// The lifetime is the one field that drives the post-save reminder offer: an
/// item that states "15 000 km / 12 months" is what lets the record propose the
/// next service itself (J7). It is a suggestion the user edits here and again
/// afterwards (hard rule 13) - once set it is theirs.
struct EditEntryServiceItemRow: View {
    @Binding var item: ServiceEntryItemDraft
    let onDelete: () -> Void

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
                deleteButton
            }
            if item.category.otherText != nil {
                TextField("Category name", text: otherTextBinding)
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("editEntryServiceItemOtherCategory")
            }
            ServiceItemLifetimeFields(lifetime: $item.lifetime)
        }
        .padding(13)
        .formCard()
    }

    /// Delete is an explicit affordance, never hidden behind a swipe - the same
    /// treatment the create screen's row uses.
    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete line item")
        .accessibilityIdentifier("editEntryServiceItemDelete")
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
