import os
import SwiftUI
import TankbookCore

/// The Car switcher sheet (P1.11, design/screens/CarSwitcher.dc.html), reached
/// from Home's garage card/chip (docs/SCREENMAP.md). The sheet that makes the
/// app genuinely multi-vehicle: every car in the garage with its OWN vitals -
/// odometer, consumption in that car's units (L/100 for petrol, kWh/100 for
/// EV - `Vehicle.headlineUnit`), and this month's spend. Archived cars (J13)
/// stay visible, dimmed and honestly labelled, but out of active stats and not
/// selectable. `Add car` is the ONE monetization surface in the app
/// (hard rule 5): at the free-tier cap it shows the limit sheet, never an
/// error, and never mid-capture.
///
/// Selecting a car persists it (`AppCarSelection.select` ->
/// `Preferences.defaultVehicleId`) and dismisses - Home/Trends observe the
/// change and reload, so "Capture always logs to the selected car" holds.
struct CarSwitcherView: View {
    /// Add car / archived detail / Pro: the host dismisses the sheet and
    /// pushes the route on the presenting tab's stack (the switcher's own
    /// NavigationStack cannot push; the routes live on the tab stack).
    let onNavigate: (Route) -> Void

    @Environment(AppCarSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [CarSwitcherRow] = []
    @State private var selectedID: UUID?
    @State private var showsLimitSheet = false
    @State private var didLoad = false

    private static let log = Logger(subsystem: "app.tankbook", category: "carSwitcher")

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    rowView(row)
                }
                addCarRow
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(Theme.Palette.midnight)
        .task { await load() }
        .sheet(isPresented: $showsLimitSheet) { limitSheet }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: CarSwitcherRow) -> some View {
        if row.vehicle.archived {
            archivedRow(row)
        } else {
            liveRow(row)
        }
    }

    /// A live car: name, its own vitals, and the selected marker. The accent
    /// (taillight for fuel, headlight for EV) encodes the powertrain - hard
    /// rule 5: accent is meaning, not chrome.
    private func liveRow(_ row: CarSwitcherRow) -> some View {
        let isSelected = row.vehicle.id == selectedID
        let accent = Self.accent(row.vehicle)
        return Button {
            select(row.vehicle)
        } label: {
            HStack(spacing: 12) {
                carIcon
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(row.vehicle.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(1)
                        if isSelected {
                            Circle()
                                .fill(accent)
                                .frame(width: 7, height: 7)
                        }
                    }
                    if let vitals = row.vitals {
                        Text(vitals)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .accessibilityHidden(false)
                }
            }
            .contentShape(Rectangle())
            .padding(14)
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? accent : Theme.Palette.hairline,
                            lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("carSwitcherRow")
        .accessibilityLabel(rowAccessibilityLabel(row, isSelected: isSelected))
    }

    /// An archived car (J13): history kept, out of active stats, not
    /// selectable. The row dims (the artboard's `opacity: 0.55`) and leads to
    /// the vehicle detail. The subtitle renders "sold <month>" honestly from
    /// `archivedAt` (P1.12) - the artboard's "Archived · sold Mar 2026 ·
    /// history kept", or the bare "Archived · history kept" when no date is
    /// held, rather than fabricating one.
    private func archivedRow(_ row: CarSwitcherRow) -> some View {
        Button {
            onNavigate(.vehicleDetail(row.vehicle.id))
        } label: {
            HStack(spacing: 12) {
                carIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.vehicle.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Palette.inkSoft)
                        .lineLimit(1)
                    Text(L10n.archivedSubtitle(archivedAt: row.vehicle.archivedAt))
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.inkSoft)
            }
            .contentShape(Rectangle())
            .padding(14)
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(0.55)
        .accessibilityIdentifier("carSwitcherArchivedRow")
    }

    /// The `+ Add car` row (the artboard's dashed tile). At the free-tier cap
    /// this is where the limit sheet appears - the only place monetization
    /// may surface (docs/ERRORS.md -> Car switcher / Garage).
    private var addCarRow: some View {
        Button {
            let activeCount = rows.filter { !$0.vehicle.archived }.count
            if CarLimit.canAddCar(activeCount: activeCount) {
                onNavigate(.addVehicle)
            } else {
                showsLimitSheet = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                Text("Add car")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .padding(14)
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Theme.Palette.hairline,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("carSwitcherAddCar")
    }

    /// The artboard footer: the invariant in the user's words.
    private var footer: some View {
        Text("Capture always logs to the selected car. Swipe the garage card to switch without opening this list.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.top, 8)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("carSwitcherFooter")
    }

    // MARK: - The free-tier limit sheet (the ONE monetization surface)

    private var limitSheet: some View {
        CarLimitSheet(
            onArchive: {
                showsLimitSheet = false
                // "Archive a car" lands on the selected car's detail (P1.12):
                // the screen where archiving actually happens.
                onNavigate(.vehicleDetail(nil))
            },
            onPro: {
                showsLimitSheet = false
                onNavigate(.paywall)
            },
            onCancel: { showsLimitSheet = false })
            .presentationDetents([.height(340)])
    }

    // MARK: - Behavior

    private func select(_ vehicle: Vehicle) {
        do {
            try selection.select(vehicle)
            dismiss()
        } catch {
            Self.log.error("Car selection failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var carIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(Theme.Palette.midnight)
            Image(systemName: "car.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(width: 42, height: 42)
    }

    /// taillight = fuel, headlight = electric (hard rule 5; the accent encodes
    /// the powertrain, exactly as the switcher artboard shows).
    static func accent(_ vehicle: Vehicle) -> Color {
        vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight
    }

    private func rowAccessibilityLabel(_ row: CarSwitcherRow, isSelected: Bool) -> String {
        var label = row.vehicle.name
        if let vitals = row.vitals { label += ", \(vitals)" }
        if isSelected { label += ", \(L10n.localize("Selected"))" }
        return label
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        CarSwitcherTestSeed.seedIfRequested()
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            selectedID = selection.selectedVehicle(vehicles)?.id
            let resolutions = (try? repository.resolvedDuplicateKeys()) ?? []
            rows = try vehicles.map { vehicle in
                let entries = try repository.liveEntries(forVehicle: vehicle.id)
                let vitals = vehicle.archived ? nil : Self.vitals(
                    HomeStats(vehicle: vehicle, entries: entries,
                              duplicateResolutions: resolutions))
                return CarSwitcherRow(vehicle: vehicle, vitals: vitals)
            }
        } catch {
            Self.log.error("Car switcher load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "119 486 km · 6.8 L/100 · €212 this month" - each segment its own unit,
    /// joined by the artboard's separator. A segment with nothing honest to
    /// show is omitted, never "N/A".
    private static func vitals(_ stats: HomeStats) -> String {
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

/// One garage row: the vehicle plus its derived vitals line (nil for an
/// archived car - the artboard shows no vitals there).
private struct CarSwitcherRow: Identifiable {
    let vehicle: Vehicle
    let vitals: String?
    var id: UUID { vehicle.id }
}
