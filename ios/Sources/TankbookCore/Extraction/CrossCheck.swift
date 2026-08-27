import Foundation

// MARK: - The four-outcome cross-check (P2.12)

/// The result of checking `liters x unitPrice` against `total` (docs/EXTRACTION.md
/// -> "Cross-check: four outcomes, not two"). The boolean this replaces could
/// only say "agrees or not"; the confirm-screen lock needs more, because a
/// loyalty receipt is *correct* while failing the naive product check, and the
/// residual is the honest thing to show when it is not (hard rule 7).
///
/// The cross-check is a **consistency check, not a correctness one** - it
/// catches a misread digit and picks among discrete candidates, and it is blind
/// to a swapped volume/price pair (`a x b == b x a`) and to lost decimal
/// separators. A `reconciled` result does not make the parse more trustworthy;
/// it makes the check stop crying wolf.
public enum ExtractionCrossCheck: Sendable, Equatable, Hashable, Codable {
    /// product == total within the shared tolerance. High confidence: the three
    /// numbers lock together.
    case lock
    /// The residual (product - total) is explained by a discount line on the
    /// document. **Not an error.** `discountLine` is the printed discount the
    /// residual reconciles against (itself, on a fuel-only receipt; the fuel's
    /// share of the document's total discount on a mixed one).
    case reconciled(residual: Decimal, discountLine: Decimal)
    /// product < total and the gap is explained by other priced lines: the
    /// amount passed in is the receipt's GRAND TOTAL, not the fuel amount. The
    /// fill-up amount is the fuel line, never the grand total (hard rule 4) -
    /// `fuelLine` is the amount to use.
    case mixed(grandTotal: Decimal, fuelLine: Decimal)
    /// None of the above. `residual` is what the UI shows and names a next step
    /// for - "1.01 less than 67 x 1.884" beats a bare amber warning (hard rule 7).
    case mismatch(residual: Decimal)
    /// A number is missing: no cross-check is possible.
    case notApplicable
}

/// The pure cross-check: liter x unitPrice against total, four outcomes, over a
/// document's OCR lines. No Vision, no persistence - L1-testable from plain
/// `[String]`. The tolerance is the one shared constant
/// (`ConfirmConfidenceGate.crossCheckTolerance`) - forked nowhere, and not
/// loosened to make a fixture pass: P4.12/P4.13 scored three engine arms at it.
public extension ExtractionCrossCheck {
    static func evaluate(liters: Double?, unitPrice: Decimal?, total: Decimal?,
                         lines: [OCRLine]) -> ExtractionCrossCheck {
        // The volume enters through the exact Decimal boundary; `unitPrice` and
        // `total` are already exact Decimals (the extraction types money as
        // Decimal since P2.2b), so they need no Double round trip here.
        guard let liters = ConfirmFormat.decimal(fromExtraction: liters, fractionDigits: 2),
              let unitPrice, let total else {
            return .notApplicable
        }
        let product = liters * unitPrice
        let residual = product - total
        // 1. lock: product == total within tolerance.
        if abs(residual) <= ConfirmConfidenceGate.crossCheckTolerance(amount: total) {
            return .lock
        }

        // The document's own figures: its grand total, its discount lines, and
        // the sum of the non-fuel priced lines at list (liters x price).
        let grandTotal = FuelExtractor().receiptGrandTotal(lines)
            .flatMap { ConfirmFormat.decimal(fromExtraction: $0, fractionDigits: 2) }
            ?? total
        let shopList = nonFuelListSum(in: lines)
        let discounts = discountLines(in: lines)

        // 2. reconciled: the residual is EXPLAINED by a discount line, not
        // merely "a discount line exists" (receipt-038 prints `EXTRA SOODUS
        // -0,23` beneath an item whose total already equals the product - the
        // residual is ~0 there, so lock fires first and this never runs).
        //
        // A mixed receipt reconciles as a whole: the fuel line and the shop
        // lines each carry a list and a charged figure, and the printed
        // discount is the sum of the two shares. Writing `product + shopList ==
        // grandTotal + discount` makes that check span both cases - on a
        // fuel-only receipt `shopList` is 0 and `grandTotal == total`, so it
        // reduces to "residual == discount", which is the five Circle K
        // screenshots. On a mixed one it is the whole-document accounting that
        // `screenshot-008` passes completely (115.02 + 11.14 == 122.99 + 3.17).
        for discount in discounts {
            let reconciledMagnitude = abs(grandTotal + discount)
            let difference = abs((product + shopList) - (grandTotal + discount))
            if difference <= ConfirmConfidenceGate.crossCheckTolerance(amount: reconciledMagnitude) {
                return .reconciled(residual: rounded(residual), discountLine: rounded(discount))
            }
        }

        // 3. mixed: product < total and the gap is explained by the other
        // priced lines. The caller's `total` is the receipt's grand total; the
        // fuel amount is the fuel line (hard rule 4).
        if product < total {
            let gap = total - product
            let tolerance = ConfirmConfidenceGate.crossCheckTolerance(amount: gap)
            if abs(shopList - gap) <= tolerance {
                return .mixed(grandTotal: total, fuelLine: product)
            }
        }

        // 4. none of the above.
        return .mismatch(residual: rounded(residual))
    }

    // MARK: - Document structure

