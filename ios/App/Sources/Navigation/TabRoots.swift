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
    @State private var tabSelection: AppTab
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

    init() {
        // `-selectTrendsTab`: land on the Trends tab at launch so simctl-driven
        // screenshots and UI tests can reach it without a tab tap (simctl cannot
        // tap). DEBUG/test-only.
        if ProcessInfo.processInfo.arguments.contains("-selectTrendsTab") {
            _tabSelection = State(initialValue: .trends)
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
            AppTabBar(selection: $tabSelection) {
                openCapture()
            }
        }
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
        .task { runPurgeIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { runPurgeIfNeeded() }
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
            GarageRootView()
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
