import Foundation

// The import wire models (docs/API.md -> Import parsing, hard rule 9's named
// exception). The server returns *candidates* and commits nothing; these types
// are proposals the device reviews, edits and writes (hard rule 13). All
// numeric fields that arrive as JSON strings stay strings here and resolve via
// a POSIX locale, so a comma-decimal device locale can never corrupt a parse.

/// A supported import source as listed by `GET /import/formats` - server-driven,
/// never hardcoded (a format the picker cannot list is a format that does not
/// exist; API.md). `id` is the wire token the user's declaration is sent as.
public struct ImportFormat: Codable, Sendable, Equatable, Hashable {
    public let id: String
    public let displayName: String
    public let fileKinds: [String]
    public let helpUrl: String?
    public let addedInPackVersion: Int

    public init(id: String, displayName: String, fileKinds: [String],
                helpUrl: String?, addedInPackVersion: Int) {
        self.id = id
        self.displayName = displayName
        self.fileKinds = fileKinds
        self.helpUrl = helpUrl
        self.addedInPackVersion = addedInPackVersion
    }
}

/// `money` on a candidate: the amount as printed and the currency the file
/// declares. Strings on the wire; resolved with a POSIX locale.
public struct ImportMoney: Codable, Sendable, Equatable {
    public let amount: String
    public let currency: String

    public init(amount: String, currency: String) {
        self.amount = amount
        self.currency = currency
    }

    /// `amount` as a Decimal, parsed with a POSIX locale so a comma-decimal
    /// device never misreads a dot-decimal file.
    public var amountDecimal: Decimal? {
        Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
    }

    public var currencyCode: CurrencyCode? {
        CurrencyCode(rawValue: currency)
    }
}

/// The candidate's provenance, echoed from the parse (`tag: "import"`,
/// `source: <format id>`).
public struct ImportProvenance: Codable, Sendable, Equatable {
    public let tag: String
    public let source: String

    public init(tag: String, source: String) {
        self.tag = tag
        self.source = source
    }
}

/// A non-fuel candidate's invoice line item (docs/API.md; the server's
/// `serviceRecord` payloads carry `items`). `category.tag` is the wire's stable
/// code ("repair", "oil", "wash", ...); `cost` the item's money.
public struct ImportServiceItem: Codable, Sendable, Equatable {
    public let title: String?
    public let category: ImportCategoryTag?
    public let cost: ImportMoney?

    public init(title: String?, category: ImportCategoryTag?, cost: ImportMoney?) {
        self.title = title
        self.category = category
        self.cost = cost
    }
}

/// A `{ tag }` category payload on a non-fuel candidate.
public struct ImportCategoryTag: Codable, Sendable, Equatable {
    public let tag: String

    public init(tag: String) {
        self.tag = tag
    }
}

/// One parsed row - a proposal the device may commit (docs/API.md). The fields
/// follow the entity payloads the device writes; `sourceRow` is the 1-based
/// data-row number in the file, and `vehicleName` the car the row belonged to
/// in the source app. A missing value stays missing: `odometer` is nil, never
/// coerced to `0` (F6b - a blank is an honest absence). Non-fuel rows
/// (`entityType` `serviceRecord`/`expense`) carry `items`/`category`/`title`
/// instead of the fuel fields; the others stay nil for them (PJ.9).
public struct ImportCandidate: Codable, Sendable, Equatable {
    public let entityType: String
    public let date: Date
    public let odometer: Int?
    public let volumeL: Double?
    public let unitPrice: String?
    public let money: ImportMoney?
    public let fuelKind: String?
    public let isFull: Bool?
    public let tankLevelAfterPct: Double?
    public let note: String?
    public let vehicleName: String?
    public let provenance: ImportProvenance?
    public let sourceRow: Int
    /// A `serviceRecord` candidate's invoice line items.
    public let items: [ImportServiceItem]?
    /// An `expense` candidate's category.
    public let category: ImportCategoryTag?
    /// An `expense` candidate's title.
    public let title: String?

