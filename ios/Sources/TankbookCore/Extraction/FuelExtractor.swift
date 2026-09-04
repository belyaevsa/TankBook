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

    public func extract(lines: [OCRLine],
                        source: ExtractionSource = .receipt,
                        qrAnchor: FiscalQRAnchor? = nil) -> FuelExtraction {
        var result = FuelExtraction()
        // RV.48: currency and date read the RAW lines, every value finder reads
        // the FILTERED ones. The asymmetry is the whole design of
        // `ReceiptNoiseFilter` - a Russian receipt's currency is established by
        // its `ИНН`/`ККТ`/`ОФД` lines, which are exactly the lines the filter
        // classifies as carrying no value. Filtering before the currency gate
        // would delete the evidence the gate runs on.
        result.currency = CurrencyDetection.detect(in: lines)
        result.date = detectDate(lines)
        // RV.48: the band is era-keyed (docs/SCHEMA.md -> Fuel price bands),
        // so the ladder needs the receipt's own date, never today's. The date
        // string `detectDate` produced is parsed once here and handed down;
        // a nil date (no date printed, or one the regex did not match) is a
        // plain absence - the band provider then applies its most recent period.
        let parsedDate = result.date.flatMap { ConfirmDate.parse($0) }
        let candidates = ReceiptNoiseFilter.candidateLines(lines)
        if source != .pump {
            result.fuelKind = detectFuelKind(candidates)
        }

        if source == .pump {
            // B2: a pump display is three bare numbers under three labels, not
            // the operand-pair / lone-marker shapes the receipt ladder expects
            // (no `×`, no `L` marker, no `ИТОГ` label, and a decimal point that
            // is often absent). The pump path reads the display's own shape:
            // separator-liberal tokens, label anchors, and a scale search pinned
            // by the currency-wide band and a plausible volume. Every ambiguity
            // abstains; the receipt ladder never runs on a pump.
            let band = bandProvider?.currencyBand(currency: result.currency)
            let pump = PumpExtractor.resolve(lines: candidates, currency: result.currency, band: band)
            result.liters = pump.liters
            result.unitPrice = pump.price.flatMap {
                ConfirmFormat.decimal(fromExtraction: $0,
                                      fractionDigits: ConfirmFormat.fractionDigits(for: .unitPrice))
            }
            result.total = pump.total.flatMap {
                ConfirmFormat.decimal(fromExtraction: $0,
                                      fractionDigits: ConfirmFormat.fractionDigits(for: .total))
            }
        } else {
            let volumePrice = resolveVolumeAndPrice(
                candidates, currency: result.currency, fuelKind: result.fuelKind, date: parsedDate
            )
            result.liters = volumePrice.liters
            // Money is born Decimal here (P2.2b), never Decimal(Double).
            result.unitPrice = volumePrice.price.flatMap {
                ConfirmFormat.decimal(fromExtraction: $0,
                                      fractionDigits: ConfirmFormat.fractionDigits(for: .unitPrice))
            }
            result.total = resolveTotal(lines, liters: result.liters, unitPrice: volumePrice.price)
        }

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
        // A zero-litres guard mirroring the two above. A printed `0,00L` volume
        // is a VOID (receipt-039), never "the fill was zero litres" - and it
        // would otherwise bias consumption exactly the way a zero price does,
        // only in the opposite direction (a zero denominator poisons L/100km
        // rather than cost/km). The zero-operand guard above already returns
        // the non-zero operand as the volume, so this also keeps a
        // `0.00 Х 30.61`-shaped pair from surfacing a zero-litre fill.
        if result.liters == 0 { result.liters = nil }
        // The fiscal QR carries the grand total (`s`) and the date (`t`) and
        // nothing else (FiscalQR.swift) - no litres, no unit price, no fuel
        // kind, no currency. When one decodes it is composed here so the scored
        // extraction is the extraction the app actually produces, not a weaker
        // OCR-only one (the same `ConfirmQRTotal.resolve` rule the confirm
        // sheet applies - authoritative on a disagreement, the fuel line stands
        // on a mixed receipt, hard rule 4).
        Self.composeQR(qrAnchor, into: &result)
        result.crossCheck = ExtractionCrossCheck.evaluate(
            liters: result.liters, unitPrice: result.unitPrice, total: result.total, lines: lines
        )

        // P2.13 digit repair, after the cross-check and never replacing its
        // four outcomes: on a PUMP display a single misread seven-segment bar
        // can make `liters x unitPrice` miss `total` by one digit step of one
        // operand (docs/EXTRACTION.md -> "Cross-multiplication as digit
        // repair"). The repair is a SUGGESTION, not a lock (hard rule 13): the
        // corrected value pre-fills the field, but `crossCheck` is kept a
        // `mismatch` carrying the read residual, so the confirm screen never
        // confirms the repaired triple.
        if source == .pump,
           let repair = DigitRepair.apply(liters: result.liters, unitPrice: result.unitPrice,
                                          total: result.total, source: source) {
            let residual = (ConfirmFormat.decimal(fromExtraction: result.liters,
                                                  fractionDigits: ConfirmFormat.fractionDigits(for: .volume)) ?? 0)
                * (result.unitPrice ?? 0)
                - (result.total ?? 0)
            result.crossCheck = .mismatch(residual: ExtractionCrossCheck.rounded(residual))
            switch repair.operand {
            case .liters: result.liters = repair.repaired
            case .unitPrice: result.unitPrice = ConfirmFormat.decimal(
                fromExtraction: repair.repaired, fractionDigits: 3)
            }
            result.digitRepair = repair
        }
        return result
    }

    /// Pure-text convenience, so the bulk of the core is testable from plain
    /// `[String]` with no image at all. Lines carry a `.zero` box, so the
    /// total-finder falls back to reading-order adjacency.
    public func extract(textLines: [String],
                        source: ExtractionSource = .receipt,
                        qrAnchor: FiscalQRAnchor? = nil) -> FuelExtraction {
        extract(lines: textLines.map { OCRLine(text: $0) }, source: source, qrAnchor: qrAnchor)
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
        // Step 3/4 fallback: the only unmarked operand pair. `OperandPair.first`
        // is NOT used here - on a mixed receipt the first pair is often a
        // non-fuel item (receipt-025 prints a service `69.28 X 1` ahead of the
        // fuel `43.38 Х 38.28`), and resolving that as the fill-up is a
        // confident wrong value (hard rule 13). With more than one unmarked
        // pair the parser cannot know which is fuel, so it abstains rather than
        // guess which line to read.
        if let (pair, index) = OperandPair.single(in: lines) {
            let discounted = lines[index].text.uppercased().contains("СКИДК")
            return resolveOperands(pair, at: index, in: lines, discounted: discounted, context: context)
        }
        // A labelled pump-style receipt with no explicit `x` (e.g. "67,00L"),
        // and the reference-block "цена за ед." price with its value to the
        // right.
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
        // A printed `0.00` operand names the price, never the volume. B2B
        // contract fuel cards settle the price between the fleet and the
        // network, so the driver's copy prints `30.61 Х 0.00` (receipt-034)
        // with the unit declared on the stranded product line above it. The
        // volume is the only certain number on the line; the price is
        // contract-hidden and stays nil (the same doctrine as the zero-total
        // guard below: a printed ZERO is "not on this receipt", never a fact).
        //
        // This runs BEFORE `resolveUnmarked` on purpose: with the user's own
        // price history wired (ladder step 3, `AppFuelPriceBand`), a realistic
        // median makes `resolveUnmarked` see the zero as the implausible
        // operand and return a zero-litre fill at a price that is really a
        // volume - a confident wrong value nothing downstream catches. The
        // marker paths above are already safe (a marked `0,00L` void, e.g.
        // receipt-039, never reaches here), so this guards only the unmarked
        // fallback.
        let leftZero = pair.left == 0
        let rightZero = pair.right == 0
        if leftZero != rightZero {
            return (liters: leftZero ? pair.right : pair.left, price: nil)
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
            // A quantity label/header states the volume with its value beside
            // or below it: "Колич. пр." (receipt-030) puts the value to the
            // right, "единиц" (receipt-023/044) puts it directly below in its
            // column.
            if volume == nil, line.text.isQuantityLabel {
                volume = quantityValue(forLabelAt: index, in: lines)
            }
            if price == nil, line.text.isPricePerUnitLabel {
                price = pricePerUnitValue(forLabelAt: index, in: lines)
            }
        }
        return (volume, price)
    }

    // MARK: - Total finder

    /// Resolves the total the extraction records as an exact `Decimal`; the
    /// DECISION stays in `Double` so the mode selection and fuel-line comparison
    /// stay bit-identical (a Decimal re-key would move the pinned scores).
    func resolveTotal(_ lines: [OCRLine], liters: Double?, unitPrice: Double?) -> Decimal? {
        let total = grandTotal(lines)
        let fuelLine = arithmeticFuelLine(lines, liters: liters, unitPrice: unitPrice)
        // No labelled total: the arithmetic fuel line is the amount the document
        // settles. On a fuel-only receipt it equals the total; on a mixed one it
        // is the fuel amount (hard rule 4). A discount receipt with no label at
        // all is not a shape the corpus carries.
        guard let total else {
            return fuelLine.flatMap(totalDecimal)
        }
        // A labelled total but unresolved operands. Hard rule 4 still applies to
        // a mixed receipt: its fuel line is the fuel operand pair's own product
        // (`a x b` is the fuel amount whichever operand is the volume), never the
        // grand total - receipt-025's service line pushes the total above the fuel.
        guard let fuelLine else {
            if ExtractionCrossCheck.nonFuelListSum(in: lines) > 0,
               let product = fuelOperandProduct(in: lines),
               abs(product - total) > max(0.02, total * 0.005) {
                return totalDecimal(product)
            }
            return totalDecimal(total)
        }
        let tolerance = max(0.02, total * 0.005)
        if abs(fuelLine - total) > tolerance {
            // The gap is either a mixed receipt (the fuel line wins - hard rule 4),
            // a printed discount (the labelled total is the charged amount and the
            // fuel line is the pre-discount list - the total stays), or a mispaired
            // total (the fuel line is the arithmetic truth). Only a discount that
            // actually reconciles the two keeps the labelled total.
            let residual = fuelLine - total
            let discounts = ExtractionCrossCheck.discountLines(in: lines).map {
                NSDecimalNumber(decimal: $0).doubleValue
            }
            let reconciled = discounts.contains { abs(abs(residual) - $0) <= tolerance }
            if ExtractionCrossCheck.nonFuelListSum(in: lines) > 0 || !reconciled {
                return totalDecimal(fuelLine)
            }
        }
        return totalDecimal(total)
    }

    /// The fuel line's amount: its own printed figure when the document prints
    /// one, else the arithmetic product. Nil when neither the volume nor the
    /// price resolved.
    private func arithmeticFuelLine(_ lines: [OCRLine], liters: Double?, unitPrice: Double?) -> Double? {
        guard let liters, let unitPrice else { return nil }
        if let printed = ExtractionCrossCheck.printedFuelLineAmount(
            lines, liters: liters, unitPrice: unitPrice
        ) {
            return printed
        }
        return liters * unitPrice
    }

    private func totalDecimal(_ value: Double) -> Decimal? {
        ConfirmFormat.decimal(fromExtraction: value, fractionDigits: 2)
    }

    /// The fuel operand pair's own product. `a x b == b x a`, so this is the
    /// fuel amount even when the parser could not decide which operand is the
    /// volume - the case on an unmarked, unresolvable fuel line.
    private func fuelOperandProduct(in lines: [OCRLine]) -> Double? {
        guard let index = fuelOperandIndex(in: lines),
              let pair = OperandPair(line: lines[index].text) else { return nil }
        return pair.left * pair.right
    }

    /// The index of the fuel operand line. Prefers the volume-marked operand;
    /// otherwise the operand pair that sits directly below a fuel product line
    /// (an unmarked fuel line on a mixed receipt, receipt-025).
    private func fuelOperandIndex(in lines: [OCRLine]) -> Int? {
        if let fuel = OperandPair.fuelLine(in: lines) { return fuel.index }
        for (index, line) in lines.enumerated() {
            guard OperandPair(line: line.text) != nil else { continue }
            guard index > 0, FuelKindNormalizer.isProductLine(lines[index - 1].text) else { continue }
            return index
        }
        return nil
    }

    /// The receipt's own grand total (ИТОГ/ВСЕГО/...), independent of the fuel
    /// line. Used by the mixed-receipt detector (P2.4) to verify that detected
    /// non-fuel items explain the gap between the fuel line and the receipt
    /// total when no QR is present. Nil when no total label is present.
    public func receiptGrandTotal(_ lines: [OCRLine]) -> Double? {
        grandTotal(lines)
    }

    // MARK: - Currency / date / fuel kind

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

    /// The one and only operand pair in the document, or nil when there are
    /// none or several. Used by the band's fallback: a pair the parser knows is
    /// the sole operand is the fuel line by elimination, but with two unmarked
    /// pairs (a mixed receipt's service ahead of the fuel, receipt-025) it
    /// cannot tell which is fuel and must abstain rather than resolve the first
    /// one as the fill-up.
    static func single(in lines: [OCRLine]) -> (OperandPair, Int)? {
        var found: (OperandPair, Int)?
        for (index, line) in lines.enumerated() {
            guard let pair = OperandPair(line: line.text) else { continue }
            if found != nil { return nil }
            found = (pair, index)
        }
        return found
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
        var normalized = line.replacingOccurrences(of: currencyPattern, with: " ", options: .regularExpression)
        // A GRADE NUMBER IS NOT AN OPERAND. receipt-036 prints the whole fill on
        // one line - `Аи-98 х25.00 лит х99.99 РУБ` - and it carries TWO
        // multiplication signs, so the leftmost `num op num` match is
        // `98 х 25.00`: the octane of the grade name times the volume. The
        // parser took 98 as the unit price (the truth is 99.99) and then
        // reported a total of 25 x 98 = 2450.00 against a printed 2499.75.
        // Masking the grade token leaves `25.00 лит х 99.99` as the only pair on
        // the line, which is the pair the paper states.
        let gradePattern = #"[АA][ИИHН][-\s]*\d{2,3}"#
        normalized = normalized.replacingOccurrences(
            of: gradePattern, with: " ", options: [.regularExpression, .caseInsensitive]
        )
        // The optional trailing marker must accept an UPPERCASE Cyrillic `Л`
        // for the same reason `hasVolumeMarker` must: `99.99 Х 25 Л`
        // (receipt-037) and `69.98 Х 30 Л` (receipt-031) print it that way, and
        // a marker the pattern cannot capture is a marker `resolveOperands`
        // cannot see.
        // The marker may be spelled out: receipt-036 writes `лит`, and once the
        // grade token above is masked the remaining pair is
        // `25.00 лит х 99.99`, whose marker a single-character class cannot
        // consume - the operator then fails to match the `и` and the whole line
        // yields no pair at all. `л`, `лит`, `литр` and their uppercase forms
        // are all the same marker.
        let pattern = /(\d+(?:[.,]\d+)?)\s*([лЛL](?:ИТР?|итр?)?(?!\p{L}))?\s*([xXхХ*·×])\s*(\d+(?:[.,]\d+)?)\s*([лЛL](?:ИТР?|итр?)?(?!\p{L}))?/
        guard let match = normalized.firstMatch(of: pattern) else { return nil }
        guard let left = Self.parse(match.1), let right = Self.parse(match.4) else { return nil }
        self.left = left
        self.right = right
        self.leftText = String(match.1) + (match.2.map(String.init) ?? "")
        self.rightText = String(match.4) + (match.5.map(String.init) ?? "")
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
    /// Whether the text carries a litre marker beside a number.
    ///
    /// The character class must hold BOTH cases of the Cyrillic letter. It held
    /// only lowercase `л` (U+043B) and Latin `L` until 2026-09-04, and Russian
    /// receipts print the marker in either case: `69.98 Х 30 Л` (receipt-031)
    /// and `99.99 Х 25 Л` (receipt-037) both carry an UPPERCASE Cyrillic `Л`
    /// (U+041B), so neither line was recognised as the fuel line. The ladder
    /// then fell through to `OperandPair.first`, which on receipt-031 picks the
    /// `БЕЗ СКИДКИ` list-price line instead - an unmarked pair - and abstained.
    /// One missing character cost four cells.
    /// A marker must be a STANDALONE token, never a letter inside a word or an
    /// identifier. Without the boundaries, `2X5LT6` - a card authorisation code
    /// on receipt-041 - reads as `2 X 5L` with a marked volume of five litres,
    /// and `wNLL32986034/90` on receipt-023 offers a volume of 32,986,034. Both
    /// are confident wrong values, which is the one outcome hard rule 13 rules
    /// out; an abstention would have been correct.
    ///
    /// The boundaries are not sufficient on their own and are not meant to be:
    /// `EE1003L` (receipt-046's `KMKR nr• EE1003L`) ends in a token-final `L`
    /// and passes this test. That line is removed by `ReceiptNoiseFilter`
    /// instead - the two layers cover different halves of the same problem.
    /// The optional `ИТ`/`ИТР` suffix is part of the marker, not a violation of
    /// the boundary: receipt-036 spells it `лит`, and a rule that demanded a
    /// bare `л` would reject the spelled-out form as if it were an identifier -
    /// which is exactly what happened when the boundary landed without it.
    var hasVolumeMarker: Bool {
        firstMatch(of: /\d\s*[лЛL](?:ИТР?|итр?)?(?!\p{L})/) != nil
            || firstMatch(of: /(?:^|[^\p{L}])[лЛL]\s*\d/) != nil
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
            || upper.contains("ЦЕНА ЗА ЕД")
    }

    /// A quantity label or column header. Deliberately "КОЛИЧ" and "ЕДИНИЦ",
    /// never bare "КОЛ" or "KOGUS": "КОЛ" also matches "Колонка" (receipt-006's
    /// pump number) and "KOGUS" would read the Estonian quantity header as a
    /// label-value row, where the receipt total sits beside it.
    var isQuantityLabel: Bool {
        let upper = uppercased()
        return upper.contains("КОЛИЧ") || upper.contains("ЕДИНИЦ")
    }
}

