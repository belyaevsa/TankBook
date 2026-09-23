import Foundation

// The reader's answer for one pump display, and every type between the
// classifier's eight probabilities per cell and that answer. All pure values;
// the law over them is `PumpReadingLaw`. Design: docs/EXTRACTION.md -> "The
// pump reader"; the measured argument for each rule is
// agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md.

/// The transaction fields a display shows; a `board` is a grade-price cell
/// that is not the transaction (the ship gate scores the first three only).
public enum PumpField: String, Sendable, Equatable, Hashable, Codable {
    case total
    case liters
    case unitPrice
    case board
}

/// Why the law refused to commit a field or a whole reading. Diagnosis only:
/// nothing reads it back to decide a verdict (hard rule 13 - the app suggests,
/// the user decides). One case per genuinely distinct refusal, so a live
/// histogram names the branch that dominates rather than lumping every miss
/// into "did not close".
public enum PumpAbstentionReason: String, Sendable, Equatable, Codable {
    /// No window was assigned the liters role.
    case noLitersWindow
    /// The liters row's cells all read `0`: an idle pump shows nothing to read.
    case litersAllZero
    /// No window was assigned the total role, so the arithmetic has no judge.
    case noTotalWindow
    /// No unit-price window, and no board cell could stand in as the price
    /// (no board at all, or no single board closed the triple). Also the
    /// pair-commit refusal when no band bounds the implied price (decision 11):
    /// a price that is not available and cannot be bounded is not committed.
    case boardFoundNoPrice
    /// A pair no shown price validated: its implied price is in band, but the
    /// band is too wide to catch a misread pair (decision 11, PU.54 amendment).
    case priceUnvalidated
    /// The price field of a pair whose shown price validated it but differs from
    /// the price it implies by more than rounding (a loyalty discount). The pair
    /// stands - the shown price never overwrites the paid one - and the reading
    /// carries `PumpReadingCaution.shownPriceDiffers` for the form.
    case priceDisagrees
    /// The price row's candidates all fell outside the currency's price band.
    case priceOutOfBand
    /// A field's window produced no candidate string at all - no cells, more
    /// cells than the law reads, or no decimal placement to try.
    case cellUnknown
    /// Candidates formed, but no triple closed the arithmetic within the read
    /// window (exact, preset and repair tiers all failed).
    case nothingClosed
    /// More than one candidate closed the arithmetic and the survivors
    /// disagree: the read is ambiguous, so the field (or the reading) abstains.
    case ambiguous
}

/// What the form must say about a committed reading the law could not fully
/// check (decision 11, docs/EXTRACTION.md). Not a refusal - the fields commit - and
/// never a verdict: the form shows it beside the pre-filled fields.
public enum PumpReadingCaution: Sendable, Equatable {
    /// The display shows a price that differs from the one the pair implies -
    /// a discount, or a misread. Both numbers go to the form.
    case shownPriceDiffers(shown: Decimal, implied: Decimal)
}

/// One digit hypothesis for one cell, ranked by the constrained decode.
public struct PumpGlyphCandidate: Sendable, Equatable {
    public let digit: Int
    public let logPosterior: Double

    public init(digit: Int, logPosterior: Double) {
        self.digit = digit
        self.logPosterior = logPosterior
    }
}

/// Everything the law knows about one glyph cell: the raw probabilities as
/// provenance, all ten digits ranked, and whether the cell carries the
/// decimal mark.
public struct PumpCellReading: Sendable, Equatable {
    public let probabilities: [Double]
    public let ranked: [PumpGlyphCandidate]
    public let decimalPoint: Bool

    public init(probabilities: [Double], ranked: [PumpGlyphCandidate], decimalPoint: Bool) {
        self.probabilities = probabilities
        self.ranked = ranked
        self.decimalPoint = decimalPoint
    }

    /// Builds the ranking from the classifier's eight probabilities with the
    /// same likelihood rule `PumpSegmentsModel.decode` uses.
    public init(probabilities: [Double]) {
        self.probabilities = probabilities
        self.ranked = PumpSegmentsModel.rank(probabilities)
        self.decimalPoint = probabilities.count > 7 && probabilities[7] >= 0.5
    }

    /// A cell that certainly shows `digit` - the oracle-string harness's
    /// "perfect but not certain" reader, with `confidence` on every true
    /// segment state.
    public init(certainDigit digit: Int, decimalPoint: Bool, confidence: Double = 0.97) {
        let pattern = PumpSegmentsModel.digitPatterns.first { Int(String($0.digit))! == digit }!
        var probs = (0..<7).map { i in (pattern.bits >> UInt8(i)) & 1 == 1 ? confidence : 1 - confidence }
        probs.append(decimalPoint ? confidence : 1 - confidence)
        self.init(probabilities: probs)
    }

    public var top: PumpGlyphCandidate { ranked[0] }
    public var margin: Double { ranked[0].logPosterior - ranked[1].logPosterior }
}

/// A window the locator found and the slicer cut, with the role row
/// assignment gave it. The cell count is a slicer fact, not a hypothesis.
public struct PumpLocatedWindow: Sendable, Equatable {
    public let field: PumpField
    public let cells: [PumpCellReading]