    public init(entityType: String, date: Date, odometer: Int?, volumeL: Double?,
                unitPrice: String?, money: ImportMoney?, fuelKind: String?,
                isFull: Bool?, tankLevelAfterPct: Double?, note: String?,
                vehicleName: String?, provenance: ImportProvenance?, sourceRow: Int,
                items: [ImportServiceItem]? = nil,
                category: ImportCategoryTag? = nil,
                title: String? = nil) {
        self.entityType = entityType
        self.date = date
        self.odometer = odometer
        self.volumeL = volumeL
        self.unitPrice = unitPrice
        self.money = money
        self.fuelKind = fuelKind
        self.isFull = isFull
        self.tankLevelAfterPct = tankLevelAfterPct
        self.note = note
        self.vehicleName = vehicleName
        self.provenance = provenance
        self.sourceRow = sourceRow
        self.items = items
        self.category = category
        self.title = title
    }

    /// The fuel kind the file declared, if it maps to a kind Tankbook models.
    /// An unknown code resolves to nil (the row then needs a look) rather than
    /// failing the whole parse.
    public var fuelKindResolved: FuelKind? {
        fuelKind.flatMap(FuelKind.init(rawValue:))
    }

    /// `unitPrice` as a Decimal with a POSIX locale (dot-decimal files must not
    /// be misread by a comma-decimal device).
    public var unitPriceDecimal: Decimal? {
        unitPrice.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
    }

    /// A copy with `odometer` replaced by the user's review-list edit (PJ.11).
    /// The candidate is the single source the partition reads, so an edit
    /// applied here flows through the SAME conversion and timeline validation
    /// as an untouched row - a fixed odometer can resolve a `.timelineConflict`
    /// row exactly as it resolves a `.missingOdometer` one.
    public func applyingOdometer(_ value: Int?) -> ImportCandidate {
        ImportCandidate(entityType: entityType, date: date, odometer: value,
                        volumeL: volumeL, unitPrice: unitPrice, money: money,
                        fuelKind: fuelKind, isFull: isFull,
                        tankLevelAfterPct: tankLevelAfterPct, note: note,
                        vehicleName: vehicleName, provenance: provenance,
                        sourceRow: sourceRow, items: items, category: category,
                        title: title)
    }

    /// A copy with the total replaced by the user's review-list edit (PJ.11).
    /// The cross-check is recomputed at conversion from the edited amount, so
    /// a corrected total resolves a `.crossCheckMismatch` row exactly as the
    /// partition's own check does - the number the user approves is the number
    /// that lands (F6a).
    public func applyingTotal(_ amount: Decimal) -> ImportCandidate {
        let text = (amount as NSDecimalNumber).stringValue
        let edited = money.map { ImportMoney(amount: text, currency: $0.currency) }
        return ImportCandidate(entityType: entityType, date: date, odometer: odometer,
                               volumeL: volumeL, unitPrice: unitPrice, money: edited,
                               fuelKind: fuelKind, isFull: isFull,
                               tankLevelAfterPct: tankLevelAfterPct, note: note,
                               vehicleName: vehicleName, provenance: provenance,
                               sourceRow: sourceRow, items: items, category: category,
                               title: title)
    }
}

/// A row the server could not map (docs/API.md): `row` is the same 1-based
/// data-row numbering as `ImportCandidate.sourceRow`, `reason` a stable code
/// (`invalid_date`, `invalid_number`, `missing_required`, `unknown_fuel_code`,
/// `unknown_finance_category`, `wrong_column_count`). Unparseable rows do not
/// fail the file - they land on the review list (F6, hard rule 8).
public struct ImportUnparsedRow: Codable, Sendable, Equatable {
    public let row: Int
    public let reason: String

    public init(row: Int, reason: String) {
        self.row = row
        self.reason = reason
    }
}

/// An F6 once-per-file question, returned instead of guessed
/// (docs/API.md): `kind` is `dateFormat` | `currency` | `units` | `outOfScope`.
public struct ImportAmbiguity: Codable, Sendable, Equatable {
    public let kind: String
    public let options: [String]
    public let rowCount: Int

    public init(kind: String, options: [String], rowCount: Int) {
        self.kind = kind
        self.options = options
        self.rowCount = rowCount
    }
}

