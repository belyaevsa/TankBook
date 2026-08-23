import SwiftUI
import TankbookCore
#if canImport(UIKit)
import UIKit
#endif

/// The three tab roots (docs/SCREENMAP.md "Tab roots (no back)"): Log/Home,
/// Trends, Garage. Each tab owns its own `NavigationStack` path so switching
/// tabs preserves each tab's stack - a stated requirement, not an accident.
struct AppRootView: View {
    init() {
        Self.applyNeutralTabBarAppearance()
    }

    var body: some View {
        TabView {
            HomeTabView()
                .tabItem { Label("Log", systemImage: "list.bullet") }
            TrendsTabView()
                .tabItem { Label("Trends", systemImage: "chart.line.uptrend.xyaxis") }
            GarageTabView()
                .tabItem { Label("Garage", systemImage: "car") }
        }
        // The accent still propagates to CONTENT - entry markers, the capture
        // button, the cross-check lock. The tab bar itself is overridden below.
        .tint(Theme.Palette.taillight)
    }

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

    var body: some View {
        RootedNavigationStack(path: $path) {
            HomeRootView(presentSheet: { sheet = $0 })
        }
        .sheet(item: $sheet) { SheetDestinationView(route: $0) }
        .fullScreenCover(item: $modal) { ModalDestinationView(route: $0) }
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
