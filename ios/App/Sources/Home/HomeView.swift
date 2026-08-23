import os
import SwiftUI
import TankbookCore
import UIKit

/// The Home tab root content (P1.4), replacing the P1.1 placeholder. Renders
/// per design/screens/HomeA.dc.html (the Home C screen set) with every empty
/// and partial state honest: guest (GuestHome.dc.html), no car yet, car with
/// zero entries (vitals omitted, never "N/A"), one fill-up with no segment yet
/// (the D4 hint), and the full state.
///
/// All figures come from `HomeStats`, which derives them from the Consumption
/// engine - Home does no arithmetic of its own (hard rule 2). The sync-shaped
/// states (S2/S5/S7, reminder banner, guest chrome) are presentation fixtures
/// driven by launch arguments until P4 (HomePresentables).
struct HomeView: View {
    let presentSheet: (SheetRoute) -> Void

    @Environment(AppToastCenter.self) private var toastCenter
    @State private var vehicle: Vehicle?
    @State private var entries: [any Entry] = []
    @State private var stations: [Station] = []
    @State private var photoData: Data?
    @State private var didSeed = false
    @State private var presentables = HomePresentables.fromLaunchArguments()
    @State private var resolvedDuplicateKeys: Set<DuplicateDetector.PairKey> = []

    private static let log = Logger(subsystem: "app.tankbook", category: "home")

