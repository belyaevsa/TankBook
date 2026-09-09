import Foundation

/// The Log stream, derived (never stored - hard rule 2) from a vehicle and its
/// entries. This is the decision layer the SwiftUI stream renders:
///
/// - Entries ordered by `date` descending, ties broken by `EntryOrder` - the
///   one chronological order the Log, the consumption engines and the timeline
///   validator share (docs/SCHEMA.md, Entry -> ordering rule): same-day fills
///   read by odometer, so a top-up and a full fill on one date never display
///   backwards. The four entry types interleaved (docs/SCHEMA.md, Entry: "The
///   Log renders their union ordered by date").
/// - Calendar-month sections, newest first, each carrying the month's total
///   spend in DIN (docs/DESIGN.md: "Monthly dividers carry the month's total
///   spend in DIN"). A month's total sums every entry type, and a purchase
///   group contributes its grand total ONCE - never once per member row. The
///   total is denominated in the home currency its rows were recorded in - the
///   vehicle's when that is consistent, each row's own pair when the history
///   mixes (RV.145) - and is carried WITH the figure so a renderer cannot pair
///   it with a foreign symbol.
/// - Entries sharing a `purchaseGroupId` become one purchase group - the
///   receipt as the user holds it. The group states its receipt total exactly
///   as honestly as the month dividers do: the members' home amounts reduced
///   through the shared accumulator (RV.112, RV.166), so a group whose receipt
///   still waits on a rate is `.partial` (its known sum marked with the pending
///   count), never a bare total that reads as the whole receipt - and a group
///   whose known lines span home currencies is `.mixed`, with no single figure.
///   The total is never the fill-up's amount alone (hard rule 4 / docs/SCHEMA.md
///   CHECK 3 - the fuel amount is the FUEL LINE, not the receipt grand total),
///   never summed into consumption maths, and counted ONCE in a month's
///   divider. Until P2.4 stores the receipt's own total, the sum of the logged
///   lines is the honest figure the group can show.
///
/// Every display decision (what shows, what is omitted) lives here so it tests
/// without a simulator (docs/TESTING.md, L1); the SwiftUI layer only formats
/// each value and renders the sections.
public struct LogStream: Equatable, Sendable {
    /// One calendar month of the stream, newest first.
    public struct Section: Equatable, Sendable, Identifiable {
        /// The month start is the stable identity of a section.
        public var id: Date { monthStart }
        /// Start of the calendar month, in the calendar the stream was built with.
        public let monthStart: Date
        /// What the month's divider may honestly print: its spend figure, with
        /// the rate-pending honesty built in. A month whose rows are still
        /// waiting on a rate must not report a bare total (RV.106) - `0 €`
        /// beside rows that carry no home amount is a wrong number, not a
        /// missing one (hard rule 2, docs/ERRORS.md -> Home, F9). The same
        /// honesty guards the currency axis (RV.145): a month whose known
        /// figures span home currencies is `.mixed` and prints no bare number.
        public let total: MonthTotal
        public let rows: [Row]
    }

