import Foundation

// RV.48 - the cleaning stage. "The data must be stripped, filtered and left
// only meaningful. That's the goal of the local OCR." (product owner,
// 2026-09-04, docs/TASKS.md -> RV.48)
//
// A fuel receipt prints far more numbers than it prints facts. Before this
// filter existed every one of them was a candidate operand, and four fixtures
// in the corpus proved what that costs - not a missed field, which is
// recoverable, but a CONFIDENT WRONG ONE, which hard rule 13 forbids outright:
//
//   receipt-023  volume 32986034.000  from `wNLL32986034/90`
//   receipt-046  volume 10180925.000  from `Reg.kood 10180925, KMKR nr• EE1003L`
//   receipt-041  volume 5.000         from `2X5LT6`, a card authorisation code
//                                     that parses as the operand pair `2 X 5L`
//   receipt-044  volume 1.000 AND fuel kind `lpg`
//                                     from `1 ед.=1 литр для нефтепродуктов/суг`
//
// Two properties make this a filter rather than a deletion, and both matter.
//
// **It tags, it never deletes.** The raw OCR text is kept in full (RV.48's
// storage half): it is the evidence that lets a bad parse be re-examined, and
// docs/EXTRACTION.md's named failure modes are pinned to it. This type only
// decides which lines may produce a NUMBER CANDIDATE.
//
// **The evidence gates keep reading the raw lines.** `CurrencyDetection`
// resolves a Russian receipt's currency precisely FROM `ИНН`, `ККТ` and `ОФД` -
// the very lines classified as noise here. A filter applied before that gate
// would delete the evidence it runs on, so `FuelExtractor` passes raw lines to
// currency and date detection and filtered lines only to the value finders.

/// Why a line cannot carry an entry value. The case is the record of what was
/// recognised; a line with no case is a line the value finders may read.
public enum ReceiptNoiseClass: String, Sendable, CaseIterable {
    /// Russian fiscal identifiers: `ИНН`, `ЗН ККТ`, `РН ККТ`, `ФН`, `ФД`, `ФП`
    /// and the bare 14-16 digit registry values printed under them.
    case russianFiscalIdentifier
    /// Estonian merchant registration and card-slip identifiers: `Reg.kood`,
    /// `KMKR`, `STAATUS`, `KAUPMEES`, `ATC`, `AID`.
    case estonianRegistration
    /// Card terminal furniture in any language: `RRN`, `TID`, `ТЕРМИНАЛ`,
    /// authorisation codes, masked PANs, long card numbers.
    case cardTerminal
    /// A unit-convention footnote - `1 ед.=1 литр для нефтепродуктов/суг` -
    /// which states the document's units and contains no transaction value.
    case unitConvention
    /// Postal addresses, phone numbers and web addresses.
    case contactDetails
}

public enum ReceiptNoiseFilter {

    /// The lines a value finder may read: everything the classifier could not
    /// account for. Order is preserved, because the total finder and the
    /// operand paths both rely on reading order and on neighbouring rows.
    public static func candidateLines(_ lines: [OCRLine]) -> [OCRLine] {
        lines.filter { classify($0.text) == nil }
    }

    /// The noise class of a line, or nil when the line may carry a value.
    ///
    /// Every pattern below is witnessed by a fixture. This is deliberately a
    /// list of shapes that have actually appeared rather than a general theory
    /// of receipt junk: a rule that has never been seen firing is a rule whose
    /// false positives have never been seen either.
    public static func classify(_ text: String) -> ReceiptNoiseClass? {
        let key = FuelKindNormalizer.canonicalKey(text.uppercased())
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        if matchesAny(key, russianFiscalPatterns) { return .russianFiscalIdentifier }
        if matchesAny(key, estonianRegistrationPatterns) { return .estonianRegistration }
        if matchesAny(key, cardTerminalPatterns) { return .cardTerminal }
        if key.firstMatch(of: /\d\s*[ЕE]Д\.?\s*[=]/) != nil { return .unitConvention }
        if matchesAny(key, contactPatterns) { return .contactDetails }

        // A bare identifier: a run of 14 or more digits with nothing else on the
        // line. Fiscal drive numbers and card PANs have this shape and money
        // never does - a printed total carries a decimal separator, and the
        // longest legitimate bare value in the corpus is `19719.00`.
        //
        // The bound is what keeps this safe. A shorter rule would eat real
        // values, which is the trap Kimi's read of the dump named: a bare
        // `5380.00` IS the total on receipt-015, and `3695.76` is the only
        // legible total on receipt-041.
        if trimmed.wholeMatch(of: /\d{14,}/) != nil { return .russianFiscalIdentifier }

        return nil
    }

    // MARK: - The witnessed patterns

    // All patterns are matched against the homoglyph-canonical, uppercased key
    // (FuelKindNormalizer.canonicalKey), so `ККТ` and Latin `KKT` - which
    // Vision produces for the same acronym on receipt-036 and receipt-044 - are
    // one pattern rather than two.

    private static var russianFiscalPatterns: [Regex<Substring>] { [
        /\bИHH\b/,          // ИНН, canonical (Н -> H)
        /\b[ЗЭ]H\s*KKT\b/,  // ЗН ККТ
        /\bPH\s*KKT\b/,     // РН ККТ (Р -> P)
        /\bФH\b/, /\bФД\b/, /\bФП\b/,
        /\bPHM\b/
    ] }

    private static var estonianRegistrationPatterns: [Regex<Substring>] { [
        /REG\.?\s*KOOD/, /KMKR/, /\bSTAATUS\b/, /KAUPMEES/,
        /\bATC\b/, /\bAID\b/, /\bA[0-9A-F]{10,}\b/
    ] }

    private static var cardTerminalPatterns: [Regex<Substring>] { [
        /\bRRN\b/, /\bTID\b/, /\bPSN\b/, /\bTVR\b/, /\bTSI\b/,
        /ТEPMИHAЛ/,                      // ТЕРМИНАЛ, canonical
        /KOД\s*(?:ABTOPИ3AЦИИ|OTBETA)/,  // КОД АВТОРИЗАЦИИ / КОД ОТВЕТА
        /OДOБPEHO/,                      // ОДОБРЕНО, canonical
        /\bPOS\s*NO\b/,
        /[X*]{4,}\s*\d{4}/,              // a masked PAN
        /\b\d{17,}\b/                     // a card number inside a longer line
    ] }

    private static var contactPatterns: [Regex<Substring>] { [
        /WWW\./, /HTTPS?:\/\//, /\bTEЛ[.:]/, /KLIENDITUGI/
    ] }

    private static func matchesAny(_ key: String, _ patterns: [Regex<Substring>]) -> Bool {
        patterns.contains { key.firstMatch(of: $0) != nil }
    }
}
