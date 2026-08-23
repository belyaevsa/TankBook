import Foundation

/// Extraction result for one receipt / pump photo.
struct FuelExtraction: Codable {
    var liters: Double?
    var unitPrice: Double?
    var total: Double?
    var currency: String?
    var fuelType: String?
    var date: String?

    /// liters × unitPrice ≈ total, the built-in confidence signal.
    var crossCheckPassed: Bool {
        guard let l = liters, let p = unitPrice, let t = total else { return false }
        return abs(l * p - t) <= max(0.02, t * 0.005)
    }
}

/// Deterministic, rules-only parser over OCR'd lines. No LLM involved:
/// this spike measures how far OCR + rules alone get us.
struct FuelReceiptParser {

    // Keyword vocabularies, uppercase. EN / DE / PL / CZ / RU to start; extend as fixtures demand.
    private static let totalKeywords = [
        "TOTAL", "AMOUNT", "SUM", "SUMME", "GESAMT", "ZU ZAHLEN", "BETRAG",
        "SUMA", "RAZEM", "DO ZAPLATY", "DO ZAPŁATY",
        "CELKEM", "K UHRADE", "K ÚHRADĚ",
        "ИТОГ", "К ОПЛАТЕ", "ВСЕГО",
    ]
    private static let volumeKeywords = [
        "LITER", "LITRE", "LITR", "LTR", "MENGE", "ILOSC", "ILOŚĆ", "OBJEM", "ЛИТР", "VOLUME", "QTY",
    ]
    private static let unitPriceKeywords = [
        "/L", "PER L", "PREIS", "CENA", "PRICE", "ЦЕНА", "EUR/L", "PLN/L", "CZK/L", "€/L",
    ]
    private static let fuelTypes = [
        "V-POWER", "ULTIMATE", "EXCELLIUM", "ADBLUE",
        "DIESEL", "SUPER PLUS", "SUPER", "BENZIN",
        "E5", "E10", "B7", "B10", "HVO100", "HVO",
        "PB95", "PB98", "SP95", "SP98", "ON", "LPG", "CNG",
        "95", "98", "100", "ДТ", "АИ-95", "АИ-98", "АИ-92",
    ]
    private static let currencySymbols: [(pattern: String, code: String)] = [
        ("€", "EUR"), ("EUR", "EUR"),
        ("PLN", "PLN"), ("ZŁ", "PLN"), ("ZL", "PLN"),
        ("CZK", "CZK"), ("KČ", "CZK"), ("KC", "CZK"),
        ("USD", "USD"), ("$", "USD"),
        ("GBP", "GBP"), ("£", "GBP"),
        ("₽", "RUB"), ("RUB", "RUB"), ("РУБ", "RUB"),
        ("֏", "AMD"), ("AMD", "AMD"),
        ("₾", "GEL"), ("GEL", "GEL"),
        ("CHF", "CHF"),
    ]

    func parse(lines: [String]) -> FuelExtraction {
        var result = FuelExtraction()
        let upper = lines.map { $0.uppercased() }

        result.currency = detectCurrency(upper)
        result.fuelType = detectFuelType(upper)
        result.date = detectDate(lines)

        // Pass 1: keyword-anchored extraction.
        for (i, line) in upper.enumerated() {
            let numbers = decimals(in: line)
            if result.total == nil, Self.totalKeywords.contains(where: line.contains) {
                // Total is usually the largest number on its line (avoids picking up VAT rate).
                result.total = numbers.max()
                // Sometimes the amount sits on the following line.
                if result.total == nil, i + 1 < upper.count {
                    result.total = decimals(in: upper[i + 1]).max()
                }
            }
            if result.liters == nil, Self.volumeKeywords.contains(where: line.contains) {
                result.liters = numbers.first { (0.5...200).contains($0) }
            }
            if result.unitPrice == nil, Self.unitPriceKeywords.contains(where: line.contains) {
                // Unit prices are typically printed with 2–3 decimals and are small-ish.
                result.unitPrice = numbers.first { (0.3...3000).contains($0) && $0 != result.liters }
            }
        }

        // Pass 1b: "42,30 L" – a number immediately followed by a lone L is the volume
        // on most European receipts, even without any volume keyword on the line.
        if result.liters == nil {
            let volumeRegex = /(\d+[.,]\d{1,3}) ?L(?![A-Z0-9])/
            for line in upper {
                if let match = line.firstMatch(of: volumeRegex),
                   let value = Double(match.1.replacing(",", with: ".")),
                   (0.5...200).contains(value) {
                    result.liters = value
                    break
                }
            }
        }

        // Pass 2: arithmetic fallback. On pump displays (and many receipts) the three
        // numbers satisfy liters × price = total; find the best-fitting triple among
        // all decimals in the image, holding any fields pass 1 already pinned down.
        if !result.crossCheckPassed {
            let all = upper.flatMap(decimals(in:))
            if let triple = bestTriple(among: all, liters: result.liters, total: result.total) {
                result.liters = triple.liters
                result.unitPrice = triple.price
                result.total = triple.total
            }
        }
        return result
    }

