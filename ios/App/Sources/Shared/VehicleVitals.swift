import Foundation
import TankbookCore

/// The one-line vitals string for a garage car ("119 486 km · 6.8 L/100 ·
/// €212 this month") - the Car switcher rows and the Garage tab grid render the
/// same line from this one place so they can never disagree. Each segment is its
/// own unit, joined by the artboard's separator; a segment with nothing honest
/// to show is omitted, never "N/A".
enum VehicleVitals {
    static func line(_ stats: HomeStats) -> String {
        var parts: [String] = []
        if let odometer = stats.odometer {
            parts.append("\(OdometerFormat.grouped(odometer)) \(L10n.distanceUnit(stats.vehicle.units.distance))")
        }
        if let headline = stats.headline {
            let value = ManualFillUpFormat.decimal(headline.value, fractionDigits: 1)
            let unit = L10n.consumptionUnitShort(stats.vehicle.headlineUnit)
            parts.append("\(value) \(unit)")
        }
        // The month-spend segment states exactly what the data supports
        // (RV.112): a complete month is the bare figure, a partial one carries
        // the pending phrase so the known sum is never read as the whole month,
        // and a pending month prints NO number - only the phrase that says why.
        if let monthSpend = stats.monthSpend {
            let symbol = AddVehicleSupport.currencySymbol(for: stats.vehicle.homeCurrency)
            switch monthSpend {
            case .complete(let amount):
                parts.append(String(format: L10n.localize("%@ this month"),
                                    HomeFormat.spend(amount, symbol: symbol)))
            case .partial(let amount, let pendingCount):
                parts.append(String(format: L10n.localize("%@ this month"),
                                    HomeFormat.spend(amount, symbol: symbol)))
                parts.append(L10n.pendingRates(pendingCount))
            case .pending(let pendingCount):
                parts.append(L10n.pendingRates(pendingCount))
            }
        }
        return parts.joined(separator: " · ")
    }
}
