import Foundation

/// Deterministic, rules-only extractor over OCR'd lines. No Vision, no LLM:
/// the pure text -> fields core of the P2.2 port (see Spike/ReceiptSpike for
/// the reference it was extracted from). Every field is a suggestion, never a
/// fact (CLAUDE.md hard rule 13) - an uncertain field is returned nil.
public struct FuelExtractor: Sendable {
    public var bandProvider: (any FuelPriceBandProvider)?

    public init(bandProvider: (any FuelPriceBandProvider)? = nil) {
        self.bandProvider = bandProvider
    }

    // MARK: - Entry point

    public func extract(lines: [OCRLine], source: ExtractionSource = .receipt) -> FuelExtraction {
        var result = FuelExtraction()
        result.currency = detectCurrency(lines)
        result.date = detectDate(lines)
        if source != .pump {
            result.fuelKind = detectFuelKind(lines)
        }

        let volumePrice = resolveVolumeAndPrice(
            lines, currency: result.currency, fuelKind: result.fuelKind, date: nil
        )
        result.liters = volumePrice.liters
        result.unitPrice = volumePrice.price
        result.total = resolveTotal(lines, liters: result.liters, unitPrice: result.unitPrice)

        // A printed ZERO is "the price is not on this receipt", never "the fuel
        // was free". B2B contract fuel cards settle the price between the fleet
        // and the network, so the driver's copy prints `30.61 X 0.00` and
        // `ИТОГ 0.00` under "Цена определена договором" (receipt-034). Storing
        // 0.00 would be a confident wrong value (hard rule 13) and it biases
        // stats silently: cost/km keeps the fill's odometer span in the
        // denominator while contributing nothing to the numerator, so every
        // corporate fill drags the rate down.
        //
        // `FillUp.money` is already optional and `ConsumptionEngine.costPerKm`
        // already skips entries without it, so nil is the representation the
        // rest of the app is built for: consumption still computes from volume,
        // and only the cost figures abstain.
        if result.total == 0 { result.total = nil }
        if result.unitPrice == 0 { result.unitPrice = nil }
        result.crossCheck = ExtractionCrossCheck.evaluate(
            liters: result.liters, unitPrice: result.unitPrice, total: result.total, lines: lines
        )
        return result
    }

    /// Pure-text convenience, so the bulk of the core is testable from plain
    /// `[String]` with no image at all. Lines carry a `.zero` box, so the
    /// total-finder falls back to reading-order adjacency.
    public func extract(textLines: [String], source: ExtractionSource = .receipt) -> FuelExtraction {
        extract(lines: textLines.map { OCRLine(text: $0) }, source: source)
    }

    // MARK: - Volume / price ladder (docs/SCHEMA.md -> Fuel price bands)

    func resolveVolumeAndPrice(
        _ lines: [OCRLine], currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?
    ) -> (liters: Double?, price: Double?) {
        // Step 1: a labelled column states which column is which.
        if let column = labelledColumn(lines) {
            return column
        }
        let context = BandContext(currency: currency, fuelKind: fuelKind, date: date)
        // Step 2: the unit marker's position names the volume. The FUEL line is
        // the operand pair carrying the volume marker - on a mixed receipt
        // there are many operand lines (Latvian `Gab.` items on
        // screenshot-008) and the fuel line is the only one with `L`, so
        // neither "first priced line" nor "line nearest the total" finds it
        // (docs/EXTRACTION.md failure mode 2). Steps 3/4 disambiguate the
        // unmarked rest via the injected provider.
        if let fuel = OperandPair.fuelLine(in: lines) {
            let discounted = lines[fuel.index].text.uppercased().contains("СКИДК")
            return resolveOperands(fuel.pair, at: fuel.index, in: lines,
                                   discounted: discounted, context: context)
        }
        if let (pair, index) = OperandPair.first(in: lines) {
            let discounted = lines[index].text.uppercased().contains("СКИДК")
            return resolveOperands(pair, at: index, in: lines, discounted: discounted, context: context)
        }
        // A labelled pump-style receipt with no explicit `x` (e.g. "67,00L").
        if let lone = loneMarkers(lines) {
            return lone
        }
        // Step 5: undecided.
        return (nil, nil)
    }

