import SwiftUI
import TankbookCore

// MARK: - The divider's glance lines (RV.119, docs/JOURNEYS.md J8)

/// Under the month divider: what the month's rows add up to beyond the spend
/// - "1 000 km · 8.5 L/100km · 0.27 €/km" - and, when the month can honestly
/// be compared, "42% lower than December". Every figure is the section's own
/// `MonthGlance` (derived in core, hard rule 2); a figure the month cannot
/// yield is simply not printed - never a dash or a zero.
struct HomeMonthGlanceLines: View {
    let glance: MonthGlance
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let facts = HomeMonthGlanceFormat.facts(glance, vehicle: vehicle) {
                Text(facts)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .accessibilityIdentifier("logMonthGlance")
            }
            if let delta = glance.spendDelta {
                Text(HomeMonthGlanceFormat.delta(delta))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(delta.percent > 0 ? Theme.Palette.warn : Theme.Palette.inkSoft)
                    .accessibilityIdentifier("logMonthDelta")
            }
        }
        .padding(.horizontal, 2)
    }
}

enum HomeMonthGlanceFormat {
    /// The fact line: the parts the month has, joined by the middle dot the
    /// rows already use between independent facts. Nil when it has none.
    static func facts(_ glance: MonthGlance, vehicle: Vehicle) -> String? {
        var parts: [String] = []
        if let distance = glance.distanceKm {
            parts.append("\(OdometerFormat.grouped(distance)) \(L10n.distanceUnit(vehicle.units.distance))")
        }
        if let per100 = glance.per100 {
            let figure = ConsumptionDisplay.value(per100: per100, unit: vehicle.headlineUnit)
            parts.append("\(ManualFillUpFormat.decimal(figure, fractionDigits: 1)) "
                         + L10n.consumptionUnit(vehicle.units.consumption))
        }
        if let cost = glance.costPerKm {
            let value = HomeFormat.costPerDistanceValue(cost.perKm, distanceUnit: vehicle.units.distance)
            let symbol = AddVehicleSupport.moneySymbol(for: cost.currency)
            let unit = "\(symbol)/\(L10n.distanceUnit(vehicle.units.distance))"
            parts.append("\(value) \(unit)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "42% lower than December" - one whole localised phrase per direction,
    /// the month in the case the sentence needs (RU's genitive comes from the
    /// format-context month name).
    static func delta(_ delta: MonthGlance.SpendDelta) -> String {
        let month = Self.monthInSentence(delta.previousMonthStart)
        let percent = "\(abs(delta.percent))%"
        if delta.percent < 0 { return String(format: L10n.localize("%1$@ lower than %2$@"), percent, month) }
        if delta.percent > 0 { return String(format: L10n.localize("%1$@ higher than %2$@"), percent, month) }
        return String(format: L10n.localize("same as %@"), month)
    }

    private static func monthInSentence(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }
}
