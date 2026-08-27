import Foundation

// MARK: - Mixed-receipt detection (P2.4)
//
// A receipt is MIXED when it carries non-fuel items alongside the fuel line
// (docs/SCHEMA.md CHECK 3, "MIXED RECEIPTS"). The fill-up's amount is then the
// FUEL LINE, never the grand total (CLAUDE.md hard rule 4), and the remaining
// lines are offered on the Confirm sheet as separate Expenses the user can
// accept or dismiss individually - nothing is created without their action.
//
// Detection combines two independent signals, and is deliberately conservative
// (hard rule 13): a false "this is mixed" splits a plain fill-up into two
// entries and corrupts the log, so when unsure we treat the receipt as normal
// and let the user say otherwise.
//
//   1. The QR signal - `FiscalQRCrossCheck.classify` already returns
//      `.suggestsMixedReceipt` when the QR's grand total exceeds the fuel line
//      beyond tolerance. Strong and exact, but only present on 9 of 22 corpus
//      receipts.
//   2. The structure signal - a non-fuel product line alongside the fuel line,
//      carrying its own quantity x price. This is the path that works without a
//      QR, and where receipt-009's 129.00 collision bites (the bottled water
//      costs 129.00, the exact same number as the fuel's price per litre - a
//      detector that matches on "a number appearing twice" picks the wrong
//      line; this one matches on operand pairs and product names instead).

/// A non-fuel line item detected on a mixed receipt. Offered on the Confirm
/// sheet as a separate Expense the user can accept or dismiss (hard rule 13).
public struct ReceiptLineItem: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let amount: Decimal
    public let category: ExpenseCategory
    /// Whether the line is a car-related cost (car wash, wiper fluid). Car
    /// lines default to accepted, non-car lines (coffee, water) to dismissed -
    /// a suggestion the user can always flip.
    public let isCarRelated: Bool

    public init(id: UUID = UUID.v7(), title: String, amount: Decimal,
                category: ExpenseCategory, isCarRelated: Bool) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.isCarRelated = isCarRelated
    }
}

/// The result of deciding whether a receipt is mixed.
public enum MixedReceiptDetection: Equatable, Sendable {
    case notMixed
    /// The receipt is mixed: `fuelLine` is the fill-up's amount (hard rule 4),
    /// `lines` the non-fuel items offered as Expenses, and `grandTotal` the
    /// receipt total those lines account for.
    case mixed(lines: [ReceiptLineItem], fuelLine: Decimal, grandTotal: Decimal)

    public var lines: [ReceiptLineItem] {
        guard case .mixed(let lines, _, _) = self else { return [] }
        return lines
    }
}

/// The pure detector. No Vision, no persistence - it reads OCR lines, the
/// extraction's fuel line, and the optional fiscal QR anchor.
public enum MixedReceiptDetector {

    /// The tolerance, in the receipt currency, within which the fuel line plus
    /// the detected non-fuel items must match the receipt's own total for the
    /// structure signal to confirm a mixed receipt. One rouble absorbs the
    /// whole-rouble rounding the corpus shows (receipt-009 rounds 6264.24 to
    /// 6264.00) while staying far tighter than the cross-check's ~0.5%, so a
    /// non-fuel line is claimed only when the numbers genuinely add up.
    public static let structureTolerance: Decimal = Decimal(1)

    /// Decides whether `lines` describe a mixed receipt. `extraction` supplies
    /// the fuel line (liters, unit price); `qrAnchor` the fiscal total when a
    /// QR decoded (nil otherwise).
    public static func detect(lines: [OCRLine],
                              extraction: FuelExtraction,
                              qrAnchor: FiscalQRAnchor?) -> MixedReceiptDetection {
        guard let fuelLine = fuelLineAmount(extraction) else { return .notMixed }
        let items = findExtraItems(lines: lines)
        guard !items.isEmpty else { return .notMixed }

        // Signal 1 - the QR grand total exceeds the fuel line (hard rule 4).
        let qrSuggestsMixed = qrAnchor.map { anchor in
            FiscalQRCrossCheck.classify(qrTotal: anchor.total,
                                        candidateTotal: fuelLine) == .suggestsMixedReceipt
        } ?? false

        // Signal 2 - the detected non-fuel lines explain the gap between the
        // fuel line and the receipt's own total.
        let lineExtensionTotal = fuelLine + items.reduce(Decimal.zero) { $0 + $1.amount }
        let receiptTotal = qrAnchor?.total ?? printedGrandTotal(lines)
        let structureSuggestsMixed: Bool
        if let receiptTotal {
            structureSuggestsMixed = abs(lineExtensionTotal - receiptTotal) <= structureTolerance
        } else {
            // No receipt total at all (no QR, no ИТОГ): cannot verify the items
            // add up, so stay conservative - hard rule 13.
            structureSuggestsMixed = false
        }

        guard qrSuggestsMixed || structureSuggestsMixed else { return .notMixed }

        // The grand total the group accounts for is the line-extension total:
        // what the detected items actually sum to. The fiscal total may differ
        // by the receipt's own rounding (ОКРУГЛЕНИЕ), which belongs to no line
        // and is not part of the group's accounting - so "logged <= receipt"
        // holds even on a rounded receipt (see ReceiptGroupPlan).
        return .mixed(lines: items, fuelLine: fuelLine, grandTotal: lineExtensionTotal)
    }

