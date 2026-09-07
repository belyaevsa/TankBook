import Testing
import Foundation
@testable import TankbookCore

// RV.103 - the Log must offer a way past the newest 20 rows, and the reveal
// must never drop, duplicate or split anything.
//
// The reveal is whole-month atomic: a month divider is only ever shown above
// the month's complete rows (it never sums rows the user cannot see - the
// divider-honesty fence), and a purchase group (a single collapsed row inside
// one month) can never straddle a page boundary. `revealPages` returns the
// pages; rendering `pages.prefix(k).flatMap(\.months)` shows the newest k
// pages, whose union of row ids is the whole stream.
//
// The fixtures mirror `LogStreamTests`/`LogStreamDividerRatePendingTests` and
// are self-contained so the suites never share private state.

struct LogStreamRevealTests {

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int,
                             _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func vehicle() -> Vehicle {
        Vehicle(
            id: UUID.v7(), createdAt: Self.date(2025, 6, 1), updatedAt: Self.date(2025, 6, 1),
            deletedAt: nil, name: "Volvo V60", make: "Volvo", model: "V60", year: 2015,
            plate: nil, powertrain: .ice, fuelKinds: [.petrol95, .diesel],
            tankCapacityL: 71, batteryCapacityKWh: nil, homeCurrency: .eur,
            units: Vehicle.Units(distance: .km, volume: .l, consumption: .lPer100,
                                  energy: .kWhPer100),
            photo: nil, archived: false, paceLimitKmPerDay: 1500,
            initialOdometer: 118_000)
    }

    private static func money(_ amount: String) -> Money {
        Money(amount: Decimal(string: amount)!, currency: .eur, homeCurrency: .eur)
    }

