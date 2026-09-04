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
    /// 3. **The same reasoning, applied to Russia** (2026-09-04). A Russian
    ///    cash-register receipt is denominated in roubles as a matter of law
    ///    (54-ФЗ), and it names its country the same way the Kazakh one does:
    ///    the cash register (`ККТ`), the fiscal-data operator (`ОФД`), the tax
    ///    service host (`nalog.ru`), the taxpayer number (`ИНН`) and the fiscal
    ///    document trio (`ФН`/`ФД`/`ФП`). This gate exists because the marker
    ///    tier resolves only 11 of the corpus's 39 currency cells: most Russian
    ///    receipts print no currency word Vision reads, so 28 of them came back
    ///    nil while plainly saying which country's fiscal system issued them.
    ///
    ///    **Kazakhstan is checked first and keeps winning**, which matters
    ///    because `receipt-033` is a Kazakh receipt printed in Russian; it
    ///    carries `КГД`, `ККС` and `ЖИЫНЫ` and no `ИНН`/`ККТ` at all.
    static func detect(in lines: [OCRLine]) -> CurrencyCode? {
        if let marker = explicitMarker(in: lines) { return marker }
        if kazakhstanEvidence(in: lines) { return .kzt }
        if russiaEvidence(in: lines) { return .rub }
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
    // MARK: - Tier 3: Russian fiscal document evidence

    /// Whether the document's own text names the Russian fiscal system.
    ///
    /// Matching runs on the homoglyph-canonical key
    /// (`FuelKindNormalizer.canonicalKey`), because Vision picks glyphs by
    /// shape and reads the very same acronym as `ККТ` on one receipt and Latin
    /// `KKT` on the next (receipt-036 against receipt-044). Canonicalising both
    /// sides is how P2.11 already handles `АИ-95` and it costs nothing here.
    ///
    /// Two groups, the same shape as the Kazakh gate above. The first exists on
    /// no receipt outside the Russian system: the cash register acronym, the
    /// fiscal-data operator, and the tax service's own host. Any one of them
    /// settles it. The second group is ordinary Russian fiscal furniture - each
    /// token is individually weak (a `ЧЕК` is just a receipt) so two must agree.
    ///
    /// What this deliberately does NOT use: the language of the receipt.
    /// Russian is printed in Kazakhstan, Belarus and Armenia, and a
    /// Russian-language receipt is not a rouble receipt - `receipt-033` is the
    /// corpus's proof. The evidence is the *fiscal system*, not the script.
    private static func russiaEvidence(in lines: [OCRLine]) -> Bool {
        let decisive = ["ККТ", "ОФД", "NALOG", "ФНС"].map(FuelKindNormalizer.canonicalKey)
        let supporting = ["ИНН", "КАССОВЫЙ ЧЕК", "ПРИХОД", "БЕЗНАЛИЧНЫМИ", "ФН ", "ФД ", "ФП "]
            .map(FuelKindNormalizer.canonicalKey)
        var corroboration = 0
        for line in lines {
            let key = FuelKindNormalizer.canonicalKey(line.text.uppercased())
            if decisive.contains(where: key.contains) { return true }
            corroboration += supporting.filter(key.contains).count
            if corroboration >= 2 { return true }
        }
        return false
    }

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
