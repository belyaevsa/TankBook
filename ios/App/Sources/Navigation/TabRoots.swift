import SwiftUI
import TankbookCore
#if canImport(UIKit)
import UIKit
#endif

/// The three tab roots (docs/SCREENMAP.md "Tab roots (no back)"): Log/Home,
/// Trends, Garage. Each tab owns its own `NavigationStack` path so switching
/// tabs preserves each tab's stack - a stated requirement, not an accident.
///
/// The delta toast (docs/ERRORS.md -> Edit entry, row 4) is owned here, above
/// the TabView: it must survive a navigation pop (the edit save dismisses back
/// to Home) and its "tap -> Trends" next step is a TAB switch, which only the
/// root can perform.
struct AppRootView: View {
    @State private var toastCenter = AppToastCenter()
    @State private var tabSelection: Int = 0

    init() {
        Self.applyNeutralTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $tabSelection) {
            HomeTabView()
                .tabItem { Label("Log", systemImage: "list.bullet") }
                .tag(0)
            TrendsTabView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)
            GarageTabView()
                .tabItem { Label("Garage", systemImage: "car") }
                .tag(2)
        }
        // The accent still propagates to CONTENT - entry markers, the capture
        // button, the cross-check lock. The tab bar itself is overridden below.
        .tint(Theme.Palette.taillight)
        .overlay(alignment: .bottom) {
            if let message = toastCenter.message {
                DeltaToast(message: message) {
                    toastCenter.dismiss()
                    tabSelection = 1   // Trends is the toast's next step
                }
                .padding(.bottom, Self.toastBottomClearance)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastCenter.message)
        .environment(toastCenter)
    }

    /// Clears the floating tab bar plus its float margin (the same geometry
    /// Home's bottom clearance accounts for) so the toast never covers the bar.
    private static let toastBottomClearance: CGFloat = 88

    /// The tab bar stays neutral: `ink` when selected, `inkSoft` when not.
    ///
    /// CLAUDE.md hard rule 5 and `docs/DESIGN.md`: "taillight is meaning, not
    /// chrome - navigation bars, backgrounds, and tab bars stay neutral; the
    /// accent appears on numbers, entry markers, the capture button, and the
    /// cross-check lock, nowhere else." A plain `.tint` on the `TabView` paints
    /// the selected tab item accent-red, which is precisely the chrome use the
    /// rule forbids - so the item colours are set explicitly here while `.tint`
    /// keeps doing its job for the content inside each tab.
    ///
    /// Values match the `HomeA` artboard: selected `#EAEDF2`, unselected
    /// `#98A2B3` (the dark-theme values of `ink` and `inkSoft`).
    private static func applyNeutralTabBarAppearance() {
        #if os(iOS)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let unselected = UIColor(Theme.Palette.inkSoft)
        let selected = UIColor(Theme.Palette.ink)
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = unselected
            layout.normal.titleTextAttributes = [.foregroundColor: unselected]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        #endif
    }
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
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?
    @State private var modal: ModalRoute?
    @State private var didPresentDebugLaunch = false

    var body: some View {
        RootedNavigationStack(path: $path) {
            HomeRootView(presentSheet: { sheet = $0 })
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) { ModalDestinationView(route: $0) }
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
        }
        #endif
    }
}

struct TrendsTabView: View {
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?
    @State private var modal: ModalRoute?

    var body: some View {
        RootedNavigationStack(path: $path) {
            TrendsRootView()
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) { ModalDestinationView(route: $0) }
    }
}

struct GarageTabView: View {
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?
    @State private var modal: ModalRoute?

    var body: some View {
        RootedNavigationStack(path: $path) {
            GarageRootView()
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) { ModalDestinationView(route: $0) }
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