    /// The month divider's spend figure, stated exactly as honestly as the
    /// data allows (docs/ERRORS.md -> Home, F9). Sums every entry type in the
    /// month's home currency, a purchase group counted once by its grand total
    /// (hard rule 4). A rate-pending row's home amount is NOT known - it can
    /// never be summed as zero, because a derived figure that asserts a
    /// falsehood is the defect (RV.106).
    ///
    /// Every case that carries an amount carries the CURRENCY with it (RV.145):
    /// a figure and its symbol read from two different objects - the amount
    /// from the entries, the symbol from the vehicle - is how the Log printed a
    /// euro sum under a dollar sign. A month's known figures are printable only
    /// when they share ONE home currency; the amounts below are always
    /// denominated in the currency they carry, and the mixed case refuses a bare
    /// number outright.
    public enum MonthTotal: Equatable, Sendable {
        /// No row in the month is waiting on a rate and every known figure is
        /// home in `currency`: `amount` is exact and the divider may print it
        /// as fact. A month with no money-bearing row at all is an honest
        /// zero-spend month in the vehicle's home currency (only free events -
        /// prints `0 €`).
        case complete(amount: Decimal, currency: CurrencyCode)
        /// Some rows have a home figure and some are still waiting on a rate.
        /// `amount` is the exact sum of the figures that ARE known, all home in
        /// `currency` - the divider may print it only as a partial, marked with
        /// `pendingCount`.
        case partial(amount: Decimal, currency: CurrencyCode, pendingCount: Int)
        /// The month's KNOWN figures are home in more than one currency, so no
        /// single number states the month honestly (RV.145, docs/ERRORS.md ->
        /// Home): `subtotals` is the per-currency breakdown - each figure exact
        /// and paired with its own currency - and `pendingCount` counts rows
        /// still waiting on a rate. Do not sum `subtotals` across currencies
        /// (hard rule 3); a renderer shows the breakdown, never a bare total.
        case mixed(subtotals: [SpendSubtotal], pendingCount: Int)
        /// Every money-bearing row in the month is still waiting on a rate: no
        /// home figure exists, so there is no number to print. The divider says
        /// why instead of inventing a `0 €` (RV.106).
        case pending(pendingCount: Int)
    }

    /// One currency's exact share of a mixed month (RV.145). Carries its
    /// currency so a figure and its symbol can never be read from two different
    /// objects - the amount and the marker always travel together.
    public struct SpendSubtotal: Equatable, Sendable {
        /// The exact sum of the month's known figures homed in `currency`.
        public let amount: Decimal
        /// The currency `amount` is denominated in - the marker the renderer
        /// must print beside it.
        public let currency: CurrencyCode

        public init(amount: Decimal, currency: CurrencyCode) {
            self.amount = amount
            self.currency = currency
        }
    }

    /// A rendered row: a standalone entry, a purchase group, or an unresolved
    /// S2 duplicate pair shown as one combined card.
    public enum Row: Equatable, Sendable, Identifiable {
        case entry(LogEntry)
        case group(LogGroup)
        case duplicate(DuplicateGroup)

        public var id: UUID {
            switch self {
            case .entry(let entry): entry.id
            case .group(let group): group.id
            case .duplicate(let group): group.id
            }
        }

        /// The row's position in time: a group sits at its newest member's date,
        /// a duplicate card at its counted entry's date.
        public var date: Date {
            switch self {
            case .entry(let entry): entry.date
            case .group(let group): group.members.first?.date ?? .distantPast
            case .duplicate(let group): group.date
            }
        }
    }

    /// One unresolved S2 duplicate pair (docs/SYNC.md S2): two fill-ups that
    /// the heuristic flags as the same physical fill logged twice. Rendered as
    /// ONE combined card - "Possible duplicate" with Keep both / Merge - where
    /// the pair would otherwise appear as two rows. Until resolved only
    /// `counted` counts in any derived figure; `excluded` is set aside.
    public struct DuplicateGroup: Equatable, Sendable, Identifiable {
        /// The entry that counts while the pair is unresolved (the Merge
        /// survivor - docs/SYNC.md: "the one with an attachment wins").
        public let counted: LogEntry
        /// The entry that does NOT count until the user decides.
        public let excluded: LogEntry

        public var id: UUID { counted.id }
        public var date: Date { counted.date }
    }

    /// One physical purchase: the entries a single receipt produced.
    public struct LogGroup: Equatable, Sendable, Identifiable {
        /// The shared `purchaseGroupId`.
        public let id: UUID
        /// Member entries, newest first.
        public let members: [LogEntry]
        /// The receipt's stated figure, classified exactly as the month divider
        /// classifies a month's (the SAME `MonthTotal` from the SAME accumulator
        /// - RV.112, RV.166, docs/ERRORS.md -> Home, F9). `.complete` is the
        /// exact sum of the members' known home amounts and may print bare;
        /// `.partial` is that exact sum MARKED with the pending count - a
        /// rate-pending member's home amount is not known, and summing it as
        /// zero would present the receipt as fully stated (the RV.106 lie);
        /// `.mixed` has no single figure (the known lines span home currencies -
        /// the member rows state each amount, RV.145); `.pending` has no home
        /// figure at all. The group contributes this ONE figure to a month's
        /// divider total (hard rule 4), never one per member row.
        public let total: MonthTotal
        /// True when any member keeps a receipt or photo (they share it).
        public let hasAttachment: Bool
    }

