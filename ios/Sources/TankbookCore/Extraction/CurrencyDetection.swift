import Foundation

// P2.10 - KZT is never detected. The tenge marker `тг` OCRs as `гг` on the
// Kazakh receipt (receipt-033 prints `(6000,00 гг)`), so the marker family
// alone cannot resolve it. Currency is decided from the document's own
// evidence, never from the size of a number: a tenge total of `6000.00` and a
// rouble total of `6000.00` are the same digits, only the document says which.
// Where the document does not say, nil (hard rule 13) - a currency guessed
// from magnitude is a wrong fact stated confidently.

/// Decides the currency a document uses, or nil when the document does not say.
enum CurrencyDetection {

    /// Two tiers, in order:
    ///
    /// 1. **An explicit marker.** A printed ₽/₸/€/$/руб/тенге/... names the
    ///    currency the document uses, and outranks every country heuristic.
    /// 2. **The document's own evidence.** A Kazakh receipt is in tenge - KZT
    ///    is the only legal tender there - and it says so in its tax
    ///    authority, its OFD host, its VAT acronym and its total label. This
    ///    is where the `тг` -> `гг` misread resolves: the marker itself is
    ///    unreadable, but the document still names its country.
    static func detect(in lines: [OCRLine]) -> CurrencyCode? {
        if let marker = explicitMarker(in: lines) { return marker }
        if kazakhstanEvidence(in: lines) { return .kzt }
        return nil
    }

    // MARK: - Tier 1: explicit markers

    private static func explicitMarker(in lines: [OCRLine]) -> CurrencyCode? {
        let markers: [(String, String)] = [
            ("₽", "RUB"), ("РУБ", "RUB"), ("RUB", "RUB"), ("ТЕНГЕ", "KZT"), ("KZT", "KZT"),
            ("₸", "KZT"),
            ("€", "EUR"), ("EUR", "EUR"), ("PLN", "PLN"), ("ZŁ", "PLN"),
            ("CZK", "CZK"), ("KČ", "CZK"), ("USD", "USD"), ("$", "USD"),
            ("GBP", "GBP"), ("£", "GBP"), ("CHF", "CHF")
        ]
        for line in lines {
            let upper = line.text.uppercased()
            // The two-letter tenge marker `тг` must sit beside a digit - two
            // bare letters are not a currency. Its OCR misread `гг` is
            // deliberately not here: in Russian `гг` is the years abbreviation,
            // so it is corroborated in `kazakhstanEvidence`, never alone.
            if upper.firstMatch(of: /\d\s*ТГ(?!\p{L})/) != nil { return .kzt }
            for (marker, code) in markers where upper.contains(marker) {
                if let currency = CurrencyCode(rawValue: code) { return currency }
            }
        }
        return nil
    }

    // MARK: - Tier 2: Kazakhstan document evidence

    /// Whether the document's own text names Kazakhstan. The first group of
    /// tokens exists on no non-Kazakh document - the OFD host, the tax
    /// authority abbreviation, the Kazakh VAT acronym and the Kazakh total
    /// label - so any one of them establishes the country. The second group is
    /// weaker and needs a second signal to agree: `гг` after a digit is the
    /// tenge marker `тг` as Vision reads it (receipt-033 prints
    /// `(6000,00 гг)`), but it is also the Russian years abbreviation; and the
    /// 16% rate is KZ's VAT - read as country evidence, never as a fixed set
    /// the parser keys on (receipt-037 README).
    private static func kazakhstanEvidence(in lines: [OCRLine]) -> Bool {
        let kazakhDocumentTokens = ["KOFD", "КГД", "ККС", "ЖИЫНЫ"]
        var corroboration = 0
        for line in lines {
            let upper = line.text.uppercased()
            if kazakhDocumentTokens.contains(where: upper.contains) { return true }
            if upper.firstMatch(of: /\d\s*ГГ(?!\p{L})/) != nil { corroboration += 1 }
            if upper.contains("16%") { corroboration += 1 }
            if corroboration >= 2 { return true }
        }
        return false
    }
}
