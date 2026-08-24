import Foundation

// Fiscal QR (ФНС / OFD) payload parser and anchor (docs/TASKS.md P2.6, the
// parser half; docs/JOURNEYS.md J5 and F5; Spike/ReceiptSpike/fixtures/fiscal/README.md).
//
// The QR is NOT a capture path: its payload carries exactly six fields - the
// total `s`, the timestamp `t`, and three fiscal identifiers `fn`/`i`/`fp`,
// plus the operation type `n` - and nothing else. No litres, no unit price,
// no fuel kind, no station. Its job is to act as an authoritative ANCHOR for
// an OCR result: the total and date outrank anything OCR produced, and a
// disagreement between the QR grand total and an OCR fuel line is the signal
// that a receipt is mixed (hard rule 4: the fill-up amount is the fuel line,
// never the receipt grand total).
//
// Enrichment (looking up line items) is permanently deferred: the OFD document
// URL is keyed on an opaque id that is not derivable from the QR (verified
// against two OFDs). Nothing here does any networking - parsing works fully
// offline (hard rule 1).

// MARK: - The payload

/// The six fields carried by a ФНС fiscal QR, decoded from a `String` that a
/// QR detector already produced. Field names follow the canonical ФНС keys.
public struct FiscalQRPayload: Equatable, Sendable {
    public let timestamp: Date
    public let total: Decimal
    public let fiscalDriveNumber: String    // fn
    public let documentNumber: String       // i
    public let fiscalSign: String           // fp
    public let operationType: Int           // n

    public init(timestamp: Date, total: Decimal,
                fiscalDriveNumber: String, documentNumber: String,
                fiscalSign: String, operationType: Int) {
        self.timestamp = timestamp
        self.total = total
        self.fiscalDriveNumber = fiscalDriveNumber
        self.documentNumber = documentNumber
        self.fiscalSign = fiscalSign
        self.operationType = operationType
    }

    /// The stable fiscal identity of this document: `fn` + `i` + `fp` together
    /// identify a fiscal document uniquely, so a re-scan of the same receipt is
    /// recognisable as the same purchase rather than a second fill-up.
    public var fiscalDocumentIdentity: FiscalDocumentIdentity {
        FiscalDocumentIdentity(fiscalDriveNumber: fiscalDriveNumber,
                               documentNumber: documentNumber,
                               fiscalSign: fiscalSign)
    }

    /// What this QR can authoritatively assert about a purchase, for an OCR
    /// result to be checked against (see `FiscalQRAnchor`).
    public var anchor: FiscalQRAnchor {
        FiscalQRAnchor(payload: self)
    }
}

// MARK: - The ФНС field keys

/// The canonical key of each ФНС payload field. Used to report field *names*
/// (never values) in parse errors and logs (docs/LOGGING.md, hard rule 12).
public enum FiscalQRField: String, Sendable, Equatable, CaseIterable {
    case timestamp = "t"
    case total = "s"
    case fiscalDriveNumber = "fn"
    case documentNumber = "i"
    case fiscalSign = "fp"
    case operationType = "n"
}

// MARK: - Parse errors

/// A typed parse failure. `reasonCode` is the stable, loggable description; it
/// carries field *names* and reasons only, never a domain value (total,
/// timestamp, or any of `fn`/`i`/`fp`) - docs/LOGGING.md, hard rule 12.
public enum FiscalQRParseError: Error, Sendable, Equatable {
    /// The input was empty.
    case emptyInput
    /// The input exceeded `FiscalQRParser.maxInputLength`.
    case inputTooLong
    /// A `&`-separated segment was not a `key=value` pair.
    case malformedPair
    /// A required key was absent.
    case missingField(FiscalQRField)
    /// A key appeared more than once.
    case duplicatedField(FiscalQRField)
    /// `s` was present but not a decimal number.
    case nonNumericTotal
    /// `t` was present but not a valid `yyyyMMdd'T'HHmm[ss]` timestamp.
    case invalidTimestamp
    /// `fn`, `i` or `fp` was present but not a run of decimal digits.
    case nonNumericFiscalIdentifier(FiscalQRField)
    /// `n` was present but not an integer.
    case invalidOperationType

    /// The stable code used when logging this failure. Field names are safe to
    /// log; the offending value is never attached.
    public var reasonCode: String {
        switch self {
        case .emptyInput: return "emptyInput"
        case .inputTooLong: return "inputTooLong"
        case .malformedPair: return "malformedPair"
        case .missingField(let field): return "missingField:\(field.rawValue)"
        case .duplicatedField(let field): return "duplicatedField:\(field.rawValue)"
        case .nonNumericTotal: return "nonNumericTotal"
        case .invalidTimestamp: return "invalidTimestamp"
        case .nonNumericFiscalIdentifier(let field): return "nonNumericFiscalId:\(field.rawValue)"
        case .invalidOperationType: return "invalidOperationType"
        }
    }
}

// MARK: - Parser