    // MARK: - Helpers

    /// All decimal numbers in a line, tolerating both "," and "." separators
    /// and thousands grouping ("1 234,56", "1.234,56").
    func decimals(in line: String) -> [Double] {
        let regex = /(\d{1,3}(?:[ .]\d{3})*|\d+)[.,](\d{1,3})/
        return line.matches(of: regex).compactMap { match in
            let intPart = match.1.replacing(/[ .]/, with: "")
            return Double("\(intPart).\(match.2)")
        }
    }

    /// Best (liters, price, total) triple with liters × price ≈ total.
    /// Known fields from the keyword pass constrain the search and break the
    /// l×p / p×l symmetry that makes bare triples ambiguous.
    func bestTriple(
        among numbers: [Double], liters: Double? = nil, total: Double? = nil
    ) -> (liters: Double, price: Double, total: Double)? {
        /// A candidate assignment plus the two values used to rank it. A named
        /// type rather than a 5-tuple: at that width, positional access stops
        /// being readable and a transposed pair compiles fine.
        struct Candidate {
            let liters: Double
            let price: Double
            let total: Double
            let error: Double
            let score: Int

            /// Lower error wins; ties break toward the higher symmetry score.
            func beats(_ other: Candidate) -> Bool {
                (error, -score) < (other.error, -other.score)
            }
        }

        var best: Candidate?
        let candidates = Set(numbers).sorted()
        let litersCandidates = liters.map { [$0] } ?? candidates
        let totalCandidates = total.map { [$0] } ?? candidates
        for l in litersCandidates where (1...150).contains(l) {
            for p in candidates where p != l && (0.3...3000).contains(p) {
                for t in totalCandidates where t != l && t != p {
                    let error = abs(l * p - t)
                    guard error <= max(0.02, t * 0.005) else { continue }
                    // Symmetry breaker for equal-error assignments: unit prices are
                    // usually printed with 3 decimals, volumes with 2.
                    let score = decimalDigits(p) - decimalDigits(l)
                    let candidate = Candidate(liters: l, price: p, total: t, error: error, score: score)
                    if best == nil || candidate.beats(best!) {
                        best = candidate
                    }
                }
            }
        }
        return best.map { ($0.liters, $0.price, $0.total) }
    }

    private func decimalDigits(_ value: Double) -> Int {
        for digits in 0...3 where (value * pow(10, Double(digits))).truncatingRemainder(dividingBy: 1) < 1e-9 {
            return digits
        }
        return 3
    }

    private func detectCurrency(_ lines: [String]) -> String? {
        for line in lines {
            for (pattern, code) in Self.currencySymbols where line.contains(pattern) {
                return code
            }
        }
        return nil
    }

    private func detectFuelType(_ lines: [String]) -> String? {
        for line in lines {
            for type in Self.fuelTypes {
                // Whole-word match, so "ON" doesn't fire inside "STATION" or "E5" inside "1E55".
                let escaped = NSRegularExpression.escapedPattern(for: type)
                if line.range(of: "(?<![A-Z0-9À-Я])\(escaped)(?![A-Z0-9À-Я])", options: .regularExpression) != nil {
                    return type
                }
            }
        }
        return nil
    }

    private func detectDate(_ lines: [String]) -> String? {
        let regex = /\b(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{2,4})\b|\b(\d{4})-(\d{2})-(\d{2})\b/
        for line in lines {
            if let match = line.firstMatch(of: regex) {
                return String(match.0)
            }
        }
        return nil
    }
}
