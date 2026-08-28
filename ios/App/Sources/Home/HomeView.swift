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
    @Environment(AppCarSelection.self) private var carSelection
    @State private var vehicle: Vehicle?
    @State private var vehicles: [Vehicle] = []
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

    /// The J9 anomaly, derived the same way as `stats` - the engine's verdict,
    /// never a stored value (hard rule 2), filtered by the recorded dismissals.
    /// `nil` is the engine abstaining: insufficient history, a seasonal rise
    /// that last year matched, or a dismissed cause (docs/SCHEMA.md -> ANOMALY).
    /// Silence is the common case, so the card renders only on a real verdict.
    private var anomaly: ConsumptionAnomaly? {
        guard let vehicle else { return nil }
        return AnomalyInsight.detect(
            vehicle: vehicle, entries: entries,
            duplicateResolutions: resolvedDuplicateKeys,
            dismissals: AnomalyInsightStore.dismissals(for: vehicle.id))
    }

    /// Title and settings gear on ONE row (docs/DESIGN.md: "The Home header is
    /// ONE row"). Not `.navigationTitle` + `.toolbar`: SwiftUI's large-title
    /// layout puts toolbar items on the bar ABOVE the title by construction, so
    /// two rows went to chrome before any of the user's data appeared - on a
    /// screen whose job is "your car, at a glance", the car should come first.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Log")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier("homeHeaderTitle")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.Palette.taillight)
                    .frame(width: 44, height: 44)          // tap target >= 44pt
                    .background(Circle().fill(Theme.Palette.dash))
                    .overlay(Circle().stroke(Theme.Palette.hairline, lineWidth: 1))
            }
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")
        }
        .padding(.top, 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                header
                if presentables.syncToast {
                    HomeSyncToast()
                }
                content
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            // The owned tab bar insets the scroll content via
            // `safeAreaInset(edge: .bottom)`, but its raised capture circle
            // sits above that inset; this clearance keeps the last row clear of
            // it (verified by the L4 "last row clears the tab bar" assertion).
            .padding(.bottom, AppTabBar.contentBottomClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.Palette.midnight)
        .task { await load() }
        .onChange(of: carSelection.selectedID) { _, _ in
            // A car switch from the switcher sheet or the garage-card swipe:
            // reload so Home, the log stream and Trends all show the SAME car
            // (the selected-car invariant, P1.11).
            Task { await load() }
        }
        .onChange(of: toastCenter.revision) { _, _ in
            // An edit saved (with or without a delta toast) changed the data:
            // reload so the derived stats and the log reflect it immediately.
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if presentables.guest {
            HomeGuestLayout(vehicle: vehicle, stats: stats, photoData: photoData,
                            onTypeIt: { presentSheet(.confirmManual) })
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
            .simultaneousGesture(swipeToSwitchGesture)
        HomeHeadlineBlock(stats: stats, vehicle: stats.vehicle,
                          onTypeIt: { presentSheet(.confirmManual) })
        HomeVitalsRow(stats: stats, vehicle: stats.vehicle)
        if let anomaly {
            AnomalyInsightCard(anomaly: anomaly,
                               unitLabel: L10n.headlineUnit(stats.vehicle.headlineUnit),
                               onAct: { actOnAnomaly(anomaly) },
                               onDismiss: { dismissal in recordAnomalyDismissal(dismissal) })
        }
        if stats.hasEntries {
            HomeRecentEntries(entries: entries, stations: stations,
                              vehicle: stats.vehicle,
                              excludedEntryCount: stats.excludedEntryCount,
                              pendingRateCount: stats.pendingRateCount,
                              duplicateResolutions: resolvedDuplicateKeys,
                              onKeepBoth: { group in resolveDuplicate(group, as: .keepBoth) },
                              onMerge: { group in mergeDuplicate(group) })
        } else {
            HomeEmptyEntriesCard(onTypeIt: { presentSheet(.confirmManual) })
        }
    }

    // MARK: - J9 anomaly actions (docs/JOURNEYS.md J9, hard rule 7)

    /// "Act": creates a service reminder to check the car. One tap - the
    /// reminder exists immediately and is editable from the Reminders list
    /// (hard rule 13). Acting also records a dismissal for this cause so the
    /// card is not a nag (a card with only "act" is the failure mode J9 names);
    /// the reminder itself is the record of the action. No notification is
    /// scheduled - J9's "never a push alarm" (docs/NOTIFICATIONS.md).
    private func actOnAnomaly(_ anomaly: ConsumptionAnomaly) {
        guard let vehicle else { return }
        do {
            let repository = try AppStore.repository()
            let reminder = ReminderLifecycle.makeReminder(
                vehicleId: vehicle.id,
                title: L10n.localize("Check fuel consumption"),
                category: .custom,
                dueDate: Date(),
                dueOdometer: nil)
            try repository.upsertReminder(reminder)
            recordAnomalyDismissal(
                AnomalyDismissal(cause: anomaly.cause, reason: nil, dismissedAt: Date()))
        } catch {
            Self.log.error("Anomaly act failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "Dismiss with reason": remembers what the user said (the dismissal, never
    /// the verdict - hard rule 2). The engine re-derives; the store only
    /// records. `noteEntryChanged` reloads so the card disappears for this
    /// cause without a toast (the data itself did not change).
    private func recordAnomalyDismissal(_ dismissal: AnomalyDismissal) {
        guard let vehicle else { return }
        AnomalyInsightStore.record(dismissal, for: vehicle.id)
        toastCenter.noteEntryChanged()
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

    // MARK: - Swipe-to-switch (the switcher footer's promise)

    /// "Swipe the garage card to switch without opening this list"
    /// (design/screens/CarSwitcher.dc.html). A horizontal drag on the garage
    /// card cycles through the live cars. `simultaneousGesture` means the
    /// vertical scroll keeps working - the two gestures don't fight, so the
    /// log stream is untouched (P1.11 scope note).
    private var swipeToSwitchGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                switchCar(by: value.translation.width)
            }
    }

    private func switchCar(by translationWidth: CGFloat) {
        guard let current = vehicle else { return }
        let live = vehicles.filter { !$0.archived }
        guard live.count > 1, let index = live.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex: Int
        if translationWidth < -40 {
            nextIndex = (index + 1) % live.count
        } else if translationWidth > 40 {
            nextIndex = (index - 1 + live.count) % live.count
        } else {
            return
        }
        do {
            try carSelection.select(live[nextIndex])
        } catch {
            Self.log.error("Swipe switch failed: \(error.localizedDescription, privacy: .public)")
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
            RateBackfillDebugHook.runIfRequested {
                // A backfill filled rate-pending entries: reload so the F9
                // footnote disappears and the home amounts appear - silently
                // (docs/SYNC.md S8). `noteEntryChanged` bumps the revision
                // without a toast; this is exactly the edit-save reload path.
                toastCenter.noteEntryChanged()
            }
        }
        do {
            let repository = try AppStore.repository()
            let vehicles = try repository.liveVehicles()
            self.vehicles = vehicles
            // The selected-car invariant: resolve through the shared selection,
            // never "the first vehicle" - Home, the switcher, the manual form
            // and Trends all read the same source (P1.11).
            guard let selected = carSelection.selectedVehicle(vehicles) else {
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

    private func loadPhoto(repository: TankbookRepository, vehicle: Vehicle) throws -> Data? {
        guard let photoID = vehicle.photo else { return nil }
        let attachments = try repository.liveAttachments()
        guard let attachment = attachments.first(where: { $0.id == photoID }) else { return nil }
        let url = try VehiclePhotoStore.attachmentsDirectory()
            .appendingPathComponent(attachment.file.relativePath)
        return try? Data(contentsOf: url)
    }
}
