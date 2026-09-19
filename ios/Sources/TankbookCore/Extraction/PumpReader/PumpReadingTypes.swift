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

/// A resolved field. `value == nil` is the abstention (hard rule 13).
public struct PumpFieldReading: Sendable, Equatable {
    public let value: Decimal?
    public let provenance: PumpFieldProvenance?
    public let logPosterior: Double

    public static let abstained = PumpFieldReading(value: nil, provenance: nil, logPosterior: 0)

    public init(value: Decimal?, provenance: PumpFieldProvenance?, logPosterior: Double) {
        self.value = value
        self.provenance = provenance
        self.logPosterior = logPosterior
    }
}

/// The reader's whole answer for one photo.
public struct PumpDisplayReading: Sendable, Equatable {
    public let liters: PumpFieldReading
    public let unitPrice: PumpFieldReading
    public let total: PumpFieldReading

    public static let abstained = PumpDisplayReading(
        liters: .abstained, unitPrice: .abstained, total: .abstained)

    public init(liters: PumpFieldReading, unitPrice: PumpFieldReading, total: PumpFieldReading) {
        self.liters = liters
        self.unitPrice = unitPrice
        self.total = total
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
        default:
            return PumpDisplayConventions(volumeDecimals: [2, 3], priceDecimals: [2, 3],
                                          totalDecimals: [2], truncatedTotalDecimals: [1])
        }
    }
}
