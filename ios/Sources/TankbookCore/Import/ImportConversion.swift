import Foundation

// The candidate -> record conversion, the preview summary and the review-list
// classification (docs/API.md -> Import parsing, docs/ERRORS.md -> Import
// wizard, docs/JOURNEYS.md F6). All pure and testable without a repository:
// the preview figures come from the candidates through the SAME engine that
// computes them after commit, so approving the preview cannot approve a
// different number (F6a).

/// The one consumption figure the preview shows and the post-commit path
/// reproduces: distance-weighted L/100km over ALL conflict-free segments of the
/// merged fill history (docs/SCHEMA.md -> Derived: consumption -> LIFETIME).
/// The figure a driver can check from memory ("does 8.2 L/100km sound like your
/// car?") and, because both the preview and the post-commit computation call
/// exactly this function over the same fills, the number the user approves is
/// the number that lands. A display-only figure is the F6a failure this exists
/// to make impossible.
public enum ImportConsumption {
    public static func compute(fills: [FillUp], tankCapacityL: Double?) -> Double? {
        let segments = ConsumptionEngine.recompute(fills: fills, tankCapacityL: tankCapacityL)
        return ConsumptionEngine.lifetime(segments: segments)
    }
}

/// Turns a `fillUp` candidate into a `FillUp` targeted at `vehicle`, or nil
/// when the row cannot be mapped honestly (an unknown fuel code, or no volume -
/// hard rule 13: never guess). Fields the file lacked stay nil: an odometer
/// the source did not record is an honest absence, never `0` (F6b).
public enum ImportConverter {
    public static func makeFill(from candidate: ImportCandidate,
                                vehicle: Vehicle,
                                source: String,
                                now: Date = Date()) -> FillUp? {
        guard candidate.entityType == "fillUp" else { return nil }
        guard let fuelKind = candidate.fuelKindResolved else { return nil }
        guard let volumeL = candidate.volumeL else { return nil }

        let id = UUID.v7()
        let money: Money?
        if let wireMoney = candidate.money,
           let amount = wireMoney.amountDecimal,
           let currency = wireMoney.currencyCode {
            money = Money(amount: amount, currency: currency,
                          homeCurrency: vehicle.homeCurrency)
        } else {
            money = nil
        }
        let crossCheck = TimelineValidator.crossCheck(
            volumeL: volumeL,
            unitPrice: candidate.unitPriceDecimal,
            amount: candidate.money?.amountDecimal)

        return FillUp(
            id: id, createdAt: candidate.date, updatedAt: candidate.date, deletedAt: nil,
            vehicleId: vehicle.id, date: candidate.date, odometer: candidate.odometer,
            money: money, note: candidate.note, attachments: [],
            provenance: .import(source: source), conflict: .none, purchaseGroupId: nil,
            volumeL: volumeL, unitPrice: candidate.unitPriceDecimal,
            fuelKind: fuelKind, fuelGrade: nil, isFull: candidate.isFull ?? true,
            tankLevelAfterPct: candidate.tankLevelAfterPct, stationId: nil,
            crossCheck: crossCheck, extraction: nil)
    }

    /// Maps every candidate that can be mapped honestly; unmappable rows return
    /// as a tuple with a stable reason code (the same vocabulary as the wire's
    /// `unparsed`). Used by the review list to label why a row needs a look.
    public static func classify(_ candidate: ImportCandidate,
                                vehicle: Vehicle,
                                source: String,
                                now: Date = Date()) -> (fill: FillUp?, reason: String?) {
        guard candidate.entityType == "fillUp" else {
            return (nil, "not_fill_up")
        }
        guard candidate.fuelKindResolved != nil else {
            return (nil, "unknown_fuel_code")
        }
        guard candidate.volumeL != nil else {
            return (nil, "missing_required")
        }
        return (makeFill(from: candidate, vehicle: vehicle, source: source, now: now), nil)
    }

    /// Maps a `serviceRecord` candidate to a `ServiceRecord` targeted at
    /// `vehicle`, or nil when it cannot be mapped honestly (no money, no item).
    /// The candidate's money becomes the record's; its first line item becomes
    /// the note when the candidate carries none (PJ.9: a non-fuel row is
    /// offered as what it is, never dropped - hard rule 8).
    public static func makeService(from candidate: ImportCandidate,
                                   vehicle: Vehicle,
                                   source: String,
                                   now: Date = Date()) -> ServiceRecord? {
        guard candidate.entityType == "serviceRecord" else { return nil }
        guard let money = money(from: candidate, homeCurrency: vehicle.homeCurrency) else { return nil }
        let items = (candidate.items ?? []).compactMap(makeItem)
        guard !items.isEmpty else { return nil }
        let note = candidate.note ?? items.first?.title
        return ServiceRecord(
            id: UUID.v7(), createdAt: candidate.date, updatedAt: candidate.date,
            deletedAt: nil, vehicleId: vehicle.id, date: candidate.date,
            odometer: candidate.odometer, money: money, note: note, attachments: [],
            provenance: .import(source: source), conflict: .none, purchaseGroupId: nil,
            vendor: nil, items: items, usedParts: [], tireSetId: nil, proposedReminderId: nil)
    }

