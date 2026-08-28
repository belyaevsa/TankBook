import SwiftUI
import TankbookCore
import UIKit

// MARK: - Guest layout

/// The no-account Home (design/screens/GuestHome.dc.html): garage card, the
/// capture CTA, the import card and the privacy line. Fully usable offline -
/// sync is not required for anything (hard rule 1). The card's action is the
/// "Type it" peer door (hard rule 15); the tab bar's centre capture button is
/// the other, always one thumb-tap away.
struct HomeGuestLayout: View {
    let vehicle: Vehicle?
    let stats: HomeStats?
    let photoData: Data?
    let onTypeIt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let vehicle, let stats {
                guestGarageCard(vehicle: vehicle, stats: stats)
            } else {
                noCarCard
            }
            captureCard
            importCard
            privacyLine
        }
    }

    private func guestGarageCard(vehicle: Vehicle, stats: HomeStats) -> some View {
        VStack(spacing: 0) {
            garageHeader(vehicle: vehicle, stats: stats)
                .padding(16)

            CardDivider()

            // The three-vitals strip (GuestHome artboard). Tiles with nothing
            // honest to show are omitted - never a dash placeholder or "0.0".
            vitalsStrip(stats)
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
        }
        .formCard()
    }

    private func garageHeader(vehicle: Vehicle, stats: HomeStats) -> some View {
        HStack(spacing: 12) {
            Group {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
            }
            .frame(width: 60, height: 60)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.midnight))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name)
                    .font(.custom(AppFonts.dinAlternateBold, size: 22))
                    .foregroundStyle(Theme.Palette.ink)
                if let odometer = stats.odometer {
                    let grouped = OdometerFormat.grouped(odometer)
                    let unit = L10n.distanceUnit(vehicle.units.distance)
                    Text("\(grouped) \(unit) · \(updatedOrAdded(stats))")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("homeOdometer")
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func vitalsStrip(_ stats: HomeStats) -> some View {
        HStack(spacing: 0) {
            if stats.headline != nil {
                vitalColumn(label: L10n.localize("L/100km"),
                            value: headlineValue(stats), identifier: "homeHeadlineValue")
            } else {
                if stats.needsAnotherFullTank {
                    Text("One more full tank and your consumption appears")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .accessibilityIdentifier("homeD4Hint")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let cost = stats.costPerKm {
                Divider().overlay(Theme.Palette.hairline).frame(height: 40)
                vitalColumn(label: L10n.localize("per km"),
                            value: HomeFormat.costPerKm(cost, symbol: symbol(stats)),
                            identifier: "homeCostPerKmTile")
            }
            if let monthSpend = stats.monthSpend {
                Divider().overlay(Theme.Palette.hairline).frame(height: 40)
                vitalColumn(label: HomeFormat.currentMonth(),
                            value: HomeFormat.spend(monthSpend, symbol: symbol(stats)),
                            identifier: "homeMonthSpendTile")
            }
        }
    }

    private func vitalColumn(label: String, value: String, identifier: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom(AppFonts.dinAlternateBold, size: 20))
                .foregroundStyle(Theme.Palette.ink)
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private func headlineValue(_ stats: HomeStats) -> String {
        guard let headline = stats.headline else { return "" }
        return ManualFillUpFormat.decimal(headline.value, fractionDigits: 1)
    }

    private func updatedOrAdded(_ stats: HomeStats) -> String {
        if let updatedAt = stats.updatedAt {
            return String(format: L10n.localize("updated %@"), HomeFormat.day(updatedAt))
        }
        return String(format: L10n.localize("added %@"), HomeFormat.day(stats.vehicle.createdAt))
    }

    private func symbol(_ stats: HomeStats) -> String {
        AddVehicleSupport.currencySymbol(for: stats.vehicle.homeCurrency)
    }

    private var captureCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.Palette.taillight.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "camera")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Palette.taillight)
            }
            Text("Scan your first fill-up")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Point the camera at a receipt – even an old one from the glovebox. Your consumption appears after the second full tank.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            Button("Type it", action: onTypeIt)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 11)
                .background(Theme.Palette.taillight)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("homeGuestCaptureButton")
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.Palette.dash)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Theme.Palette.hairline, lineWidth: 1.5)
        )
    }

    private var importCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Coming from Fuelio, Drivvo or My Fuel Manager? Bring your history along.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            NavigationLink(value: Route.importWizard) {
                Text("Import")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.action)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeGuestImportButton")
        }
        .padding(14)
        .formCard()
    }

    private var privacyLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("Everything stays on this phone. Sign in later only if you want a second device.")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var noCarCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No car yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Add your first car to start logging fill-ups.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
    }
}
