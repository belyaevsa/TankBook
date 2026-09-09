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
}
