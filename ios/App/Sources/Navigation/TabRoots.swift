import SwiftUI
import UIKit
import TankbookCore

/// The three tab roots (docs/SCREENMAP.md "Tab roots (no back)"): Log/Home,
/// Trends, Garage. Each tab owns its own `NavigationStack` path so switching
/// tabs preserves each tab's stack - a stated requirement, not an accident.
///
/// `TabView` stays as the state engine while its system bar is hidden
/// (`.toolbar(.hidden, for: .tabBar)`) and replaced with the owned `AppTabBar`
/// via `safeAreaInset(edge: .bottom)` (P2.1b). See `AppTabBar` for why the bar
/// is owned rather than measured off the system one.
///
/// The delta toast (docs/ERRORS.md -> Edit entry, row 4) is owned here, above
/// the TabView: it must survive a navigation pop (the edit save dismisses back
/// to Home) and its "tap -> Trends" next step is a TAB switch, which only the
/// root can perform.
struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var toastCenter = AppToastCenter()
    @State private var carSelection = AppCarSelection()
    /// Carries the scanned invoice pre-fill from Capture into ServiceEntry.
    @State private var invoiceSession = ServiceInvoiceSession()
    /// Carries the expense-category pre-selection into the ExpenseEntry sheet.
    @State private var expenseEntrySession = ExpenseEntrySession()
    /// Carries the P3.5 "type amount" hand-off from the ReminderComplete sheet
    /// into the entry screen and back.
    @State private var reminderCompletionSession = ReminderCompletionSession()
    /// Owns local-notification arming, cancellation and permission (P3.6).
    @State private var notificationCoordinator = ReminderNotificationCoordinator()
    /// The app's one config surface (P6.18b): the update requirement derived
    /// from the held config snapshot at launch, refreshed on foreground.
    @State private var configService: AppConfigService
    /// The app's single sync surface (P4.9b): the Settings status, "Sync now"
    /// trigger and the derived flagged count all read from here.
    @State private var sync: AppSync
    @State private var tabSelection: AppTab
    /// Set by `ConfirmableFormScreen` through a preference: a form with a
    /// primary confirmation action hides the bar while it is on screen.
    @State private var isConfirmableFormOnTop = false
    // Capture is presented by the ACTIVE tab, not by this root. Hoisting the
    // three modal routes keeps the capture full-screen cover and each tab's own
    // sheet (the "Type it" manual form) on the SAME view, so one presentation
    // coordinator serializes them. A root-level `.fullScreenCover` dismissed
    // while a tab's `.sheet` presented was the race behind the P2.1b crash
    // (presenting a sheet while an ancestor's cover was mid-dismissal).
    @State private var logModal: ModalRoute?
    @State private var trendsModal: ModalRoute?
    @State private var garageModal: ModalRoute?
    @State private var didRunStartupPurge = false
    /// The app's one Low Power Mode seam (P6.8): the injected power state the
    /// sync surface, the coordinator and the rate store all consult, plus the
    /// resumer that drains deferred work when the mode ends.
    @State private var power: AppPower

    init() {
        let configService = AppConfigService.make()
        let power = AppPower()
        // DEBUG/test: write the seeded session before the launch opportunistic
        // sync runs, so the launch trigger really consults the Low Power policy
        // instead of being skipped for a still-empty Keychain (see
        // `SettingsTestSeed.seedSessionAtLaunchIfRequested`). Inert in release.
        SettingsTestSeed.seedSessionAtLaunchIfRequested()
        _configService = State(initialValue: configService)
        _sync = State(initialValue: AppSync(configService: configService,
                                            powerState: power.powerState,
                                            resumer: power.resumer))
        // The rate pack refresh is the other registered piece of deferred work
        // (docs/SYNC.md): it shares the same resumer, so its deferred fetch
        // drains with the deferred sync when the mode ends.
        AppRates.resumer = power.resumer
        _power = State(initialValue: power)
        // `-selectTrendsTab`: land on the Trends tab at launch so simctl-driven
        // screenshots and UI tests can reach it without a tab tap (simctl cannot
        // tap). DEBUG/test-only.
        if ProcessInfo.processInfo.arguments.contains("-selectTrendsTab") {
            _tabSelection = State(initialValue: .trends)
        } else if ProcessInfo.processInfo.arguments.contains("-selectGarageTab") {
            _tabSelection = State(initialValue: .garage)
        } else {
            _tabSelection = State(initialValue: .log)
        }
    }

    /// One tab's root, always present in the hierarchy so its NavigationStack
    /// survives a switch. The inactive ones are fully transparent, take no
    /// touches, and are hidden from VoiceOver so it does not read three screens.
    @ViewBuilder
    private func tabRoot(_ tab: AppTab, @ViewBuilder content: () -> some View) -> some View {
        let isActive = tabSelection == tab
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }

    var body: some View {
        VStack(spacing: 0) {
            // NO `TabView`. Three attempts to suppress its bar failed: on iOS 26
            // the tab bar is not a `UITabBar` - which is why a UIKit probe could
            // never find one to measure, and why emptying `UITabBarAppearance`
            // changed nothing - and `.toolbar(.hidden, for: .tabBar)` removes
            // only its ITEMS. Its glass container kept painting a grey pill over
            // the log content: invisible to every UI test, since the
            // accessibility tree really was empty, and visible in every
            // screenshot.
            //
            // So there is no system bar to fight. All three roots stay in the
            // hierarchy permanently and only visibility changes, which is what
            // `TabView` was being kept for: each tab's `NavigationStack` keeps
            // its stack and scroll position across switches because the view is
            // never torn down. `.opacity` + `allowsHitTesting` rather than an
            // `if`, because an `if` would destroy and rebuild the losing tabs.
            ZStack {
                tabRoot(.log) { HomeTabView(modal: $logModal) }
                tabRoot(.trends) { TrendsTabView(modal: $trendsModal) }
                tabRoot(.garage) { GarageTabView(modal: $garageModal) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The accent still propagates to CONTENT - entry markers, the
            // capture button, the cross-check lock. The owned tab bar draws its
            // own colours, so `.tint` no longer paints any chrome.
            .tint(Theme.Palette.taillight)

            // The bar is a sibling below the TabView, not a `safeAreaInset` on
            // it: that makes the TabView's frame end at the bar's top, so BOTH
            // root scroll views and pushed screens are inset above it. A
            // `safeAreaInset` on the TabView does not propagate through a
            // NavigationStack push on iOS 26, which left pushed screens' bottom
            // bars behind ours.
            // Hidden while a form with a confirmation button is on top: two
            // taillight-red primary actions must never stack, and a tap meant
            // for Save that lands on Capture abandons a half-filled form. See
            // `ConfirmableFormScreen`.
            if !isConfirmableFormOnTop {
                AppTabBar(selection: $tabSelection) {
                    openCapture()
                }
                .transition(.move(edge: .bottom))
            }
        }
        .onPreferenceChange(ConfirmableFormPreference.self) { isForm in
            isConfirmableFormOnTop = isForm
        }
        .animation(.easeInOut(duration: 0.2), value: isConfirmableFormOnTop)
        // The bar stays put when the keyboard rises (the keyboard covers it, as
        // it covers the system tab bar) instead of riding up with the safe area.
        .ignoresSafeArea(.keyboard)
        .overlay(alignment: .bottom) {
            if let message = toastCenter.message {
                DeltaToast(message: message) {
                    toastCenter.dismiss()
                    tabSelection = .trends   // the toast's next step
                }
                .padding(.bottom, Self.toastBottomClearance)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastCenter.message)
        .environment(toastCenter)
        .environment(carSelection)
        .environment(invoiceSession)
        .environment(expenseEntrySession)
        .environment(reminderCompletionSession)
        .environment(notificationCoordinator)
        .environment(configService)
        .environment(sync)
        .task {
            runPurgeIfNeeded()
            // Launch counts as a foreground event (docs/CONFIG.md -> Delivery):
            // the requirement is re-evaluated, but the UI already drew from the
            // held snapshot - nothing waits on this (P6.18b).
            await configService.refresh()
            // P6.2: the monthly summary (if enabled) is re-armed with whatever
            // data exists now - the fire date is the next 1st at 10:00, so a
            // launch after more entries refreshes the figure by identifier.
            await notificationCoordinator.reconcileMonthlySummary()
            // P6.8: launch is an OPPORTUNISTIC sync cycle (docs/SYNC.md ->
            // Low Power Mode table). It passes `.background`, so it defers while
            // Low Power Mode is on and is registered with the resumer, which
            // drains it when the mode ends - never gated on anything a user
            // tapped, never a second door into sync (hard rule 1: the automatic
            // cycle and the Settings button both go through `syncNow`).
            await sync.runOpportunisticSync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                runPurgeIfNeeded()
                Task { await configService.refresh() }
                // P6.2: foreground re-arms the monthly summary too - same
                // replace-by-identifier discipline as the launch reconcile.
                Task { await notificationCoordinator.reconcileMonthlySummary() }
                // P6.8: foreground is the other opportunistic cycle; same
                // `.background` trigger, same deferral-and-drain contract.
                Task { await sync.runOpportunisticSync() }
            }
        }
    }

    /// Routes the capture button to whichever tab is on screen, so the cover is
    /// presented by that tab (its `modal`), never by the root.
    private func openCapture() {
        switch tabSelection {
        case .log: logModal = .capture
        case .trends: trendsModal = .capture
        case .garage: garageModal = .capture
        }
    }

    /// The scheduled tombstone purge (docs/SYNC.md: 30-day undo window; P1.7
    /// wires the repository's existing grace-period purge to run). Runs at
    /// launch and again on every foreground - the purge is idempotent, so
    /// running twice is identical to running once, and a tombstone that
    /// crossed the boundary while the app sat backgrounded is cleared on the
    /// next visit to the surface that would have shown it.
    private func runPurgeIfNeeded() {
        guard !didRunStartupPurge || scenePhase == .active else { return }
        didRunStartupPurge = true
        guard let repository = try? AppStore.repository() else { return }
        try? repository.purgeTombstones()
    }

    /// The delta toast sits just above the owned bar (and its raised circle):
    /// the bar's content height plus the circle's overhang and a margin.
    private static let toastBottomClearance: CGFloat = AppTabBar.contentHeight + 20
}

/// A `NavigationStack` that owns a typed `[Route]` path and registers the
/// single `navigationDestination(for: Route.self)` mapping for the whole stack.
struct RootedNavigationStack<Root: View>: View {
    @Binding var path: [Route]
    @ViewBuilder var root: () -> Root

    var body: some View {
        NavigationStack(path: $path) {
            root()
                .navigationDestination(for: Route.self) { DestinationView(route: $0) }
        }
    }
}

struct HomeTabView: View {
    @Binding var modal: ModalRoute?
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?
    @State private var didPresentDebugLaunch = false

    var body: some View {
        RootedNavigationStack(path: $path) {
            HomeRootView(presentSheet: { sheet = $0 })
        }
        .sheet(item: $sheet) { route in
            SheetDestinationView(route: route) { target in
                // The switcher's forward exits land on THIS tab's stack: close
                // the sheet, push the route (docs/SCREENMAP.md CarSwitcher).
                sheet = nil
                path = [target]
            }
        }
        .fullScreenCover(item: $modal) {
            ModalDestinationView(route: $0) {
                modal = nil
                sheet = .serviceEntry
            }
        }
        .onAppear(perform: presentDebugLaunch)
    }

    /// `-presentScreen <route>` / `-openManualForm`: DEBUG-only launch hook
    /// (DebugLaunch) so `simctl`-driven screenshots can reach sheet screens
    /// without a UI test tap. Compiled out of release builds.
    private func presentDebugLaunch() {
        #if DEBUG
        guard !didPresentDebugLaunch else { return }
        didPresentDebugLaunch = true
        let request = DebugLaunch.resolve()
        if let sheet = request.sheet {
            self.sheet = sheet
        } else if let route = request.route {
            path = [route]
        } else if let modal = request.modal {
            self.modal = modal
        }
        #endif
    }
}

struct TrendsTabView: View {
    @Binding var modal: ModalRoute?
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?

    var body: some View {
        RootedNavigationStack(path: $path) {
            TrendsRootView(presentSheet: { sheet = $0 })
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) {
            ModalDestinationView(route: $0) {
                modal = nil
                sheet = .serviceEntry
            }
        }
    }
}

struct GarageTabView: View {
    @Binding var modal: ModalRoute?
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?

    var body: some View {
        RootedNavigationStack(path: $path) {
            GarageRootView(onNavigate: { path = [$0] })
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) {
            ModalDestinationView(route: $0) {
                modal = nil
                sheet = .serviceEntry
            }
        }
    }
}

// MARK: - Delta toast

/// The informational "Consumption updated: 6.9 -> 6.8 L/100km" notice
/// (docs/ERRORS.md -> Edit entry, row 4). Rendered above the tab bar, tappable
/// -> Trends. Never rendered for an edit that moved nothing - the caller only
/// posts a message when a figure actually changed.
struct DeltaToast: View {
    let message: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.Palette.taillight)
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.Palette.dash)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.Palette.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("deltaToast")
    }
}
