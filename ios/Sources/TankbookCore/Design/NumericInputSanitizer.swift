import Foundation

/// Filters user-entered text at the binding so that only what a `.numberPad` or
/// `.decimalPad` could legitimately produce ever reaches the model (P2.15).
///
/// `keyboardType(.numberPad/.decimalPad)` is a *hint*, never a constraint: a
/// hardware keyboard, paste and dictation all bypass it, so a field gated only
/// by its keyboard type will happily hold `12a34`. That text then parses to
/// nil on save and the value is dropped with no error (hard rule 8). Filtering
/// at the binding means garbage never enters the field, so there is nothing to
/// discard and nothing to warn about (hard rule 7).
///
/// This is a pure string-in/string-out function and lives in core so the L1
/// suite can prove every rule; the app layer only applies it at each field.
public enum NumericInputSanitizer {

    /// The field kind. Integer fields keep digits only; decimal fields keep
    /// digits plus at most one decimal separator.
    public enum Kind {
        case integer
        case decimal
    }

    /// Sanitizes `text` for a field of `kind`.
    ///
    /// Integer (`"119 486 km"` -> `"119486"`): ASCII digits, plus the two
    /// DISPLAY grouping separators `OdometerFormat` writes into odometer fields
    /// on blur (no-break space U+00A0 and the legacy thin space U+2009). Those
    /// must survive the format-on-blur round trip, so they are kept; everything
    /// else - letters, signs, plain spaces, punctuation - is dropped, so a
    /// pasted mixed string keeps its usable digits instead of clearing the
    /// field. The parse side (`OdometerFormat.ungrouped`) strips the separator.
    ///
    /// Decimal: ASCII digits plus at most one decimal separator. Both `.` and
    /// `,` are accepted (a RU keypad produces a comma - the separator belongs
    /// to the device, not the country) and normalised to `.`, the pinned parse
    /// separator the codebase already uses (`ManualRate`, `ManualFillUpFormat`,
    /// `OdometerFormat`). A second separator is rejected, not appended:
    /// `"1,2,3"` -> `"1.23"`, `"1..2"` -> `"1.2"`.
    public static func sanitize(_ text: String, kind: Kind) -> String {
        switch kind {
        case .integer:
            return text.filter { Self.isIntegerCharacter($0) }
        case .decimal:
            return sanitizeDecimal(text)
        }
    }

    private static func isIntegerCharacter(_ character: Character) -> Bool {
        if character >= "0" && character <= "9" { return true }
        // The display grouping separators (see the doc comment above).
        if character == "\u{00A0}" || character == "\u{2009}" { return true }
        return false
    }

    private static func sanitizeDecimal(_ text: String) -> String {
        var seenSeparator = false
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if character >= "0" && character <= "9" {
                result.append(character)
            } else if character == "." || character == "," {
                // The first separator wins (normalised to the pinned dot); a
                // second is rejected, and the digits after it are kept.
                if !seenSeparator {
                    result.append(".")
                    seenSeparator = true
                }
            }
            // Every other character is dropped.
        }
        return result
    }
}
