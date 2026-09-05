import Foundation

/// Number scanning for the extraction core. Handles the separators real
/// receipts use: comma or period decimals, space as a thousands separator
/// ("1 932.00"), and a hyphen standing in for a decimal point ("2385-83", a
/// thermal-printer quirk) - plus the single-digit misread "0D" for "00".
enum NumberScanner {
    /// Every decimal number in a line, tolerating both separators and
    /// thousands grouping ("1 234,56", "1.234,56", "1 932.00"). A number with
    /// no fractional part (a bare "20" in "205.00*20") is deliberately NOT
    /// returned here - operands are parsed separately by the ladder.
    static func decimals(in line: String) -> [Double] {
        let regex = /(\d{1,3}(?:[ .]\d{3})*|\d+)[.,](\d{1,3})/
        return line.matches(of: regex).compactMap { match in
            let intPart = match.1.replacing(/[ .]/, with: "")
            return Double("\(intPart).\(match.2)")
        }
    }

    /// All numbers in a line, including bare integers ("20", "30") - used where
    /// a receipt prints a quantity without a decimal point ("23 x 73.06").
    static func numbers(in line: String) -> [Double] {
        var results = decimals(in: line)
        let tokenRegex = /\d+(?:[.,]\d+)|\d+/
        for match in line.matches(of: tokenRegex) {
            let text = String(match.0)
            if !text.contains("."), !text.contains(","),
               let value = Double(text),
               !results.contains(where: { abs($0 - value) < 1e-9 }) {
                results.append(value)
            }
        }
        return results
    }

    /// The number a right-aligned value line denotes. Safe to call on any line:
    /// it reads a decimal, a hyphen-as-decimal, or nothing.
    static func value(in line: String) -> Double? {
        let normalized = line
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "≡", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "₽", with: "")
            .replacingOccurrences(of: "฿", with: "")
            .replacingOccurrences(of: "₴", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "$", with: "")
        // A hyphen standing in for a decimal point ("2385-83" -> 2385.83).
        if let match = normalized.firstMatch(of: /(\d{3,})-(\d{2})(?![\d-])/) {
            return Double("\(match.1).\(match.2)")
        }
        return decimals(in: normalized).first
    }

    /// True when the line's number carries a leading minus: a subtraction (a
    /// VAT credit, a discount, change), never a total. A receipt total is never
    /// printed negative. The leading `=`/`#`/`≡` of a right-aligned value is
    /// stripped first, so `=961.80` is not negative while `-3555.89` (receipt-018's
    /// VAT amount) is.
    static func isNegativeAmount(_ line: String) -> Bool {
        var start = line.startIndex
        while start < line.endIndex, "=#≡ _".contains(line[start]) {
            start = line.index(after: start)
        }
        return line[start...].hasPrefix("-")
    }

    /// True when the line is a bare value: an optional `=`/currency prefix then
    /// one number, with at most a stray letter of OCR noise. Sentences like
    /// "В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83" are excluded.
    static func isValueLine(_ line: String) -> Bool {
        guard value(in: line) != nil else { return false }
        var stripped = line.uppercased()
        for token in ["НДС", "РУБ", "RUB", "EUR", "ТЕНГЕ", "=", "≡", "#", "_",
                      "₽", "฿", "₴", "€", "$", " "] {
            stripped = stripped.replacingOccurrences(of: token, with: "")
        }
        return stripped.filter { $0.isLetter }.count <= 2
    }
}

// MARK: - Pump number tokens (B2)

/// A digit run read from a pump display, kept with its raw text. A seven-segment
/// display routinely drops the decimal point, so a bare run like `12522` is a
/// candidate whose decimal scale is UNKNOWN - not a number to discard (the
/// receipt scanner's mandatory separator made exactly that discard). A run that
/// still carries a `[.,]` separator has its scale intact and reads as written.
struct PumpNumber: Sendable, Equatable {
    /// The raw digit run, e.g. `12522`, `67.00`, `005580`. Zero-padding is kept
    /// so a zero-padded Gilbarco value (`005580`) survives to have its scale
    /// searched the same way an unpadded one does.
    let raw: String
    /// Whether the run carries a decimal separator. A separator-carrying token's
    /// value is known; a bare token's value must be searched over 10^0..10^-3.
    let hasSeparator: Bool

    /// The value as written: a separator-carrying token parses directly (leading
    /// zeros dropped by `Double`), a bare token is its integer.
    var value: Double? { Double(raw.replacingOccurrences(of: ",", with: ".")) }

    /// The candidate values. A separator-carrying token has exactly one; a bare
    /// token is the integer divided by 10^k for k in 0...3 (up to three decimal
    /// places - the most a pump price or volume shows).
    func candidates() -> [Double] {
        guard let base = value else { return [] }
        guard !hasSeparator else { return [base] }
        return (0...3).map { k in base / pow(10.0, Double(k)) }
    }

    /// The candidates for a MONEY field, which is a narrower set: an amount is
    /// printed either whole or to the currency's minor unit, never to one or
    /// three decimals. `10038` on a Gilbarco is `100.38` or `10038`, never
    /// `1003.8` or `10.038`.
    ///
    /// This is what breaks the factor-of-ten tie the arithmetic cannot.
    /// `pump-057` reads `005580` and `10038` against a price of `1.799`, and
    /// BOTH `55.80 x 1.799 = 100.38` and `5.58 x 1.799 = 10.038` close exactly -
    /// the cross-check is scale-invariant, so it cannot choose, and the whole
    /// fixture abstained. Requiring the total to be money-shaped drops `10.038`,
    /// which then pins the volume through the arithmetic.
    ///
    /// **Zero decimals is kept deliberately, and it is not padding for its own
    /// sake**: a Kazakh pump truncates to whole tenge (`pump-004` prints `3008`
    /// for a 3008.34 fill, `pump-006` prints `10980`), so a 0-decimal money
    /// reading is a real one, not a fallback.
    func moneyCandidates() -> [Double] {
        guard let base = value else { return [] }
        guard !hasSeparator else { return [base] }
        return [0, 2].map { k in base / pow(10.0, Double(k)) }
    }
}

extension NumberScanner {
    /// Every digit run on a pump line, bare or separated, as a scale-unknown
    /// token. `\d+(?:[.,]\d+)?` reads both `12522` and `67.00`; a run is not
    /// discarded for missing its separator the way `decimals(in:)` would discard
    /// it. The receipt paths are untouched - this is pump-only.
    static func pumpNumbers(in line: String) -> [PumpNumber] {
        line.matches(of: /\d+(?:[.,]\d+)?/).map { match in
            let raw = String(match.0)
            return PumpNumber(raw: raw, hasSeparator: raw.contains(".") || raw.contains(","))
        }
    }
}