// MARK: - Total labels

enum TotalLabel {
    enum Kind { case primary, payment }

    private static let excluded = [
        "СУММА НДС", "СУММА БЕЗ НДС", "НДС", "ОКРУГЛЕНИЕ", "СДАЧА", "ПОЛУЧЕНО", "ПО НАЛОГУ",
        // The Estonian VAT total (`Käibemaks kokku`) contains the total word
        // `KOKKU`, so it used to be read as a primary total - receipt-001's
        // `Käibemaks kokku 24,24` tied with the real `KOKKU` and forced an
        // abstention. VAT is never the receipt total; both the `Ä` and the
        // OCR'd `A` spelling are excluded.
        "KÄIBEMAKS", "KAIBEMAKS"
    ]
    // `СУММА` is here in BOTH scripts on purpose. The Latin `SUMMA` is the
    // Estonian label; the Cyrillic `СУММА` is the Russian one, and until
    // 2026-09-04 only the Latin form was listed - so receipt-036's `СУММА:`
    // against `2499.75 РУБ` on the same baseline matched nothing and the total
    // came back nil. The two strings are different sequences of code points and
    // `uppercased()` never bridges them; the exclusion list above already
    // carries the Cyrillic `СУММА НДС`, which is checked first, so a VAT line
    // still cannot be read as the total.
    private static let primary = [
        "ИТОГ", "ВСЕГО", "К ОПЛАТЕ", "TOTAL", "KOKKU", "SUMMA", "СУММА", "AMOUNT"
    ]
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