    private func labelledColumn(_ lines: [OCRLine]) -> (liters: Double?, price: Double?)? {
        guard let priceX = headerMidX(lines, matching: ["ЦЕНА", "PRICE", "PREIS"]),
              let qtyX = headerMidX(lines, matching: ["КОЛ", "QTY", "КОЛИЧЕСТВО", "KOGUS"]) else {
            return nil
        }
        guard abs(priceX - qtyX) > 0.05 else { return nil }

        // The item row sits on the product line's baseline; its numbers align
        // to the header columns.
        guard let productY = lines.first(where: { FuelKindNormalizer.isProductLine($0.text) })?.midY else {
            return nil
        }
        var price: Double?
        var qty: Double?
        for line in lines where abs(line.midY - productY) < 0.03 {
            guard line.text.firstMatch(of: /[xXхХ*·×]/) == nil else { continue }
            for number in NumberScanner.numbers(in: line.text) {
                let dxPrice = abs(line.midX - priceX)
                let dxQty = abs(line.midX - qtyX)
                if dxPrice < dxQty, dxPrice < 0.1, price == nil {
                    price = number
                } else if dxQty < 0.1, qty == nil {
                    qty = number
                }
            }
        }
        guard price != nil || qty != nil else { return nil }
        return (qty, price)
    }

    private func headerMidX(_ lines: [OCRLine], matching keywords: [String]) -> CGFloat? {
        for line in lines {
            let upper = line.text.uppercased()
            if upper.contains("НДС") { continue }
            guard upper.split(separator: " ").count <= 3 else { continue }
            if keywords.contains(where: upper.contains) {
                return line.midX
            }
        }
        return nil
    }

    private func resolveOperands(
        _ pair: OperandPair, at index: Int, in lines: [OCRLine], discounted: Bool, context: BandContext
    ) -> (liters: Double?, price: Double?) {
        let leftVol = pair.leftText.hasVolumeMarker
        let rightVol = pair.rightText.hasVolumeMarker
        var leftPrice = pair.leftText.hasPriceMarker
        var rightPrice = pair.rightText.hasPriceMarker
        // A currency word ("руб") often prints on its own line, labelling the
        // operand it sits beside (receipt-016). Check the pair's own baseline.
        if !leftPrice, !rightPrice {
            let side = adjacentPriceMarkerSide(at: index, in: lines)
            if side == .left { leftPrice = true }
            if side == .right { rightPrice = true }
        }

        if leftVol != rightVol {
            let liters = leftVol ? pair.left : pair.right
            // A "без скидки" line prints the list price, not the price paid
            // (receipt-010): the volume is still certain, the price is not.
            let price = discounted ? nil : (leftVol ? pair.right : pair.left)
            return (liters, price)
        }
        if leftPrice != rightPrice {
            let price = leftPrice ? pair.left : pair.right
            let liters = discounted ? nil : (leftPrice ? pair.right : pair.left)
            return (liters, price)
        }
        return resolveUnmarked(left: pair.left, right: pair.right, context: context)
    }

    private func adjacentPriceMarkerSide(at index: Int, in lines: [OCRLine]) -> MarkerSide? {
        let pair = lines[index]
        for (otherIndex, line) in lines.enumerated() where otherIndex != index {
            guard abs(line.midY - pair.midY) < 0.02, line.text.isCurrencyWord else { continue }
            if line.midX < pair.midX { return .left }
            if line.midX > pair.midX { return .right }
        }
        return nil
    }

    private func resolveUnmarked(
        left: Double, right: Double, context: BandContext
    ) -> (liters: Double?, price: Double?) {
        guard let provider = bandProvider else { return (nil, nil) }
        // Step 3: the user's price history (needs no network).
        if let history = provider.historicalPrice(currency: context.currency, fuelKind: context.fuelKind) {
            let tolerance = history * 0.6
            let leftPlausible = abs(left - history) <= tolerance
            let rightPlausible = abs(right - history) <= tolerance
            if leftPlausible != rightPlausible {
                return leftPlausible ? (right, left) : (left, right)
            }
        }
        // Step 4: the curated band (rank, never veto).
        if let band = provider.band(currency: context.currency, fuelKind: context.fuelKind, date: context.date) {
            let leftIn = band.contains(left)
            let rightIn = band.contains(right)
            if leftIn != rightIn {
                return leftIn ? (right, left) : (left, right)
            }
        }
        return (nil, nil)
    }

