import SwiftUI
import TankbookCore

/// The edit form for the three non-FillUp entry types (docs/SCHEMA.md, Entry):
/// a charge, a service record or an expense. Compact editable rows - amount +
/// currency chips (the lifted `CurrencyChipRow`), the type's own headline field,
/// date, odometer and note. Every value is a default input, never a fact
/// (hard rule 13).
struct EditEntryNonFillView: View {
    @Binding var form: EditEntryNonFillForm
    let entry: any Entry
    let vehicle: Vehicle
    let attachments: [Attachment]
    @Binding var showDatePicker: Bool
    let showChangedBySync: Bool
    let pendingBlobIDs: Set<UUID>

    @FocusState private var odometerFocused: Bool

    private var distanceUnit: DistanceUnit { vehicle.units.distance }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if !attachments.isEmpty {
                    EditEntryRows.receiptCard(attachments: attachments, entry: entry,
                                              pendingBlobIDs: pendingBlobIDs)
                }
                typeCard
                moneyCard
                ManualFillUpDateRow(date: $form.date, showDatePicker: $showDatePicker)
                odometerRow
                EditEntryRows.noteRow(text: $form.note, identifier: "editEntryNonFillNoteField")
                if showChangedBySync {
                    EditEntryRows.changedBySyncRow
                }
                EditEntryRows.footer
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
                FieldRow("Energy") {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        TextField("0", text: $form.energyKWh)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.custom(AppFonts.dinAlternateBold, size: 24))
                            .foregroundStyle(Theme.Palette.ink)
                            .accessibilityIdentifier("editEntryEnergyField")
                        Text(L10n.kWh)
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.inkSoft)
                    }
                }
                CardDivider()
                FieldRow("Provider") {
                    TextField(charge.provider ?? "Provider", text: $form.provider)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("editEntryProviderField")
                }
            }
            .formCard()
        case let service as ServiceRecord:
            FieldRow("Vendor") {
                TextField(service.vendor ?? "Vendor", text: $form.vendor)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("editEntryVendorField")
            }
            .formCard()
        case let expense as Expense:
            FieldRow("Title") {
                TextField(expense.title, text: $form.title)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("editEntryTitleField")
            }
            .formCard()
        default:
            EmptyView()
        }
    }

    private var moneyCard: some View {
        VStack(spacing: 0) {
            FieldRow("Amount") {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TextField("0.00", text: $form.amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.custom(AppFonts.dinAlternateBold, size: 24))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("editEntryAmountField")
                    Text(AddVehicleSupport.currencySymbol(for: form.currency))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            CardDivider()
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Currency")
                CurrencyChipRow(currency: $form.currency,
                                homeCurrency: vehicle.homeCurrency,
                                lowConfidence: false)
            }
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 6)
        }
        .formCard()
    }

    private var odometerRow: some View {
        FieldRow("Odometer") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("", text: $form.odometer)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.custom(AppFonts.dinAlternateBold, size: 24))
                    .foregroundStyle(Theme.Palette.ink)
                    .focused($odometerFocused)
                    .accessibilityIdentifier("editEntryOdometerField")
                    .onChange(of: odometerFocused) { oldValue, newValue in
                        if newValue {
                            form.odometer = OdometerFormat.ungrouped(form.odometer)
                        } else if oldValue, let value = form.odometerValue {
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