/// Parses a ФНС QR payload `String` into a `FiscalQRPayload`.
///
/// Tolerances, all deliberate (the format may grow and the fixtures show it
/// varies):
/// - Order-independent: `t` need not come first.
/// - Tolerant of unknown extra keys, which are ignored.
/// - Case-insensitive on keys (`S=...` and `s=...` both parse).
/// - The timestamp has two valid forms - `yyyyMMdd'T'HHmm` and
///   `yyyyMMdd'T'HHmmss` - both present in the real corpus.
/// - `fp` and `i` are variable-length numbers (8, 9 and 10 digits are all in
///   the corpus); never validated to a fixed width.
///
/// The timestamp is a LOCAL wall-clock time with no zone in the payload, so
/// `timeZone` is injected and never taken from the device ambient (hard rule
/// 13's spirit applied to parsing: the value is interpreted in the zone the
/// caller supplies, not silently shifted by the device's zone).
public enum FiscalQRParser {

    /// Upper bound on a payload's length. A real payload is a few dozen bytes;
    /// the bound exists so absurdly long input is rejected deterministically
    /// rather than parsed. Generous on purpose, since unknown keys are legal.
    public static let maxInputLength = 4096

    /// Parses a payload, throwing a typed `FiscalQRParseError` on any malformed
    /// input. Never `fatalError`s, never force-unwraps.
    public static func parse(_ raw: String, timeZone: TimeZone) throws -> FiscalQRPayload {
        guard !raw.isEmpty else { throw FiscalQRParseError.emptyInput }
        guard raw.count <= maxInputLength else { throw FiscalQRParseError.inputTooLong }
        return try build(from: collectFields(from: raw), timeZone: timeZone)
    }

    // MARK: Private

    /// The fields that must be present, checked in this order so the first
    /// missing one is reported deterministically.
    private static let requiredOrder: [FiscalQRField] = [
        .timestamp, .total, .fiscalDriveNumber, .documentNumber, .fiscalSign, .operationType
    ]

    private static let fiscalIdentifierFields: [FiscalQRField] = [
        .fiscalDriveNumber, .documentNumber, .fiscalSign
    ]

    /// Splits the payload into `key=value` pairs and maps the known keys to
    /// their fields. Unknown keys are ignored; malformed or duplicated known
    /// keys throw.
    private static func collectFields(from raw: String) throws -> [FiscalQRField: String] {
        var values: [FiscalQRField: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: false) {
            guard !pair.isEmpty else { throw FiscalQRParseError.malformedPair }
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2, !kv[0].isEmpty else { throw FiscalQRParseError.malformedPair }
            guard let field = field(forKey: kv[0].lowercased()) else { continue }
            guard values[field] == nil else { throw FiscalQRParseError.duplicatedField(field) }
            values[field] = String(kv[1])
        }
        return values
    }

    /// Validates the collected fields and constructs the payload. Values are
    /// read with `value(_:from:)` (a defaulted subscript), never a force-unwrap.
    private static func build(from values: [FiscalQRField: String], timeZone: TimeZone) throws -> FiscalQRPayload {
        for field in requiredOrder where values[field] == nil {
            throw FiscalQRParseError.missingField(field)
        }

        guard let total = Decimal(string: value(.total, from: values), locale: posixLocale) else {
            throw FiscalQRParseError.nonNumericTotal
        }
        let timestamp = try parseTimestamp(value(.timestamp, from: values), timeZone: timeZone)
        for field in fiscalIdentifierFields {
            guard isDecimalDigits(value(field, from: values)) else {
                throw FiscalQRParseError.nonNumericFiscalIdentifier(field)
            }
        }
        guard let operationType = Int(value(.operationType, from: values)) else {
            throw FiscalQRParseError.invalidOperationType
        }

        return FiscalQRPayload(timestamp: timestamp,
                               total: total,
                               fiscalDriveNumber: value(.fiscalDriveNumber, from: values),
                               documentNumber: value(.documentNumber, from: values),
                               fiscalSign: value(.fiscalSign, from: values),
                               operationType: operationType)
    }

    /// The value for a field, or an empty string when absent. An empty string
    /// then fails the field's own validation, so a value is never force-unwrapped.
    private static func value(_ field: FiscalQRField, from values: [FiscalQRField: String]) -> String {
        values[field, default: ""]
    }

    /// Case-insensitive key lookup against the canonical lowercase keys.
    private static let keyMap: [String: FiscalQRField] = {
        var map: [String: FiscalQRField] = [:]
        for field in FiscalQRField.allCases {
            map[field.rawValue] = field
        }
        return map
    }()

    private static func field(forKey key: String) -> FiscalQRField? {
        keyMap[key]
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// True when `value` is a non-empty run of ASCII decimal digits.
    private static func isDecimalDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48 ... 57).contains($0.value) }
    }

    private static func parseTimestamp(_ value: String, timeZone: TimeZone) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let date = formatter.date(from: value) { return date }
        formatter.dateFormat = "yyyyMMdd'T'HHmm"
        if let date = formatter.date(from: value) { return date }
        throw FiscalQRParseError.invalidTimestamp
    }
}

// MARK: - The anchor