    private func loneMarkers(_ lines: [OCRLine]) -> (liters: Double?, price: Double?)? {
        var volume: Double?
        var price: Double?
        for (index, line) in lines.enumerated() {
            if volume == nil, line.text.firstMatch(of: /[xXхХ*·×]/) == nil, line.text.hasVolumeMarker,
               let value = NumberScanner.numbers(in: line.text).first {
                volume = value
            }
            if price == nil, line.text.isPricePerUnitLabel {
                // The value sits directly below its "/L" label, in the same
                // column - never above it, where the row's sum lives.
                var best: (distance: CGFloat, value: Double)?
                for (otherIndex, other) in lines.enumerated() where otherIndex != index {
                    let distance = line.midY - other.midY
                    guard distance > 0, distance < 0.02,
                          NumberScanner.isValueLine(other.text),
                          let value = NumberScanner.value(in: other.text) else { continue }
                    if best == nil || distance < best!.distance {
                        best = (distance, value)
                    }
                }
                price = best?.value
            }
        }
        return (volume, price)
    }

    // MARK: - Total finder

    func resolveTotal(_ lines: [OCRLine], liters: Double?, unitPrice: Double?) -> Double? {
        let total = grandTotal(lines)
        // Hard rule 4: on a mixed receipt the fill-up amount is the fuel line,
        // never the grand total. Detection is the cross-check itself
        // (docs/SCHEMA.md CHECK 3). The fuel line's own printed amount wins
        // over the arithmetic product when the document prints one (a fuel
        // discount makes the charged line differ from liters x unitPrice -
        // screenshot-008 returns 112.63, never 115.02 or the grand total
        // 122.99).
        guard let liters, let unitPrice, let total else { return total }
        let fuelLine = ExtractionCrossCheck.printedFuelLineAmount(lines, liters: liters, unitPrice: unitPrice)
            ?? liters * unitPrice
        if abs(fuelLine - total) > max(0.02, total * 0.005) {
            return fuelLine
        }
        return total
    }

    /// The receipt's own grand total (ИТОГ/ВСЕГО/...), independent of the fuel
    /// line. Used by the mixed-receipt detector (P2.4) to verify that detected
    /// non-fuel items explain the gap between the fuel line and the receipt
    /// total when no QR is present. Nil when no total label is present.
    public func receiptGrandTotal(_ lines: [OCRLine]) -> Double? {
        grandTotal(lines)
    }

    private func grandTotal(_ lines: [OCRLine]) -> Double? {
        var candidates: [Double] = []
        var primaryCandidates: [Double] = []
        for (index, line) in lines.enumerated() {
            guard let kind = TotalLabel.classify(line.text) else { continue }
            if let value = pairedValue(forLabelAt: index, in: lines) {
                candidates.append(value)
                if kind == .primary { primaryCandidates.append(value) }
            }
        }
        return modal(candidates, preferring: primaryCandidates)
    }

    private func pairedValue(forLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let label = lines[index]
        // Same-baseline value to the right (the reading-order fix: Vision emits
        // value before label, so array order cannot be trusted).
        var best: (distance: CGFloat, value: Double)?
        for (otherIndex, line) in lines.enumerated() where otherIndex != index {
            guard line.boundingBox.minX > label.boundingBox.minX,
                  abs(line.midY - label.midY) < 0.012,
                  NumberScanner.isValueLine(line.text),
                  let value = NumberScanner.value(in: line.text) else { continue }
            let distance = abs(line.midY - label.midY)
            if best == nil || distance < best!.distance {
                best = (distance, value)
            }
        }
        if let best { return best.value }
        // Adjacent value lines (reading order), for receipts where the value
        // sits on its own row above or below the label.
        if index > 0, let value = adjacentValue(lines[index - 1]) { return value }
        if index + 1 < lines.count, let value = adjacentValue(lines[index + 1]) { return value }
        return nil
    }

    private func adjacentValue(_ line: OCRLine) -> Double? {
        guard NumberScanner.isValueLine(line.text) else { return nil }
        return NumberScanner.value(in: line.text)
    }