/// The full `POST /import/parse` / `GET /import/{id}` response.
public struct ImportParseResponse: Codable, Sendable, Equatable {
    public let importId: String
    public let format: String
    public let scope: String
    public let candidates: [ImportCandidate]
    public let unparsed: [ImportUnparsedRow]
    public let ambiguities: [ImportAmbiguity]

    public init(importId: String, format: String, scope: String,
                candidates: [ImportCandidate], unparsed: [ImportUnparsedRow],
                ambiguities: [ImportAmbiguity]) {
        self.importId = importId
        self.format = format
        self.scope = scope
        self.candidates = candidates
        self.unparsed = unparsed
        self.ambiguities = ambiguities
    }

    /// The currency the file declares, if any (the `currency` ambiguity's first
    /// option, else the first candidate's). A default the user can correct
    /// (hard rule 13), never a fact.
    public var declaredCurrency: CurrencyCode? {
        if let option = ambiguities.first(where: { $0.kind == "currency" })?.options.first {
            return CurrencyCode(rawValue: option)
        }
        return candidates.first(where: { $0.money != nil })?.money?.currencyCode
    }

    /// Whether the import may be confirmed (PJ.10): every F6 question the
    /// server raised is answered. A `dateFormat` ambiguity unanswered would
    /// commit the file under the parser's guessed M/D reading (docs/JOURNEYS.md
    /// F6, docs/API.md) - so it blocks the commit until `dateFormatAnswer` is
    /// set. No ambiguity is an unconditional pass.
    public func canCommit(dateFormatAnswer: String?) -> Bool {
        guard ambiguities.contains(where: { $0.kind == "dateFormat" }) else { return true }
        return dateFormatAnswer != nil
    }

    /// A copy whose ambiguous candidates are re-dated to the D/M reading
    /// (month and day swapped): the answer to the `dateFormat` question when
    /// the user chooses `options[1]`. The wire carries the M/D reading, so only
    /// the counted rows change - a candidate whose day is ≤ 12 is genuinely
    /// ambiguous (the same string parses either way), and one whose day is > 12
    /// parses the same under both readings and stays untouched. A fixed UTC
    /// calendar keeps a non-UTC device from shifting the date a day.
    public func reDatingAsDMY() -> ImportParseResponse {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return ImportParseResponse(
            importId: importId, format: format, scope: scope,
            candidates: candidates.map { $0.reDatingToDMY(calendar: calendar) ?? $0 },
            unparsed: unparsed, ambiguities: ambiguities)
    }
}

extension ImportCandidate {
    /// The D/M flip of this candidate's date, or nil when it is not ambiguous
    /// (its day is > 12, so both readings agree). Uses `calendar` only for its
    /// component extraction - the caller fixes a timezone so the device's own
    /// cannot shift the UTC-midnight date a day.
    func reDatingToDMY(calendar: Calendar) -> ImportCandidate? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month,
              let day = components.day, day <= 12,
              let flipped = calendar.date(from: DateComponents(year: year, month: day, day: month)) else {
            return nil
        }
        return ImportCandidate(entityType: entityType, date: flipped, odometer: odometer,
                               volumeL: volumeL, unitPrice: unitPrice, money: money,
                               fuelKind: fuelKind, isFull: isFull,
                               tankLevelAfterPct: tankLevelAfterPct, note: note,
                               vehicleName: vehicleName, provenance: provenance,
                               sourceRow: sourceRow, items: items, category: category,
                               title: title)
    }
}

/// Resolves the `dateFormat` question's answer to the candidate set the
/// preview and the commit should read (PJ.10). The wire carries the M/D
/// reading; choosing the flip reading re-dates the ambiguous rows, anything
/// else leaves the candidates as the server sent them. One place for the
/// decision so the preview, the review list and the commit cannot disagree
/// about which dates a file carries (F6a).
public enum ImportDateFormat {
    public static func candidates(for parse: ImportParseResponse,
                                  answer: String?) -> [ImportCandidate] {
        guard let answer,
              let ambiguity = parse.ambiguities.first(where: { $0.kind == "dateFormat" }),
              ambiguity.options.count == 2,
              answer == ambiguity.options[1] else {
            return parse.candidates
        }
        return parse.reDatingAsDMY().candidates
    }
}
