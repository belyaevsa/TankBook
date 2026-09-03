import SwiftUI
import TankbookCore

// Tab-root content. Each root is a placeholder: a title plus the SCREENMAP
// navigation affordances that make its routes reachable. P1.2-P1.11 replace
// these bodies with real screens; the affordances (and their identifiers) stay.

struct HomeRootView: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        // The three tab roots share ONE header treatment (RV.21): each draws
        // its own one-row header - title + gear on the same line, docs/DESIGN.md
        // - via the shared `TabRootHeader`, so the navigation bar is hidden
        // rather than stacked above it.
        HomeView(presentSheet: presentSheet)
            .navigationTitle("Log")
            .toolbar(.hidden, for: .navigationBar)
    }
}

struct TrendsRootView: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        TrendsView(presentSheet: presentSheet)
            .navigationTitle("Trends")
            .toolbar(.hidden, for: .navigationBar)
    }
}

struct GarageRootView: View {
    /// Pushes a route onto the Garage tab's own NavigationStack path (the
    /// "Add car" tile and the limit sheet's exits - Button-driven pushes).
    let onNavigate: (Route) -> Void
    /// Presents a sheet on the Garage tab (the sync chip's "Sign in" door).
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        GarageView(onNavigate: onNavigate, presentSheet: presentSheet)
            .navigationTitle("Garage")
            .toolbar(.hidden, for: .navigationBar)
    }
}
