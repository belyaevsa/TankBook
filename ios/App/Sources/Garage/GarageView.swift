import SwiftUI
import TankbookCore

/// The Garage tab root (P6.4) - the vehicle grid, the real screen behind the
/// third tab (docs/SCREENMAP.md "Garage | tab root"). The Car switcher sheet
/// covers quick switching; this tab is where the cars live and where each car's
/// settings are reached: every card navigates to `VehicleDetail`, the screen
/// that makes hard rule 13 real - every catalog-derived value (name, fuel
/// kinds, tank size, currency, units) is editable there, and editable again
/// later (`docs/DESIGN.md` -> Settings: per-car settings live on the car in the
/// Garage, never in Settings).
///
/// Layout follows the Car switcher artboard (design/screens/CarSwitcher.dc.html
/// - the only drawn reference for a vehicle list): the 42pt car tile, the name
/// with the selected dot, the one-line vitals in the car's own units, the
/// dashed "Add car" tile, and the footer invariant. Live cards carry the accent
/// (taillight fuel / headlight EV - hard rule 5, accent encodes powertrain) for
/// the selected marker. Archived cars stay visible, dimmed and honestly
/// labelled (J13), and lead to the same detail screen.
///
/// "Add car" is the ONE monetization surface in the app (hard rule 5): at the
/// free-tier cap it shows the limit sheet, never an error, and never
/// mid-capture (docs/ERRORS.md -> Car switcher / Garage).
struct GarageView: View {
    /// The tab root pushes routes through this (the Garage tab's own
    /// NavigationStack path), so a Button - the "Add car" tile at the free-tier
    /// cap, and the limit sheet's "Archive a car" - can push exactly like the
    /// Car switcher's host does.
    let onNavigate: (Route) -> Void

    @Environment(AppCarSelection.self) private var selection

    @State private var rows: [GarageRow] = []
    @State private var selectedID: UUID?
    @State private var showsLimitSheet = false
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if rows.isEmpty {
                    emptyGarage
                } else {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
                addCarRow
                footer
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
        .navigationTitle("Garage")
        .task { await load() }
        .sheet(isPresented: $showsLimitSheet) { limitSheet }
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: GarageRow) -> some View {
        if row.vehicle.archived {
            archivedRow(row)
        } else {
            liveRow(row)
        }
    }

    /// A live car: name, its own vitals, the selected marker - and the whole
    /// card leads to that car's detail (per-car settings, docs/DESIGN.md). The
    /// accent (taillight fuel, headlight EV) encodes the powertrain, exactly as
    /// the Car switcher artboard draws it (hard rule 5).
    private func liveRow(_ row: GarageRow) -> some View {
        let isSelected = row.vehicle.id == selectedID
        let accent = Self.accent(row.vehicle)
        return NavigationLink(value: Route.vehicleDetail(row.vehicle.id)) {
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
                }
                chevron
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
        .accessibilityIdentifier("garageCarRow")
        .accessibilityLabel(rowAccessibilityLabel(row, isSelected: isSelected))
    }

    /// An archived car (J13): history kept, out of active stats. The row dims
    /// (the artboard's `opacity: 0.55`) and leads to the same vehicle detail
    /// where archiving is reversible (P1.12).
    private func archivedRow(_ row: GarageRow) -> some View {
        NavigationLink(value: Route.vehicleDetail(row.vehicle.id)) {
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
                chevron
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
        .accessibilityIdentifier("garageArchivedRow")
    }

    /// The `+ Add car` tile (the artboard's dashed tile). At the free-tier cap
    /// this is where the limit sheet appears - the only place monetization may
    /// surface (docs/ERRORS.md -> Car switcher / Garage).
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
                    .foregroundStyle(Theme.Palette.action)
                Text("Add car")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.action)
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
        .accessibilityIdentifier("garageAddCar")
    }

    /// A Garage with no cars yet: the honest empty state, leading to Add car.
    private var emptyGarage: some View {
        VStack(spacing: 8) {
            Image(systemName: "car")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No cars yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Add your first car to start logging fill-ups.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
    }

    /// The footer invariant, in the user's words (the switcher sheet's line).
    private var footer: some View {
        Text("Capture always logs to the selected car. Each car's settings live on the car.")
            .font(.caption)
            .foregroundStyle(Theme.Palette.inkSoft)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .padding(.top, 8)
            .padding(.horizontal, 6)
            .accessibilityIdentifier("garageFooter")
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

    private var carIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(Theme.Palette.midnight)
            Image(systemName: "car.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .frame(width: 42, height: 42)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Palette.inkSoft)
    }

    /// taillight = fuel, headlight = electric (hard rule 5; the accent encodes
    /// the powertrain, exactly as the switcher artboard shows).
    static func accent(_ vehicle: Vehicle) -> Color {
        vehicle.powertrain == .ev ? Theme.Palette.headlight : Theme.Palette.taillight
    }

    private func rowAccessibilityLabel(_ row: GarageRow, isSelected: Bool) -> String {
        var label = row.vehicle.name
        if let vitals = row.vitals { label += ", \(vitals)" }
        if isSelected { label += ", \(L10n.localize("Selected"))" }
        return label
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        #if DEBUG
        GarageTestSeed.seedIfRequested()
        #endif
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            selectedID = selection.selectedVehicle(vehicles)?.id
            let resolutions = (try? repository.resolvedDuplicateKeys()) ?? []
            rows = try vehicles.map { vehicle in
                let entries = try repository.liveEntries(forVehicle: vehicle.id)
                let vitals = vehicle.archived ? nil : VehicleVitals.line(
                    HomeStats(vehicle: vehicle, entries: entries,
                              duplicateResolutions: resolutions))
                return GarageRow(vehicle: vehicle, vitals: vitals)
            }
        } catch {
            AppLog.error(operation: "garage.load", category: .ui, error: error)
        }
    }
}

/// One garage row: the vehicle plus its derived vitals line (nil for an
/// archived car - the artboard shows no vitals there).
private struct GarageRow: Identifiable {
    let vehicle: Vehicle
    let vitals: String?
    var id: UUID { vehicle.id }
}

#if DEBUG
/// UI-test DB seeding for the Garage tab root. The artboard's garage (a petrol
/// car, an EV and an archived car) is the Car switcher seed's state, so the tab
/// reuses it - the two surfaces must render the same garage.
enum GarageTestSeed {
    @MainActor
    static func seedIfRequested() {
        HomeTestSeed.seedIfRequested()
    }
}
#endif