    /// Maps an `expense` candidate to an `Expense`, or nil when it cannot be
    /// mapped honestly (no money). The candidate's title feeds the expense's
    /// title, with its note as the fallback (PJ.9).
    public static func makeExpense(from candidate: ImportCandidate,
                                   vehicle: Vehicle,
                                   source: String,
                                   now: Date = Date()) -> Expense? {
        guard candidate.entityType == "expense" else { return nil }
        guard let money = money(from: candidate, homeCurrency: vehicle.homeCurrency) else { return nil }
        let category = candidate.category.flatMap { ExpenseCategory(tag: $0.tag) } ?? .other("")
        let title = candidate.title ?? candidate.note ?? ""
        return Expense(
            id: UUID.v7(), createdAt: candidate.date, updatedAt: candidate.date,
            deletedAt: nil, vehicleId: vehicle.id, date: candidate.date,
            odometer: candidate.odometer, money: money, note: candidate.note,
            attachments: [], provenance: .import(source: source), conflict: .none,
            purchaseGroupId: nil, category: category, title: title)
    }

    private static func money(from candidate: ImportCandidate,
                              homeCurrency: CurrencyCode) -> Money? {
        guard let wire = candidate.money,
              let amount = wire.amountDecimal,
              let currency = wire.currencyCode else { return nil }
        return Money(amount: amount, currency: currency, homeCurrency: homeCurrency)
    }

    private static func makeItem(_ item: ImportServiceItem) -> ServiceItem? {
        guard let title = item.title, !title.isEmpty else { return nil }
        let category = item.category.flatMap { ServiceCategory(tag: $0.tag) } ?? .other("")
        let cost = item.cost.flatMap { wire -> Money? in
            guard let amount = wire.amountDecimal, let currency = wire.currencyCode else { return nil }
            return Money(amount: amount, currency: currency, homeCurrency: .eur)
        }
        return ServiceItem(title: title, category: category, cost: cost, partNumber: nil,
                           lifetime: nil)
    }
}

extension ServiceCategory {
    /// Maps the wire's stable category tag (`MfmParser.cs`: "repair",
    /// "inspection", "oil", "wash", "parts") to the domain category. An unknown
    /// tag lands in `.other` rather than failing the row (hard rule 13: never
    /// guess, never drop).
    init(tag: String) {
        switch tag {
        case "oil": self = .oil
        case "brakes": self = .brakes
        case "tires": self = .tires
        case "battery": self = .battery
        case "filters": self = .filters
        case "inspection": self = .inspection
        case "repair": self = .repair
        case "parts": self = .parts
        case "wash": self = .wash
        default: self = .other(tag)
        }
    }
}

extension ExpenseCategory {
    /// Maps the wire's stable category tag to the domain category; unknown tags
    /// land in `.other` (hard rule 13).
    init(tag: String) {
        switch tag {
        case "insurance": self = .insurance
        case "tax": self = .tax
        case "parking": self = .parking
        case "toll": self = .toll
        case "fine": self = .fine
        case "accessory": self = .accessory
        case "parts": self = .parts
        default: self = .other(tag)
        }
    }
}

