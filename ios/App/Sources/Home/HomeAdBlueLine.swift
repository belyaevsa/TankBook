import SwiftUI
import TankbookCore

// MARK: - The AdBlue line

/// The figures an AdBlue line shows, in the car's own units: the last top-up's
/// volume and day, and the rate per 1000 of the car's distance unit. The
/// odometer is stored in the car's distance unit, so `AdBlueStats`' rate is
/// already per 1000 of it; only the volume converts.
enum AdBlueFormat {
    static func volume(_ litres: Double, vehicle: Vehicle) -> String {
        ManualFillUpFormat.decimal(ManualFillUpMath.displayVolume(from: litres, unit: vehicle.units.volume),
                                   fractionDigits: 2)
    }

    /// nil when the rate is unavailable - the caller shows a dash, never an estimate.
    static func rate(_ stats: AdBlueStats, vehicle: Vehicle) -> String? {
        stats.litresPer1000.map {
            ManualFillUpFormat.decimal(ManualFillUpMath.displayVolume(from: $0, unit: vehicle.units.volume),
                                       fractionDigits: 1)
        }
    }

    /// "L/1000 km" - one catalogue phrase per language with both units as data.
    static func rateUnit(vehicle: Vehicle) -> String {
        String(format: L10n.localize("%1$@/1000 %2$@"),
               L10n.volumeUnit(vehicle.units.volume), L10n.distanceUnit(vehicle.units.distance))
    }
}

/// One quiet line on the car's Home card for a car that takes AdBlue: the
/// last top-up and the rate. It is never a second headline - the fuel figures
/// above stay fuel-only (docs/DESIGN.md -> AdBlue rows). Absent for a car with
/// no top-up.
struct HomeAdBlueLine: View {
    let stats: AdBlueStats
    let vehicle: Vehicle

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: LogStream.Kind.adBlue.glyph)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(LogStream.Kind.adBlue.color)
                .accessibilityHidden(true)
            Text("AdBlue")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.inkSoft)
            figure(AdBlueFormat.volume(stats.lastFill.volumeL, vehicle: vehicle),
                   unit: L10n.volumeUnit(vehicle.units.volume))
            separator
            Text(HomeFormat.day(stats.lastFill.date))
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            separator
            figure(AdBlueFormat.rate(stats, vehicle: vehicle) ?? "–", unit: AdBlueFormat.rateUnit(vehicle: vehicle))
                .accessibilityIdentifier("homeAdBlueRate")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homeAdBlueLine")
    }

    private var separator: some View {
        Text("·").font(.caption).foregroundStyle(Theme.Palette.inkSoft)
    }

    private func figure(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.custom(AppFonts.dinAlternateBold, size: 14))
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
    }
}
