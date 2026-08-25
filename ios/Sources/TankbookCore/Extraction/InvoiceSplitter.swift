import Foundation

/// One invoice line item the deterministic splitter produced. `title` is raw OCR
/// text (a default input the user edits - hard rule 13); `amount` is the exact
/// `Decimal` cost; `category` is a vocabulary guess that is always a suggestion,
/// never a fact; `confidence` is the source line's OCR confidence, carried for
/// provenance (dimming is driven separately by "scanned but not yet confirmed").
public struct InvoiceLineItem: Equatable, Sendable {
    public var title: String
    public var amount: Decimal
    public var category: ServiceCategory
    public var confidence: Double

    public init(title: String, amount: Decimal, category: ServiceCategory,
                confidence: Double = 1.0) {
        self.title = title
        self.amount = amount
        self.category = category
        self.confidence = confidence
    }
}

/// The deterministic split result (docs/JOURNEYS.md J7). Three outcomes, none of
/// them an error:
///   - `items.count >= 2` with `lumpSum == false`: the split, only ever returned
///     when the items sum to the invoice total within the CHECK 3 tolerance.
///   - `items.count == 1` with `lumpSum == true`: the honest fallback - one
///     uncategorized item carrying the full total (never force itemization).
///   - `items.isEmpty`: nothing confident enough to pre-fill (vendor/date only).
public struct InvoiceSplitResult: Equatable, Sendable {
    public var vendor: String?
    public var date: Date?
    public var total: Decimal?
    public var items: [InvoiceLineItem]
    public var lumpSum: Bool
    public var extraction: ExtractionMeta

    public var pipeline: String { extraction.pipeline }

    public init(vendor: String?, date: Date?, total: Decimal?,
                items: [InvoiceLineItem], lumpSum: Bool, extraction: ExtractionMeta) {
        self.vendor = vendor
        self.date = date
        self.total = total
        self.items = items
        self.lumpSum = lumpSum
        self.extraction = extraction
    }
}

/// The rules-only invoice line splitter. No LLM, no Vision - pure text in, a
/// suggested split out (CLAUDE.md hard rule 13: every field is a default input).
///
/// The load-bearing invariant: **the sum of the split items must equal the
/// invoice total** within the CHECK 3 tolerance `max(0.02, total x 0.005)`. When
/// it does not, the split is discarded entirely in favour of the lump sum - a
/// partial split that silently loses a line is worse than no split, because it
/// produces a wrong number that looks right (the exact failure mode the fuel
/// corpus documented).
public struct InvoiceSplitter: Sendable {

    /// The pipeline label recorded on every result (regression tracking).
    public static let pipeline = "vision+rules invoice v1"

    public init() {}

    // MARK: - Entry points

    public func split(lines: [OCRLine]) -> InvoiceSplitResult {
        let vendor = detectVendor(lines)
        let dateString = detectDateString(lines)
        let date = dateString.flatMap { ConfirmDate.parse($0) }
        let total = detectTotal(lines)
        let candidates = detectLineItems(lines, excluding: total)

        // The sum invariant. It is the whole task: a split is returned ONLY when
        // it explains the total; otherwise the honest lump sum stands (J7).
        if let total, candidates.count >= 2, sumsToTotal(candidates, total: total) {
            return InvoiceSplitResult(
                vendor: vendor, date: date, total: total,
                items: candidates, lumpSum: false,
                extraction: makeExtraction(items: candidates, vendor: vendor))
        }
        if let total {
            let lump = InvoiceLineItem(
                title: vendor ?? "", amount: total,
                category: .other(""), confidence: 1.0)
            return InvoiceSplitResult(
                vendor: vendor, date: date, total: total,
                items: [lump], lumpSum: true,
                extraction: makeExtraction(items: [lump], vendor: vendor))
        }
        // No total: nothing confident enough to pre-fill. The vendor and date
        // still land, the items stay empty for the user to type.
        return InvoiceSplitResult(
            vendor: vendor, date: date, total: nil,
            items: [], lumpSum: false,
            extraction: makeExtraction(items: [], vendor: vendor))
    }

    /// Pure-text convenience for the bulk of the core tests: lines carry a
    /// `.zero` box and default confidence, so the splitter is exercised from
    /// plain `[String]` with no image.
    public func split(textLines: [String]) -> InvoiceSplitResult {
        split(lines: textLines.map { OCRLine(text: $0) })
    }

    // MARK: - The sum invariant