    // MARK: - Fuel line

    /// The fuel line as an exact Decimal: liters x unit price. The price is
    /// already an exact Decimal (the extraction types money as Decimal since
    /// P2.2b); the volume enters through the same Decimal(string:) boundary as
    /// the Confirm sheet (P2.3) and the product is then rounded to the
    /// currency's two decimal places - the receipt prints the fuel line as
    /// money (42.30 x 1.679 prints "71.02", not "71.0217"), so the detector
    /// and the form can never disagree about the figure. Falls back to the OCR
    /// total when the operands are missing.
    static func fuelLineAmount(_ extraction: FuelExtraction) -> Decimal? {
        if let liters = ConfirmFormat.decimal(fromExtraction: extraction.liters,
                                              fractionDigits: 2),
           let price = extraction.unitPrice {
            return rounded(liters * price)
        }
        return extraction.total
    }

    /// Rounds a Decimal to the currency's two decimal places (the receipt's own
    /// display precision), half-up.
    private static func rounded(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var source = value
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }

    // MARK: - Line-item structure

    /// Finds the non-fuel line items: a product name line followed by a
    /// quantity x price pair that is not the fuel's own operand pair. The fuel
    /// line is the first operand pair (the extractor resolves volume/price the
    /// same way), so any later pair with its own product name is a candidate
    /// item. Conservative by construction - a candidate must name a product and
    /// carry a positive amount, otherwise it is ignored.
    static func findExtraItems(lines: [OCRLine]) -> [ReceiptLineItem] {
        let fuelPairIndex = OperandPair.first(in: lines)?.1
        var items: [ReceiptLineItem] = []
        for (index, line) in lines.enumerated() {
            if index == fuelPairIndex { continue }
            if hasVolumeMarker(line.text) { continue }
            guard let pair = quantityPricePair(line.text) else { continue }
            guard let title = precedingProductTitle(lines, before: index) else { continue }
            guard !FuelKindNormalizer.isProductLine(title) else { continue }
            let amount = ConfirmFormat.decimal(fromExtraction: pair.quantity * pair.price,
                                               fractionDigits: 2) ?? Decimal.zero
            guard amount > 0 else { continue }
            items.append(ReceiptLineItem(title: title,
                                         amount: amount,
                                         category: suggestCategory(title),
                                         isCarRelated: isCarRelated(title)))
        }
        return items
    }

    /// A quantity x price pair, tolerating the unit word thermal printers
    /// abbreviate between the quantity and the operator ("1 т. X 129.00" - т. =
    /// pieces). The unit abbreviations are stripped, then the shared operand
    /// parser does the rest, so this and the fuel extractor never disagree
    /// about what counts as an operand pair. Internal so the cross-check's
    /// non-fuel line sum and the mixed detector share one definition of "a
    /// priced line".
    static func quantityPricePair(_ line: String) -> (quantity: Double, price: Double)? {
        let cleaned = line
            .replacingOccurrences(of: "т.", with: " ")
            .replacingOccurrences(of: "Т.", with: " ")
            .replacingOccurrences(of: "шт", with: " ")
            .replacingOccurrences(of: "ШТ", with: " ")
            .replacingOccurrences(of: "ед", with: " ")
            .replacingOccurrences(of: "ЕД", with: " ")
            .replacingOccurrences(of: "уп", with: " ")
            .replacingOccurrences(of: "УП", with: " ")
            .replacingOccurrences(of: "кг", with: " ")
            .replacingOccurrences(of: "КГ", with: " ")
        guard let pair = OperandPair(line: cleaned) else { return nil }
        return (pair.left, pair.right)
    }

    /// The nearest product-name line above `index`, skipping labels, values,
    /// VAT/rounding/discount noise and the fuel product line. A line names a
    /// product when it is non-empty, non-numeric and not a recognised receipt
    /// artefact.
    private static func precedingProductTitle(_ lines: [OCRLine], before index: Int) -> String? {
        let lowerBound = max(0, index - 3)
        guard lowerBound < index else { return nil }
        for lineIndex in stride(from: index - 1, through: lowerBound, by: -1) {
            let text = lines[lineIndex].text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !isReceiptNoise(text) else { continue }
            return text
        }
        return nil
    }

    private static func isReceiptNoise(_ text: String) -> Bool {
        if TotalLabel.classify(text) != nil { return true }
        let upper = text.uppercased()
        let noise = ["НДС", "ОКРУГЛ", "СКИДК", "СДАЧА", "ПОЛУЧЕНО", "В ТОМ ЧИСЛЕ",
                     "СУММА", "БЕЗНАЛИЧНЫМИ", "НАЛИЧНЫМИ", "ПЛАТ.КАРТОЙ", "КАРТОЙ",
                     "ВСЕГО", "ИТОГ", "К ОПЛАТЕ"]
        if noise.contains(where: upper.contains) { return true }
        if NumberScanner.isValueLine(text) { return true }
        if FuelKindNormalizer.isProductLine(text) { return true }
        return false
    }

