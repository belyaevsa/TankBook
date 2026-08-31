import Foundation

/// docs/DESIGN.md -> Accessibility floor: "Increase Contrast respected".
///
/// The app's palette is already WCAG AA (guarded by `PaletteAccentGuardTests`),
/// so Increase Contrast cannot change the text tokens. What it CAN change is
/// the decorative low-opacity chrome the user asked to see more clearly: the
/// 1px hairline card border (`Theme.Palette.hairline` = ink at 0.08 opacity) is
/// near-invisible on some displays, and it is exactly the kind of subtle
/// border "Increase Contrast" exists to fix. The raised value lives in core so
/// every surface that honours the setting reads the same number, and so the
/// number itself is unit-tested rather than eyeballed.
public enum ContrastPolicy {
    /// The standard hairline opacity (`Theme.Palette.hairline`).
    public static let standardHairlineOpacity: Double = 0.08

    /// The hairline border opacity, raised when the user has Increase Contrast
    /// on. The standard 0.08 is the generated token; 0.24 keeps the border a
    /// hairline (never a heavy rule) while making card edges legible.
    public static func hairlineOpacity(increasedContrast: Bool) -> Double {
        increasedContrast ? 0.24 : standardHairlineOpacity
    }
}