    /// `abs(sum - total) <= max(0.02, total x 0.005)` (docs/SCHEMA.md CHECK 3),
    /// shared with the pump-card cross-check so the two can never disagree.
    public static func sumsToTotal(_ items: [InvoiceLineItem], total: Decimal) -> Bool {
        let sum = items.reduce(Decimal.zero) { $0 + $1.amount }
        let tolerance = ConfirmConfidenceGate.crossCheckTolerance(amount: total)
        return abs(sum - total) <= tolerance
    }

    private func sumsToTotal(_ items: [InvoiceLineItem], total: Decimal) -> Bool {
        Self.sumsToTotal(items, total: total)
    }

    // MARK: - Vendor

    /// The first line that reads as a company name: letters, few tokens, no
    /// more than one number, and not a date/total/VAT/payment line.
    func detectVendor(_ lines: [OCRLine]) -> String? {
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard text.contains(where: \.isLetter) else { continue }
            guard detectDateString([line]) == nil else { continue }
            if isTotalOrExcludedLine(text) { continue }
            let tokens = text.split(separator: " ").filter { !$0.isEmpty }
            guard tokens.count <= 6 else { continue }
            let numberTokens = tokens.filter { $0.contains(where: \.isNumber) }
            guard numberTokens.count <= 1 else { continue }
            let upper = text.uppercased()
            if Self.vendorDenyList.contains(where: upper.contains) { continue }
            return text
        }
        return nil
    }

    private static let vendorDenyList = [
        "RECHNUNG", "INVOICE", "СЧЕТ", "СЧЁТ", "ФАКТУРА", "QUITTUNG", "BELEG",
        "DATUM", "DATE", "ДАТА", "TEL", "TEL.", "PHONE", "ТЕЛ", "WWW", "HTTP"
    ]

    // MARK: - Date

    func detectDateString(_ lines: [OCRLine]) -> String? {
        let regex = /\b(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{2,4})\b|\b(\d{4})-(\d{2})-(\d{2})\b/
        for line in lines {
            if let match = line.text.firstMatch(of: regex) {
                return String(match.0)
            }
        }
        return nil
    }

    // MARK: - Total

    /// The invoice's own grand total. Labels are invoice-specific (GESAMT,
    /// ИТОГО, СУММА, TOTAL, ...), read from the same line or the one directly
    /// after, and resolved by mode like the receipt total-finder.
    func detectTotal(_ lines: [OCRLine]) -> Decimal? {
        var candidates: [Decimal] = []
        for (index, line) in lines.enumerated() {
            guard Self.totalLabelKind(line.text) == .primary else { continue }
            if let value = value(in: line) ?? nextLineValue(after: index, in: lines) {
                candidates.append(value)
            }
        }
        guard !candidates.isEmpty else { return nil }
        let counts = Dictionary(grouping: candidates, by: { $0 }).mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        let modes = counts.filter { $0.value == maxCount }.map(\.key)
        return modes.count == 1 ? modes[0] : modes.max(by: { $0 < $1 })
    }

    private func value(in line: OCRLine) -> Decimal? {
        guard let raw = NumberScanner.value(in: line.text) else { return nil }
        return Self.decimal(raw)
    }

    private func nextLineValue(after index: Int, in lines: [OCRLine]) -> Decimal? {
        guard index + 1 < lines.count else { return nil }
        let next = lines[index + 1]
        guard NumberScanner.isValueLine(next.text) else { return nil }
        return value(in: next)
    }

    private static func decimal(_ value: Double) -> Decimal? {
        ConfirmFormat.decimal(fromExtraction: value, fractionDigits: 2)
    }

    enum TotalLabelKind { case primary }

    /// Classifies a line as an invoice total line. Excluded labels (VAT, subtotal,
    /// discount, change) come first so they never win.
    private static let excludedLabels = [
        "СУММА НДС", "СУММА БЕЗ НДС", "НДС", "В Т.Ч. НДС", "ОКРУГЛЕНИЕ", "СДАЧА",
        "ПОЛУЧЕНО", "ИТОГО БЕЗ", "ИТОГО НДС", "SUBTOTAL", "VAT", "MWST", "TAX",
        "DISCOUNT", "RABATT", "СКИДКА", "ZWISCHENSUMME", "СУММА СКИДК"
    ]
    private static let primaryLabels = [
        "ИТОГО", "ИТОГ", "ВСЕГО", "СУММА", "К ОПЛАТЕ", "К ОПЛАТЕ",
        "TOTAL", "GRAND TOTAL", "AMOUNT DUE", "TOTAL DUE",
        "GESAMT", "GESAMTBETRAG", "RECHNUNGSBETRAG", "SUMME", "SUMMA", "TOTALE", "KOKKU"
    ]

    static func totalLabelKind(_ text: String) -> TotalLabelKind? {
        let upper = text.uppercased()
        if excludedLabels.contains(where: upper.contains) { return nil }
        if primaryLabels.contains(where: upper.contains) { return .primary }
        return nil
    }

    private func isTotalOrExcludedLine(_ text: String) -> Bool {
        Self.totalLabelKind(text) != nil
            || Self.excludedLabels.contains(where: text.uppercased().contains)
    }

    // MARK: - Line items

    /// Candidate rows of `title` + trailing amount, skipping the total/VAT/
    /// header lines. The amount is the LAST decimal on the line (invoices print
    /// quantity then cost: "2 x Oil filter 12.40"); the title is what precedes
    /// it. A bare line with no amount is not a candidate.
    func detectLineItems(_ lines: [OCRLine], excluding total: Decimal?) -> [InvoiceLineItem] {
        var items: [InvoiceLineItem] = []
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if isTotalOrExcludedLine(text) { continue }
            if detectDateString([line]) != nil { continue }
            if text.uppercased().contains("СУММА") || text.uppercased().contains("ИТОГО") { continue }
            guard let (title, amount) = Self.splitTitleAmount(text) else { continue }
            guard !title.isEmpty else { continue }
            // A line whose amount is the grand total is the total line itself
            // re-read; skip it so it is not double-counted as an item.
            if let total, amount == total { continue }
            items.append(InvoiceLineItem(
                title: title,
                amount: amount,
                category: Self.category(for: title),
                confidence: Double(line.confidence)))
        }
        return items
    }

    /// Splits a line into its leading title and its trailing amount. The value is
    /// read through `NumberScanner` (the one number parser); the regex here only
    /// LOCATES the trailing amount so the title can be stripped - it uses the
    /// same separator rules `NumberScanner` documents.
    static func splitTitleAmount(_ line: String) -> (title: String, amount: Decimal)? {
        let pattern = /(\d{1,3}(?:[ .]\d{3})*|\d+)[.,](\d{1,3})/
        let matches = line.matches(of: pattern)
        guard let last = matches.last else { return nil }
        let amountText = String(line[last.range])
        guard let value = NumberScanner.value(in: amountText),
              let amount = decimal(value) else { return nil }
        var title = String(line[..<last.range.lowerBound])
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "·•-–:| "))
        guard !title.isEmpty else { return nil }
        return (title, amount)
    }

    /// The category vocabulary (docs/SCHEMA.md, ServiceCategory). A suggestion,
    /// never a fact - the user overrides (hard rule 13). Unknown titles become
    /// `.other("")`, which the screen renders as "Other" with free text.
    static func category(for title: String) -> ServiceCategory {
        let lower = title.lowercased()
        if matches(lower, ["oil", "öl", "масл", "lubricant", "schmierung"]) { return .oil }
        if matches(lower, ["brake", "brems", "тормоз", "belag", "beläge", "pad", "scheibenbremse"]) { return .brakes }
        if matches(lower, ["tire", "tyre", "reifen", "шина", "шиномонтаж", "wheel", "радиал"]) { return .tires }
        if matches(lower, ["battery", "batterie", "аккум", "батаре"]) { return .battery }
        if matches(lower, ["filter", "фильтр", "luftfilter", "pollen", "kraftstofffilter"]) { return .filters }
        if matches(lower, ["inspection", "inspektion", "check-up", "check up",
                           "осмотр", "техосмотр", "диагност", "diagnos", "service"]) {
            return .inspection
        }
        if matches(lower, ["repair", "reparatur", "ремонт", "instandsetzung"]) { return .repair }
        if matches(lower, ["part", "teil", "детал", "запчаст", "ersatzteil"]) { return .parts }
        if matches(lower, ["wash", "wäsche", "waschen", "мойка", "clean", "reinigung", "carwash"]) { return .wash }
        return .other("")
    }

    private static func matches(_ lower: String, _ keywords: [String]) -> Bool {
        keywords.contains { lower.contains($0) }
    }

    // MARK: - Provenance

    private func makeExtraction(items: [InvoiceLineItem], vendor: String?) -> ExtractionMeta {
        var fields: [FieldRef: FieldExtraction] = [:]
        if vendor != nil {
            fields[.vendor] = FieldExtraction(cropRect: nil, confidence: 0.9, userCorrected: false)
        }
        for (index, item) in items.enumerated() {
            fields[.lineItem(index)] = FieldExtraction(
                cropRect: nil, confidence: item.confidence, userCorrected: false)
        }
        return ExtractionMeta(fields: fields, pipeline: Self.pipeline)
    }
}