    /// An entry's kind in the stream - the accent dot's meaning.
    public enum Kind: Equatable, Sendable {
        case fuel, charge, service, expense
    }

    /// The quantity an entry card can carry: litres for a fill, kWh for a charge.
    public enum Quantity: Equatable, Sendable {
        case volumeL(Double)
        case energyKWh(Double)
    }

    /// A subtitle segment in display order. The view formats each value (DIN
    /// figures, localized units); this list is the DECISION of what the card
    /// shows and in what order - testable without a simulator.
    public enum SubtitleSegment: Equatable, Sendable {
        case quantity(Quantity)
        case fuelKind(FuelKind)
        case odometer(Int)
        /// The per-fill consumption (L/100km) of the segment this fill closes,
        /// from the engine's own `Segment.per100` (hard rule 2 - the view never
        /// recomputes it). ABSENT for a fill that closes no segment (RV.142,
        /// docs/SCHEMA.md -> Derived: consumption): a `0.0` would be a wrong
        /// claim about the car, so nothing renders.
        case consumption(Double)
        case attachment
        case date(Date)
    }

    /// An entry stripped to what the stream card renders (docs/DESIGN.md ->
    /// "Entry card content").
    public struct LogEntry: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let date: Date
        public let kind: Kind
        /// Which entry the card's title resolves from: the fuel station's id,
        /// the charge provider, the service vendor, or the expense's own title.
        public let stationId: UUID?
        public let provider: String?
        public let vendor: String?
        public let entryTitle: String?
        /// The quantity segment, when the entry has one.
        public let quantity: Quantity?
        /// The fuel kind (fill-ups only). `.nil` for charge/service/expense.
        public let fuelKind: FuelKind?
        /// Whether the fuel kind earns its place in the subtitle - conditional,
        /// never decorative (docs/DESIGN.md): hidden when the row's TITLE is
        /// already that kind (the fallback for a fill whose station does not
        /// resolve - repeating it is the RV.142 duplicate), hidden for a
        /// single-fuel vehicle whose kind is the usual one, and shown for a
        /// multi-fuel vehicle and when this entry's kind differs from the car's
        /// usual - but only when the title is the station name.
        public let showsFuelKind: Bool
        /// The entry's odometer; `nil` means the segment is OMITTED, never
        /// rendered as a dash or zero (optional on non-FillUp entries).
        public let odometer: Int?
        /// The derived per-fill consumption of the segment this entry closes
        /// (fill-ups only): the engine's `Segment.per100` for the segment whose
        /// `closingFillID` is this fill. `nil` - ABSENT, never `0` - for an
        /// entry that closes no segment (RV.142): the first fill, a non-full
        /// tank, a gap, or any non-FillUp entry.
        public let consumptionPer100: Double?
        public let money: Money?
        public let hasAttachment: Bool
        public let isConflicted: Bool

