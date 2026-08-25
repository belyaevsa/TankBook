import CoreGraphics
import Testing
@testable import TankbookCore

/// P3.7: the tab bar double-counted the home indicator.
///
/// `AppTabBar.bottomPadding` was the artboard's 28 pt, and the bar is drawn
/// through `safeAreaInset(edge: .bottom)`, which supplies the real inset on top
/// of it - about 62 pt of dead space below the labels against the artboard's 28.
///
/// These assertions inject the inset rather than reading one off a runtime,
/// which is the whole point: the arithmetic must be checkable on every device
/// the app supports, including the ones nobody has booted lately.
@Suite("Tab bar metrics (P3.7)")
struct TabBarMetricsTests {

    /// A device with no home indicator (an SE) gets the artboard's exact figure.
    /// This is the direction that catches a "fix" which simply hardcodes a small
    /// number: 28 is not a magic constant, it is what the design says when
    /// nothing else is claiming the space.
    @Test("no home indicator renders the artboard's exact 28 pt")
    func noIndicatorMatchesTheArtboard() {
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 0) == 28)
    }

    /// A device with an indicator spends the allowance THROUGH the inset and
    /// lands on the floor - never 28 + 34.
    @Test("an indicator device spends the allowance through the inset")
    func indicatorDeviceLandsOnTheFloor() {
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 34) == 2)
        // Total space below the labels is padding + inset: 36, not 62.
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 34) + 34 == 36)
    }

    /// The in-between case, which is the one a `max` can silently break: an
    /// inset smaller than the allowance must consume it partially, not fall
    /// straight to the floor.
    @Test("a partial inset consumes the allowance proportionally")
    func partialInsetConsumesTheAllowance() {
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 20) == 8)
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 26) == 2)
    }

    /// The floor never yields, however large the inset claims to be - a negative
    /// padding would put the labels inside the swipe-to-home band, where taps
    /// are intercepted and the indicator pill is drawn over them.
    @Test("the floor holds against an oversized inset")
    func theFloorHolds() {
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 60) == TabBarMetrics.minBottomPadding)
        #expect(TabBarMetrics.bottomPadding(safeAreaBottom: 200) >= 0)
    }

    /// The height the bar reports must move with the device, and the fixed
    /// clearance used where no inset is available must be the conservative one -
    /// too generous is a gap, too small is a control hidden under the bar.
    @Test("content height follows the device, and the fixed clearance is the larger")
    func contentHeightFollowsTheDevice() {
        #expect(TabBarMetrics.contentHeight(safeAreaBottom: 0) == CGFloat(94))
        #expect(TabBarMetrics.contentHeight(safeAreaBottom: 34) == CGFloat(68))
        #expect(TabBarMetrics.maximumContentHeight
                >= TabBarMetrics.contentHeight(safeAreaBottom: 34))
        #expect(TabBarMetrics.maximumContentHeight
                == TabBarMetrics.contentHeight(safeAreaBottom: 0))
    }
}