    public init(field: PumpField, cells: [PumpCellReading]) {
        self.field = field
        self.cells = cells
    }
}

/// Why a field holds the value it holds. `derived` is never cross-check
/// evidence - it was computed from the other two fields.
public enum PumpFieldProvenance: Sendable, Equatable {
    case read
    case repaired(cellIndex: Int, fromDigit: Int, toDigit: Int)
    case derived
}

/// A resolved field. `value == nil` is the abstention (hard rule 13). `reason`
/// names the branch that refused where a single field abstains while the rest
/// of the reading commits; a whole-reading abstention carries the reason on the
/// `PumpDisplayReading`.
public struct PumpFieldReading: Sendable, Equatable {
    public let value: Decimal?
    public let provenance: PumpFieldProvenance?
    public let logPosterior: Double
    public let reason: PumpAbstentionReason?

    public static let abstained = PumpFieldReading(value: nil, provenance: nil, logPosterior: 0, reason: nil)

    public init(value: Decimal?, provenance: PumpFieldProvenance?, logPosterior: Double,
                reason: PumpAbstentionReason? = nil) {
        self.value = value
        self.provenance = provenance
        self.logPosterior = logPosterior
        self.reason = reason
    }

    /// An abstained field that names why it refused.
    public static func abstained(_ reason: PumpAbstentionReason) -> PumpFieldReading {
        PumpFieldReading(value: nil, provenance: nil, logPosterior: 0, reason: reason)
    }
}

/// The reader's whole answer for one photo. `reason` is non-nil exactly when
/// nothing committed; a partial read carries its reasons on the nil fields.
public struct PumpDisplayReading: Sendable, Equatable {
    public let liters: PumpFieldReading
    public let unitPrice: PumpFieldReading
    public let total: PumpFieldReading
    public let reason: PumpAbstentionReason?
    /// Set on a committed reading the form must qualify; nil otherwise.
    public let caution: PumpReadingCaution?

    /// The reason-less default, for construction only; every law verdict that
    /// commits nothing uses `abstained(_:)` and names its branch.
    public static let abstained = PumpDisplayReading(
        liters: .abstained, unitPrice: .abstained, total: .abstained, reason: nil)

    public init(liters: PumpFieldReading, unitPrice: PumpFieldReading, total: PumpFieldReading,
                reason: PumpAbstentionReason? = nil, caution: PumpReadingCaution? = nil) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
        self.reason = reason
        self.caution = caution
    }

    /// A reading that committed nothing, with the reason every field shares.
    public static func abstained(_ reason: PumpAbstentionReason) -> PumpDisplayReading {
        PumpDisplayReading(liters: .abstained, unitPrice: .abstained, total: .abstained, reason: reason)
    }

    public var committedCount: Int {
        [liters, unitPrice, total].filter { $0.value != nil }.count
    }
}

/// What a display in a currency shows: the decimals each field carries. A
/// value's digits are read from the cells; the decimal placement is a
/// convention of the head and the currency, so it is a small candidate set
/// the arithmetic chooses from, never a guess from a dot the classifier may
/// not have seen. Measured from the corpus strings (PU.14 §2.1).
public struct PumpDisplayConventions: Sendable, Equatable {
    public let volumeDecimals: [Int]
    public let priceDecimals: [Int]
    /// Decimals a total is READ with; a shorter total (one decimal on RUB
    /// heads, `3765,7`) is a truncated display value and is only ever derived.
    public let totalDecimals: [Int]
    public let truncatedTotalDecimals: [Int]

    public init(volumeDecimals: [Int], priceDecimals: [Int], totalDecimals: [Int],
                truncatedTotalDecimals: [Int]) {
        self.volumeDecimals = volumeDecimals
        self.priceDecimals = priceDecimals
        self.totalDecimals = totalDecimals
        self.truncatedTotalDecimals = truncatedTotalDecimals
    }

    public static func forCurrency(_ currency: CurrencyCode?) -> PumpDisplayConventions {
        switch currency?.rawValue {
        case "EUR":
            return PumpDisplayConventions(volumeDecimals: [2], priceDecimals: [3],
                                          totalDecimals: [2], truncatedTotalDecimals: [])
        case "RUB":
            // Some RN heads show the price to one decimal (`68,3`); the band
            // keeps `683,0` from passing as a price.
            return PumpDisplayConventions(volumeDecimals: [2], priceDecimals: [1, 2],
                                          totalDecimals: [2], truncatedTotalDecimals: [1])
        case "KZT":
            return PumpDisplayConventions(volumeDecimals: [2], priceDecimals: [0, 1],
                                          totalDecimals: [0, 2], truncatedTotalDecimals: [1])
        case "KGS":
            // Som prices are two digits to one decimal (`99,9`, video-004); the
            // default's two or three decimals can never place that mark.
            return PumpDisplayConventions(volumeDecimals: [2], priceDecimals: [1, 2],
                                          totalDecimals: [2], truncatedTotalDecimals: [1])
        default:
            return PumpDisplayConventions(volumeDecimals: [2, 3], priceDecimals: [2, 3],
                                          totalDecimals: [2], truncatedTotalDecimals: [1])
        }
    }
}