/// The review list's rows (F6b): candidates that parsed but need a human look
/// (a missing value, a cross-check that does not multiply up) and rows the
/// server could not map. Everything that mapped is kept as labelled fields;
/// only the field that is wrong is marked. `rawLine` carries the original file
/// line for the rarer case where the *mapping* is wrong rather than a value.
public struct ImportReviewRow: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sourceRow: Int
    public let kind: Kind
    /// The parsed fields when the server mapped most of the row. Mutable so the
    /// review list can fix a value (e.g. "Add odometer") before the commit.
    public var fill: FillUp?
    /// The record a `.noFuel` row becomes when the user imports it as what it
    /// is (PJ.9) - a service or an expense. nil on every other kind, and nil on
    /// a `.noFuel` row that could not be mapped honestly.
    public let nonFuel: NonFuel?
    /// The original line in the file, shown behind "Original row".
    public let rawLine: String?

    public enum Kind: Equatable, Sendable {
        /// A field the mapping expected is absent (odometer is the common one).
        case missingOdometer
        /// `volumeL x unitPrice` does not reconcile with the total.
        case crossCheckMismatch(offBy: Decimal)
        /// The row parsed but is not a fill-up (a service, an expense).
        case noFuel
        /// The server could not map the row at all; `reason` is a stable code.
        case unmappable(reason: String)
        /// The server reported it in `unparsed`; `reason` is a stable code.
        case unparsed(reason: String)
    }

    /// What a `.noFuel` row is (PJ.9): the concrete record the "Import as
    /// service / expense" action would write.
    public enum NonFuel: Equatable, Sendable {
        case service(ServiceRecord)
        case expense(Expense)
    }

    public init(id: UUID = UUID.v7(), sourceRow: Int, kind: Kind,
                fill: FillUp?, nonFuel: NonFuel? = nil, rawLine: String?) {
        self.id = id
        self.sourceRow = sourceRow
        self.kind = kind
        self.fill = fill
        self.nonFuel = nonFuel
        self.rawLine = rawLine
    }
}

/// Classifies a parse into the fills that are ready to commit and the rows that
/// need a look, preserving file order. Purely derived: given the same parse and
/// the same target vehicle, every device produces the same partition.
public enum ImportReviewClassifier {

    /// Splits the parse's candidates into ready fills and review rows, and adds
    /// the wire's `unparsed` rows (their raw lines come from `rawLinesByRow`).
    public static func partition(candidates: [ImportCandidate],
                                 unparsed: [ImportUnparsedRow],
                                 rawLinesByRow: [Int: String],
                                 vehicle: Vehicle,
                                 source: String) -> (ready: [FillUp], review: [ImportReviewRow]) {
        var ready: [FillUp] = []
        var review: [ImportReviewRow] = []

        for candidate in candidates {
            if candidate.entityType != "fillUp" {
                // A row that parsed cleanly but is not a fill-up (a service, an
                // expense). Offered as the right kind of entry rather than
                // discarded (hard rule 8, F6b) - the "Import as service /
                // expense" path (PJ.9). A row that cannot be mapped honestly
                // needs a look instead of being silently typed.
                let nonFuel: ImportReviewRow.NonFuel?
                switch candidate.entityType {
                case "serviceRecord":
                    nonFuel = ImportConverter.makeService(from: candidate, vehicle: vehicle,
                                                          source: source)
                        .map(ImportReviewRow.NonFuel.service)
                case "expense":
                    nonFuel = ImportConverter.makeExpense(from: candidate, vehicle: vehicle,
                                                          source: source)
                        .map(ImportReviewRow.NonFuel.expense)
                default:
                    nonFuel = nil
                }
                review.append(ImportReviewRow(
                    sourceRow: candidate.sourceRow,
                    kind: nonFuel == nil ? .unmappable(reason: "missing_required") : .noFuel,
                    fill: nil, nonFuel: nonFuel,
                    rawLine: rawLinesByRow[candidate.sourceRow]))
                continue
            }
            let (fill, reason) = ImportConverter.classify(candidate, vehicle: vehicle, source: source)
            guard let fill else {
                review.append(ImportReviewRow(
                    sourceRow: candidate.sourceRow,
                    kind: .unmappable(reason: reason ?? "missing_required"),
                    fill: nil,
                    rawLine: rawLinesByRow[candidate.sourceRow]))
                continue
            }
            if let kind = stillNeedsLook(fill) {
                review.append(ImportReviewRow(
                    sourceRow: candidate.sourceRow, kind: kind, fill: fill,
                    rawLine: rawLinesByRow[candidate.sourceRow]))
                continue
            }
            ready.append(fill)
        }

        for row in unparsed {
            review.append(ImportReviewRow(
                sourceRow: row.row,
                kind: .unparsed(reason: row.reason),
                fill: nil,
                rawLine: rawLinesByRow[row.row]))
        }

        review.sort { $0.sourceRow < $1.sourceRow }
        return (ready, review)
    }

    /// Whether a converted fill still needs a human look (F6b), and why - the
    /// same predicate the partition uses, exposed so the review list can
    /// reclassify a row after the user fixes a value ("Add odometer", "Fix").
    /// nil means the row is ready to commit.
    public static func stillNeedsLook(_ fill: FillUp) -> ImportReviewRow.Kind? {
        if fill.odometer == nil { return .missingOdometer }
        if case .mismatch = fill.crossCheck,
           let amount = fill.money?.amount, let unitPrice = fill.unitPrice {
            return .crossCheckMismatch(offBy: Decimal(fill.volumeL) * unitPrice - amount)
        }
        return nil
    }
}

