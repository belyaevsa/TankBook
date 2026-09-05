import CoreGraphics
import Foundation

// MARK: - Pump display extraction (B2)

// The pump path. A pump display prints three bare numbers under three labels in
// a fixed layout, with no operator and often no decimal point: Vision reads the
// digits at confidence 1.00 and drops the seven-segment dot per field. The
// receipt parser's operand pairing (an `×`) and lone-marker (`L`, `/L`) paths
// never fire, and `NumberScanner.decimals` discarded the separator-less runs
// outright - the digits were read and thrown away one layer down.
//
// This resolver reads the display's own shape: separator-liberal tokens, labels
// that assign a number to a role by POSITION rather than magnitude, and a scale
// search pinned by the currency price band and a plausible volume. Every
// ambiguity abstains (hard rule 13): a factor-of-ten volume error is invisible
// on the Confirm screen and corrupts consumption for the life of the vehicle.

enum PumpExtractor {
    struct Result {
        var liters: Double?
        var price: Double?
        var total: Double?
    }

    private enum Role { case total, volume, price }

    /// The plausible fill range. The floor is 2, not 5 - `pump-014` is a real
    /// 3.92 L fill and the pumps themselves print `Vmin 2 LIITRIT`
    /// (docs/EXTRACTION.md). Small fills are data, not noise.
    static let volumeRange = 2.0...150.0

    /// Resolves a pump display to a (liters, price, total) triple, committing a
    /// field only when the cross-check plus the physical bounds pin it to a
    /// single value. A field whose label is missing or garbled stays empty -
    /// the fallback is abstention, never a guess.
    static func resolve(lines: [OCRLine], currency: CurrencyCode?, band: FuelPriceBand?) -> Result {
        let hasGeometry = lines.contains { $0.boundingBox != .zero }
        // The total and volume values, once their labels claim them, must not
        // reappear as price candidates (a volume `8792` re-scaled to `87.92` is
        // a plausible price that re-opens the factor-of-ten ambiguity). Claimed
        // lines are tracked so the price's board scan skips them - in BOTH
        // modes, not just the text fallback (a compact Gilbarco display like
        // pump-003 stacks every field within the price's geometry band).
        let claimed = claimedValueIndices(in: lines, geometry: hasGeometry)
        let volumeTokens = tokens(for: .volume, in: lines, geometry: hasGeometry, claimed: claimed)
        let priceTokens = tokens(for: .price, in: lines, geometry: hasGeometry, claimed: claimed)
        let totalTokens = tokens(for: .total, in: lines, geometry: hasGeometry, claimed: claimed)
        let volumeValues = flattened(volumeTokens)
        let priceValues = flattened(priceTokens)
        // The total is money, so its scale search is narrower - see
        // `PumpNumber.moneyCandidates`. This is what resolves the
        // factor-of-ten tie the scale-invariant cross-check cannot.
        let totalValues = flattened(totalTokens, money: true)
        // A grade BOARD carries several distinct price tokens (pump-005, 035);
        // a selected-price WINDOW carries one (`€/L` -> `1,799`). A board price
        // may rank a candidate but never becomes the unit price alone - it must
        // be pinned by an exact close or a unique repair.
        let priceIsBoard = Set(priceTokens.map(\.raw)).count > 1
        return solve(volumeValues: volumeValues, priceValues: priceValues, totalValues: totalValues,
                     band: band, priceIsBoard: priceIsBoard)
    }

    // MARK: - Label anchors

    /// The digit-run tokens a role's label(s) name. With real geometry the value
    /// is read from the lines beside the label (on the same baseline, left or
    /// right, or - for the price's grade board - the cluster above/below in the
    /// same column region); with a text-only line array the value is the
    /// adjacent value line in reading order. A number printed ON the label line
    /// itself (`1869 HIND/1L`, `1,799 EUR/L`) is read inline, with the label's
    /// own `1` markers (`/1L`, `ЗА 1 ЛИТР`) stripped so they are never a value.
    private static func tokens(for field: Role, in lines: [OCRLine], geometry: Bool,
                               claimed: Set<Int>) -> [PumpNumber] {
        var collected: [PumpNumber] = []
        for (index, line) in lines.enumerated() {
            guard role(of: line.text) == field else { continue }
            collected += NumberScanner.pumpNumbers(in: stripInlineLabel(line.text))
            collected += geometry
                ? nearbyValues(field: field, index: index, in: lines, claimed: claimed)
                : textNearbyValues(field: field, index: index, in: lines, claimed: claimed)
        }
        return collected
    }