        /// The subtitle line: `quantity · consumption? · fuelKind? · odometer? ·
        /// 📎? · date`. An entry with no odometer simply omits that segment; a
        /// fill that closes no segment carries no consumption figure (RV.142).
        public var subtitleSegments: [SubtitleSegment] {
            var segments: [SubtitleSegment] = []
            if let quantity {
                segments.append(.quantity(quantity))
            }
            if let consumptionPer100 {
                segments.append(.consumption(consumptionPer100))
            }
            if let fuelKind, showsFuelKind {
                segments.append(.fuelKind(fuelKind))
            }
            if let odometer {
                segments.append(.odometer(odometer))
            }
            if hasAttachment {
                segments.append(.attachment)
            }
            segments.append(.date(date))
            return segments
        }
    }

    /// Month sections, newest first.
    public let sections: [Section]

    /// The number of entries still waiting on a rate among the counting rows -
    /// the F9 "N entries pending rates" footnote count (docs/JOURNEYS.md F9).
    /// S2-excluded members never count; `money == nil` (free events) is not
    /// pending. Derived, never stored (hard rule 2).
    public let pendingRateCount: Int

    /// The calendar the sections were grouped with, retained so a preview
    /// re-sectioning uses the same month boundaries.
    private let calendar: Calendar

    /// The vehicle's home currency, retained so a preview re-sectioning can
    /// classify a money-less month (`0` is denominated in the car's home
    /// currency) exactly as the full stream did.
    private let homeCurrency: CurrencyCode

    public init(vehicle: Vehicle, entries: [any Entry], calendar: Calendar = .current,
                duplicateResolutions: Set<DuplicateDetector.PairKey> = [],
                stations: [Station] = []) {
        self.calendar = calendar
        self.homeCurrency = vehicle.homeCurrency

        // The one chronological order the Log, the consumption engines and the
        // timeline validator share (docs/SCHEMA.md, Entry -> ordering rule):
        // same-day fills read by odometer, so two fills on one date never
        // display backwards and never reorder a recompute. Newest first.
        let sorted = entries.sorted(by: EntryOrder.descending)

        // The S2 pair detection is the stream's decision layer too: an
        // unresolved duplicate pair renders as ONE combined card, and its
        // excluded member is dropped from the rows (it is represented by the
        // card) - only the counted member ever reaches a month total
        // (docs/SYNC.md S2: "Until resolved, only ONE of the pair counts in
        // consumption and totals").
        let pairs = DuplicateDetector.pairs(
            in: sorted.compactMap { $0 as? FillUp },
            resolved: duplicateResolutions)
        let excludedIDs = Set(pairs.map(\.excludedID))
        self.pendingRateCount = sorted
            .filter { !excludedIDs.contains($0.id) && ($0.money?.isRatePending ?? false) }
            .count
        let pairByCountedID = Dictionary(pairs.map { ($0.countedID, $0) },
                                         uniquingKeysWith: { $1 })

        // The per-fill consumption figure (RV.142): the engine's segments over
        // the SAME counting fills HomeStats derives the headline from (S2
        // excluded members never count, docs/SYNC.md S2) - so the row's figure
        // and the headline can never disagree. Keyed by the closing fill, which
        // is the fill the segment's consumption belongs to (docs/SCHEMA.md ->
        // Derived: consumption -> SEGMENT).
        let countingFills = sorted.compactMap { $0 as? FillUp }
            .filter { !excludedIDs.contains($0.id) }
        let per100ByClosingFillID = Dictionary(
            uniqueKeysWithValues: ConsumptionEngine.recompute(
                fills: countingFills, tankCapacityL: vehicle.tankCapacityL)
                .map { ($0.closingFillID, $0.per100) })
        let logEntryByID = Dictionary(
            sorted.map { ($0.id, LogEntry(vehicle: vehicle, entry: $0, stations: stations,
                                          closingPer100: per100ByClosingFillID[$0.id])) },
            uniquingKeysWith: { $1 })

        var groupMembers: [UUID: [any Entry]] = [:]
        for entry in sorted {
            if let groupID = entry.purchaseGroupId {
                groupMembers[groupID, default: []].append(entry)
            }
        }

        // Rows are emitted in the same canonical order the entries were sorted
        // into, so no later re-sort can scramble two same-day rows. A purchase
        // group appears once, at the position of its NEWEST member (a receipt's
        // other lines collapse into it); its excluded S2 member never renders.
        var rows: [Row] = []
        var emittedGroups = Set<UUID>()
        for entry in sorted {
            if excludedIDs.contains(entry.id) {
                // Represented by the combined card - never rendered twice.
                continue
            }
            if let groupID = entry.purchaseGroupId {
                guard !emittedGroups.contains(groupID) else { continue }
                emittedGroups.insert(groupID)
                let logMembers = (groupMembers[groupID] ?? [])
                    .sorted(by: EntryOrder.descending)
                    .map { LogEntry(vehicle: vehicle, entry: $0, stations: stations,
                                    closingPer100: per100ByClosingFillID[$0.id]) }
                rows.append(.group(Self.group(id: groupID, members: logMembers,
                                              homeCurrency: vehicle.homeCurrency)))
                continue
            }
            if let pair = pairByCountedID[entry.id],
               let countedEntry = logEntryByID[entry.id],
               let excludedEntry = logEntryByID[pair.excludedID] {
                rows.append(.duplicate(DuplicateGroup(counted: countedEntry,
                                                      excluded: excludedEntry)))
                continue
            }
            rows.append(.entry(LogEntry(vehicle: vehicle, entry: entry, stations: stations,
                                        closingPer100: per100ByClosingFillID[entry.id])))
        }

        self.sections = Self.buildSections(rows: rows, calendar: calendar,
                                           homeCurrency: vehicle.homeCurrency)
    }

    /// A purchase group's display figure (RV.166): the members' money pairs
    /// reduced through the SAME accumulator the month dividers and the stats
    /// reduce through (RV.112) - so a rate-pending member is COUNTED but never
    /// summed as zero, and a group whose known lines span home currencies can
    /// never pair one sum with a foreign symbol (RV.145). The classification
    /// therefore agrees with the divider that sums the same receipt's members,
    /// and the divider's partial/mixed/pending rendering rules apply verbatim
    /// to the group header.
    private static func group(id: UUID, members: [LogEntry],
                              homeCurrency: CurrencyCode) -> LogGroup {
        var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: homeCurrency)
        accumulator.add(contentsOf: members.map(\.money))
        return LogGroup(id: id, members: members,
                        total: accumulator.monthTotal,
                        hasAttachment: members.contains { $0.hasAttachment })
    }

    /// The number of rendered rows with the given purchase groups collapsed.
    /// A collapsed group reports ONE row; an expanded one reports its members.
    /// This is the collapse/expand contract, pure and testable.
    public func rowCount(collapsedGroupIDs: Set<UUID>) -> Int {
        sections.reduce(0) { count, section in
            count + section.rows.reduce(0) { partial, row in
                switch row {
                case .entry, .duplicate:
                    return partial + 1
                case .group(let group):
                    return partial + (collapsedGroupIDs.contains(group.id) ? 1 : group.members.count)
                }
            }
        }
    }

    public var allRows: [Row] {
        sections.flatMap(\.rows)
    }

    /// A preview of the newest `count` rows, re-sectioned by month. A purchase
    /// group on the cut is never split - the receipt stays whole.
    public func previewRows(_ count: Int) -> LogStream {
        var rows = Array(allRows.prefix(count))
        if let last = rows.last, case .group(let group) = last, group.members.count > 1 {
            let afterCut = allRows.dropFirst(rows.count)
            let missing = afterCut.prefix { row in
                if case .group(let candidate) = row { return candidate.id == group.id } else { return false }
            }
            rows.append(contentsOf: missing)
        }
        return LogStream(sections: Self.buildSections(rows: rows, calendar: calendar,
                                                      homeCurrency: homeCurrency),
                         calendar: calendar, homeCurrency: homeCurrency,
                         pendingRateCount: pendingRateCount)
    }

    // MARK: - Whole-month reveal (RV.103)

    /// One page of the reveal: the whole months shown by a reveal step. Months
    /// are atomic - a boundary never splits one - so a month divider is only
    /// ever shown above the month's complete rows (it never sums rows the user
    /// cannot see), and a purchase group (a single collapsed row inside one
    /// month) can never straddle a page boundary.
    public struct RevealPage: Equatable, Sendable {
        /// The whole months this page adds, newest first.
        public let months: [Section]
        /// How many of the stream's whole months are visible once this page is
        /// revealed - the reveal's running position.
        public let visibleMonthCount: Int
        /// The whole months still hidden after this page.
        public let hiddenMonths: [Section]
        /// Entries (rows) still hidden after this page - the count a "show more"
        /// affordance states (hard rule 7).
        public let hiddenEntryCount: Int
    }

    /// The whole-month reveal pages of the stream: the first page shows the
    /// newest whole months whose combined rows first reach `initialRowCount`
    /// rows, and every later page adds the next whole months until
    /// `pageRowCount` more rows are covered (or the stream ends). The union of
    /// row ids across all pages equals the whole stream with no drop and no
    /// duplicate. A month never spans two pages, so a divider is only ever
    /// rendered above a complete month.
    ///
    /// Each page's `months` are the months THAT page adds (the first page's
    /// `visibleMonthCount` is its own month count; the next page's is the
    /// running total). Render `pages.prefix(k).flatMap(\.months)` to show the
    /// newest `k` pages.
    public func revealPages(initialRowCount: Int = 20, pageRowCount: Int = 20) -> [RevealPage] {
        guard !sections.isEmpty else { return [] }
        var pages: [RevealPage] = []
        var cursor = 0
        var cumulativeRows = 0
        var nextTarget = max(initialRowCount, 1)
        while cursor < sections.count {
            let start = cursor
            // Add whole months until the cumulative row count reaches the page
            // target. A month is atomic: if one month alone overshoots the
            // target, it is its own page - never split.
            while cursor < sections.count, cumulativeRows < nextTarget {
                cumulativeRows += sections[cursor].rows.count
                cursor += 1
            }
            let months = Array(sections[start..<cursor])
            let hidden = Array(sections[cursor...])
            pages.append(RevealPage(months: months,
                                    visibleMonthCount: cursor,
                                    hiddenMonths: hidden,
                                    hiddenEntryCount: Self.entryCount(of: hidden)))
            nextTarget = cumulativeRows + max(pageRowCount, 1)
        }
        return pages
    }

    /// The number of entries a list of whole-month rows represents: an entry
    /// row counts one, a purchase group counts its members (each receipt line
    /// is an entry), and an S2 duplicate card counts its counted member once -
    /// the excluded member never counts anywhere (docs/SYNC.md S2). Rows are the
    /// count Home's "N older entries" affordance states.
    public static func entryCount(of sections: [Section]) -> Int {
        sections.reduce(0) { count, section in
            count + section.rows.reduce(0) { partial, row in
                switch row {
                case .entry, .duplicate: return partial + 1
                case .group(let group): return partial + group.members.count
                }
            }
        }
    }

    // MARK: - Construction

    private init(sections: [Section], calendar: Calendar, homeCurrency: CurrencyCode,
                 pendingRateCount: Int) {
        self.sections = sections
        self.calendar = calendar
        self.homeCurrency = homeCurrency
        self.pendingRateCount = pendingRateCount
    }

    private static func buildSections(rows: [Row], calendar: Calendar,
                                      homeCurrency: CurrencyCode) -> [Section] {
        var sections: [Section] = []
        var currentRows: [Row] = []
        var currentMonth: Date?
        for row in rows {
            let month = monthStart(of: row.date, calendar: calendar)
            if month != currentMonth {
                if let existing = currentMonth {
                    sections.append(section(monthStart: existing, rows: currentRows,
                                            homeCurrency: homeCurrency))
                }
                currentMonth = month
                currentRows = []
            }
            currentRows.append(row)
        }
        if let currentMonth, !currentRows.isEmpty {
            sections.append(section(monthStart: currentMonth, rows: currentRows,
                                    homeCurrency: homeCurrency))
        }
        return sections
    }

    private static func section(monthStart: Date, rows: [Row],
                                homeCurrency: CurrencyCode) -> Section {
        // The one sum the divider may print, and the count of rows still waiting
        // on a rate, come from the shared accumulator HomeStats and TrendsStats
        // reduce through (RV.112) - so a rate-pending row contributes NOTHING
        // to the sum (its home amount is not known) and is counted, and the
        // three surfaces can never disagree about a month's figure. The
        // accumulator also carries each figure's home currency and refuses a
        // bare number when the month's known figures span currencies (RV.145).
        // All three row arms follow the same rule so a purchase group and a
        // duplicate pair can never disagree with a standalone entry: a group
        // sums the members whose home amount is known (its grand total, hard
        // rule 4 - counted once), a duplicate card only its COUNTED entry
        // (docs/SYNC.md S2 - the excluded member never counts anywhere).
        var accumulator = LogStream.MonthTotal.Accumulator(vehicleHome: homeCurrency)
        for row in rows {
            switch row {
            case .entry(let entry):
                accumulator.add(entry.money)
            case .group(let group):
                accumulator.add(contentsOf: group.members.map(\.money))
            case .duplicate(let group):
                accumulator.add(group.counted.money)
            }
        }
        return Section(monthStart: monthStart, total: accumulator.monthTotal, rows: rows)
    }

    private static func monthStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.date(from: calendar.dateComponents([.year, .month], from: date))
            ?? date
    }
}

