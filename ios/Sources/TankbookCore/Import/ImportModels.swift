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

/// One parsed row - a proposal the device may commit (docs/API.md). The fields
/// follow the entity payloads the device writes; `sourceRow` is the 1-based
/// data-row number in the file, and `vehicleName` the car the row belonged to
/// in the source app. A missing value stays missing: `odometer` is nil, never
/// coerced to `0` (F6b - a blank is an honest absence).
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

    public init(entityType: String, date: Date, odometer: Int?, volumeL: Double?,
                unitPrice: String?, money: ImportMoney?, fuelKind: String?,
                isFull: Bool?, tankLevelAfterPct: Double?, note: String?,
                vehicleName: String?, provenance: ImportProvenance?, sourceRow: Int) {
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
}
