import Testing
import Foundation
@testable import TankbookCore

/// The odometer display formatter (HANDOVER.md open item 0): thin-space
/// thousands grouping, pinned to en_US_POSIX, asserted on the EXACT string -
/// "contains a space" would not distinguish the thin space from the decimal
/// separator the formatter is deliberately hiding.
struct OdometerFormatTests {

    @Test func groupsAtFourDigits() {
        #expect(OdometerFormat.grouped(1000) == "1\u{2009}000")
    }

    @Test func groupsAtFiveDigits() {
        #expect(OdometerFormat.grouped(119_486) == "119\u{2009}486")
        #expect(OdometerFormat.grouped(48_000) == "48\u{2009}000")
    }

    @Test func groupsAtSixDigits() {
        #expect(OdometerFormat.grouped(123_456) == "123\u{2009}456")
    }

    @Test func groupsAtSevenDigits() {
        #expect(OdometerFormat.grouped(1_234_567) == "1\u{2009}234\u{2009}567")
    }

    @Test func doesNotGroupBelowOneThousand() {
        #expect(OdometerFormat.grouped(999) == "999")
        #expect(OdometerFormat.grouped(0) == "0")
    }

    @Test func groupsNegativeValues() {
        #expect(OdometerFormat.grouped(-12_000) == "-12\u{2009}000")
        #expect(OdometerFormat.grouped(-1000) == "-1\u{2009}000")
    }

    @Test func separatorIsThinSpaceNotCommaOrRegularSpace() {
        // The exact assertion: U+2009 (thin space), not the comma en_US would
        // print and not a regular space that would double-space the odometer.
        let grouped = OdometerFormat.grouped(119_486)
        #expect(grouped == "119\u{2009}486")
        #expect(grouped.contains("\u{2009}"))
        #expect(!grouped.contains(","))
        #expect(!grouped.contains(" "))
    }

    @Test func ungroupedStripsThinSpaceForTyping() {
        #expect(OdometerFormat.ungrouped("119\u{2009}486") == "119486")
        #expect(OdometerFormat.ungrouped("1\u{2009}234\u{2009}567") == "1234567")
        // Plain digits pass through untouched - the format-on-blur round trip.
        #expect(OdometerFormat.ungrouped("119486") == "119486")
    }
}
