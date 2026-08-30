import Testing
@testable import TankbookCore

/// The binding-side numeric input filter (P2.15). `keyboardType` is a hint, not
/// a constraint - a hardware keyboard, paste and dictation all bypass it - so
/// these tests feed the sanitizer exactly what a numberPad/decimalPad would NOT
/// produce: `12a34`, `1..2`, `1,2,3`, `abc`, an empty paste, `119 486 km`. A
/// test that only feeds valid digits cannot see the defect.
@Suite("Numeric input sanitizer (P2.15)")
struct NumericInputSanitizerTests {

    // MARK: - Integer: digits only

    @Test("integer keeps digits and drops letters, signs and spaces")
    func integerKeepsOnlyDigits() {
        #expect(NumericInputSanitizer.sanitize("1234", kind: .integer) == "1234")
        #expect(NumericInputSanitizer.sanitize("12a34", kind: .integer) == "1234")
        #expect(NumericInputSanitizer.sanitize("abc", kind: .integer) == "")
        #expect(NumericInputSanitizer.sanitize("119 486 km", kind: .integer) == "119486")
        #expect(NumericInputSanitizer.sanitize("", kind: .integer) == "")
        #expect(NumericInputSanitizer.sanitize("-12", kind: .integer) == "12")
        #expect(NumericInputSanitizer.sanitize("1.5", kind: .integer) == "15")
    }

    @Test("integer preserves the odometer's display grouping separators")
    func integerPreservesDisplayGroupingSeparators() {
        // The no-break space OdometerFormat writes on blur, and the legacy thin
        // space, survive a format-on-blur round trip; plain spaces do not.
        #expect(NumericInputSanitizer.sanitize("119\u{00A0}486", kind: .integer) == "119\u{00A0}486")
        #expect(NumericInputSanitizer.sanitize("119\u{2009}486", kind: .integer) == "119\u{2009}486")
        #expect(NumericInputSanitizer.sanitize("119 486", kind: .integer) == "119486")
    }

    // MARK: - Decimal: digits plus at most one separator

    @Test("decimal keeps a lone dot and normalises a comma to a dot")
    func decimalKeepsASingleSeparator() {
        #expect(NumericInputSanitizer.sanitize("4.2706", kind: .decimal) == "4.2706")
        // The RU keypad's comma is accepted and normalised to the pinned dot.
        #expect(NumericInputSanitizer.sanitize("4,2706", kind: .decimal) == "4.2706")
        #expect(NumericInputSanitizer.sanitize("71.02", kind: .decimal) == "71.02")
    }

    @Test("decimal rejects a second separator rather than appending it")
    func decimalRejectsASecondSeparator() {
        #expect(NumericInputSanitizer.sanitize("1..2", kind: .decimal) == "1.2")
        #expect(NumericInputSanitizer.sanitize("1,2,3", kind: .decimal) == "1.23")
        #expect(NumericInputSanitizer.sanitize("1.2.3", kind: .decimal) == "1.23")
        #expect(NumericInputSanitizer.sanitize("1,2.3", kind: .decimal) == "1.23")
    }

    @Test("decimal drops letters and keeps the digits of a mixed paste")
    func decimalKeepsUsableDigits() {
        #expect(NumericInputSanitizer.sanitize("12a34", kind: .decimal) == "1234")
        #expect(NumericInputSanitizer.sanitize("119 486 km", kind: .decimal) == "119486")
        #expect(NumericInputSanitizer.sanitize("abc", kind: .decimal) == "")
        #expect(NumericInputSanitizer.sanitize("", kind: .decimal) == "")
        #expect(NumericInputSanitizer.sanitize("42.30 L", kind: .decimal) == "42.30")
    }

    @Test("decimal keeps a leading or trailing separator")
    func decimalKeepsEdgeSeparators() {
        #expect(NumericInputSanitizer.sanitize(".5", kind: .decimal) == ".5")
        #expect(NumericInputSanitizer.sanitize("5.", kind: .decimal) == "5.")
        #expect(NumericInputSanitizer.sanitize(",5", kind: .decimal) == ".5")
    }
}
