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
        if let monthSpend = stats.monthSpend {
            let symbol = AddVehicleSupport.currencySymbol(for: stats.vehicle.homeCurrency)
            parts.append(String(format: L10n.localize("%@ this month"),
                                HomeFormat.spend(monthSpend, symbol: symbol)))
        }
        return parts.joined(separator: " · ")
    }
}
