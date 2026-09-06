import Testing
import Foundation
@testable import TankbookCore

/// RV.89 - the dated-entry surfaces must say WHICH year an entry is in.
/// `EntryDateText` is the one formatter behind the Log rows, the flagged list,
/// Recently deleted, Trends and the month dividers, and its year rule is:
/// never print a year for a date in the current calendar year, print the
/// locale's own TWO-DIGIT year otherwise. Every test here freezes `now` - a
/// test that calls `Date()` can only ever exercise the current-year branch and
/// lets a year bug survive for a year at a time.
struct EntryDateTextTests {

    /// A fixed UTC Gregorian calendar so month/year boundaries are
    /// deterministic no matter what machine (or time zone) the suite runs on.
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func enUS() -> Locale { Locale(identifier: "en_US") }

    // MARK: - The current-year branch renders no year

    @Test func currentYearDateRendersWithoutAYear() {
        // Frozen clock: mid-June 2026. The 14th is inside the same calendar
        // year, so the row shows month + day and nothing else.
        let now = Self.date(2026, 6, 15)
        #expect(EntryDateText.dayMonth(Self.date(2026, 6, 14), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Jun 14")
    }

    @Test func currentYearDateNeverCarriesATwoOrFourDigitYear() {
        // Assert the WHOLE rendered string, never a "contains no year digit"
        // check - the day of the month itself can be "24" or "26", so a
        // substring test would trip on a date that happens to fall on the
        // 24th/26th without any year being present.
        let now = Self.date(2026, 6, 15)
        #expect(EntryDateText.dayMonth(Self.date(2026, 6, 14), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Jun 14")
    }

    // MARK: - Any other year renders the two-digit year

    @Test func otherYearRendersExactlyTwoDigitYear() {
        let now = Self.date(2026, 6, 15)
        #expect(EntryDateText.dayMonth(Self.date(2015, 6, 14), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Jun 14, 15")
    }

    @Test func otherYearNeverRendersFourDigitYear() {
        // Mutation 3: a formatter using `.year()` (four digits) must fail
        // here - the product owner asked for the last two numbers.
        let now = Self.date(2026, 6, 15)
        let rendered = EntryDateText.dayMonth(Self.date(2015, 6, 14), now: now,
                                              calendar: Self.calendar, locale: Self.enUS())
        #expect(rendered == "Jun 14, 15")
        #expect(!rendered.contains("2015"), "the year must be two digits, got \(rendered)")
    }

    // MARK: - The 31 Dec / 1 Jan boundary is asserted explicitly

    @Test func theDayBeforeNewYearShowsTheYearEvenWhenNowIsNewYearsDay() {
        // now = 1 Jan 2026. 1 Jan is current-year and shows nothing; the
        // previous day is the previous year and MUST show its year. A
        // formatter that compared within some sliding window (not the
        // calendar year) would get this wrong.
        let now = Self.date(2026, 1, 1)
        #expect(EntryDateText.dayMonth(Self.date(2026, 1, 1), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Jan 1")
        #expect(EntryDateText.dayMonth(Self.date(2025, 12, 31), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Dec 31, 25")
    }

    @Test func midDecemberOfThePreviousYearShowsTheYear() {
        let now = Self.date(2026, 1, 1)
        #expect(EntryDateText.dayMonth(Self.date(2025, 12, 16), now: now,
                                        calendar: Self.calendar, locale: Self.enUS()) == "Dec 16, 25")
    }

    // MARK: - The RU form is the locale's own, never an apostrophe

    @Test func russianYearIsTheLocalesOwnMarkerNotAnApostrophe() {
        // Mutation 4 (an imagined "18 Jul '15" composition): Russian does not
        // use an apostrophe for years. Apple's own tables render the year
        // marker "г." after a narrow no-break space - assert THAT, exactly.
        let now = Self.date(2026, 9, 6)
        let ru = Locale(identifier: "ru_RU")
        #expect(EntryDateText.dayMonth(Self.date(2025, 8, 17), now: now,
                                        calendar: Self.calendar, locale: ru) == "17 авг. 25\u{202F}г.")
        #expect(EntryDateText.dayMonth(Self.date(2025, 8, 17), now: now,
                                        calendar: Self.calendar, locale: ru)
                .contains("25\u{202F}г."),
                "RU marks the two-digit year with its own \u{202F}г. suffix")
        #expect(!EntryDateText.dayMonth(Self.date(2025, 8, 17), now: now,
                                         calendar: Self.calendar, locale: ru).contains("'"),
                "an apostrophe year is an English habit, never Russian")
    }

    @Test func russianCurrentYearDateRendersNoYearMarker() {
        // Note "авг." itself ends in "г.", so a "no г. present" check is the
        // vacuous trap here - assert the WHOLE string and the absence of the
        // year's two digits instead.
        let now = Self.date(2026, 9, 6)
        let ru = Locale(identifier: "ru_RU")
        #expect(EntryDateText.dayMonth(Self.date(2026, 8, 17), now: now,
                                        calendar: Self.calendar, locale: ru) == "17 авг.")
        #expect(!EntryDateText.dayMonth(Self.date(2026, 8, 17), now: now,
                                         calendar: Self.calendar, locale: ru).contains("25"),
                "a current-year RU date must carry no year")
    }

    @Test func britishEnglishUsesItsOwnDayFirstOrder() {
        // The ordering is the locale's, not ours: en_GB writes "17 Aug 15"
        // without the en_US comma. A formatter that composed "month day, yy"
        // for every locale would fail here.
        let now = Self.date(2026, 9, 6)
        let gb = Locale(identifier: "en_GB")
        #expect(EntryDateText.dayMonth(Self.date(2025, 8, 17), now: now,
                                        calendar: Self.calendar, locale: gb) == "17 Aug 25")
        #expect(EntryDateText.dayMonth(Self.date(2026, 8, 17), now: now,
                                        calendar: Self.calendar, locale: gb) == "17 Aug")
    }

    // MARK: - The month dividers carry the year as a full heading

    @Test func currentYearMonthHeadingCarriesNoYear() {
        let now = Self.date(2026, 9, 6)
        #expect(EntryDateText.monthHeading(Self.date(2026, 9, 1), now: now,
                                            calendar: Self.calendar, locale: Self.enUS()) == "September")
    }

    @Test func otherYearMonthHeadingCarriesTheFullYear() {
        // The divider is a HEADER with no day to anchor the date, so "August
        // 15" would read as the fifteenth of August; a heading carries the
        // full year while the rows beneath it carry two digits.
        let now = Self.date(2026, 9, 6)
        #expect(EntryDateText.monthHeading(Self.date(2025, 8, 1), now: now,
                                            calendar: Self.calendar, locale: Self.enUS()) == "August 2025")
    }
}
