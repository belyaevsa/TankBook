import SwiftUI
import TankbookCore

// MARK: - Amount + currency card (RV.279)

// Split out of `ExpenseEntryView.swift` (which sits near the linter's
// file-length ceiling), the same split `ExpenseEntrySave.swift` made. These are
// the components Edit entry renders - the amount states its own currency's
// symbol and the chips pick what the amount is in - so the two doors to one
// entry are the same screen.
extension ExpenseEntryView {
    /// The distance unit the odometer card reads, defaulting to km until the car
    /// loads (the same default the rest of the app uses).
    var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    /// The car's complete, ordered currency offer (docs/SCHEMA.md -> Currency
    /// offer): home first, then the currencies this car's entries have used,
    /// then the device region's. Pure local derivation - no network (hard
    /// rule 1).
    var currencyOffer: [CurrencyCode] {
        guard let vehicle else { return [.eur] }
        return CurrencyOfferBuilder.offer(
            homeCurrency: vehicle.homeCurrency,
            history: CurrencyHistory.recentCurrencies(in: existingEntries),
            region: Locale.current.region?.identifier)
    }

    /// The odometer card, the SAME component Edit entry renders, in the same
    /// position (after the date). Typed or blank - a blank stays nil, never the
    /// "last known" as a fact (hard rule 13).
    var odometerCard: some View {
        EntryOdometerCard(
            odometer: $form.odometer,
            focus: $focus,
            target: EditEntryNonFillFocus.odometer,
            distanceUnit: distanceUnit,
            rowIdentifier: "editEntryOdometerRow",
            fieldIdentifier: "editEntryOdometerField")
    }

    /// The Amount row and the currency chip row, mirroring Edit entry's money
    /// card: the amount states its own currency's symbol, and the chips let the
    /// user pick what the amount is in. A foreign pick saves the pair with the
    /// shared conversion - never silently as home money (hard rule 3).
    var amountCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Amount")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TextField("0.00", text: $form.amount)
                        .keyboardType(.decimalPad)
                        .font(.custom(AppFonts.dinAlternateBold, size: 24))
                        .foregroundStyle(Theme.Palette.ink)
                        .accessibilityIdentifier("expenseEntryAmountField")
                        .numericInput($form.amount, kind: .decimal)
                    Text(AddVehicleSupport.moneySymbol(for: form.currency))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 12)
            CardDivider()
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow("Currency")
                CurrencyChipRow(currency: $form.currency, offer: currencyOffer,
                                lowConfidence: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.cardPadding)
            .padding(.vertical, 6)
        }
        .formCard()
    }
}