    /// The total-finder's mode, with a deterministic, deliberate tie-break.
    ///
    /// Two candidates can tie on how often they appear AND on how often the
    /// primary labels (ИТОГ/ИТОГО/...) named each. That is precisely "the parser
    /// does not know which total is the receipt's", and the rest of this file
    /// already refuses rather than guesses at exactly that point (a printed
    /// `0.00` becomes nil, an unmarked operand pair returns nil - `SCHEMA.md`
    /// -> Fuel price bands, step 5: "Undecided. Leave the fields empty"). So
    /// the tie-break is **nil on an unbreakable tie**, not "sort for stability":
    /// a confident wrong total is worse than an empty field the user fills
    /// (hard rule 13), and the previous rule - `modes.max(by:)` over equal
    /// `primaryCounts`, with `?? modes.first` behind it - returned whichever
    /// value Swift's `Dictionary` hash seed had left last. That made the score
    /// move between identical runs (P4.13 saw receipt-021/-026/-029 flip
    /// 29/96 <-> 30/96). Only a tie that the primary labels genuinely break
    /// still resolves; an unbreakable tie abstains.
    private func modal(_ candidates: [Double], preferring primary: [Double]) -> Double? {
        guard !candidates.isEmpty else { return nil }
        let counts = Dictionary(grouping: candidates, by: { $0 }).mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        let modes = counts.filter { $0.value == maxCount }.map(\.key)
        if modes.count == 1 { return modes[0] }
        // Tie on count: prefer the value the primary labels named most often.
        // That preference is itself allowed to tie; when it does, abstain.
        let primaryCounts = Dictionary(grouping: primary, by: { $0 }).mapValues(\.count)
        let topPrimary = modes.map { primaryCounts[$0] ?? 0 }.max() ?? 0
        let winners = modes.filter { (primaryCounts[$0] ?? 0) == topPrimary }
        return winners.count == 1 ? winners[0] : nil
    }

    // MARK: - Currency / date / fuel kind

    private func detectCurrency(_ lines: [OCRLine]) -> CurrencyCode? {
        let markers: [(String, String)] = [
            ("₽", "RUB"), ("РУБ", "RUB"), ("RUB", "RUB"), ("ТЕНГЕ", "KZT"), ("KZT", "KZT"),
            ("€", "EUR"), ("EUR", "EUR"), ("PLN", "PLN"), ("ZŁ", "PLN"),
            ("CZK", "CZK"), ("KČ", "CZK"), ("USD", "USD"), ("$", "USD"),
            ("GBP", "GBP"), ("£", "GBP"), ("CHF", "CHF")
        ]
        for line in lines {
            let upper = line.text.uppercased()
            for (marker, code) in markers where upper.contains(marker) {
                if let currency = CurrencyCode(rawValue: code) { return currency }
            }
        }
        return nil
    }

    private func detectDate(_ lines: [OCRLine]) -> String? {
        let regex = /\b(\d{1,2})[.\/-](\d{1,2})[.\/-](\d{2,4})\b|\b(\d{4})-(\d{2})-(\d{2})\b/
        for line in lines {
            if let match = line.text.firstMatch(of: regex) {
                return String(match.0)
            }
        }
        return nil
    }

    private func detectFuelKind(_ lines: [OCRLine]) -> FuelKind? {
        for line in lines where FuelKindNormalizer.isProductLine(line.text) {
            if let kind = FuelKindNormalizer.normalize(line.text) {
                return kind
            }
        }
        return nil
    }
}

// MARK: - Operand pair

/// The hints steps 3/4 of the ladder need: currency, fuel kind and receipt date.
private struct BandContext {
    let currency: CurrencyCode?
    let fuelKind: FuelKind?
    let date: Date?
}

struct OperandPair {
    let left: Double
    let right: Double
    let leftText: String
    let rightText: String

    /// Finds the first `A op B` operand line in the document and returns both
    /// values, their surrounding text (so a trailing unit marker can name the
    /// volume) and the line index (so an adjacent currency word can be read).
    static func first(in lines: [OCRLine]) -> (OperandPair, Int)? {
        for (index, line) in lines.enumerated() {
            if let pair = OperandPair(line: line.text) {
                return (pair, index)
            }
        }
        return nil
    }