    /// The fuel line's own printed amount when the document prints one: the
    /// money value on the line directly above the fuel operand line (Circle K
    /// app rows lay out name / charged / `price x volume L`). Only a clean
    /// money line counts - a label-carrying line (`26135.24 НДС 22%` on
    /// receipt-009) is the receipt's noise, not the fuel amount - and it must
    /// be a plausible charge for the volume (a fuel discount moves the line by
    /// a few percent, never by a factor). Used by `FuelExtractor.resolveTotal`
    /// so a mixed receipt keeps its printed fuel line (hard rule 4).
    static func printedFuelLineAmount(_ lines: [OCRLine], liters: Double, unitPrice: Double) -> Double? {
        guard let fuel = OperandPair.fuelLine(in: lines) else { return nil }
        let product = liters * unitPrice
        let candidate = fuel.index - 1
        guard candidate >= 0, candidate < lines.count else { return nil }
        let line = lines[candidate]
        guard NumberScanner.isValueLine(line.text),
              !isNoiseValueLine(line.text),
              let value = NumberScanner.value(in: line.text),
              value > 0,
              abs(value - product) < product * 0.25 else { return nil }
        return value
    }

    private static func isNoiseValueLine(_ text: String) -> Bool {
        let upper = text.uppercased()
        let noise = ["НДС", "ИТОГ", "ВСЕГО", "СУММА", "TOTAL", "TAX", "KOKKU", "SUMMA",
                     "KK MAKSE", "ОКРУГЛ", "СДАЧА", "ПОЛУЧЕНО", "В ТОМ ЧИСЛЕ", "DISCOUNT",
                     "БЕЗНАЛИЧНЫМИ", "НАЛИЧНЫМИ", "К ОПЛАТЕ", "KÄIBEMAKS"]
        return noise.contains(where: upper.contains)
    }

    /// The sum of the non-fuel priced lines at LIST price (quantity x price).
    /// Zero on a fuel-only receipt. The fuel line is excluded by its volume
    /// marker (the `L`/`л` token that distinguishes it from Latvian `Gab.`
    /// items on `screenshot-008` - EXTRACTION.md failure mode 2).
    static func nonFuelListSum(in lines: [OCRLine]) -> Decimal {
        let fuelIndex = OperandPair.fuelLine(in: lines)?.index
        var sum = Decimal.zero
        for (index, line) in lines.enumerated() {
            if index == fuelIndex { continue }
            guard !line.text.hasVolumeMarker else { continue }
            guard let pair = MixedReceiptDetector.quantityPricePair(line.text) else { continue }
            let quantity = ConfirmFormat.decimal(fromExtraction: pair.quantity, fractionDigits: 2) ?? 0
            let price = ConfirmFormat.decimal(fromExtraction: pair.price, fractionDigits: 3) ?? 0
            sum += quantity * price
        }
        return sum
    }

    /// The discount lines a document prints: a line carrying a discount
    /// keyword ("Discount", "СКИДКА", "EXTRA SOODUS", "You saved ...") with a
    /// value attached - on the same line, on the same baseline, or on an
    /// adjacent line. The value is what matters, and `reconciled` matches the
    /// RESIDUAL against it; the presence of such a line is never enough on its
    /// own.
    static func discountLines(in lines: [OCRLine]) -> [Decimal] {
        let keywords = ["DISCOUNT", "СКИДК", "SOODUS", "SÄÄST", "ALLEHINDLUS", "SAVED", "ЭКОНОМ"]
        var values: [Decimal] = []
        for (index, line) in lines.enumerated() {
            let upper = line.text.uppercased()
            guard keywords.contains(where: upper.contains) else { continue }
            guard let value = discountValue(for: line, at: index, in: lines) else { continue }
            values.append(value)
        }
        return values
    }

    private static func discountValue(for label: OCRLine, at index: Int,
                                      in lines: [OCRLine]) -> Decimal? {
        // The label line itself carries the amount ("You saved 1.01 EUR",
        // "В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83", "Discount 1.01 EUR").
        if let value = NumberScanner.value(in: label.text) {
            return ConfirmFormat.decimal(fromExtraction: value, fractionDigits: 2)
        }
        // Same-baseline value: Circle K rows print `1.01 EUR  Discount` with
        // the value beside the label. Only meaningful with real geometry; a
        // text-line convenience array has `.zero` boxes and would pair
        // everything with the first value.
        if label.boundingBox != .zero {
            var best: (distance: CGFloat, value: Double)?
            for (otherIndex, line) in lines.enumerated() where otherIndex != index {
                guard abs(line.midY - label.midY) < 0.012,
                      NumberScanner.isValueLine(line.text),
                      let value = NumberScanner.value(in: line.text) else { continue }
                let distance = abs(line.boundingBox.midX - label.boundingBox.midX)
                if best == nil || distance < best!.distance {
                    best = (distance, value)
                }
            }
            if let best {
                return ConfirmFormat.decimal(fromExtraction: best.value, fractionDigits: 2)
            }
        }
        // Adjacent value line in reading order (`EXTRA SOODUS` then
        // `-0,23 EUR`). Checked only when the box is zero, so a text-line test
        // exercises the same path the real geometry does for a label above its
        // value.
        if label.boundingBox == .zero {
            for otherIndex in [index - 1, index + 1] where otherIndex >= 0 && otherIndex < lines.count {
                if let value = NumberScanner.value(in: lines[otherIndex].text) {
                    return ConfirmFormat.decimal(fromExtraction: value, fractionDigits: 2)
                }
            }
        }
        return nil
    }

    /// Rounds a Decimal to the currency's two decimal places (the receipt's
    /// own display precision), half-up - the residual the UI will render.
    static func rounded(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var source = value
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
}