/// What the QR can authoritatively assert about a purchase.
///
/// `total` and `date` are exact and outrank anything OCR produced for the same
/// receipt. `liters`, `unitPrice` and `fuelKind` are EMPTY - always - because
/// the QR does not carry them. They are `nil`, not zero: a zero litre count is
/// a wrong fact, `nil` is an honest absence. Never derive, guess or default
/// them - a field the user fills is correct, a fabricated one is the defect
/// (hard rule 13). Works with no network at all (hard rule 1).
public struct FiscalQRAnchor: Equatable, Sendable {
    public let total: Decimal
    public let date: Date
    public let liters: Double?       // always nil - the QR carries no volume
    public let unitPrice: Decimal?   // always nil - the QR carries no unit price
    public let fuelKind: FuelKind?   // always nil - the QR carries no fuel kind

    public init(payload: FiscalQRPayload) {
        self.total = payload.total
        self.date = payload.timestamp
        self.liters = nil
        self.unitPrice = nil
        self.fuelKind = nil
    }

    public init(total: Decimal, date: Date) {
        self.total = total
        self.date = date
        self.liters = nil
        self.unitPrice = nil
        self.fuelKind = nil
    }
}

// MARK: - Duplicate identity

/// The unique identity of a fiscal document: `fn` + `i` + `fp` together. A
/// re-scan of the same receipt yields the same identity and is recognised as
/// the same purchase rather than a second fill-up. Not wired into duplicate
/// detection (that is P2.4) - provided here and tested.
public struct FiscalDocumentIdentity: Hashable, Sendable {
    public let fiscalDriveNumber: String
    public let documentNumber: String
    public let fiscalSign: String

    public init(fiscalDriveNumber: String, documentNumber: String, fiscalSign: String) {
        self.fiscalDriveNumber = fiscalDriveNumber
        self.documentNumber = documentNumber
        self.fiscalSign = fiscalSign
    }

    /// A stable string form of the identity. The three components are decimal
    /// digit strings, so the delimiter cannot appear inside any of them.
    public var key: String {
        "\(fiscalDriveNumber):\(documentNumber):\(fiscalSign)"
    }
}

// MARK: - Cross-check

/// The classification of a QR grand total against a candidate total extracted
/// from the same receipt. Typed on purpose - a `Bool` could not carry the
/// three-way distinction between "confirmed", "OCR grabbed the wrong line",
/// and "this receipt is mixed".
public enum FiscalQRCrossCheckResult: Equatable, Sendable {
    /// The candidate matches the QR grand total. The OCR total is confirmed.
    case agrees
    /// The candidate does not match, and the QR wins for the grand total. On
    /// the corpus this catches an OCR total that was actually the VAT line or
    /// the rounding line.
    case disagrees
    /// The candidate is the fuel line of a receipt that also carries non-fuel
    /// items: less than the QR grand total by more than tolerance, but still
    /// most of it. Not an error - the fill-up amount is the fuel line, not the
    /// grand total (hard rule 4), so the fuel line stands.
    case suggestsMixedReceipt
}

/// The pure cross-check function. Not wired into the parser, the duplicate
/// detector or any screen - those are P2.2/P2.3/P2.4.
public enum FiscalQRCrossCheck {

    /// The money tolerance within which a candidate is treated as the same
    /// figure as the QR grand total. One rouble absorbs ЛУКОЙЛ-style whole-rouble
    /// rounding (the fiscal total is rounded down to the whole rouble) and
    /// kopeck-level OCR slips.
    public static let tolerance: Decimal = Decimal(1)

    /// At or above this fraction of the grand total, a candidate that is short
    /// of the QR total is treated as the fuel line of a mixed receipt rather
    /// than a mis-read line. A VAT line is at most ~22% of the gross and a
    /// rounding line is < 1 rouble, while a fuel line is the dominant item, so
    /// half is a safe boundary. A heuristic, not a fact - the app suggests, the
    /// user decides (hard rule 13).
    public static let mixedReceiptFuelLineFloor: Decimal = Decimal(1) / Decimal(2)

    /// Classifies `candidateTotal` against the authoritative `qrTotal`.
    public static func classify(qrTotal: Decimal, candidateTotal: Decimal) -> FiscalQRCrossCheckResult {
        if abs(qrTotal - candidateTotal) <= tolerance { return .agrees }
        if candidateTotal < qrTotal && candidateTotal >= qrTotal * mixedReceiptFuelLineFloor {
            return .suggestsMixedReceipt
        }
        return .disagrees
    }
}

// MARK: - Logging

/// Emits the fiscal-QR parse event without leaking domain values. On success it
/// logs only that the payload parsed; on failure it logs the stable reason code
/// (which carries field *names*, never values) - docs/LOGGING.md, hard rule 12.
public enum FiscalQRLogging {
    public static func report(_ result: Result<FiscalQRPayload, FiscalQRParseError>,
                              to log: TankbookLog, traceId: UUID? = nil) {
        switch result {
        case .success:
            log.emit(FiscalQRParse(outcome: .parsed), traceId: traceId)
        case .failure(let error):
            log.emit(FiscalQRParse(outcome: .rejected, reason: error.reasonCode), traceId: traceId)
        }
    }
}
