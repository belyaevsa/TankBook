import SwiftUI
import TankbookCore

extension ManualFillUpView {
    /// The complete, ordered currency offer for this car (docs/SCHEMA.md ->
    /// Currency offer): home currency first, then the currencies this car's own
    /// entries were paid in (most recent first), then the device region's
    /// neighbours. Pure local derivation - no network (hard rule 1).
    func currencyOffer(vehicle: Vehicle) -> [CurrencyCode] {
        CurrencyOfferBuilder.offer(
            homeCurrency: vehicle.homeCurrency,
            history: CurrencyHistory.recentCurrencies(in: existingEntries),
            region: Locale.current.region?.identifier)
    }

    /// A currency needing attention renders ABOVE the numbers card; the folded
    /// home-currency case sits below it. Opening itself below the fold would not
    /// be opening at all.
    var currencyNeedsAttention: Bool {
        guard let vehicle else { return false }
        return ManualFillUpCurrencySection.needsAttention(
            currency: form.currency, homeCurrency: vehicle.homeCurrency,
            lowConfidence: currencyLowConfidence, state: conversionState)
    }

    @ViewBuilder
    var currencySection: some View {
        if let vehicle {
            ManualFillUpCurrencySection(
                form: $form,
                homeCurrency: vehicle.homeCurrency,
                lowConfidence: currencyLowConfidence,
                state: conversionState, offer: currencyOffer(vehicle: vehicle))
        }
    }
}
