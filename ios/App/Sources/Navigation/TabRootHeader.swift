import SwiftUI
import TankbookCore

/// The ONE header treatment shared by the three tab roots (RV.21). Log/Home,
/// Trends and Garage are peer tab roots with no back button
/// (docs/SCREENMAP.md "Tab roots (no back)"), so each draws the same row: the
/// screen's `.largeTitle.bold()` title on the left and the Settings gear on the
/// same line on the right (docs/DESIGN.md -> "The Home header is ONE row", now
/// the shared tab-root header). The gear is `taillight` on `dash` with a 44 pt
/// hit circle, in the identical place on every root - reachability and
/// consistency are one fix.
///
/// A custom row, never `.navigationTitle` + `.toolbar`: SwiftUI's large-title
/// layout puts toolbar items on the bar ABOVE the title by construction - the
/// stacked two-row chrome the design doc rejects - and a half-migration (one
/// root drawing its own header, another a system bar) reads as a bug rather
/// than a difference. The host view hides the navigation bar (`.toolbar(.hidden,
/// for: .navigationBar)`) and draws this header as the first scroll row.
struct TabRootHeader: View {
    /// The tab's title - a catalog key ("Log" / "Trends" / "Garage").
    let title: LocalizedStringKey
    /// The title's accessibility identifier. Each root names its own so a test
    /// can tell WHICH tab root is on screen: with the navigation bar hidden the
    /// root exposes no `navigationBars["X"]` element to assert against.
    let titleIdentifier: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier(titleIdentifier)
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
}
