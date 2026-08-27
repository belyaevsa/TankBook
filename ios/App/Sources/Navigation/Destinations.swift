import SwiftUI
import TankbookCore

/// Maps a pushed `Route` to its screen. Today every case renders a placeholder;
/// P1.2-P1.11 replace the placeholder bodies, not this wiring.
struct DestinationView: View {
    let route: Route

    var body: some View {
        content
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
            // The system tab bar is hidden at the root (`.toolbar(.hidden, for:
            // .tabBar)` on the TabView), but iOS 26 still reserves its bottom
            // safe area on PUSHED screens - a phantom ~83pt gap below each
            // pushed screen's own save bar (Edit entry, Vehicle detail, Add
            // car). Re-hiding it here removes that reservation so a pushed
            // screen's `safeAreaInset(edge: .bottom)` save bar sits directly on
            // the owned tab bar instead of floating 83pt above it. The owned
            // bar itself is a sibling below the TabView, so this does not hide
            // it.
            .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .settings: SettingsView()
        case .about: LeafContent()
        case .reminders: RemindersView()
        case .reminderForm(let reminderID): ReminderFormView(reminderID: reminderID)
        case .recentlyDeleted: RecentlyDeletedView()
        case .editEntry(let entryID): EditEntryView(entryID: entryID)
        case .vehicleDetail(let vehicleID): VehicleDetailView(vehicleID: vehicleID)
        case .tireSets: TireSetsView()
        case .tireSetForm(let tireSetID): TireSetFormView(tireSetID: tireSetID)
        case .addVehicle: AddVehicleView()
        case .accountDevices: LeafContent()
        case .paywall: LeafContent()
        case .importWizard: ImportWizardView()
        case .flaggedEntries: FlaggedEntriesView()
        }
    }
}

/// Maps a `SheetRoute` to its sheet, wrapped in the discard-aware chrome.
struct SheetDestinationView: View {
    let route: SheetRoute
    /// Host callback for the Car switcher's forward exits (Add car, archived
    /// detail, Pro): dismiss the sheet and push the route on the presenting
    /// tab's stack. The sheet's own NavigationStack cannot push tab-stack
    /// routes, so the host owns the transition.
    var onNavigate: (Route) -> Void = { _ in }
    @State private var hasUnsavedChanges = false

    var body: some View {
        DiscardAwareSheet(policy: route.discardPolicy, hasUnsavedChanges: $hasUnsavedChanges) {
            sheetContent
                .navigationTitle(route.title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        switch route {
        case .confirmManual: ManualFillUpView(hasUnsavedChanges: $hasUnsavedChanges)
        case .tankLevel: TankLevelStandaloneHost()
        case .carSwitcher: CarSwitcherView(onNavigate: onNavigate)
        case .signIn: SignInFlowHost()
        case .reminderComplete: SheetPlaceholderContent()
        case .serviceEntry: ServiceEntryView(hasUnsavedChanges: $hasUnsavedChanges)
        case .expenseEntry: ExpenseEntryView(hasUnsavedChanges: $hasUnsavedChanges)
        case .partsShelf: PartsShelfView()
        }
    }
}

/// The `-presentScreen tankLevel` path (screenshots, DEBUG): the sheet opened
/// without a fill-up form behind it, so it owns its level state and loads the
/// default vehicle's capacity itself. Seeding happens here too
/// (`-seedTankLevel` / `-seedTankLevelNoCapacity`) so a booted app can be
/// screenshotted without a UI test driving a tap.
struct TankLevelStandaloneHost: View {
    @State private var tankLevelAfterPct: Double?
    @State private var isFull = false
    @State private var capacityL: Double?
    @State private var didLoad = false

    var body: some View {
        TankLevelSheet(tankLevelAfterPct: $tankLevelAfterPct,
                       isFull: $isFull,
                       capacityL: capacityL)
            .task { await load() }
    }

    private func load() async {
        guard !didLoad else { return }
        didLoad = true
        TankLevelTestSeed.seedIfRequested()
        guard let repository = try? AppStore.repository(),
              let vehicle = (try? repository.liveVehicles())?.first else { return }
        capacityL = vehicle.tankCapacityL
    }
}

/// Maps a `ModalRoute` to its full-screen cover. Capture (P2.1) fills the body;
/// the X and its `captureCloseButton` accessibility identifier are owned here
/// so a UI test that closes the cover keeps working unchanged.
struct ModalDestinationView: View {
    let route: ModalRoute
    /// Host callback for the Capture -> ServiceEntry exit (SCREENMAP.md:
    /// "Capture -->|Service mode| ServiceEntry"): the capture cover closes and
    /// the ServiceEntry sheet opens on the presenting tab, carrying the scanned
    /// invoice pre-fill through the shared `ServiceInvoiceSession`.
    var onServiceEntry: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(route.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Theme.Palette.midnight.opacity(0.7)))
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("captureCloseButton")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .capture:
            CaptureView(onServiceEntry: onServiceEntry)
        }
    }
}

// MARK: - Placeholder content (P1.2-P1.11 replace these)

/// A placeholder leaf: a titled screen with no forward exit yet (its forward
/// exits - Save, Delete, rate, send feedback - arrive with its real screen).
/// Every pushed screen still has a back path, so it is never a dead end.
struct LeafContent: View {
    var body: some View {
        Color.clear
    }
}

private struct SheetPlaceholderContent: View {
    var body: some View {
        Color.clear
    }
}