    /// The FUEL line: the operand pair carrying a volume marker on either
    /// operand. On a mixed receipt there are many operand lines (Latvian
    /// `Gab.` items on screenshot-008) and the fuel line is the only one whose
    /// volume is marked `L`/`л` - so this is what separates the diesel from a
    /// chocolate bar when the fuel line is neither first nor nearest the total
    /// (docs/EXTRACTION.md failure mode 2). Nil when no operand carries a
    /// marker; callers then fall back to `first(in:)`.
    static func fuelLine(in lines: [OCRLine]) -> (pair: OperandPair, index: Int)? {
        for (index, line) in lines.enumerated() {
            guard let pair = OperandPair(line: line.text) else { continue }
            if pair.leftText.hasVolumeMarker || pair.rightText.hasVolumeMarker {
                return (pair, index)
            }
        }
        return nil
    }

    init?(line: String) {
        // num (marker?) op (marker?) num - the marker is an optional trailing
        // л/L on either operand. A currency word may sit between an operand and
        // the operator (`1.884 EUR x 67 L` on the Circle K screenshots): the
        // confirm-screen lines print it and the thermal receipts omit it, so
        // the currency tokens are stripped before the shared pattern runs.
        let currencyPattern = #"\s*(?:EUR|€|RUB|₽|USD|\$|ТЕНГЕ|KZT|PLN|ZŁ|CZK|KČ|GBP|£|CHF|грн)\s*"#
        let normalized = line.replacingOccurrences(of: currencyPattern, with: " ", options: .regularExpression)
        let pattern = /(\d+(?:[.,]\d+)?)\s*([лL]?)\s*([xXхХ*·×])\s*(\d+(?:[.,]\d+)?)\s*([лL]?)/
        guard let match = normalized.firstMatch(of: pattern) else { return nil }
        guard let left = Self.parse(match.1), let right = Self.parse(match.4) else { return nil }
        self.left = left
        self.right = right
        self.leftText = String(match.1) + String(match.2)
        self.rightText = String(match.4) + String(match.5)
    }

    private static func parse(_ text: Substring) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}

// MARK: - Marker helpers

enum MarkerSide { case left, right }

extension String {
    /// A unit marker attached to a number: "67,00L", "40 л", "66.810л". A bare
    /// "L" inside a word (Tallinn, ЛУКОЙЛ) is not a volume marker.
    var hasVolumeMarker: Bool {
        firstMatch(of: /\d\s*[лL]/) != nil || firstMatch(of: /[лL]\s*\d/) != nil
    }

    var hasPriceMarker: Bool {
        let upper = uppercased()
        return upper.contains("РУБ") || upper.contains("₽") || upper.contains("€")
            || upper.contains("$") || upper.contains("EUR") || upper.contains("ТЕНГЕ")
    }

    /// A short line that names a currency and nothing else ("руб", "₽", "тенге").
    var isCurrencyWord: Bool {
        let upper = uppercased().trimmingCharacters(in: .whitespaces)
        let words = upper.split(separator: " ")
        guard words.count <= 2 else { return false }
        return words.allSatisfy { word in
            ["РУБ", "РУБ.", "РУБЛИ", "ТЕНГЕ", "KZT", "€", "₽", "$", "EUR"].contains(String(word))
        }
    }

    var isPricePerUnitLabel: Bool {
        let upper = uppercased()
        return upper.contains("/L") || upper.contains("/Л") || upper.contains("ЦЕНА/ЛИТР")
            || upper.contains("ЦЕНА ЗА 1 ЛИТР") || upper.contains("HIND/1L")
    }
}

// MARK: - Total labels

enum TotalLabel {
    enum Kind { case primary, payment }

    private static let excluded = [
        "СУММА НДС", "СУММА БЕЗ НДС", "НДС", "ОКРУГЛЕНИЕ", "СДАЧА", "ПОЛУЧЕНО", "ПО НАЛОГУ"
    ]
    private static let primary = ["ИТОГ", "ВСЕГО", "К ОПЛАТЕ", "TOTAL", "KOKKU", "SUMMA", "AMOUNT"]
    private static let payment = [
        "НАЛИЧНЫМИ", "БЕЗНАЛИЧНЫМИ", "ПЛАТ.КАРТОЙ", "ПЛАТ. КАРТОЙ", "КАРТОЙ", "KK MAKSE"
    ]

    static func classify(_ text: String) -> Kind? {
        let upper = text.uppercased()
        if excluded.contains(where: upper.contains) { return nil }
        if primary.contains(where: upper.contains) { return .primary }
        if payment.contains(where: upper.contains) { return .payment }
        return nil
    }
}
