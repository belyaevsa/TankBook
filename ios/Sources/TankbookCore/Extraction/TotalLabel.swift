import Foundation

enum TotalLabel {
    enum Kind { case document, primary, payment }

    private static let excluded = [
        "СУММА НДС", "СУММА БЕЗ НДС", "НДС", "ОКРУГЛЕНИЕ", "СДАЧА", "ПОЛУЧЕНО", "ПО НАЛОГУ",
        // The Estonian VAT total (`Käibemaks kokku`) contains the total word
        // `KOKKU` and would otherwise tie with the real `KOKKU` line. VAT is
        // never the receipt total; both the `Ä` and the OCR'd `A` spelling
        // are excluded.
        "KÄIBEMAKS", "KAIBEMAKS",
        // `NETO` is the Estonian net figure, not the charged amount. On the
        // Tallinn Airport parking tickets it prints beside `TASU`/`MAKSTUD`
        // (the fee and what was paid) and must never be read as the total.
        "NETO"
    ]
    // `СУММА` is here in BOTH scripts on purpose. The Latin `SUMMA` is the
    // Estonian label; the Cyrillic `СУММА` is the Russian one. The two strings
    // are different sequences of code points and `uppercased()` never bridges
    // them; the exclusion list above carries the Cyrillic `СУММА НДС`, which is
    // checked first, so a VAT line cannot be read as the total.
    //
    // The expense markers (`TASU` fee, `MAKSTUD` paid, `PAID`, `ШТРАФ` fine)
    // live in the same list because one total finder serves both entry kinds
    // (docs/EXTRACTION.md): a parking ticket prints `TASU: 4.00 EUR` /
    // `MAKSTUD: 4.00 EUR` and no fuel-receipt total word.
    private static let primary = [
        "ИТОГ", "ВСЕГО", "К ОПЛАТЕ", "TOTAL", "KOKKU", "SUMMA", "СУММА", "AMOUNT",
        "TASU", "MAKSTUD", "PAID", "ШТРАФ"
    ]
    private static let payment = [
        "НАЛИЧНЫМИ", "БЕЗНАЛИЧНЫМИ", "ПЛАТ.КАРТОЙ", "ПЛАТ. КАРТОЙ", "КАРТОЙ", "KK MAKSE"
    ]
    // A document's own grand total, which OUTRANKS a column total (the ranking
    // `grandTotalRead` applies). On a multi-column Russian invoice the `Итого:`
    // line is a column sum - several figures sit on one baseline and its nearest
    // value is whichever column happens to be beside it - while `Сумма
    // документа:` (`На сумму:` on a delivery note) is the figure the document
    // actually charges. `НА СУММУ` is the accusative form the nominative `СУММА`
    // never matches: the two are different letter sequences, exactly as the
    // Cyrillic/Latin pair above is. Checked before `primary` because
    // `СУММА ДОКУМЕНТА` contains the `СУММА` stem.
    private static let document = ["СУММА ДОКУМЕНТА", "НА СУММУ"]

    static func classify(_ text: String) -> Kind? {
        let upper = text.uppercased()
        if excluded.contains(where: upper.contains) { return nil }
        if document.contains(where: upper.contains) { return .document }
        if primary.contains(where: upper.contains) { return .primary }
        if payment.contains(where: upper.contains) { return .payment }
        return nil
    }
}
