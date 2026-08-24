import SwiftUI
import TankbookCore

// Tab-root content. Each root is a placeholder: a title plus the SCREENMAP
// navigation affordances that make its routes reachable. P1.2-P1.11 replace
// these bodies with real screens; the affordances (and their identifiers) stay.

struct HomeRootView: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        // Home draws its own one-row header (title + gear on the same line,
        // docs/DESIGN.md), so the navigation bar is hidden rather than stacked
        // above it. The other tab roots keep the standard large title.
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
    }
}

struct GarageRootView: View {
    var body: some View {
        List {
            NavigationLink("Vehicle", value: Route.vehicleDetail(nil))
                .accessibilityIdentifier("vehicleDetailButton")

            NavigationLink("Add car", value: Route.addVehicle)
                .accessibilityIdentifier("addVehicleButton")
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
        .navigationTitle("Garage")
    }
}
