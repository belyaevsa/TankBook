import SwiftUI
import TankbookCore

// MARK: - P2.5 the conversion card (design/screens/ConfirmForeign.dc.html)

// The card that shows when a fill-up is in a foreign currency: the original
// amount's conversion into the vehicle's home currency, with the rate and its
// date. Two states:
//
//   - converted: "≈ 67.79 €" plus "4.2706 zł/€ · ECB, Aug 21" - the rate was
//     found (seed pack or cache) for the ENTRY's date.
//   - rate-pending (F9): "≈ –" plus "converts when online" - no rate for that
//     date; the entry saves rate-pending, the original amount is exact.
//
// It NEVER appears on low confidence: an uncertain currency shows the amber
// "Which currency is this?" prompt instead, because a wrong currency silently
// converted is a number the user cannot spot later (docs/ERRORS.md -> Confirm).
struct ForeignCurrencyCard: View {
    let currency: CurrencyCode
    let homeCurrency: CurrencyCode
    let state: ForeignCurrencyState
    /// The converted home amount for the current total, nil while none is typed
    /// or the state is not `.converted`.
    let convertedAmount: Decimal?

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.headlight)
                    Text(labelText)
                        .font(.caption)
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 8)
                valueText
            }
            subtitleText
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .formCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manualFillUpConversionCard")
    }

    // MARK: Label

    /// "In EUR" - the reporting currency. The code is declension-free, so the
    /// same composed phrase reads correctly in RU ("В EUR"), unlike a currency
    /// NAME ("złoty" -> "в злотых" would need prepositional case per language).
    private var labelText: String {
        String(format: L10n.localize("In %@"), homeCurrency.rawValue)
    }

    // MARK: Value (DIN, tabular digits)

    @ViewBuilder
    private var valueText: some View {
        if case .converted = state, let convertedAmount {
            Text(convertedValueText(convertedAmount))
                .font(.custom(AppFonts.dinAlternateBold, size: 22))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("manualFillUpConvertedValue")
        } else {
            // "≈ –" is a typographic placeholder, not copy: no localisation.
            Text(pendingGlyph)
                .font(.custom(AppFonts.dinAlternateBold, size: 22))
                .foregroundStyle(Theme.Palette.inkSoft)
                .accessibilityIdentifier("manualFillUpPendingValue")
        }
    }

    private let pendingGlyph = "≈ –"

    private func convertedValueText(_ amount: Decimal) -> String {
        "≈ \(ManualFillUpFormat.decimal(amount, fractionDigits: 2)) \(symbolOrCode(homeCurrency))"
    }

    // MARK: Subtitle (rate + source + date, or the pending hint)

    @ViewBuilder
    private var subtitleText: some View {
        if case .converted(let snapshot) = state {
            Text(rateLine(snapshot))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("manualFillUpRateLine")
        } else {
            Text(L10n.localize("converts when online"))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("manualFillUpPendingHint")
        }
    }

    /// "4.2706 zł/€ · ECB, Aug 21". The rate is ORIGINAL per HOME (the symbol
    /// pair reads the direction), the source is a proper noun/acronym, and the
    /// date is a fully-localised DateFormatter output - so nothing here needs
    /// word-order composition across languages.
    private func rateLine(_ snapshot: RateSnapshot) -> String {
        let rate = ManualFillUpFormat.decimal(snapshot.rate, fractionDigits: 4)
        let pair = "\(symbolOrCode(currency))/\(symbolOrCode(homeCurrency))"
        let source = sourceLabel(snapshot.source)
        let date = snapshot.rateDate.formatted(.dateTime.month(.abbreviated).day())
        return "\(rate) \(pair) · \(source), \(date)"
    }

    private func sourceLabel(_ source: RateSource) -> String {
        switch source {
        case .ecb: return "ECB"
        case .cis: return "CIS"
        case .manual: return L10n.localize("Manual")
        }
    }

    private func symbolOrCode(_ code: CurrencyCode) -> String {
        let symbol = AddVehicleSupport.currencySymbol(for: code)
        return symbol.isEmpty ? code.rawValue : symbol
    }
}