    /// The geometry form. Total and volume read the single value line nearest
    /// their own baseline (the label sits left OR right of it, per make); the
    /// price reads every value line in a band above/below the label, because the
    /// transaction price sits among the grade board whose four prices are
    /// stacked above or beside the price label.
    private static func nearbyValues(field: Role, index: Int, in lines: [OCRLine],
                                     claimed: Set<Int>) -> [PumpNumber] {
        let label = lines[index]
        if field == .price {
            var result: [PumpNumber] = []
            for (otherIndex, other) in lines.enumerated()
                where otherIndex != index && other.boundingBox != .zero && !claimed.contains(otherIndex) {
                guard isCandidateValueLine(other.text) else { continue }
                guard abs(other.midY - label.midY) < 0.12 else { continue }
                result += NumberScanner.pumpNumbers(in: other.text)
            }
            return result
        }
        // Among the value lines on the label's row, the label's own value is the
        // one NEAREST IT HORIZONTALLY - not the one nearest in y. Two fixtures
        // show why the vertical rule fails, in opposite directions:
        //
        //   pump-009  `РУБЛИ` sits at y=0.777 with its total `0203800` at 0.745
        //             (dy 0.032) while a grade-board price `060,80` sits at
        //             0.757 (dy 0.020). Nearest-in-y takes the BOARD PRICE.
        //   pump-057  `€` sits beside `10038`, but the zero pad `0` is split off
        //             as its own line 3 thousandths closer in y. Nearest-in-y
        //             takes the fragment, which every arithmetic rejects.
        //
        // Horizontal distance settles both: the board price is far to the left
        // of the display, and the pad fragment is further from the label than
        // the body it was split from. The vertical window stays, loose enough
        // for a label printed a little above or below its own row.
        var best: (dx: CGFloat, numbers: [PumpNumber])?
        var nearestByRow: (dy: CGFloat, numbers: [PumpNumber])?
        for (otherIndex, other) in lines.enumerated()
            where otherIndex != index && other.boundingBox != .zero {
            guard isCandidateValueLine(other.text) else { continue }
            let dy = abs(other.midY - label.midY)
            guard dy < 0.08 else { continue }
            if nearestByRow == nil || dy < nearestByRow!.dy {
                nearestByRow = (dy, NumberScanner.pumpNumbers(in: other.text))
            }
            guard dy < 0.05 else { continue }
            let dx = abs(other.midX - label.midX)
            if best == nil || dx < best!.dx {
                best = (dx, NumberScanner.pumpNumbers(in: other.text))
            }
        }
        // The union of the horizontal pick and everything on the label's exact
        // baseline. Both are needed and neither subsumes the other: the x-rule
        // rescues pump-009 from the board price, the baseline rule rescues the
        // displays whose label sits directly over a stack. Union is safe because
        // `solve` commits only a value that survives UNIQUELY - an extra
        // candidate can cause an abstention, never a wrong number.
        var result = best?.numbers ?? []
        var seen = Set(result.map(\.raw))
        for (otherIndex, other) in lines.enumerated()
            where otherIndex != index && other.boundingBox != .zero {
            guard isCandidateValueLine(other.text),
                  abs(other.midY - label.midY) < 0.02 else { continue }
            for number in NumberScanner.pumpNumbers(in: other.text) where seen.insert(number.raw).inserted {
                result.append(number)
            }
        }
        return result.isEmpty ? (nearestByRow?.numbers ?? []) : result
    }

