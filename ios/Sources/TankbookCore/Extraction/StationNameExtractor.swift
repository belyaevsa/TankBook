import Foundation

// MARK: - The shared company-name predicate (RV.161)

/// The one definition of "this OCR line reads as a company name", shared by the
/// service-invoice vendor finder (`InvoiceSplitter.detectVendor`) and the fuel
/// station extractor. Two independent "find the company name" rules drift, and
/// the drift is invisible - so both start here.
///
/// The shape: a line with letters, at most six tokens, at most one numeric
/// token, not a date, and not on the document-furniture deny list.
enum CompanyNameLine {

    /// Labels that name a document rather than the company that issued it. The
    /// vendor finder and the station extractor both reject these.
    static let denyList = [
        "RECHNUNG", "INVOICE", "СЧЕТ", "СЧЁТ", "ФАКТУРА", "QUITTUNG", "BELEG",
        "DATUM", "DATE", "ДАТА", "TEL", "TEL.", "PHONE", "ТЕЛ", "WWW", "HTTP"
    ]

    /// A date anywhere in the line means the line is document furniture, not a
    /// company name. Same regex as `InvoiceSplitter.detectDateString` and
    /// `FuelExtractor.detectDate`.
    static func containsDate(_ text: String) -> Bool {
        text.firstMatch(of: /\b(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{2,4})\b|\b(\d{4})-(\d{2})-(\d{2})\b/) != nil
    }

    /// Whether `text` has the shape of a company name.
    ///
    /// `stripsLegalMarkerDigits` exists for fuel receipts, whose thermal print
    /// turns a legal form into something with digits in it (`0О]"КРЫМ ОИЛ"`,
    /// receipt-004). The legal form is not an operand, so it must not count
    /// toward the one-numeric-token budget; the invoice path leaves it off and
    /// keeps its original counting.
    static func isCompanyName(_ text: String, stripsLegalMarkerDigits: Bool = false) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains(where: \.isLetter) else { return false }
        guard !containsDate(trimmed) else { return false }
        let tokens = trimmed.split(separator: " ").filter { !$0.isEmpty }
        guard tokens.count <= 6 else { return false }
        let probe = stripsLegalMarkerDigits
            ? trimmed.replacingOccurrences(of: legalMarkerPrefix, with: " ",
                                           options: [.regularExpression, .caseInsensitive])
            : trimmed
        let numberTokens = probe.split(separator: " ").filter { $0.contains(where: \.isNumber) }
        guard numberTokens.count <= 1 else { return false }
        let upper = trimmed.uppercased()
        return !denyList.contains(where: upper.contains)
    }

    /// A legal form at the very start of a line, with the OCR digit confusions
    /// the corpus demonstrates (`0О]`, `0ОО`, `ООЗ`).
    private static let legalMarkerPrefix =
        #"^\s*["«„]?\s*(ООО|ОО0|ООЗ|0ОО|0О]|0О|О0О|ОАО|ЗАО|ПАО|ТОО|АО|ИП|ОО)(?![\p{L}\d])"#
}

// MARK: - Fuel-receipt station extraction (RV.161)

/// The station identity line of a fuel receipt - the brand-level name a Log row
/// and a picker show, and the string `ImportStationResolver` keys the station
/// on, so a scanned name and a typed one converge on one id.
///
/// It reuses `CompanyNameLine.isCompanyName` and adds the three rules fuel
/// receipts need that invoices do not:
///
/// - **A confidence floor.** A fuel receipt photographs the pump and the
///   counter, so low-confidence fragments (`G Э` at 0.30 on receipt-060,
///   `РЕбеНЫЙ РаСЧеТ` at 0.30 on receipt-002) sit above the brand. An invoice
///   is a flat scan where the vendor is usually the first confident line.
/// - **A receipt-furniture deny list.** A fuel receipt prints its own titles,
///   fiscal identifiers and card-terminal boilerplate (`КАССОВЫЙ ЧЕК`, `ИНН`,
///   `ЗН ККТ`, `СПАСИБО`) above the brand; every one of them has the shape of a
///   company name and would win the vendor heuristic. An invoice prints its
///   vendor first, so the shared predicate alone is enough there.
/// - **A person-name and currency-figure filter.** A cashier line
///   (`НАФАНАИЛОВА Т.В.`) and a bare amount (`79,32 EUR`) have the same shape.
///
/// The result is a default input the user edits (hard rule 13), never a fact:
/// the caller puts it in the Confirm pre-fill, where it is visible and
/// changeable, and only a save writes it.
public enum StationNameExtractor {

    /// The first line that reads as a fuel receipt's station identity.
    public static func stationName(from lines: [OCRLine]) -> String? {
        for line in lines {
            guard line.confidence >= 0.5 else { continue }
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // A value line (`n=19719.00`, `ЗН`, `A0000000041010`) has the
            // shape of a company name once the shared predicate allows one
            // numeric token; a station name has real letters.
            let letters = text.filter(\.isLetter)
            guard letters.count >= 3 else { continue }
            let tokens = text.split(separator: " ").filter { !$0.isEmpty }
            guard !(tokens.count == 1 && letters.count < 5) else { continue }
            guard !isFurniture(text) else { continue }
            guard !isCurrencyOnly(text) else { continue }
            guard !isPersonName(text) else { continue }
            guard TotalLabel.classify(text) == nil else { continue }
            guard CompanyNameLine.isCompanyName(text, stripsLegalMarkerDigits: true) else { continue }
            return text
        }
        return nil
    }

