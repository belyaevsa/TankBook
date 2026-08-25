import Foundation

/// DISPLAY formatting for odometer figures: no-break-space thousands grouping,
/// rendering what the artboards spell as `119&thinsp;486 km`
/// (`AddVehicle.dc.html`). Shared
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
    /// `-12000` -> `-12 000`, `0` -> `0`. The group separator is a **no-break
    /// space (U+00A0)**, not a comma and not a plain space.
    public static func grouped(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// Removes every group separator, so a grouped value can be parsed back
    /// into a `TextField` (format-on-blur round trip). U+2009 is stripped too:
    /// it was the separator until 2026-08-25, and a field still holding one
    /// must not become unparseable.
    public static func ungrouped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{2009}", with: "")
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        // Never "119,486" (en_US) or "119.486" (de_DE) - the figure is a
        // number, not a locale quiz.
        //
        // WHY NOT the thin space (U+2009) this used to be, 2026-08-25: the
        // odometer renders in **DIN Alternate Bold**, and that font has no
        // glyph for U+2009. CoreText is unambiguous - for DINAlternate-Bold,
        // `CTFontGetGlyphsForCharacters` returns false for U+2009, U+202F,
        // U+2007 and U+2008, and true for U+00A0 and U+0020 with an advance of
        // 3.596 at 15 pt (0.24 em - thin-space proportions, which is why this
        // matches the artboard rather than compromising with it). The missing
        // glyph rendered as nothing, so every DIN-rendered odometer in the app
        // printed "118930" while `OdometerFormatTests` stayed green asserting
        // the exact U+2009 string. A formatter test cannot see a missing glyph;
        // `separatorHasAGlyphInTheDisplayFont` below is the check that can.
        formatter.groupingSeparator = "\u{00A0}"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
