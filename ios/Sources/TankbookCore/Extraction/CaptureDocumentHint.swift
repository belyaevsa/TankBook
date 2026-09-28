import Foundation

/// What a Fill-up capture looks like when it is not a fuel document: a
/// workshop invoice or a shop receipt photographed in the mode the capture
/// screen opens on. The verify screen then offers the Service and Expense
/// forms with the photo carried over (docs/JOURNEYS.md J7, RV.319) - a
/// suggestion the user takes or ignores, never a switch made for them (hard
/// rule 13).
public enum CaptureDocumentHint {
    /// The form to suggest first, or nil when the document reads as fuel or
    /// nothing on it is positive evidence of a workshop.
    ///
    /// Fuel evidence always wins: a fuel kind read, or a fuel word on any row
    /// (`EUR/L`, `LIITRIT`, `ДИЗЕЛЬ`, `АИ-95`). Without it, service evidence -
    /// an invoice or work-order word, or a costed row whose title names a
    /// service category - suggests Service. A read volume alone is not fuel
    /// evidence here, because an oil change is sold in litres too.
    ///
    /// A document with only a total suggests nothing: on the corpus that shape
    /// is as often a fuel receipt whose fuel line went unread as a shop
    /// receipt, and an offer on a real fill-up would send it away from its form.
    public static func suggestedForm(lines: [OCRLine], extraction: FuelExtraction?) -> CaptureEntryForm? {
        guard !lines.isEmpty, extraction?.fuelKind == nil else { return nil }
        let rows = InvoiceSplitter.rows(lines)
        let texts = rows.map { $0.text.uppercased() }
        if texts.contains(where: { row in fuelWords.contains(where: row.contains) }) { return nil }
        let serviceRow = rows.contains { row in serviceCategories.contains(workshopCategory(of: row.text)) }
        let invoiceWord = texts.contains { row in invoiceWords.contains(where: row.contains) }
        return serviceRow || invoiceWord ? .service : nil
    }

    /// A row's service category, read without the bare word "service" - a
    /// receipt's footer says "customer service" and bills nothing.
    static func workshopCategory(of text: String) -> ServiceCategory {
        let stripped = text.replacingOccurrences(of: "service", with: "", options: .caseInsensitive)
        return InvoiceSplitter.category(for: stripped)
    }

    /// Words a fuel receipt or pump display prints and a workshop invoice does
    /// not: per-litre prices and fuel names. The bare word "litre" is not one -
    /// engine oil is sold in litres (`от 3-х литров`, `service-002`).
    static let fuelWords = [
        "/L", "/Л", "/GAL", "DIESEL", "DIISEL", "ДИЗЕЛ", "ДТ ",
        "БЕНЗИН", "BENSIIN", "BENZIN", "PETROL", "GASOLINE", "АИ-9", "АИ 9", "AI-9", "AI 9", "E10", "E85",
        "95E", "98E", "MILES+", "ADBLUE", "KÜTUS", "KUTUS", "ТОПЛИВО", "LPG", "CNG", "SP95", "SP98", "GAZOLE"
    ]

    /// Words a workshop invoice or work order prints.
    static let invoiceWords = [
        "ARVE SUMMA", "ARVE NR", "INVOICE", "RECHNUNG", "СЧЕТ-ФАКТУРА", "СЧЁТ-ФАКТУРА", "ЗАКАЗ-НАРЯД",
        "ЗАКАЗ НАРЯД", "ВЫПОЛНЕННЫХ РАБОТ", "WORK ORDER", "TÖÖTELLIMUS", "HOOLDUS", "WERKSTATT"
    ]

    /// The line categories only a workshop bills. Parts, washes and "other"
    /// are bought at shops too, so they are not service evidence.
    static let serviceCategories: [ServiceCategory] = [.oil, .brakes, .tires, .battery, .filters, .inspection,
                                                        .repair]
}
