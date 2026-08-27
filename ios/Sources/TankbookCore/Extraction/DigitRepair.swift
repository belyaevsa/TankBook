import Foundation

// MARK: - P2.13 seven-segment digit repair

// docs/EXTRACTION.md -> "Cross-multiplication as digit repair". On a pump
// display, `liters x unitPrice` missing `total` by one digit step of one
// operand is evidence of a SINGLE misread seven-segment bar, not of three
// independent errors: the glyphs of a seven-segment display differ by one lit
// segment, so `pump-015` reads `1.884` under glare where `15.89 x 1.889 =
// 30.02` exactly, and the same correction resolves `pump-013`
// (`7.34 x 1.779 = 13.06`).

/// Cross-multiplication as a digit-repair engine (P2.13).
///
/// When the product of the two operands misses the total by one digit step,
/// substitute the visually-confusable seven-segment pairs in turn - 4/9, 8/9,
/// 8/6, 8/0, 3/9, 5/6, 1/7 - and accept a repair only when **exactly one**
/// substitution reproduces the total at the display's money precision. If two
/// different substitutions both close the arithmetic, the document does not
/// determine the answer and the engine returns `nil` (hard rule 13: a value the
/// parser cannot know is left for the user - inventing a digit is worse than
/// abstaining, which is the lesson `pump-004` paid for when Vision returned a
/// wrong digit at confidence 1.00).
///
/// The engine is **pump source only**: thermal print has no segment topology,
/// so a receipt is never repaired - a repair there would be a fabricated number
/// with no physical story behind it.
///
/// A repair is a **suggestion, never a lock** (hard rule 13). The caller
/// (`FuelExtractor.extract`) keeps the cross-check a `mismatch` when a repair
/// fires, so the confirm screen never treats the corrected triple as confirmed;
/// the corrected value is offered as an editable pre-fill.
public enum DigitRepair {

    /// The operand the single substituted digit belonged to.
    public enum Operand: String, Sendable, Equatable, Codable {
        case liters
        case unitPrice
    }

    /// A completed repair: one digit of one operand substituted so that the
    /// product reproduces the total. `original` is what OCR delivered, `repaired`
    /// is the parser's best hypothesis for the user to confirm.
    ///
    /// `original` and `repaired` are `Double` by design (P2.2b): they are
    /// provenance of the display-precision hypothesis (at most 3 fraction
    /// digits, the pump display's precision), never the money boundary. The
    /// authoritative money write happens when `FuelExtractor.extract` assigns
    /// `repair.repaired` into `FuelExtraction.unitPrice` through the exact
    /// `ConfirmFormat.decimal(fromExtraction:)` path, and the volume operand
    /// (`liters`) stays `Double` per SCHEMA.md.
    public struct Result: Sendable, Equatable, Codable {
        public let operand: Operand
        public let original: Double
        public let repaired: Double
    }

    /// The seven-segment confusion table (docs/EXTRACTION.md). Undirected: glare
    /// can fill OR drop the distinguishing segment, so a `4` can be read as a
    /// `9` and a `9` as a `4`.
    private static let confusable: [Character: [Character]] = [
        "1": ["7"], "7": ["1"],
        "3": ["9"],
        "4": ["9"],
        "5": ["6"], "6": ["5", "8"],
        "8": ["6", "0", "9"],
        "9": ["3", "4", "8"],
        "0": ["8"]
    ]

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// Applies the digit-repair rule to a resolved triple, or returns nil.
    ///
    /// Nil means one of:
    /// - a non-pump source (a receipt is never repaired),
    /// - a missing number (no cross-check is possible),
    /// - a product that already reproduces the total (nothing to repair),
    /// - zero closing substitutions (the misread-segment hypothesis fails),
    /// - more than one (the document does not determine the answer).
    public static func apply(liters: Double?, unitPrice: Decimal?, total: Decimal?,
                             source: ExtractionSource) -> Result? {
        guard source == .pump else { return nil }
        guard let liters, let unitPrice, let total else { return nil }
        // `unitPrice` and `total` are already exact Decimals (the extraction
        // types money as Decimal since P2.2b); only the volume goes through the
        // Double -> Decimal boundary.
        guard let litersDecimal = ConfirmFormat.decimal(
                  fromExtraction: liters, fractionDigits: ConfirmFormat.fractionDigits(for: .volume)) else {
            return nil
        }
        // A triple that already reproduces the total needs no repair: the
        // misread-segment hypothesis is unnecessary.
        guard !reproduces(liters: litersDecimal, price: unitPrice, total: total) else {
            return nil
        }

        var candidates: [Result] = []
        candidates += closingCandidates(
            operand: .liters, value: liters,
            formatted: ConfirmFormat.string(
                fromExtraction: liters, fractionDigits: ConfirmFormat.fractionDigits(for: .volume)),
            other: unitPrice, total: total)
        candidates += closingCandidates(
            operand: .unitPrice, value: faithfulDouble(unitPrice),
            formatted: ConfirmFormat.string(decimal: unitPrice,
                                            fractionDigits: ConfirmFormat.fractionDigits(for: .unitPrice)),
            other: litersDecimal, total: total)
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    /// The `Double` whose value equals the decimal's shortest representation -
    /// the faithful inverse of the extraction's `Double -> Decimal(string:)`
    /// boundary, so the repair's provenance records the same `Double` the
    /// pre-P2.2b pipeline carried (`NSDecimalNumber.doubleValue` can land one
    /// ULP off for values like 1.774).
    private static func faithfulDouble(_ value: Decimal) -> Double {
        Double("\(value)") ?? 0
    }

    // MARK: - Candidates

    /// The closing substitutions for one operand: every single-digit change
    /// against the confusion table whose repaired product reproduces the total.
    private static func closingCandidates(operand: Operand, value: Double, formatted: String,
                                          other: Decimal, total: Decimal) -> [Result] {
        let chars = Array(formatted)
        var results: [Result] = []
        for index in chars.indices {
            guard let partners = confusable[chars[index]] else { continue }
            for partner in partners {
                var substituted = chars
                substituted[index] = partner
                let text = String(substituted)
                guard let repairedValue = Double(text),
                      let repaired = Decimal(string: text, locale: posixLocale) else { continue }
                let closes = operand == .liters
                    ? reproduces(liters: repaired, price: other, total: total)
                    : reproduces(liters: other, price: repaired, total: total)
                if closes {
                    results.append(Result(operand: operand, original: value, repaired: repairedValue))
                }
            }
        }
        return results
    }

    /// Whether `liters x price` reproduces `total` at the display's two-decimal
    /// money precision. The pump prints money to two places, so "closes" means
    /// the repaired product ROUNDS to the printed total - the strictest honest
    /// reading of "15.89 x 1.889 = 30.02 exactly" (fixtures/pump/README.md).
    private static func reproduces(liters: Decimal, price: Decimal, total: Decimal) -> Bool {
        var product = liters * price
        var rounded = Decimal()
        NSDecimalRound(&rounded, &product, 2, .plain)
        return rounded == total
    }
}
