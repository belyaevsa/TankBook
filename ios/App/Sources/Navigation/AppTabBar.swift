import SwiftUI
import UIKit
import TankbookCore

/// The three destination tabs. Capture is deliberately absent: it is a button
/// on the bar, never a destination (docs/SCREENMAP.md). Tags are named, not
/// numbered - an earlier refactor renumbered Trends and Garage by inserting
/// Capture between Log and Trends and silently broke tab switching.
enum AppTab: Int, CaseIterable, Identifiable {
    case log = 0
    case trends = 1
    case garage = 2

    var id: Int { rawValue }

    var icon: String {
        switch self {
        case .log: "list.bullet"
        case .trends: "chart.line.uptrend.xyaxis"
        case .garage: "car"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .log: "Log"
        case .trends: "Trends"
        case .garage: "Garage"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .log: "tabbar.log"
        case .trends: "tabbar.trends"
        case .garage: "tabbar.garage"
        }
    }
}

/// The owned tab bar (docs/DESIGN.md, design/screens/HomeA.dc.html) - Log ·
/// Capture · Trends · Garage, with Capture a raised `taillight` circle in the
/// centre.
///
/// The system `TabView` bar is hidden (`.toolbar(.hidden, for: .tabBar)`) and
/// this bar is drawn over it via `safeAreaInset(edge: .bottom)`. Two earlier
/// attempts are the reason it exists: overlaying a circle on the system bar
/// failed because iOS 26 renders the bar as a floating pill that is not a
/// findable `UITabBar`, and making Capture a real `.tabItem` renders its glyph
/// as a template - the filled circle, shadow and 22pt raise are all
/// unattainable. Owning the bar also switches off the whole iOS 26 behaviour
/// set (floating pill, scroll-edge effects, `tabBarMinimizeBehavior`), so it is
/// static and identical on iOS 18 and iOS 26.
///
/// `TabView(selection:)` is kept as the state engine: it preserves each tab's
/// `NavigationStack` for free (a save dismisses back to Log and its stack must
/// survive). Capture is never a destination - tapping it presents the Capture
/// cover and the selection does not move.
struct AppTabBar: View {
    /// The `TabView` selection the bar drives. Capture is not a tag.
    @Binding var selection: AppTab
    /// RV.31: fires only when the tap lands on the ALREADY-selected tab. A tap
    /// that changes tabs never fires it - the host pops that tab's own
    /// `NavigationStack` path to its root (the standard iOS re-tap convention).
    let onReselectTab: (AppTab) -> Void
    /// Presents `ModalRoute.capture` via the app's existing full-screen cover.
    let onCapture: () -> Void
    /// The live home-indicator inset, so the bar can spend the artboard's
    /// allowance through it instead of stacking on top of it (P3.7).
    ///
    /// Read from the key window rather than a `GeometryReader`: the bar is drawn
    /// INSIDE `safeAreaInset(edge: .bottom)`, so a proxy here reports the safe
    /// area it has already been given - zero - which is precisely the value that
    /// would reproduce the bug. SwiftUI has no environment key for this.
    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    // The geometry lives in `TankbookCore.TabBarMetrics`, not here: a view in
    // the app target cannot be reached by the package tests, and a constant
    // "verified by looking at one device" is how the double-counted inset
    // survived P1 and P2 in the first place (P3.7). This view stays thin over
    // the arithmetic.
    private static let topPadding = TabBarMetrics.topPadding
    private static let horizontalPadding = TabBarMetrics.horizontalPadding
    private static let captureSize = TabBarMetrics.captureSize

    // EXPERIMENT 2026-08-25, kept: 0 aligns the capture button with the other
    // three slots. The artboard raises it 22 pt, which reads as unaligned next
    // to Log/Trends/Garage and collides with a screen's own save CTA.
    private static let captureRise: CGFloat = 0

    static func bottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        TabBarMetrics.bottomPadding(safeAreaBottom: safeAreaBottom)
    }

    /// The bar's layout height for a given device.
    static func contentHeight(safeAreaBottom: CGFloat) -> CGFloat {
        TabBarMetrics.contentHeight(safeAreaBottom: safeAreaBottom)
    }

    /// The conservative height, for clearances that cannot read a live inset.
    static let contentHeight: CGFloat = TabBarMetrics.maximumContentHeight

    /// The bottom clearance scroll content needs so its last row clears the
    /// raised capture circle. `safeAreaInset` insets the content by the bar's
    /// layout height, but the circle is drawn `captureRise` above its slot and
    /// the bar's background extends over the home indicator - neither is part of
    /// that inset, so the circle would otherwise sit over the last row. Sized
    /// to that overhang plus a margin, and kept honest by the L4 "last row
    /// clears the tab bar" assertion.
    static let contentBottomClearance: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            tabSlot(.log)
            captureSlot
            tabSlot(.trends)
            tabSlot(.garage)
        }
        .padding(.top, Self.topPadding)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.bottom, Self.bottomPadding(safeAreaBottom: safeAreaBottom))
        // Fill AND hairline both live in the BACKGROUND, never an overlay. An
        // `.overlay(alignment: .top)` paints above every child of the row, so
        // the hairline drew a line straight across the raised capture circle.
        // The artboard has the circle as a child of the bar with a negative top
        // margin, so it sits over the border - matching that means the border
        // belongs underneath.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Theme.Palette.tabBar.ignoresSafeArea(edges: .bottom)
                Rectangle()
                    .fill(Theme.Palette.tabBarBorder)
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabbar")
    }

    // MARK: - Destination slots

    /// A destination (Log / Trends / Garage). A real button, never a tab: there
    /// is no public SwiftUI "is tab" trait, so the active destination carries
    /// `.isSelected` instead - what custom bars ship with.
    private func tabSlot(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            if selection == tab {
                // RV.31: a re-tap of the active tab is a "return to root"
                // request, NOT a no-op. The host owns the paths, so the pop (and
                // its discard guard) lives there, never in this bar.
                onReselectTab(tab)
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                Text(tab.label)
                    // The artboard freezes labels at 10px; that fails
                    // accessibility review, so a Dynamic Type-capable font is
                    // capped (docs/DESIGN.md -> owned bar deviation). The bar
                    // grows vertically rather than wrapping.
                    .font(.caption2.weight(isSelected ? .bold : .semibold))
                    .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .dynamicTypeSize(.small ... .accessibility1)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    // MARK: - Capture

    /// The raised centre button. A child of the bar row (not an overlay), so its
    /// 56pt hit target sits at the raised position; the bar reserves headroom
    /// with top padding rather than clipping it. Unlabelled visually - the label
    /// lives in the accessibility label, localized through the String Catalog.
    private var captureSlot: some View {
        Button(action: onCapture) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.taillight)
                // The target glyph: two concentric strokes/fills
                // (design/screens/HomeA.dc.html). Ink is near-white on the
                // taillight disc, the same convention as the Capture shutter.
                Circle()
                    .stroke(Theme.Palette.ink, lineWidth: 2)
                    .frame(width: 17, height: 17)
                Circle()
                    .fill(Theme.Palette.ink)
                    .frame(width: 6, height: 6)
            }
            .frame(width: Self.captureSize, height: Self.captureSize)
            .shadow(color: Theme.Palette.taillight.opacity(0.35), radius: 16, y: 4)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(y: -Self.captureRise)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Capture")
        .accessibilityIdentifier("captureButton")
    }
}
