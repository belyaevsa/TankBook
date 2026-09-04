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
