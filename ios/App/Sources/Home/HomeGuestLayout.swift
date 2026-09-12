import SwiftUI
import TankbookCore
import UIKit

// MARK: - Guest layout

/// The no-account Home (design/screens/GuestHome.dc.html): garage card, the
/// capture CTA, the import card and the privacy line. Fully usable offline -
/// sync is not required for anything (hard rule 1). The card's action is the
/// "Type it" peer door (hard rule 15); the tab bar's centre capture button is
/// the other, always one thumb-tap away.
///
/// RV.197: once the user has an entry, the guest Home also renders the SAME log
/// stream the signed-in Home shows (`HomeView.logStream`), passed in as
/// `logStream`. The decision is `HomeLayout.logArea(for:)` in core, so it is a
/// function of the entry count and never of the session. The stream is the
/// shared `HomeRecentEntries`; the guest gets no second list.
///
/// RV.251/PJ.100/PJ.101/PJ.200: the controls the two Home layouts share are
/// single views rendered by both, never copies - `HomeCarSwitcherButton` when
/// `HomeLayout.showsCarSwitcher` says so, `HomeTypeItControl` in the capture
/// card, `HomeRemindersEntryRow` above the stream, and `HomeAddFirstCarButton`
/// on the no-car card. Nothing about any of them is account-gated.
struct HomeGuestLayout<LogContent: View>: View {
    let vehicle: Vehicle?
    let stats: HomeStats?
    let photoData: Data?
    /// How many live cars exist. `HomeLayout.showsCarSwitcher` turns this into
    /// the switcher's presence - the count alone, never the session (RV.251).
    let liveCarCount: Int
    /// The cross-car attention count for the reminders door (PJ.200), derived at
    /// read time by Home from the same live rows the merged list groups.
    let attentionCount: Int
    let presentSheet: (SheetRoute) -> Void
    let logStream: LogContent

    init(vehicle: Vehicle?, stats: HomeStats?, photoData: Data?,
         liveCarCount: Int, attentionCount: Int,
         presentSheet: @escaping (SheetRoute) -> Void,
         @ViewBuilder logStream: () -> LogContent) {
        self.vehicle = vehicle
        self.stats = stats
        self.photoData = photoData
        self.liveCarCount = liveCarCount
        self.attentionCount = attentionCount
        self.presentSheet = presentSheet
        self.logStream = logStream()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // RV.251: the SAME switcher the signed-in header renders, shown on
            // the count alone. Zero or one car keeps today's guest layout.
            if HomeLayout.showsCarSwitcher(liveCarCount: liveCarCount), let vehicle {
                HomeCarSwitcherButton(vehicleName: vehicle.name,
                                      onTap: { presentSheet(.carSwitcher) })
            }
            if let vehicle, let stats {
                guestGarageCard(vehicle: vehicle, stats: stats)
            } else {
                noCarCard
            }
            // PJ.200: the calm reminders door, the same row the signed-in
            // layout renders, so J7d's discovery surface is not account-gated.
            if vehicle != nil {
                HomeRemindersEntryRow(attentionCount: attentionCount)
            }
            logStream
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
            // The per-km column states the figure only when it is EXACT
            // (RV.147): a window holding a rate-pending row - or known figures
            // homed in more than one currency - has no cost-per-km, so the
            // column is omitted and the F9 footnote below says why (a partial
            // numerator over a complete km span would be low by an unknown
            // amount while looking plausible). The symbol is the figure's OWN
            // currency, never the car's by default.
            if let cost = stats.costPerKm {
                Divider().overlay(Theme.Palette.hairline).frame(height: 40)
                vitalColumn(label: L10n.localize("per km"),
                            value: HomeFormat.costPerKm(cost.perKm,
                                                        symbol: AddVehicleSupport.moneySymbol(for: cost.currency)),
                            identifier: "homeCostPerKmTile")
            }
            // The month-spend column states exactly what the month divider may
            // print (RV.112): a `.complete` month is the bare figure, a
            // `.partial` one prints its KNOWN sum with the pending phrase
            // beneath it (visibly partial, never a bare total), and a
            // `.pending` month has no number at all - the column is omitted, so
            // it can never read `0 €` beside rows carrying no home amount. The
            // figure carries its own currency (RV.145), and a `.mixed` month
            // prints its per-currency breakdown rather than a bare sum.
            if let total = stats.monthSpend, let figure = HomeFormat.spend(total) {
                Divider().overlay(Theme.Palette.hairline).frame(height: 40)
                vitalColumn(label: HomeFormat.currentMonth(),
                            value: figure,
                            identifier: "homeMonthSpendTile",
                            caption: Self.spendCaption(total))
            }
        }
    }

    private func vitalColumn(label: String, value: String, identifier: String,
                             caption: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.custom(AppFonts.dinAlternateBold, size: 20))
                .foregroundStyle(Theme.Palette.ink)
            Text(label)
                .font(.caption2)
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(Theme.Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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

    /// The caption under a spend figure: the pending phrase when rows still
    /// wait, `nil` otherwise.
    private static func spendCaption(_ total: LogStream.MonthTotal) -> String? {
        switch total {
        case .partial(_, _, let pendingCount), .mixed(_, let pendingCount):
            return L10n.pendingRates(pendingCount)
        case .complete, .pending:
            return nil
        }
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
            // "First" is only true before the first entry; once the log is on
            // screen the card is the capture door, not the onboarding promise.
            if stats?.hasEntries == true {
                Text("Scan a fill-up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
            } else {
                Text("Scan your first fill-up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Palette.ink)
            }
            Text("Point the camera at a receipt – even an old one from the glovebox. Your consumption appears after the second full tank.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
            // PJ.100: the SAME `typeItControl` the signed-in header renders, so
            // the guest's typed door offers Service and Expense too - nothing
            // about being a guest gates them.
            HomeTypeItControl(presentSheet: presentSheet)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No car yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Add your first car to start logging fill-ups.")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            // PJ.101: the SAME filled Add-car button the signed-in no-car
            // layout renders, so the two no-car states cannot drift.
            HomeAddFirstCarButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .formCard()
    }
}