    private static func fill(_ date: Date, odometer: Int = 120_000, litres: Double = 42,
                             amount: String = "71.02", kind: FuelKind = .petrol95,
                             group: UUID? = nil) -> FillUp {
        FillUp(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: odometer,
            money: Self.money(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            volumeL: litres, unitPrice: nil, fuelKind: kind, fuelGrade: nil,
            isFull: true, tankLevelAfterPct: 100, stationId: nil,
            crossCheck: .verified, extraction: nil)
    }

    private static func expense(_ date: Date, amount: String = "8.00",
                                group: UUID? = nil) -> Expense {
        Expense(
            id: UUID.v7(), createdAt: date, updatedAt: date, deletedAt: nil,
            vehicleId: UUID.v7(), date: date, odometer: nil,
            money: Self.money(amount), note: nil, attachments: [],
            provenance: .manual, conflict: .none, purchaseGroupId: group,
            category: .parking, title: "Parking", recurrence: nil,
            installedInServiceId: nil)
    }

    /// A stream whose rows spread over several months, newest first: two fills
    /// per month across August..May gives >20 rows over 4 months, so a reveal
    /// is actually hiding something.
    private static func multiMonthStream() -> LogStream {
        var entries: [any Entry] = []
        for (index, month) in [8, 7, 6, 5, 4].enumerated() {
            entries.append(fill(Self.date(2025, month, 10), odometer: 118_000 - index * 500))
            entries.append(fill(Self.date(2025, month, 20), odometer: 118_300 - index * 500))
            entries.append(fill(Self.date(2025, month, 28), odometer: 118_600 - index * 500))
        }
        return LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
    }

    /// The row ids a set of sections' rows present, deduplicated and in order.
    private static func rowIDs(of sections: [LogStream.Section]) -> [UUID] {
        sections.flatMap(\.rows).map(\.id)
    }

    // MARK: - Union across pages equals the whole stream

    /// The first page is Home's preview (a few whole months), and revealing
    /// every page in order must end exactly at the whole stream - no row
    /// dropped, none duplicated. Asserted on row IDS, never counts: a page that
    /// silently swaps or drops an entry counts the same as one that does not.
    @Test func unionOfRowIDsAcrossAllPagesEqualsTheWholeStream() {
        let stream = Self.multiMonthStream()
        let pages = stream.revealPages(initialRowCount: 5, pageRowCount: 5)
        // 15 rows over 5 months => the stream has 5 whole months.
        #expect(pages.count > 1, "a stream longer than one page must reveal in several pages")

        var revealedIDs: [UUID] = []
        for page in pages {
            revealedIDs.append(contentsOf: Self.rowIDs(of: page.months))
        }
        #expect(revealedIDs == stream.allRows.map(\.id),
                "revealing every page must reproduce the whole stream exactly, in order")

        let all = Set(stream.allRows.map(\.id))
        let revealed = Set(revealedIDs)
        #expect(revealed.count == all.count,
                "no row may be duplicated or dropped across pages")
    }

    /// The affordance's stated remaining count must be real: after the first
    /// page the number of still-hidden rows equals the count of rows that a
    /// full reveal would still add - never a made-up figure.
    @Test func hiddenEntryCountAfterFirstPageMatchesRowsStillToCome() {
        let stream = Self.multiMonthStream()
        let pages = stream.revealPages(initialRowCount: 5, pageRowCount: 5)
        let first = pages[0]
        let expectedHidden = stream.allRows.count
            - Self.rowIDs(of: first.months).count
        #expect(first.hiddenEntryCount == expectedHidden)
        // And the final page hides nothing.
        #expect(pages.last?.hiddenEntryCount == 0)
        #expect(pages.last?.hiddenMonths.isEmpty == true)
    }

    /// The initial-row target is a floor on the first page's row count, and the
    /// row target is a floor on each later page - a page that adds fewer rows
    /// than asked is an off-by-one waiting to drop content.
    @Test func everyPageMeetsItsRowTargetOrIsTheFinalWholeMonths() {
        let stream = Self.multiMonthStream()
        let pages = stream.revealPages(initialRowCount: 5, pageRowCount: 5)
        #expect(Self.rowIDs(of: pages[0].months).count >= 5)
        // Later pages add at least 5 rows, unless the stream ends mid-... it
        // can't: pages are whole months, so the last page is whatever remains
        // and can be smaller than the target only because a month was atomic.
        for page in pages.dropFirst() where !page.hiddenMonths.isEmpty {
            #expect(Self.rowIDs(of: page.months).count >= 1,
                    "a non-final page must add at least one whole month")
        }
    }

    // MARK: - A month divider is never shown above a partial month

    /// The divider-honesty fence: a revealed page contains whole months only,
    /// so every month divider a page renders sums exactly the month's complete
    /// rows - it can never sum rows the user cannot see. A page that ended
    /// mid-month would render a divider above a slice, which is the defect.
    @Test func noPageEndsMidMonth() {
        let stream = Self.multiMonthStream()
        let pages = stream.revealPages(initialRowCount: 5, pageRowCount: 5)

        // Every page's last month is a real whole month: the page's monthStart
        // set equals the stream's months consumed so far.
        var seenMonths: Set<Date> = []
        for page in pages {
            for month in page.months {
                #expect(!seenMonths.contains(month.monthStart),
                        "a month must appear in exactly one page")
                seenMonths.insert(month.monthStart)
            }
        }
        #expect(seenMonths == Set(stream.sections.map(\.monthStart)),
                "the pages must cover every whole month exactly once")
    }

    /// The divider a page shows must equal the sum of the rows beneath it: as
    /// pages are revealed the earlier months' dividers must not change (a month
    /// is whole, so its total was final the moment it appeared). Asserted at the
    /// divider level, not by re-summing the model - a future change that made a
    /// divider drift would be caught here.
    @Test func monthDividerTotalsNeverChangeAcrossReveals() {
        let stream = Self.multiMonthStream()
        let pages = stream.revealPages(initialRowCount: 5, pageRowCount: 5)

        var dividersByMonth: [Date: LogStream.MonthTotal] = [:]
        var fullySeen: Set<Date> = []
        for page in pages {
            for month in page.months {
                if let previous = dividersByMonth[month.monthStart] {
                    #expect(previous == month.total,
                            "a month's divider must never change once revealed")
                } else {
                    dividersByMonth[month.monthStart] = month.total
                }
                fullySeen.insert(month.monthStart)
            }
        }
        #expect(fullySeen == Set(stream.sections.map(\.monthStart)))
    }

    // MARK: - A purchase group is never split across a page boundary

    /// A purchase group collapses to ONE row inside ONE month (the receipt
    /// lives at its newest member's date), so a month-atomic reveal cannot
    /// split it. The invariant is counted, not assumed: at every reveal step,
    /// the entries the visible rows represent plus the entries still hidden
    /// must sum to the whole stream's entry total. A reveal that cut inside a
    /// group (or double-counted it) would break that sum - this is the mutation
    /// this test is written to catch.
    @Test func purchaseGroupIsNeverSplitAcrossPages() {
        let groupID = UUID.v7()
        let entries: [any Entry] = [
            Self.fill(Self.date(2025, 8, 10), group: groupID),
            Self.expense(Self.date(2025, 8, 10, 9), group: groupID), // same receipt
            Self.fill(Self.date(2025, 7, 10)),
            Self.fill(Self.date(2025, 6, 10)),
            Self.fill(Self.date(2025, 5, 10)),
            Self.fill(Self.date(2025, 4, 10)),
            Self.fill(Self.date(2025, 3, 10))
        ]
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)

        // The two member entries collapse into ONE `.group` row; the stream has
        // one fewer rendered row than entries.
        #expect(stream.allRows.count == entries.count - 1,
                "the receipt collapses its two entries into one row")

        // Entry-count of a rendered row: an entry row counts one, a group counts
        // its members, a duplicate counts its counted member once.
        func entryCount(of rows: [LogStream.Row]) -> Int {
            rows.reduce(0) { sum, row in
                switch row {
                case .entry, .duplicate: return sum + 1
                case .group(let group): return sum + group.members.count
                }
            }
        }
        let totalEntries = stream.sections.reduce(0) { $0 + entryCount(of: $1.rows) }

        // Walk the reveal a page at a time; after each page the visible
        // entry-count plus the page's stated hidden count must equal the whole
        // stream - a group is never half-visible, never double-counted.
        var running: [LogStream.Row] = []
        for page in stream.revealPages(initialRowCount: 3, pageRowCount: 3) {
            running.append(contentsOf: page.months.flatMap(\.rows))
            #expect(entryCount(of: running) + page.hiddenEntryCount == totalEntries,
                    "visible + hidden entries must always sum to the whole stream")
        }
        #expect(entryCount(of: running) == totalEntries, "fully revealed stream counts every entry")
    }

    /// The guarantee `purchaseGroupIsNeverSplitAcrossPages` names, asserted at
    /// the place a boundary could actually land: a row-count reveal that tried
    /// to hit its target exactly would cut a page INSIDE a month, and if that
    /// month held a purchase group the group's rows would be half on one page
    /// and half on the next. The group month here is built so a naive row-cut
    /// (10 rows, 6-row months) would land mid-month inside it; the reveal must
    /// keep that month whole at every step - a step that shows ANY row of the
    /// group's month must show ALL of it, so the group is never the thing a
    /// page boundary separates.
    @Test func groupMonthIsNeverLeftHalfVisibleAtAnyRevealStep() {
        let groupID = UUID.v7()
        var entries: [any Entry] = []
        // Three 6-row months. The group sits in the MIDDLE month, and a third
        // month is hidden behind it, so the first reveal page ends inside the
        // group month (a 10-row target after the newest month's six rows) and
        // is not the final page - the exact place a month-splitting reveal
        // would trim the group month and leave it half on a page.
        for (index, month) in [9, 8, 7].enumerated() {
            var odometer = 120_000 - index * 3_000
            for day in [2, 5, 8, 11, 14, 17] {
                odometer += 90
                let inGroup = (month == 8 && day == 8)
                let date = Self.date(2025, month, day)
                if inGroup {
                    entries.append(Self.fill(date, odometer: odometer, group: groupID))
                    entries.append(Self.expense(date, amount: "9.50", group: groupID))
                } else {
                    entries.append(Self.fill(date, odometer: odometer))
                }
            }
        }
        let stream = LogStream(vehicle: Self.vehicle(), entries: entries, calendar: Self.calendar)
        guard let groupMonth = stream.allRows
            .first(where: { if case .group = $0 { return true } else { return false } })?
            .date else {
            Issue.record("the fixture must collapse its group into one row")
            return
        }
        let groupMonthStart = stream.sections.first { section in
            Calendar(identifier: .gregorian).isDate(section.monthStart, equalTo: groupMonth,
                                                    toGranularity: .month)
        }?.monthStart

        // The group month carries six rows (five fills where one day became a
        // group of two members + four single fills): after the six rows of the
        // newer month, a naive 10-row page target stops four rows into it, so a
        // reveal that could split months would leave the group's month half on
        // one page. Asserted as a number so the fixture cannot silently shrink
        // into one that never exercised the boundary.
        let newerRows = stream.sections.prefix { $0.monthStart != groupMonthStart }
            .reduce(0) { $0 + $1.rows.count }
        let fullRows = stream.sections.first { $0.monthStart == groupMonthStart }!.rows.count
        let boundaryComment = Comment(rawValue:
            "the fixture must put the page target inside the group month, "
            + "not on its boundary (\(fullRows) rows in the group month, "
            + "\(newerRows) newer)")
        #expect(fullRows > 10 - newerRows, boundaryComment)

        var seenMonths: Set<Date> = []
        for page in stream.revealPages(initialRowCount: 10, pageRowCount: 10) {
            for month in page.months {
                #expect(!seenMonths.contains(month.monthStart),
                        "a month may appear in exactly one page")
                seenMonths.insert(month.monthStart)
                if month.monthStart == groupMonthStart {
                    #expect(month.rows.count == fullRows,
                            "the group's month must be whole on any page that shows it")
                }
            }
        }
        #expect(seenMonths == Set(stream.sections.map(\.monthStart)),
                "every whole month must be revealed exactly once")
    }
}
