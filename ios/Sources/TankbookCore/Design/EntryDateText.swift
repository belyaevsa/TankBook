import Foundation

/// RV.89: the ONE date formatter for every surface that lists dated entries -
/// the Log rows, the "needs a look" list, Recently deleted, Trends' last-price
/// caption, the parts shelf and the log's month dividers. Previously each of
/// those printed "18 Jul" through `HomeFormat.day` and a 2015 entry was
/// indistinguishable from a 2026 one; `ReminderRowFormat.dateString` already
/// dropped the year inside the current year and showed it otherwise, and this
/// enum is that pattern made shared and testable.
///
/// The rule (docs/DESIGN.md, decided 2026-09-06): a date inside the CURRENT
/// calendar year renders without a year; any other year appends one. The year
/// comes from `Date.FormatStyle`'s own `.year(.twoDigits)`, so each locale
/// renders its own convention - en_US "Aug 17, 15", en_GB "17 Aug 15", ru_RU
/// "17 авг. 15 г." - never a hand-composed apostrophe-plus-digits (hard rule
/// 10; the P1.4 "%@ расходы" trap in a different costume).
///
/// `now` is a parameter, never `Date()` inside the implementation, so a test
/// can freeze the clock. The calendar/locale default to the user's own; tests
/// pin them.
public enum EntryDateText {
    /// Whether a dated row must print its year: false inside the current
    /// calendar year, true for every other year.
    public static func showsYear(_ date: Date, now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        !calendar.isDate(date, equalTo: now, toGranularity: .year)
    }

    /// "Sep 6" for a date in the current year, "Sep 6, 25" outside it. The
    /// two-digit form is safe on a row because the day is already printed -
    /// "Sep 6, 25" cannot be read as the 25th. RU composes "6 сент. 25 г."
    /// through the locale, never an apostrophe.
    public static func dayMonth(_ date: Date, now: Date = Date(),
                                calendar: Calendar = .current,
                                locale: Locale = .autoupdatingCurrent) -> String {
        var style = baseStyle(calendar: calendar, locale: locale)
        style = style.month(.abbreviated).day()
        if showsYear(date, now: now, calendar: calendar) {
            style = style.year(.twoDigits)
        }
        return date.formatted(style)
    }

    /// "September" for a month in the current year, "September 2015" outside it
    /// - the log's month-divider heading. The divider is a HEADER, not a row:
    /// it has no day to pin the date, so a two-digit year would read as a day
    /// ("AUGUST 15" looks like the fifteenth), and the divider carries the FULL
    /// year while the rows beneath it carry the product owner's two digits.
    /// The year is added as a plain numeral - a Russian heading wants no "г."
    /// suffix, and uppercasing a composed "август 15 г." would wrongly raise
    /// the "г.".
    public static func monthHeading(_ date: Date, now: Date = Date(),
                                    calendar: Calendar = .current,
                                    locale: Locale = .autoupdatingCurrent) -> String {
        let name = date.formatted(baseStyle(calendar: calendar, locale: locale).month(.wide))
        guard showsYear(date, now: now, calendar: calendar) else { return name }
        return "\(name) \(calendar.component(.year, from: date))"
    }

    /// The one style configuration every formatter above shares: the user's
    /// calendar (so the year test and the rendered fields can never disagree at
    /// a month/day boundary) and the requested locale (so a Russian user reads
    /// "г." and an American a comma, each from Apple's own tables).
    private static func baseStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
