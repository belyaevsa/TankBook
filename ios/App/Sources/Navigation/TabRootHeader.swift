import SwiftUI
import TankbookCore

/// The ONE header treatment shared by the three tab roots (RV.21). Log/Home,
/// Trends and Garage are peer tab roots with no back button
/// (docs/SCREENMAP.md "Tab roots (no back)"), so each draws the same row: the
/// screen's `.largeTitle.bold()` title on the left and the Settings gear on the
/// same line on the right (docs/DESIGN.md -> "The tab-root header is ONE row", now
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
    /// Presents the sign-in sheet (the sync chip's signed-out destination). The
    /// three roots each pass their own `presentSheet(.signIn)`, so the chip's
    /// one tap is the same door the Settings guest card already uses.
    var onSignIn: (() -> Void)? = nil

    /// Whether this header's tab is the one on screen (`AppRootView` sets it).
    /// The three tab roots all stay mounted - their stacks and scroll positions
    /// survive a tab switch - and an inactive root's content is still visible to
    /// XCUITest element queries (opacity + `accessibilityHidden` do not remove
    /// it, documented in CarSwitcherUITests). So without this gate every tab's
    /// gear and sync chip would exist in the query tree at once:
    /// `app.buttons["settingsButton"]` stops resolving to a single match, and
    /// VoiceOver would announce three Settings buttons for one screen. Only the
    /// active root renders its gear and chip.
    @Environment(\.isTabRootActive) private var isActive

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.Palette.ink)
                .accessibilityIdentifier(titleIdentifier)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if isActive {
                syncChip
                settingsLink
            }
        }
        .padding(.top, 4)
    }

    /// The sync state chip (RV.22), to the LEFT of the gear so the two read as
    /// "account state + its settings" on one row (docs/SYNC.md -> "The sync
    /// state chip"). Shared by the three roots exactly like the gear.
    @ViewBuilder
    private var syncChip: some View {
        if let onSignIn {
            SyncStateChip(onSignIn: onSignIn)
        }
    }

    private var settingsLink: some View {
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
}

/// Whether the enclosing tab root is the active tab (see `TabRootHeader`).
/// Defaults to `true` so a header rendered outside the three-tab shell (a
/// preview, a future surface) always shows its gear.
private struct TabRootActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var isTabRootActive: Bool {
        get { self[TabRootActiveKey.self] }
        set { self[TabRootActiveKey.self] = newValue }
    }
}
