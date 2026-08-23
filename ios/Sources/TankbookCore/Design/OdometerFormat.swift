import Foundation

/// DISPLAY formatting for odometer figures: thin-space thousands grouping, as
/// the artboards spell it (`119&thinsp;486 km` in `AddVehicle.dc.html`). Shared
/// by Home, Add car and the manual form so the same figure renders identically
/// everywhere (HANDOVER.md open item 0).
///
/// Two non-negotiables learned in P1.3 (HANDOVER.md):
/// - Grouping belongs in DISPLAY only, never in a TextField being typed into.
///   Format read-only labels, and format-on-blur for fields - a grouped
///   TextField is unpleasant to type into, so the raw digits stay in the field
///   while it is focused and only the blurred, read-only figure is grouped.
/// - The locale is pinned to `en_US_POSIX`, exactly as `ManualFillUpFormat`
///   does: left to `Locale.current`, typed text (raw digits) and formatted text
///   (the device's separator) disagreed on one card. Presentation-level
///   localisation of numerals is P5's job and must change both sides together.
public enum OdometerFormat {
    /// Formats an odometer reading: `119486` -> `119 486`, `999` -> `999`,
    /// `-12000` -> `-12 000`, `0` -> `0`. The group separator is a thin space
    /// (U+2009), not a comma or a regular space.
    public static func grouped(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Removes every thin-space group separator, so a grouped value can be
    /// parsed back into a `TextField` (format-on-blur round trip).
    public static func ungrouped(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{2009}", with: "")
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        // The artboard's thin space: "119 486 km", never "119,486" (en_US) or
        // "119.486" (de_DE) - the figure is a number, not a locale quiz.
        formatter.groupingSeparator = "\u{2009}"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