    /// The receipt's own furniture, uppercased substrings. Deliberately a
    /// deny list of document furniture rather than a brand allow list: the
    /// brand vocabulary is `docs/API.md` -> `GET /reference/station-brands`
    /// (RV.115), and this extractor must not fork it.
    private static let furniture = [
        "КАССОВЫЙ ЧЕК", "КАССОВЫЙ", "КАССОВИЙ", "КАССА", "ЧЕК", "ПРИХОД",
        "СПАСИБО", "ДОБРО ПОЖАЛОВАТЬ", "ДАБРО", "ПОЖАЛОВАТЬ", "ГОРЯЧАЯ",
        "АДРЕС", "AДPЕС", "МЕСТО РАСЧЕТ", "МЕСТА РАСЧЕТ", "ЖЕЛАЕМ",
        "СЧАСТЛИВОГО", "ЗА ПОКУПКУ", "ПОДТВЕРЖ", "ОКРУГЛЕНИЕ", "ПОЛУЧЕНО",
        "НЕФИСКАЛЬНЫЙ", "ОПЕРАТОР", "КАССИР", "ТЕРМИНАЛ", "TERMINAL", "ОФД",
        "САЙТ", "КВИТАНЦИЯ", "SÄILITA", "KVIITUNG", "ТОВАР И УСЛУГИ",
        "МАСТЕРКАРТ", "MASTERCARD", "DEBIT", "CREDIT", "СБЕРБАНК", "ВЫБИРАЕТЕ",
        "ПОДАКЦИЗ", "ИНН", "ККТ", "KKT", "ДОК:", "N ДОК", "ЗН ", "РН ", "PH ",
        "ФН", "ФД", "ФП", "АЗК TR", "АЗС N", "AZS ", "НОМЕР ТРАНЗАКЦ",
        "ТРАНЗАКЦ", "СТАТУС", "STAATUS", "БАЛАНС", "СНО:", "СЧЕТ:", "СЧЁТ:",
        "CHO:", "СHO:", "НАЛИЧН", "ОБЩЕСТВО С ОГРАНИЧЕННОЙ", "ФЕДЕРАЦИЯ",
        "ФЕЛЕРДЦИЯ", "РОССИИСКАЯ", "ВОРОНЕЖСКАЯ", "НАФАНАИЛОВА", "КАРТА",
        "AUTORISEERITUD", "AUTORISEERTTUD", "ПЕТЕР-СЕРВИС", "ПЛАТА",
        "СПЕЦТЕХНОЛОГИИ", "КАЯДЖАН", "KAUPMEES", "SUMMA", "VERIFIED", "DEVICE",
        "REG.", "KOGUS", "TALLINN", "ЭКТО", "БЕНЗИН", "ОДОБРЕНО", "ННП",
        "СКИДК", "УЛ.", "ATD", "APP", "AID", "EMV", "PSN", "RRN", "CVC", "ТРК",
        "НДС", "VAT", "MWST", "TAX", "DISCOUNT", "RABATT", "SUBTOTAL",
        "ZWISCHENSUMME", "СДАЧА",
        // Two witnessed OCR strings that sit above the real station line: the
        // bank header on a mixed receipt (receipt-009) and the garble over
        // НЕФТЬМАГИСТРАЛЬ (receipt-012).
        "БАНКОВСКИЙ", "СВЯТОЙ ИСТОЧНИК", "DИЛDПОE", "ОКРУГ",
        "ПО НАЛОГУ", "СУКМА"
    ]

    private static func isFurniture(_ text: String) -> Bool {
        let upper = text.uppercased()
        return furniture.contains(where: upper.contains)
    }

    /// A line that is only an amount and a currency marker (`79,32 EUR`) is a
    /// receipt figure, never a company name - but it has letters and one
    /// numeric token, so the shared predicate alone would accept it.
    private static func isCurrencyOnly(_ text: String) -> Bool {
        let words = text.uppercased().split(separator: " ").filter { !$0.isEmpty }
        guard !words.isEmpty else { return false }
        let currencies: Set<String> = ["EUR", "RUB", "USD", "KZT", "PLN", "CZK",
                                       "GBP", "CHF", "€", "₽", "$", "ТЕНГЕ", "РУБ",
                                       "EUR/L", "RUB/L", "€/L", "РУБ/Л"]
        var sawCurrency = false
        for word in words {
            if currencies.contains(String(word)) { sawCurrency = true; continue }
            if word.allSatisfy({ $0.isNumber || ",.=:/\\-–+±".contains($0) }) { continue }
            return false
        }
        return sawCurrency
    }

    /// A cashier's name (`НАФАНАИЛОВА Т.В.`, `а Н. Ю.`) reads as a company
    /// name; a token that is an initial (`Т.`, `Т.В.`) marks the line as a
    /// person, unless the line also names a legal entity.
    private static func isPersonName(_ text: String) -> Bool {
        let tokens = text.split(separator: " ").filter { !$0.isEmpty }
        guard tokens.contains(where: { isInitial($0) }) else { return false }
        let upper = text.uppercased()
        let legalForms = ["ООО", "ОО0", "ООЗ", "0ОО", "0О]", "ОАО", "ЗАО", "ПАО",
                          "ТОО", "АО", "ИП", "ОО"]
        return !legalForms.contains(where: upper.contains)
    }

    private static func isInitial(_ token: Substring) -> Bool {
        token.wholeMatch(of: /[A-Za-zА-Яа-я]\.(?:[A-Za-zА-Яа-я]\.?)?/) != nil
    }
}
