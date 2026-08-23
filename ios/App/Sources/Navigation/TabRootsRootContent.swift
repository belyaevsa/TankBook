import SwiftUI
import TankbookCore

// Tab-root content. Each root is a placeholder: a title plus the SCREENMAP
// navigation affordances that make its routes reachable. P1.2-P1.11 replace
// these bodies with real screens; the affordances (and their identifiers) stay.

struct HomeRootView: View {
    let presentSheet: (SheetRoute) -> Void

    var body: some View {
        List {
            Button {
                presentSheet(.confirmManual)
            } label: {
                Label("Type it", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("typeItButton")

            NavigationLink("Edit entry", value: Route.editEntry)
                .accessibilityIdentifier("editEntryButton")

            Button {
                presentSheet(.carSwitcher)
            } label: {
                Label("Select car", systemImage: "car")
            }
            .accessibilityIdentifier("carSwitcherButton")
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("settingsButton")
            }
        }
        .onAppear {
            // UI-test/screenshot hook: open the manual form directly at launch.
            if ProcessInfo.processInfo.arguments.contains("-openManualForm") {
                presentSheet(.confirmManual)
            }
        }
    }
}

struct TrendsRootView: View {
    var body: some View {
        Color.clear
            .background(Theme.Palette.midnight)
            .navigationTitle("Trends")
    }
}

struct GarageRootView: View {
    var body: some View {
        List {
            NavigationLink("Vehicle", value: Route.vehicleDetail)
                .accessibilityIdentifier("vehicleDetailButton")

            NavigationLink("Add car", value: Route.addVehicle)
                .accessibilityIdentifier("addVehicleButton")
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.midnight)
        .navigationTitle("Garage")
    }
}