    /// A volume marker attached to a number names the fuel's own litres (the
    /// fuel operand line), so such a line is never a non-fuel item.
    private static func hasVolumeMarker(_ text: String) -> Bool {
        text.firstMatch(of: /\d\s*[лL]/) != nil || text.firstMatch(of: /[лL]\s*\d/) != nil
    }

    /// The receipt's own grand total from its total labels (ИТОГ/ВСЕГО/...),
    /// in exact Decimal - the no-QR fallback for the structure signal.
    private static func printedGrandTotal(_ lines: [OCRLine]) -> Decimal? {
        let extractor = FuelExtractor()
        guard let total = extractor.receiptGrandTotal(lines) else { return nil }
        return ConfirmFormat.decimal(fromExtraction: total, fractionDigits: 2)
    }

    // MARK: - Category suggestion

    /// A suggested Expense category from the item's name. Deliberately small:
    /// the enumerated categories where the name is unambiguous, `.other("wash")`
    /// for car washes (ExpenseCategory has no native wash), `.other("other")`
    /// otherwise. A suggestion, never a fact - the user re-categorises later.
    static func suggestCategory(_ title: String) -> ExpenseCategory {
        let upper = title.uppercased()
        if upper.contains("МОЙК") || upper.contains("WASH") { return .other("wash") }
        if upper.contains("ПАРКОВК") || upper.contains("PARKING") { return .parking }
        if upper.contains("ПЛАТН") || upper.contains("TOLL") || upper.contains("ДОРОГ") { return .toll }
        if upper.contains("ШТРАФ") || upper.contains("FINE") { return .fine }
        if upper.contains("ЗАПЧАСТ") || upper.contains("PARTS") { return .parts }
        if upper.contains("АКСЕССУАР") || upper.contains("ACCESSORY") { return .accessory }
        return .other("other")
    }

    /// Whether the line is a car-related cost. Non-car lines (coffee, water,
    /// food) default to dismissed; everything else defaults to accepted.
    static func isCarRelated(_ title: String) -> Bool {
        let upper = title.uppercased()
        let nonCar = ["КОФЕ", "COFFEE", "ЧАЙ", "TEA", "ВОДА", "WATER", "ЕДА", "FOOD",
                      "ПРОДУКТ", "СИГАРЕТ", "CIGARETTE", "ЖУРНАЛ", "ШОКОЛАД", "CHOCOLATE"]
        return !nonCar.contains(where: upper.contains)
    }
}

// MARK: - Grouped-save plan (the two invariants, L1-testable)

/// One accepted non-fuel line as it will be saved.
public struct ReceiptExpense: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let line: ReceiptLineItem
    public let amount: Decimal

    public var title: String { line.title }
    public var category: ExpenseCategory { line.category }
}

/// The pure plan for a grouped save: the shared `purchaseGroupId`, the fill-up's
/// amount, the accepted Expenses, and the receipt total they are checked
/// against. Producing it as a pure value is what makes the two hard-rule-4
/// invariants L1-testable instead of buried in the sheet:
///
///   - The fill-up's amount is the fuel line, never the grand total.
///   - The logged group (fill-up + accepted expenses) never exceeds the receipt
///     total - it can only ever be less, when the user dismissed a line.
public struct ReceiptGroupPlan: Equatable, Sendable {
    public let purchaseGroupId: UUID
    public let fillUpAmount: Decimal
    public let receiptTotal: Decimal
    public let expenses: [ReceiptExpense]

    public var loggedTotal: Decimal {
        fillUpAmount + expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// True when the logged group stays within the receipt (the "never more"
    /// invariant). The accepted lines are a subset of the detected lines, so
    /// this holds whenever the fill-up records the fuel line - the plan makes
    /// that relationship explicit rather than assuming it.
    public var respectsReceiptTotal: Bool {
        loggedTotal <= receiptTotal
    }
}

/// Builds the grouped-save plan from a detection result and the user's accepted
/// lines. `fillUpAmount` is what the FillUp will actually record (the form's
/// total - normally the detected fuel line, hard rule 4, but the user may have
/// edited it, and their edit wins - hard rule 13).
public enum ReceiptGroupPlanner {
    public static func plan(detection: MixedReceiptDetection,
                            fillUpAmount: Decimal,
                            acceptedLineIDs: Set<UUID>) -> ReceiptGroupPlan? {
        guard case .mixed(let lines, _, let receiptTotal) = detection else { return nil }
        let accepted = lines.filter { acceptedLineIDs.contains($0.id) }
        let expenses = accepted.map { ReceiptExpense(id: UUID.v7(), line: $0, amount: $0.amount) }
        return ReceiptGroupPlan(purchaseGroupId: UUID.v7(),
                                fillUpAmount: fillUpAmount,
                                receiptTotal: receiptTotal,
                                expenses: expenses)
    }
}
