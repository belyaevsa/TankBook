import Foundation
import SwiftUI
import TankbookCore

// MARK: - P2.5 foreign-currency support for the Confirm sheet
//
// The rate store is a shared, thread-safe instance over the bundled seed pack
// (no network - a miss is never an error, F9). The foreign-currency decision
// and its money pair live in `RateStore.resolve` (core); this extension holds
// the three thin view-side conveniences so the sheet and the save path read one
// source of truth.

/// The app-wide rate store. Bundled seed pack now; the fetcher lands with sync.
enum AppRates {
    static let store = RateStore(seed: (try? RateSeedStore.bundledSeed()) ?? [])
}

extension ManualFillUpView {
    /// The single foreign-currency decision for the current form, shared by the
    /// conversion card and the save path. Detection comes from the extraction's
    /// currency when present and the user's chip choice otherwise - never the
    /// device locale alone.
    var conversionState: ForeignCurrencyState {
        guard let vehicle else { return .notForeign }
        let snapshot = AppRates.store.snapshot(original: form.currency,
                                               home: vehicle.homeCurrency,
                                               on: form.date)
        return ForeignCurrencyDetector.state(currency: form.currency,
                                             homeCurrency: vehicle.homeCurrency,
                                             lowConfidence: currencyLowConfidence,
                                             snapshot: snapshot)
    }

    /// The converted home amount for the card, for the total Save will write -
    /// the exact same snapshot, never a separately-rounded figure.
    var convertedAmount: Decimal? {
        guard case .converted(let snapshot) = conversionState,
              let vehicle, let total = form.effectiveTotal(volumeUnit: volumeUnit) else { return nil }
        let base = Money(amount: total, currency: form.currency,
                         homeCurrency: vehicle.homeCurrency)
        return base.converted(using: snapshot).homeAmount
    }

    /// Applies the current conversion to a money pair for saving. When the
    /// state is not `.converted` the pair saves rate-pending (F9).
    func convertForSave(_ money: Money) -> Money {
        guard case .converted(let snapshot) = conversionState else { return money }
        return money.converted(using: snapshot)
    }
}

extension ManualFillUpView {
    /// The "No car yet" hint card, shown when the sheet opens with no garage.
    var noVehicleCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "car")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No car yet – add one from Garage to start logging fill-ups.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .stroke(Theme.Palette.hairline, lineWidth: 1)
        )
        .accessibilityIdentifier("manualFillUpNoVehicleHint")
    }
}
