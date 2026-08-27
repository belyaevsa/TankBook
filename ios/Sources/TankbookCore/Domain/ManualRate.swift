import Foundation

/// Parses a user-typed exchange rate for the manual-rate entry (docs/ERRORS.md
/// -> Confirm, F9; docs/JOURNEYS.md F9; hard rule 13 - the user may set a
/// manual rate per entry).
///
/// Accepts the device's own decimal separator: a Russian keypad produces
/// `4,2706`, and a parse that only accepted "." would silently reject a correct
/// rate. Both separators yield the identical `Decimal`.
///
/// A rate of 0, a negative rate, or text that does not parse is REFUSED
/// (returns nil): the manual rate is a default input, never a gate (F9), and a
/// refused rate leaves the entry rate-pending and never blocks Save.
public enum ManualRate {
    public static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Normalise the comma to a dot, then parse with a pinned locale, so the
        // result is identical whatever the device region (the same discipline
        // as `ManualFillUpFormat`).
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        // The string must be a bare decimal - ASCII digits plus at most one
        // separator. `Decimal(string:)` is lenient about trailing garbage
        // ("4.2706.123" parses as 4.2706, a typo silently turning into a
        // different rate), so the shape is checked first.
        guard normalized.allSatisfy({ ($0 >= "0" && $0 <= "9") || $0 == "." }),
              normalized.filter({ $0 == "." }).count <= 1,
              normalized.contains(where: { $0 >= "0" && $0 <= "9" }) else { return nil }
        guard let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }
}
