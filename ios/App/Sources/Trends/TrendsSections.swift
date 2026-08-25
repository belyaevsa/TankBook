import SwiftUI
import TankbookCore

// MARK: - Trends display formatting

/// Plain display helpers for the Trends tiles. Numbers in DIN, units
/// subordinate (hard rule 6); decimal separators pinned to the input's raw dot
/// via `ManualFillUpFormat` exactly as Home does, so the two screens render
/// figures identically.
enum TrendsFormat {
    /// "Aug" - the current month's abbreviated name for the Spend tile eyebrow.
    static func month(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.month(.abbreviated))
    }

    /// The tile's consumption unit, shortened to fit the grid ("L/100"). The
    /// per-vehicle choice (kWh/100 for an EV) comes from `Vehicle.headlineUnit`
    /// - the same code path Home and the Car switcher use (P1.11).
    static func consumptionUnit(_ unit: HeadlineUnit) -> String {
        switch unit {
        case .energyPer100: L10n.localize("kWh/100")
        case .consumption(.lPer100): L10n.localize("L/100")
        case .consumption(.mpgUS), .consumption(.mpgUK): L10n.localize("MPG")
        case .consumption(.kmPerL): L10n.localize("km/L")
        }
    }

    /// The price tile's caption: the % change from the previous logged price
    /// when a second price exists, else the last fill's date - a caption, never
    /// a fabricated trend.
    static func priceCaption(series: [TrendPoint]) -> String? {
        guard let last = series.last else { return nil }
        guard let previous = series.dropLast().last, previous.value > 0 else {
            return HomeFormat.day(last.date)
        }
        let change = (last.value - previous.value) / previous.value * 100
        let arrow = change >= 0 ? "▲" : "▼"
        return String(format: "%@%.1f%%", arrow, abs(change))
    }
}

// MARK: - Empty states

/// The "no car yet" Trends (design: the same truth as Home - logging needs a
/// car, so this is the Add-car path, not an empty dashboard). The Add car route
/// is a pushed link, the Type-it escape a sheet, so navigation never dead-ends.
struct TrendsNoCarLayout: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a car and your consumption, spend and price history appear here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .padding(.top, 8)

            NavigationLink(value: Route.addVehicle) {
                Text("Add your first car")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.Palette.taillight)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("trendsAddFirstCarButton")
        }
    }
}

/// The zero-entries state under a car: no fabricated numbers anywhere, just the
/// next step - the capture path (docs/ERRORS.md -> Home, "Car, zero entries").
struct TrendsEmptyEntriesCard: View {
    let onTypeIt: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fuelpump")
                .font(.system(size: 22))
                .foregroundStyle(Theme.Palette.taillight)
            Text("No entries yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Scan or type your first fill-up – consumption appears after two full tanks.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Button("Type it", action: onTypeIt)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.headlight)
                .accessibilityIdentifier("trendsEmptyEntriesButton")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .formCard()
    }
}
