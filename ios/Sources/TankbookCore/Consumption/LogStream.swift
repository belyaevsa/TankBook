import Foundation

/// The Log stream, derived (never stored - hard rule 2) from a vehicle and its
/// entries. This is the decision layer the SwiftUI stream renders:
///
/// - Entries ordered by `date` descending (`createdAt` as the tiebreak), the
///   four entry types interleaved (docs/SCHEMA.md, Entry: "The Log renders
///   their union ordered by date").
/// - Calendar-month sections, newest first, each carrying the month's total
///   spend in the vehicle's home currency (docs/DESIGN.md: "Monthly dividers
///   carry the month's total spend in DIN"). A month's total sums every entry
///   type, and a purchase group contributes its grand total ONCE - never once
///   per member row.
/// - Entries sharing a `purchaseGroupId` become one purchase group - the
///   receipt as the user holds it. The group's grand total is the sum of its
///   members' home amounts: never the fill-up's amount alone (hard rule 4 /
///   docs/SCHEMA.md CHECK 3 - the fuel amount is the FUEL LINE, not the receipt
///   grand total), and never summed into consumption maths. Until P2.4 stores
///   the receipt's own total, the sum of the logged lines is the honest figure
///   the group can show.
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
        /// Sum of every entry type's home amount in this month, a purchase
        /// group counted once by its grand total (hard rule 4).
        public let totalSpend: Decimal
        public let rows: [Row]
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
        /// The receipt total as logged: the sum of the members' home amounts.
        /// One number, counted once in a month's divider total.
        public let grandTotal: Decimal
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
        /// never decorative (docs/DESIGN.md): hidden for a single-fuel vehicle
        /// whose kind is the usual one, shown for a multi-fuel vehicle, and
        /// shown when this entry's kind differs from the car's usual.
        public let showsFuelKind: Bool
        /// The entry's odometer; `nil` means the segment is OMITTED, never
        /// rendered as a dash or zero (optional on non-FillUp entries).
        public let odometer: Int?
        public let money: Money?
        public let hasAttachment: Bool
        public let isConflicted: Bool

        /// The subtitle line: `quantity · fuelKind? · odometer? · 📎? · date`.
        /// An entry with no odometer simply omits that segment.
        public var subtitleSegments: [SubtitleSegment] {
            var segments: [SubtitleSegment] = []
            if let quantity {
                segments.append(.quantity(quantity))
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

    public init(vehicle: Vehicle, entries: [any Entry], calendar: Calendar = .current,
                duplicateResolutions: Set<DuplicateDetector.PairKey> = []) {
        self.calendar = calendar

        let sorted = entries.sorted { (lhs, rhs) in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.createdAt > rhs.createdAt
        }

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
        let logEntryByID = Dictionary(sorted.map { ($0.id, LogEntry(vehicle: vehicle, entry: $0)) },
                                      uniquingKeysWith: { $1 })

        var groupMembers: [UUID: [any Entry]] = [:]
        var standalone: [any Entry] = []
        for entry in sorted {
            if let groupID = entry.purchaseGroupId {
                groupMembers[groupID, default: []].append(entry)
            } else {
                standalone.append(entry)
            }
        }

        let entryRows: [Row] = standalone.flatMap { entry in
            if excludedIDs.contains(entry.id) {
                // Represented by the combined card - never rendered twice.
                return [Row]()
            }
            if let pair = pairByCountedID[entry.id],
               let countedEntry = logEntryByID[entry.id],
               let excludedEntry = logEntryByID[pair.excludedID] {
                return [.duplicate(DuplicateGroup(counted: countedEntry,
                                                  excluded: excludedEntry))]
            }
            return [.entry(LogEntry(vehicle: vehicle, entry: entry))]
        }
        let groupRows: [Row] = groupMembers.map { groupID, members in
            let logMembers = members
                .sorted { (lhs, rhs) in
                    if lhs.date != rhs.date { return lhs.date > rhs.date }
                    return lhs.createdAt > rhs.createdAt
                }
                .map { LogEntry(vehicle: vehicle, entry: $0) }
            let grandTotal = logMembers.reduce(Decimal.zero) { partial, member in
                partial + (member.money?.homeAmount ?? Decimal.zero)
            }
            return .group(LogGroup(id: groupID, members: logMembers,
                                   grandTotal: grandTotal,
                                   hasAttachment: logMembers.contains { $0.hasAttachment }))
        }

        let rows = (entryRows + groupRows).sorted { $0.date > $1.date }
        self.sections = Self.buildSections(rows: rows, calendar: calendar)
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
        return LogStream(sections: Self.buildSections(rows: rows, calendar: calendar),
                         calendar: calendar, pendingRateCount: pendingRateCount)
    }

    // MARK: - Construction

    private init(sections: [Section], calendar: Calendar, pendingRateCount: Int) {
        self.sections = sections
        self.calendar = calendar
        self.pendingRateCount = pendingRateCount
    }

    private static func buildSections(rows: [Row], calendar: Calendar) -> [Section] {
        var sections: [Section] = []
        var currentRows: [Row] = []
        var currentMonth: Date?
        for row in rows {
            let month = monthStart(of: row.date, calendar: calendar)
            if month != currentMonth {
                if let existing = currentMonth {
                    sections.append(section(monthStart: existing, rows: currentRows))
                }
                currentMonth = month
                currentRows = []
            }
            currentRows.append(row)
        }
        if let currentMonth, !currentRows.isEmpty {
            sections.append(section(monthStart: currentMonth, rows: currentRows))
        }
        return sections
    }

    private static func section(monthStart: Date, rows: [Row]) -> Section {
        let totalSpend = rows.reduce(Decimal.zero) { partial, row in
            switch row {
            case .entry(let entry):
                return partial + (entry.money?.homeAmount ?? Decimal.zero)
            case .group(let group):
                // The group's grand total once - never once per member row.
                return partial + group.grandTotal
            case .duplicate(let group):
                // The S2 single-count invariant: an unresolved duplicate pair
                // contributes the COUNTED entry's amount once, never twice.
                return partial + (group.counted.money?.homeAmount ?? Decimal.zero)
            }
        }
        return Section(monthStart: monthStart, totalSpend: totalSpend, rows: rows)
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
    /// rule (docs/DESIGN.md) is decided here, once, so it tests without a UI.
    init(vehicle: Vehicle, entry: any Entry) {
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
            self.showsFuelKind = Self.showsFuelKind(fill.fuelKind, vehicle: vehicle)
        case let charge as ChargeSession:
            self.kind = .charge
            self.stationId = nil
            self.provider = charge.provider
            self.vendor = nil
            self.entryTitle = nil
            self.quantity = .energyKWh(charge.energyKWh)
            self.fuelKind = nil
            self.showsFuelKind = false
        case let service as ServiceRecord:
            self.kind = .service
            self.stationId = nil
            self.provider = nil
            self.vendor = service.vendor
            self.entryTitle = nil
            self.quantity = nil
            self.fuelKind = nil
            self.showsFuelKind = false
        case let expense as Expense:
            self.kind = .expense
            self.stationId = nil
            self.provider = nil
            self.vendor = nil
            self.entryTitle = expense.title
            self.quantity = nil
            self.fuelKind = nil
            self.showsFuelKind = false
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
        }
    }

    /// docs/DESIGN.md: fuel kind is shown only when it tells the user something
    /// - when the vehicle accepts more than one fuel kind, or when this entry's
    /// kind differs from the car's usual. A diesel-only car printing "Diesel"
    /// on every row is noise dressed as information.
    private static func showsFuelKind(_ fuelKind: FuelKind, vehicle: Vehicle) -> Bool {
        vehicle.fuelKinds.count > 1 || !vehicle.fuelKinds.contains(fuelKind)
    }
}
