import os
import SwiftUI
import TankbookCore

/// The Tire sets screen (P3.3) - a pushed route reached from the Vehicle detail
/// screen (docs/SCREENMAP.md, Garage side). Each set is one row: its name and
/// its derived mileage, "–" when unknowable (docs/JOURNEYS.md J7b). Tapping a
/// row renames; the trailing menu archives.
///
/// The mileage is derived on read, never stored (hard rule 2): every reload
/// recomputes it from the vehicle's service records, so an edit to any mount
/// record's odometer is picked up with no invalidation.
struct TireSetsView: View {
    @Environment(AppCarSelection.self) private var carSelection

    @State private var sets: [TireSet] = []
    @State private var vehicle: Vehicle?
    @State private var didLoad = false
    @State private var serviceRecords: [ServiceRecord] = []
    @State private var latestOdometer: Int?
    @State private var archiveTarget: TireSet?

    private static let log = Logger(subsystem: "app.tankbook", category: "tireSets")

    private var distanceUnit: DistanceUnit { vehicle?.units.distance ?? .km }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if sets.isEmpty {
                    emptyState
                } else {
                    ForEach(sets, id: \.id) { set in
                        NavigationLink(value: Route.tireSetForm(set.id)) {
                            TireSetRow(tireSet: set,
                                       mileage: mileage(for: set),
                                       distanceUnit: distanceUnit,
                                       onArchive: { archiveTarget = set })
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tireSetRow")
                    }
                }
                newTireSetCard
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onAppear { if didLoad { reload() } }
        .alert("Archive tire set?",
               isPresented: Binding(
                   get: { archiveTarget != nil },
                   set: { if !$0 { archiveTarget = nil } })) {
            Button("Archive", role: .destructive) { confirmArchive() }
            Button("Cancel", role: .cancel) { archiveTarget = nil }
        } message: {
            Text("The set's swap history is kept – its mileage still counts for the car.")
        }
    }

    // MARK: - Mileage

    private func mileage(for set: TireSet) -> Int? {
        TireMileage.mileage(for: set.id,
                            records: serviceRecords,
                            latestOdometer: latestOdometer)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(Theme.Palette.inkSoft)
            Text("No tire sets yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.ink)
            Text("Add each seasonal set once, then log swaps to see how far it has run.")
                .font(.caption)
                .foregroundStyle(Theme.Palette.inkSoft)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .formCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tireSetEmptyState")
    }

    // MARK: - New set + archive

    private var newTireSetCard: some View {
        NavigationLink(value: Route.tireSetForm(nil)) {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
                Text("New tire set")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.headlight)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.hairline,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tireSetsNewSetButton")
    }

    private func confirmArchive() {
        guard let target = archiveTarget else { return }
        do {
            let repository = try AppStore.repository()
            try repository.softDeleteTireSet(id: target.id)
            archiveTarget = nil
            reload()
        } catch {
            Self.log.error("Tire set archive failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        TireSetTestSeed.seedIfRequested()
        reload()
    }

    private func reload() {
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            guard let vehicle = carSelection.selectedVehicle(vehicles) else {
                sets = []
                self.vehicle = nil
                serviceRecords = []
                latestOdometer = nil
                return
            }
            self.vehicle = vehicle
            let entries = try repository.liveEntries(forVehicle: vehicle.id)
            latestOdometer = entries.compactMap(\.odometer).max() ?? vehicle.initialOdometer
            serviceRecords = try repository.liveServiceRecords(forVehicle: vehicle.id)
            sets = try repository.liveTireSets(forVehicle: vehicle.id)
        } catch {
            Self.log.error("Tire sets load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
