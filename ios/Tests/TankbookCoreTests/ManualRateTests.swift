import Foundation
import Testing
@testable import TankbookCore

// P5.2b - the manual-rate input rules (docs/ERRORS.md -> Confirm, F9;
// docs/JOURNEYS.md F9; hard rule 13). The parse lives in core so a package
// test can reach it; the pair semantics are `Money.applyingManualRate` (P5.2a,
// the ONLY way a manual rate is written - never a hand-built snapshot fed to
// `converted(using:)`, which is fill-blanks-only).

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
}

private func decimal(_ string: String) -> Decimal {
    Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
}

@Suite("Manual rate input (P5.2b)")
struct ManualRateTests {

    /// A typed manual rate produces the documented pair: applied at the ENTRY's
    /// date, `rateSource == .manual`, `rateDate == the entry's date`. The entry
    /// is dated well in the past - NOT today - so a "today" implementation
    /// fails even though the test passes for the right reason's opposite.
    @Test("a typed manual rate produces the documented pair at the entry date")
    func manualRatePairIsDocumented() {
        let entryDay = day(2026, 3, 12)
        let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
        let manual = money.applyingManualRate(decimal("4.0"), on: entryDay)

        #expect(manual.homeAmount == decimal("72.38"))  // 289.50 / 4.0, rounded
        #expect(manual.rate == decimal("4.0"))
        #expect(manual.rateSource == .manual)
        #expect(manual.rateDate == entryDay,
                "rateDate must be the entry's date, never the fetch/today date")
        #expect(manual.rateDate != Date(),
                "a today-stamping implementation must fail on a past-dated entry")
    }

    /// A comma-decimal rate parses to the SAME `Decimal`, exactly: a Russian
    /// keypad produces `4,2706`, and a parse that only accepted "." would
    /// silently reject a correct rate.
    @Test("a comma-decimal rate and a dot-decimal rate yield the same Decimal")
    func commaDecimalParses() {
        let comma = ManualRate.parse("4,2706")
        let dot = ManualRate.parse("4.2706")
        #expect(comma != nil)
        #expect(comma == dot,
                "4,2706 and 4.2706 must parse to the identical Decimal")
        #expect(comma == decimal("4.2706"))
    }

    /// A rate of 0, a negative rate and unparseable text are REFUSED: the parse
    /// returns nil (the field offers nothing wrong), and `applyingManualRate`
    /// writes nothing - the money pair is byte-identical, so the entry simply
    /// stays rate-pending and nothing blocks Save (F9: conversion is metadata,
    /// never a save-blocker).
    @Test("a rate of zero, a negative rate and unparseable text are refused")
    func refusedRatesWriteNothing() {
        for bad in ["0", "0.0", "-3", "-4,5", "abc", "4.2706.123", "", "   "] {
            #expect(ManualRate.parse(bad) == nil, "'\(bad)' must be refused")
        }

        let entryDay = day(2026, 3, 12)
        let money = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
        let zero = money.applyingManualRate(0, on: entryDay)
        let negative = money.applyingManualRate(decimal("-3"), on: entryDay)
        #expect(zero == money, "a zero rate must write nothing")
        #expect(negative == money, "a negative rate must write nothing")
        #expect(zero.isRatePending, "a refused rate leaves the entry rate-pending")
    }

    /// The manual override is the ONE thing allowed to replace a written
    /// snapshot; a later feed pass must leave the user's number untouched
    /// (hard rule 13). This pins the S8 interaction at the pair level.
    @Test("a manual rate survives a later feed backfill")
    func manualRateSurvivesBackfill() {
        let entryDay = day(2026, 3, 12)
        let feed = Money(amount: decimal("289.50"), currency: .pln, homeCurrency: .eur)
            .converted(using: RateSnapshot(rate: decimal("4.2706"), rateDate: entryDay, source: .ecb))
        let manual = feed.applyingManualRate(decimal("4.0"), on: entryDay)

        let store = RateStore(seed: [
            ExchangeRate(base: .eur, quote: .pln, date: entryDay,
                         rate: decimal("4.2706"), source: .ecb)
        ], calendar: utcCalendar)
        let afterBackfill = store.convert(manual, on: entryDay)

        #expect(afterBackfill.rate == decimal("4.0"))
        #expect(afterBackfill.rateSource == .manual)
        #expect(afterBackfill.homeAmount == decimal("72.38"))
    }
}
