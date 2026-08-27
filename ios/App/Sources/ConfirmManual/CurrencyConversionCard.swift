import SwiftUI
import TankbookCore

// MARK: - P2.5 the conversion card (design/screens/ConfirmForeign.dc.html)

// The card that shows when a fill-up is in a foreign currency: the original
// amount's conversion into the vehicle's home currency, with the rate and its
// date. Three states:
//
//   - converted from the feed: "≈ 67.79 €" plus "4.2706 zł/€ · ECB, Aug 21" -
//     the rate was found (seed pack or cache) for the ENTRY's date. An
//     "Edit rate" affordance loads that rate into the manual field, so the
//     user can override the feed (hard rule 13, the artboard's "Edit rate").
//   - converted from a manual rate (F9): "≈ 67.79 €" plus "4.2706 zł/€ ·
//     Manual, Aug 21" - the user typed the rate (or it was set before and
//     loaded on Edit), the card stays editable in place ("and again
//     afterwards", hard rule 13).
//   - rate-pending (F9): "≈ –" plus "converts when online" - no rate for that
//     date; the entry saves rate-pending, the original amount is exact. The
//     pending card carries its missing next step (hard rule 7): a manual-rate
//     row is offered right there, an option that never gates Save.
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
    /// The user's typed manual rate (raw string, so a comma keypad keeps its
    /// own digits). Empty = none entered; a valid parse flips the state to
    /// `.converted(.manual)` and writes through `Money.applyingManualRate`.
    @Binding var manualRate: String
    /// Engaged once the manual-rate editor is opened, so the input row stays
    /// up even if the field is cleared mid-edit (hard rule 13: an edit the
    /// user is making is never taken away from under them).
    @Binding var isManualRateEditorOpen: Bool

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
            if showsManualRateRow {
                CardDivider()
                    .padding(.vertical, 8)
                manualRateRow
            }
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

    // MARK: Subtitle (rate + source + date, the pending hint, or Edit rate)

    @ViewBuilder
    private var subtitleText: some View {
        switch state {
        case .converted(let snapshot) where snapshot.source != .manual:
            // The feed's conversion, with the artboard's "Edit rate" next step
            // (hard rule 13: a derived value stays changeable). Loading the
            // feed's own rate into the field is the override - the card then
            // re-renders as Manual in place. The action sits on its OWN line,
            // never inside the rate line: Russian ("Изменить курс") is ~3x the
            // English and a truncated next step breaks hard rule 7.
            VStack(alignment: .trailing, spacing: 4) {
                Text(rateLine(snapshot))
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("manualFillUpRateLine")
                Button {
                    manualRate = ManualFillUpFormat.decimal(snapshot.rate, fractionDigits: 4)
                    isManualRateEditorOpen = true
                } label: {
                    Text("Edit rate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.taillight)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("manualFillUpEditRateButton")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .converted(let snapshot):
            // The user's own rate: the manual source is named, and the card
            // stays editable (the input row below).
            Text(rateLine(snapshot))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("manualFillUpRateLine")
        case .ratePending:
            Text(L10n.localize("converts when online"))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("manualFillUpPendingHint")
        case .notForeign, .lowConfidence:
            EmptyView()
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

    // MARK: Manual-rate row (the F9 next step, and the "again afterwards" edit)

    /// The input row shows on the pending card (its next step, hard rule 7),
    /// whenever a manual rate is in force (so it stays editable), and whenever
    /// the editor has been engaged - so clearing the field mid-edit never
    /// yanks the input away from under the user.
    private var showsManualRateRow: Bool {
        if isManualRateEditorOpen { return true }
        switch state {
        case .ratePending: return true
        case .converted(let snapshot): return snapshot.source == .manual
        case .notForeign, .lowConfidence: return false
        }
    }

    private var manualRateRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Rate")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.inkSoft)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            TextField("", text: $manualRate)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.custom(AppFonts.dinAlternateBold, size: 18))
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("manualFillUpManualRateField")
            Text(ratePair)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }

    /// "zł/€" - the pair names the direction (ORIGINAL per HOME), declension-
    /// free, so it composes without per-language word order.
    private var ratePair: String {
        "\(symbolOrCode(currency))/\(symbolOrCode(homeCurrency))"
    }

    private func symbolOrCode(_ code: CurrencyCode) -> String {
        let symbol = AddVehicleSupport.currencySymbol(for: code)
        return symbol.isEmpty ? code.rawValue : symbol
    }
}