    /// Derived, never stored (hard rule 2): recomputed from the current entries
    /// on every render - the engine's pure function, cheap at Home's history
    /// sizes and correct-by-construction. S2 resolutions feed the single-count
    /// invariant (docs/SYNC.md: "Until resolved, only ONE of the pair counts").
    private var stats: HomeStats? {
        guard let vehicle else { return nil }
        return HomeStats(vehicle: vehicle, entries: entries,
                         duplicateResolutions: resolvedDuplicateKeys)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                if presentables.syncToast {
                    HomeSyncToast()
                }
                content
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            // The floating tab bar overlaps the scroll content on iOS 26: the
            // automatic bottom inset ends at the home indicator, leaving the
            // last card half-hidden behind the bar. This clearance pushes the
            // last row fully above it (P1.5 - verified by the L4 "last row
            // clears the tab bar" assertion).
            .padding(.bottom, Self.bottomClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onChange(of: toastCenter.revision) { _, _ in
            // An edit saved (with or without a delta toast) changed the data:
            // reload so the derived stats and the log reflect it immediately.
            Task { await load() }
        }
    }

    /// The scroll content's extra bottom clearance so the last log row clears
    /// the floating tab bar (tab bar ~49pt + its float margin, minus the 24pt
    /// the sections already get from their own spacing).
    private static let bottomClearance: CGFloat = 64

    @ViewBuilder
    private var content: some View {
        if presentables.guest {
            HomeGuestLayout(vehicle: vehicle, stats: stats, photoData: photoData,
                            onCapture: { presentSheet(.confirmManual) })
        } else if vehicle == nil {
            HomeNoCarLayout(presentSheet: presentSheet)
        } else if let stats {
            fullLayout(stats)
        }
    }

    @ViewBuilder
    private func fullLayout(_ stats: HomeStats) -> some View {
        HomeBanners(presentables: presentables, vehicleName: stats.vehicle.name)
        headerRow(stats.vehicle)
        HomeGarageCard(vehicle: stats.vehicle, odometer: stats.odometer,
                       updatedAt: stats.updatedAt, photoData: photoData)
        HomeHeadlineBlock(stats: stats, vehicle: stats.vehicle,
                          onCapture: { presentSheet(.confirmManual) })
        HomeVitalsRow(stats: stats, vehicle: stats.vehicle)
        if stats.hasEntries {
            HomeRecentEntries(entries: entries, stations: stations,
                              vehicle: stats.vehicle,
                              excludedEntryCount: stats.excludedEntryCount,
                              duplicateResolutions: resolvedDuplicateKeys,
                              onKeepBoth: { group in resolveDuplicate(group, as: .keepBoth) },
                              onMerge: { group in mergeDuplicate(group) })
        } else {
            HomeEmptyEntriesCard(onCapture: { presentSheet(.confirmManual) })
        }
    }

    // MARK: - S2 resolution actions (docs/SYNC.md S2)

    /// "Keep both" - genuinely two purchases: recorded so the heuristic
    /// suppresses this pair from then on, and BOTH entries count.
    private func resolveDuplicate(_ group: LogStream.DuplicateGroup, as resolution: DuplicateResolution.Resolution) {
        do {
            let repository = try AppStore.repository()
            guard let vehicle else { return }
            let fills = try repository.liveFillUps(forVehicle: vehicle.id)
            guard let counted = fills.first(where: { $0.id == group.counted.id }),
                  let excluded = fills.first(where: { $0.id == group.excluded.id }) else { return }
            try repository.upsertDuplicateResolution(DuplicateResolution(
                id: UUID.v7(), createdAt: Date(), updatedAt: Date(), deletedAt: nil,
                countedEntryID: counted.id, excludedEntryID: excluded.id,
                resolution: resolution))
            toastCenter.noteEntryChanged()
        } catch {
            Self.log.error("Duplicate resolution failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "Merge" - the richer record survives (attachment wins, fields union)
    /// and the other is tombstoned into Recently deleted, where it stays
    /// recoverable for 30 days (nothing is lost silently, hard rule 8).
    private func mergeDuplicate(_ group: LogStream.DuplicateGroup) {
        do {
            let repository = try AppStore.repository()
            guard let vehicle else { return }
            let fills = try repository.liveFillUps(forVehicle: vehicle.id)
            guard let winner = fills.first(where: { $0.id == group.counted.id }),
                  let loser = fills.first(where: { $0.id == group.excluded.id }) else { return }
            let merged = DuplicateMerge.merge(winner: winner, loser: loser)
            try repository.upsertFillUp(merged)
            try repository.softDeleteFillUp(id: loser.id)
            toastCenter.noteEntryChanged()
        } catch {
            Self.log.error("Duplicate merge failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func headerRow(_ vehicle: Vehicle) -> some View {
        HStack {
            Button {
                presentSheet(.carSwitcher)
            } label: {
                HStack(spacing: 4) {
                    Text(vehicle.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.Palette.ink)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.inkSoft)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.Palette.dash))
                .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("carSwitcherButton")

            Spacer(minLength: 0)

            Button {
                presentSheet(.confirmManual)
            } label: {
                Label("Type it", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.Palette.dash))
                    .overlay(Capsule().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("typeItButton")
        }
    }

    // MARK: - Loading

    private func load() async {
        // Seeding runs once (idempotent anyway); the data reloads every time
        // the view appears or an edit revision lands, so Home never shows stale
        // derived stats after an entry change (hard rule 2).
        if !didSeed {
            didSeed = true
            HomeTestSeed.seedIfRequested()
        }
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            let preferences = try? repository.livePreferences()
            guard let selected = Self.pickVehicle(vehicles, defaultID: preferences?.defaultVehicleId) else {
                return
            }
            self.vehicle = selected
            entries = try repository.liveEntries(forVehicle: selected.id)
            stations = try repository.liveStations()
            resolvedDuplicateKeys = (try? repository.resolvedDuplicateKeys()) ?? []
            photoData = try loadPhoto(repository: repository, vehicle: selected)
        } catch {
            Self.log.error("Home load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func pickVehicle(_ vehicles: [Vehicle], defaultID: UUID?) -> Vehicle? {
        if let defaultID, let match = vehicles.first(where: { $0.id == defaultID }) {
            return match
        }
        return vehicles.first
    }

    private func loadPhoto(repository: TankbookRepository, vehicle: Vehicle) throws -> Data? {
        guard let photoID = vehicle.photo else { return nil }
        let attachments = try repository.liveAttachments()
        guard let attachment = attachments.first(where: { $0.id == photoID }) else { return nil }
        let url = try VehiclePhotoStore.attachmentsDirectory()
            .appendingPathComponent(attachment.file.relativePath)
        return try? Data(contentsOf: url)
    }
}
