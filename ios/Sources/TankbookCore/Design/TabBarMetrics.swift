import CoreGraphics

/// The owned tab bar's geometry, as arithmetic rather than as a view.
///
/// It lives in the core for one reason: `AppTabBar` is in the app target, which
/// the package test suite cannot import and a UI test cannot call into. A
/// constant that is only ever "verified by looking at one device" is exactly the
/// kind of thing this project keeps getting caught by, so the decision moves
/// here and the view stays thin over it - the same split as `ServiceEntryDraft`,
/// `PumpPhotoGate` and `TireMileage`.
///
/// The values are the artboard's (`design/screens/HomeA.dc.html`,
/// `padding: 10px 12px 28px`), and they are design tokens, not measurements read
/// off a runtime.
public enum TabBarMetrics {
    public static let topPadding: CGFloat = 10
    public static let horizontalPadding: CGFloat = 12
    public static let captureSize: CGFloat = 56

    /// The artboard's bottom padding.
    ///
    /// **It is not a safe-area inset and must never be added on top of one.**
    /// The artboard is a browser page with no home indicator, so those 28 px ARE
    /// the designer's allowance for it. The bar is drawn through
    /// `safeAreaInset(edge: .bottom)`, which supplies the real inset (~34 pt on
    /// an indicator device); adding both left ~62 pt of dead space below the
    /// labels against the artboard's 28. That was the P3.7 bug.
    public static let artboardBottomPadding: CGFloat = 28

    /// The floor kept once the safe area already exceeds the artboard's
    /// allowance: the labels sit this far above the home indicator rather than
    /// touching it, which is the opposite mistake.
    ///
    /// It cannot go below 0. The remaining ~34 pt belongs to the system - the
    /// swipe-to-home band and the indicator pill both live there, so a control
    /// placed inside it is intercepted and drawn over.
    public static let minBottomPadding: CGFloat = 2

    /// Spend the artboard's allowance **through** the safe area, never on top of
    /// it: 28 pt on a device with no home indicator (an SE - the artboard's
    /// exact figure), the floor on a device with one.
    public static func bottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        max(minBottomPadding, artboardBottomPadding - safeAreaBottom)
    }

    /// The bar's layout height above the home-indicator safe area: top padding +
    /// the capture circle (the tallest slot) + the bottom padding for this
    /// device. Anything that must clear the bar measures from this.
    public static func contentHeight(safeAreaBottom: CGFloat) -> CGFloat {
        topPadding + captureSize + bottomPadding(safeAreaBottom: safeAreaBottom)
    }

    /// The conservative height, for the fixed clearances that cannot read a live
    /// inset (the delta toast). Deliberately the **larger** of the two, so a
    /// clearance computed from it can only ever be too generous.
    public static let maximumContentHeight: CGFloat =
        topPadding + captureSize + artboardBottomPadding
}
