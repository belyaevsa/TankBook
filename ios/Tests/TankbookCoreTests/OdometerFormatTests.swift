import Testing
import Foundation
#if canImport(CoreText)
import CoreText
#endif
@testable import TankbookCore

/// The odometer display formatter (HANDOVER.md open item 0): no-break-space
/// thousands grouping, pinned to en_US_POSIX, asserted on the EXACT string -
/// "contains a space" would not distinguish the separator from the decimal
/// separator the formatter is deliberately hiding.
///
/// These assertions were **green for the whole of P1 while the app rendered no
/// separator at all**: the separator was U+2009, and DIN Alternate Bold - the
/// font every odometer renders in - has no glyph for it. A string test cannot
/// see a missing glyph, which is why `separatorHasAGlyphInTheDisplayFont`
/// exists below. Any future change to the separator must keep that test
/// passing, or the pixels will disagree with the string again.
struct OdometerFormatTests {

    @Test func groupsAtFourDigits() {
        #expect(OdometerFormat.grouped(1000) == "1\u{00A0}000")
    }

    @Test func groupsAtFiveDigits() {
        #expect(OdometerFormat.grouped(119_486) == "119\u{00A0}486")
        #expect(OdometerFormat.grouped(48_000) == "48\u{00A0}000")
    }

    @Test func groupsAtSixDigits() {
        #expect(OdometerFormat.grouped(123_456) == "123\u{00A0}456")
    }

    @Test func groupsAtSevenDigits() {
        #expect(OdometerFormat.grouped(1_234_567) == "1\u{00A0}234\u{00A0}567")
    }

    @Test func doesNotGroupBelowOneThousand() {
        #expect(OdometerFormat.grouped(999) == "999")
        #expect(OdometerFormat.grouped(0) == "0")
    }

    @Test func groupsNegativeValues() {
        #expect(OdometerFormat.grouped(-12_000) == "-12\u{00A0}000")
        #expect(OdometerFormat.grouped(-1000) == "-1\u{00A0}000")
    }

    @Test func separatorIsNoBreakSpaceNotCommaOrPlainSpace() {
        // The exact assertion: U+00A0, not the comma en_US would print and not
        // a plain space, which would let the figure break across lines.
        let grouped = OdometerFormat.grouped(119_486)
        #expect(grouped == "119\u{00A0}486")
        #expect(grouped.contains("\u{00A0}"))
        #expect(!grouped.contains(","))
        #expect(!grouped.contains(" "))
    }

    @Test func ungroupedStripsTheSeparatorForTyping() {
        #expect(OdometerFormat.ungrouped("119\u{00A0}486") == "119486")
        #expect(OdometerFormat.ungrouped("1\u{00A0}234\u{00A0}567") == "1234567")
        // Plain digits pass through untouched - the format-on-blur round trip.
        #expect(OdometerFormat.ungrouped("119486") == "119486")
        // A field still holding the old thin space stays parseable.
        #expect(OdometerFormat.ungrouped("119\u{2009}486") == "119486")
    }

    /// The check the string assertions above could never make, and the reason
    /// the app rendered "118930" for the whole of P1 with a green suite: the
    /// separator must be a character the **display font can actually draw**.
    /// DIN Alternate Bold has no glyph for U+2009, U+202F, U+2007 or U+2008,
    /// so those render as nothing at all.
    ///
    /// Skipped rather than failed when the font is unavailable (a CI image
    /// without DIN installed) - a font-availability failure would be noise,
    /// while the assertion itself is exact wherever the font exists.
    @Test func separatorHasAGlyphInTheDisplayFont() throws {
        let fontName = "DINAlternate-Bold"
        let font = CTFontCreateWithName(fontName as CFString, 15, nil)
        let resolved = CTFontCopyPostScriptName(font) as String
        try #require(resolved == fontName,
                     "DIN Alternate is not installed here; the glyph assertion cannot run")

        let separator = OdometerFormat.grouped(119_486)
            .unicodeScalars
            .first { !CharacterSet.decimalDigits.contains($0) }
        let scalar = try #require(separator, "the grouped figure must contain a separator")

        var characters: [UniChar] = Array(String(scalar).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let hasGlyph = CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
        let codePoint = String(scalar.value, radix: 16, uppercase: true)
        #expect(hasGlyph, Comment(rawValue: "U+\(codePoint) has no glyph in \(fontName) - it will "
                                  + "render as nothing, exactly as U+2009 did through P1"))

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advance, glyphs.count)
        #expect(advance.width > 1, "the separator must occupy visible width, not collapse to zero")
    }
}