    /// The text-only form (no boxes): the value is the adjacent value line in
    /// reading order. Total and volume take the nearest; the price's board spans
    /// several lines, so the price takes every nearby value line that is not a
    /// total/volume label and not already claimed as a total/volume value (the
    /// scale search + band then dispose of the board prices that do not close).
    private static func textNearbyValues(field: Role, index: Int, in lines: [OCRLine],
                                         claimed: Set<Int>) -> [PumpNumber] {
        if field == .price {
            var result: [PumpNumber] = []
            for step in 1...4 {
                for delta in [step, -step] {
                    let other = index + delta
                    guard other >= 0, other < lines.count, !claimed.contains(other) else { continue }
                    let text = lines[other].text
                    if role(of: text) == .total || role(of: text) == .volume { continue }
                    guard isCandidateValueLine(text) else { continue }
                    result += NumberScanner.pumpNumbers(in: text)
                }
            }
            return result
        }
        for step in 1...3 {
            for delta in [step, -step] {
                let other = index + delta
                guard other >= 0, other < lines.count else { continue }
                let text = lines[other].text
                if let otherRole = role(of: text), otherRole != field { continue }
                guard isCandidateValueLine(text) else { continue }
                let numbers = NumberScanner.pumpNumbers(in: text)
                if !numbers.isEmpty { return numbers }
            }
        }
        return []
    }

    /// The value-line indices a total or volume label claims - the same search
    /// `nearbyValues`/`textNearbyValues` run for those fields, so a claimed
    /// index is exactly the line the total/volume read from. Claimed lines are
    /// skipped by the price's board scan so a compact display's total and
    /// volume values never become price candidates.
    private static func claimedValueIndices(in lines: [OCRLine], geometry: Bool) -> Set<Int> {
        var claimed = Set<Int>()
        for (index, line) in lines.enumerated() {
            let field = role(of: line.text)
            guard field == .total || field == .volume else { continue }
            if geometry {
                // The nearest value line by |dy|, matching nearbyValues.
                var best: (dy: CGFloat, index: Int)?
                for (otherIndex, other) in lines.enumerated()
                    where otherIndex != index && other.boundingBox != .zero {
                    guard isCandidateValueLine(other.text) else { continue }
                    let dy = abs(other.midY - line.midY)
                    guard dy < 0.08 else { continue }
                    if best == nil || dy < best!.dy {
                        best = (dy, otherIndex)
                    }
                }
                if let best { claimed.insert(best.index) }
                continue
            }
            for step in 1...3 {
                var found: Int?
                for delta in [step, -step] {
                    let other = index + delta
                    guard other >= 0, other < lines.count else { continue }
                    let text = lines[other].text
                    if let otherRole = role(of: text), otherRole != field { continue }
                    guard isCandidateValueLine(text) else { continue }
                    if !NumberScanner.pumpNumbers(in: text).isEmpty {
                        found = other
                        break
                    }
                }
                if let found {
                    claimed.insert(found)
                    break
                }
            }
        }
        return claimed
    }

    /// Which field a label line names, or nil when the line is neither a pump
    /// label nor an instruction. Price is tested first because it is the most
    /// specific (`ЦЕНА ЗА 1 ЛИТР` contains `ЛИТР` but is a price, never a
    /// volume); a bare currency word or a lone `L` names the money/volume line
    /// only when it carries no number of its own.
    private static func role(of text: String) -> Role? {
        let upper = text.uppercased()
        if isInstruction(upper) { return nil }
        if upper.contains("HIN") { return .price }
        if upper.contains("ЦЕНА") { return .price }
        if upper.contains("/L") || upper.contains("/Л") || upper.contains("€/") || upper.contains("EUR/") {
            return .price
        }
        if upper.contains("РУБ") && upper.contains("/") { return .price }
        // The inflected volume forms, never a bare `ЛИТР`: a bare `ЛИТР` is
        // usually the tail of a split price label (`ЦЕНА ЗА ЛИТР`, `РУБ/ЛИТР`
        // on pump-008's Topaz overlay), which would read the price as a volume
        // and produce a swapped fill the cross-check cannot see.
        if upper.contains("ЛИТРЫ") || upper.contains("ЛИТРОВ") || upper.contains("ЛИТРАХ") { return .volume }
        if upper.contains("LIITRI") { return .volume }
        if upper.contains("КОЛИЧЕСТВО") { return .volume }
        if upper.contains("ОБЪЁМ") || upper.contains("ОБЪЕМ") || upper.contains("ОБЪЕМ") { return .volume }
        let trimmed = upper.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "L" || trimmed == "Л" { return .volume }
        if upper.contains("СУММ") || upper.contains("SUMM") { return .total }
        if upper.contains("СТОИМОСТ") { return .total }
        if upper.contains("ИТОГ") { return .total }
        if upper.contains("ВСЕГО") { return .total }
        if upper.contains("TOTAL") || upper.contains("KOKKU") { return .total }
        if isCurrencyWord(upper) { return .total }
        return nil
    }