/// The preview gate's figures (docs/JOURNEYS.md F6a, docs/ERRORS.md -> Import
/// wizard): numbers the user can check from memory - fill-up count, date range,
/// odometer span, total spend in the file's currency, the derived consumption
/// - plus the S2 duplicate count when merging into a car that already has
/// entries (hard rule 8). Every figure comes from the candidates through the
/// same engine that computes it after commit.
public struct ImportSummary: Equatable, Sendable {
    public let fillUpCount: Int
    public let reviewCount: Int
    public let readyCount: Int
    public let firstDate: Date?
    public let lastDate: Date?
    public let odometerMin: Int?
    public let odometerMax: Int?
    public let totalSpend: Decimal?
    public let currency: CurrencyCode?
    /// L/100km over the merged fill history, from `ImportConsumption.compute`.
    public let consumptionLPer100: Double?
    public let consumptionKm: Double?
    public let consumptionLitres: Double?
    /// Unresolved S2 duplicate pairs among the merged fills (existing + import).
    public let duplicateCount: Int

    public init(fillUpCount: Int, reviewCount: Int, readyCount: Int,
                firstDate: Date?, lastDate: Date?, odometerMin: Int?, odometerMax: Int?,
                totalSpend: Decimal?, currency: CurrencyCode?,
                consumptionLPer100: Double?, consumptionKm: Double?,
                consumptionLitres: Double?, duplicateCount: Int) {
        self.fillUpCount = fillUpCount
        self.reviewCount = reviewCount
        self.readyCount = readyCount
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.odometerMin = odometerMin
        self.odometerMax = odometerMax
        self.totalSpend = totalSpend
        self.currency = currency
        self.consumptionLPer100 = consumptionLPer100
        self.consumptionKm = consumptionKm
        self.consumptionLitres = consumptionLitres
        self.duplicateCount = duplicateCount
    }

    /// Derives the preview figures from the fills the import will write plus the
    /// target car's existing fills (a merge into a car that already has entries
    /// must show the consumption and duplicates of the COMBINED history - the
    /// number the user approves is the number that lands). `declaredCurrency` is
    /// the file's currency (a default the user can correct, hard rule 13).
    public static func compute(importFills: [FillUp],
                               existingFills: [FillUp],
                               tankCapacityL: Double?,
                               declaredCurrency: CurrencyCode?,
                               duplicateResolutions: Set<DuplicateDetector.PairKey> = []) -> ImportSummary {
        let merged = importFills + existingFills
        let pairs = DuplicateDetector.pairs(in: merged, resolved: duplicateResolutions)

        let fillCount = importFills.count
        let dates = importFills.map(\.date)
        let odometers = importFills.compactMap(\.odometer)
        let spend = importFills.reduce(Decimal.zero) { partial, fill in
            guard let amount = fill.money?.amount else { return partial }
            return partial + amount
        }

        let consumption = ImportConsumption.compute(fills: merged, tankCapacityL: tankCapacityL)

        return ImportSummary(
            fillUpCount: fillCount,
            reviewCount: 0,
            readyCount: fillCount,
            firstDate: dates.min(),
            lastDate: dates.max(),
            odometerMin: odometers.min(),
            odometerMax: odometers.max(),
            totalSpend: fillCount > 0 ? spend : nil,
            currency: declaredCurrency,
            consumptionLPer100: consumption,
            consumptionKm: ImportConsumption.totalKm(fills: merged, tankCapacityL: tankCapacityL),
            consumptionLitres: ImportConsumption.totalLitres(fills: merged, tankCapacityL: tankCapacityL),
            duplicateCount: pairs.count)
    }
}

extension ImportConsumption {
    /// Σ km over the segments the consumption figure is made of - shown next to
    /// the L/100km so the figure is checkable against a real odometer span.
    static func totalKm(fills: [FillUp], tankCapacityL: Double?) -> Double? {
        let segments = ConsumptionEngine.recompute(fills: fills, tankCapacityL: tankCapacityL)
        let km = segments.reduce(0.0) { $0 + $1.km }
        return km > 0 ? km : nil
    }

    /// Σ litres over the same segments.
    static func totalLitres(fills: [FillUp], tankCapacityL: Double?) -> Double? {
        let segments = ConsumptionEngine.recompute(fills: fills, tankCapacityL: tankCapacityL)
        let litres = segments.reduce(0.0) { $0 + $1.litres }
        return litres > 0 ? litres : nil
    }
}