// MARK: - Entry extraction

extension LogStream.LogEntry {
    /// Builds the display model from any `Entry` type. The fuel-kind visibility
    /// rule (docs/DESIGN.md) and the per-fill consumption figure (RV.142) are
    /// decided here, once, so they test without a UI. `stations` are the live
    /// stations the title resolves against - the SAME list the view renders the
    /// title from, so "the title is the fuel kind" (the no-station fallback)
    /// and "the fuel kind repeats in the subtitle" can never disagree.
    init(vehicle: Vehicle, entry: any Entry, stations: [Station] = [],
         closingPer100: Double? = nil) {
        self.id = entry.id
        self.date = entry.date
        self.odometer = entry.odometer
        self.money = entry.money
        self.hasAttachment = !entry.attachments.isEmpty
        self.isConflicted = entry.conflict != .none

        switch entry {
        case let fill as FillUp:
            self.kind = .fuel
            self.stationId = fill.stationId
            self.provider = nil
            self.vendor = nil
            self.entryTitle = nil
            self.quantity = .volumeL(fill.volumeL)
            self.fuelKind = fill.fuelKind
            // The title resolves to the STATION only when its id names one of
            // the live stations; otherwise HomeSections titles the row with the
            // fuel kind, and the subtitle must not repeat it (RV.142).
            self.showsFuelKind = fill.stationId != nil
                && stations.contains { $0.id == fill.stationId }
                && Self.showsFuelKind(fill.fuelKind, vehicle: vehicle)
            self.consumptionPer100 = closingPer100
        case let charge as ChargeSession:
            self.kind = .charge
            self.stationId = nil
            self.provider = charge.provider
            self.vendor = nil
            self.entryTitle = nil
            self.quantity = .energyKWh(charge.energyKWh)
            self.fuelKind = nil
            self.showsFuelKind = false
            self.consumptionPer100 = nil
        case let service as ServiceRecord:
            self.kind = .service
            self.stationId = nil
            self.provider = nil
            self.vendor = service.vendor
            self.entryTitle = nil
            self.quantity = nil
            self.fuelKind = nil
            self.showsFuelKind = false
            self.consumptionPer100 = nil
        case let expense as Expense:
            self.kind = .expense
            self.stationId = nil
            self.provider = nil
            self.vendor = nil
            self.entryTitle = expense.title
            self.quantity = nil
            self.fuelKind = nil
            self.showsFuelKind = false
            self.consumptionPer100 = nil
        default:
            // A future entry type: render as a neutral expense-like row rather
            // than a crash - nothing is lost silently (hard rule 8).
            self.kind = .expense
            self.stationId = nil
            self.provider = nil
            self.vendor = nil
            self.entryTitle = nil
            self.quantity = nil
            self.fuelKind = nil
            self.showsFuelKind = false
            self.consumptionPer100 = nil
        }
    }

    /// docs/DESIGN.md: fuel kind is shown only when it tells the user something
    /// - when the vehicle accepts more than one fuel kind, or when this entry's
    /// kind differs from the car's usual - AND the title is not already that
    /// kind (the caller's station-resolution gate; RV.142). A diesel-only car
    /// printing "Diesel" on every row is noise dressed as information.
    private static func showsFuelKind(_ fuelKind: FuelKind, vehicle: Vehicle) -> Bool {
        vehicle.fuelKinds.count > 1 || !vehicle.fuelKinds.contains(fuelKind)
    }
}