    /// A pump instruction line (`Vmin 5 LIITRIT`, `МИНИМАЛЬНАЯ ДОЗА ОТПУСКА 5Л`)
    /// is display furniture, never a label and never a value.
    private static func isInstruction(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("VMIN") || upper.contains("МИНИМАЛЬН") || upper.contains("ДОЗА")
            || upper.contains("ОТПУСКА") || upper.contains("ОТКРЫВАТЬ") || upper.contains("ИНСТРУКЦИ")
    }

    /// A line that may carry a field value: not an instruction, not a
    /// grade/nozzle line, and "mostly a number" (few letters after currency and
    /// unit tokens are stripped). Keeps the advertising lines (`Wrapper ja jook
    /// 0,5-0,7l`), the serial lines (`AE010578`, `M26`) and the grade lines
    /// (`95`, `miles`) out of the candidate set.
    private static func isCandidateValueLine(_ text: String) -> Bool {
        if isInstruction(text) { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.contains("MILES") { return false }
        if ["92", "95", "98", "100", "D"].contains(trimmed) { return false }
        let numbers = NumberScanner.pumpNumbers(in: text)
        guard !numbers.isEmpty else { return false }
        var stripped = text.uppercased()
        for token in ["РУБЛИ", "РУБЛЕЙ", "РУБЛЯ", "РУБ", "EUR", "ТЕНГЕ", "KZT", "₽", "€", "$", "L", "Л", " "] {
            stripped = stripped.replacingOccurrences(of: token, with: "")
        }
        return stripped.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
    }

    /// A bare currency word with no number of its own - the money-line label on
    /// the Gilbarco layouts (`РУБЛИ`, `€`, `ТЕНГЕ`). `71,05 Рублей` carries a
    /// number and is a value line, never a label.
    private static func isCurrencyWord(_ upper: String) -> Bool {
        guard NumberScanner.pumpNumbers(in: upper).isEmpty else { return false }
        let words = upper.split(separator: " ").map(String.init)
        return !words.isEmpty && words.allSatisfy { word in
            ["€", "РУБЛИ", "РУБЛЕЙ", "РУБЛЯ", "РУБ", "РУБ.", "EUR", "ТЕНГЕ", "KZT"].contains(word)
        }
    }

    /// Strips the per-litre `1` markers (`/1L`, `ЗА 1 ЛИТР`) so the inline
    /// number before the label is read and the marker's own `1` is not a value.
    private static func stripInlineLabel(_ text: String) -> String {
        var result = text
        for token in ["/1L", "/1 L", "/1Л", "/1 Л", "ЗА 1 ЛИТР", "ЗА 1 ЛИТРА", "ЗА 1 Л", "ЗА 1Л", "ЗА 1"] {
            result = result.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
        }
        return result
    }

    // MARK: - The scale search

    private static func flattened(_ numbers: [PumpNumber], money: Bool = false) -> [Double] {
        var seen = Set<Double>()
        var result: [Double] = []
        for number in numbers {
            for candidate in money ? number.moneyCandidates() : number.candidates() {
                if seen.insert(candidate).inserted {
                    result.append(candidate)
                }
                if result.count >= 60 { return result }
            }
        }
        return result
    }

    /// Searches the decimal scales of the three fields for the triples that
    /// close `liters x price ≈ total`, bounded by the volume range and the
    /// currency price band. A field is committed only when exactly one value
    /// survives across every closing triple - a factor-of-ten tie (a bare
    /// volume whose scale the display dropped) leaves the field nil rather than
    /// guessing (hard rule 13).
    ///
    /// A triple is accepted on one of two grounds, and nothing looser:
    ///
    /// 1. **Exact.** The product reproduces the total to the money cent
    ///    (`0.005`). This is the only tolerance that pins a value - the
    ///    cross-check's own `max(0.02, total x 0.005)` is a *consistency* bound
    ///    for the confirm screen, and committing at it swallows a misread digit
    ///    (pump-060's `48.75 -> 48.95`) and a board price that merely
    ///    approximately closes (pump-035's `1.819` for the off-board `1.824`).
    /// 2. **A unique seven-segment repair.** A near-miss within the
    ///    cross-check tolerance is accepted only when `DigitRepair` finds
    ///    exactly one single-digit substitution that reproduces the total - the
    ///    pump-013/015 glare `9-as-4`. The READ value is committed (extract's
    ///    existing repair step then corrects it); a near-miss with no unique
    ///    repair abstains rather than invent a digit.
    private static func solve(volumeValues: [Double], priceValues: [Double], totalValues: [Double],
                              band: FuelPriceBand?, priceIsBoard: Bool) -> Result {
        var literSurvivors: Set<Double> = []
        var priceSurvivors: Set<Double> = []
        var totalSurvivors: Set<Double> = []
        for liters in volumeValues where volumeRange.contains(liters) {
            for price in priceValues {
                if let band, !band.contains(price) { continue }
                for total in totalValues where total > 0 {
                    let product = liters * price
                    let residual = abs(product - total)
                    guard residual <= max(0.02, total * 0.005) else { continue }
                    let exact = residual <= Self.exactTolerance
                    let repairable = !exact && uniqueRepair(liters, price, total)
                    // Volume and total have no independent pin (their scale is
                    // exactly what the cross-check reconstructs), so they commit
                    // only on an exact close or a unique seven-segment repair.
                    if exact || repairable {
                        literSurvivors.insert(liters)
                        totalSurvivors.insert(total)
                    }
                    // The price is pinned by the band for its SCALE; a
                    // selected-price window (one token) commits on the loose
                    // cross-check (a displayed total may round to 0.1 - the
                    // residual is the total's, not the price's), while a grade
                    // BOARD commits only on an exact close or unique repair -
                    // a board price that merely approximately closes is a
                    // confident wrong value (pump-035's off-board 1.819).
                    if priceIsBoard {
                        if exact || repairable { priceSurvivors.insert(price) }
                    } else {
                        priceSurvivors.insert(price)
                    }
                }
            }
        }

        return Result(
            liters: literSurvivors.count == 1 ? literSurvivors.first : nil,
            price: priceSurvivors.count == 1 ? priceSurvivors.first : nil,
            total: totalSurvivors.count == 1 ? totalSurvivors.first : nil
        )
    }

    /// Whether `liters x price ≈ total` misses the total by a SINGLE seven-
    /// segment digit that `DigitRepair` can uniquely reconstruct. The read
    /// value is committed (extract's repair step then corrects it); a near-miss
    /// with no unique repair abstains rather than invent a digit.
    private static func uniqueRepair(_ liters: Double, _ price: Double, _ total: Double) -> Bool {
        guard let priceDec = ConfirmFormat.decimal(
                  fromExtraction: price,
                  fractionDigits: ConfirmFormat.fractionDigits(for: .unitPrice)),
              let totalDec = ConfirmFormat.decimal(
                  fromExtraction: total,
                  fractionDigits: ConfirmFormat.fractionDigits(for: .total)) else {
            return false
        }
        return DigitRepair.apply(liters: liters, unitPrice: priceDec, total: totalDec,
                                 source: .pump) != nil
    }

    /// The exact-close tolerance: half a money cent. A product within this of
    /// the total reproduces it at the display's two-decimal money precision;
    /// anything looser is a consistency signal, never a pin.
    static let exactTolerance = 0.005
}
