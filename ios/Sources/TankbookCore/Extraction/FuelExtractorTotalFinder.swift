import Foundation

// RV.56 - the total finder's helpers and the fiscal-QR composition, kept in an
// extension so the `FuelExtractor` struct stays under the lint file-length and
// body-length limits (the same reason `FuelExtractorLabelValue.swift` exists).
// These are pure helpers over `[OCRLine]` and injected values - no Vision, no
// network, no image access.

extension FuelExtractor {

    // MARK: - The fiscal-QR composition

    /// Composes a decoded fiscal QR into the extraction, exactly as the confirm
    /// sheet does (`ConfirmQRTotal.resolve`): the QR total is authoritative on
    /// a disagreement, the fuel line stands on a mixed receipt (hard rule 4 -
    /// the QR carries the GRAND total, never the fuel amount), and the QR date
    /// overrides an absent or garbled OCR date.
    static func composeQR(_ anchor: FiscalQRAnchor?, into result: inout FuelExtraction) {
        guard let anchor else { return }
        switch ConfirmQRTotal.resolve(extraction: result, qrAnchor: anchor) {
        case .noAnchor, .ocrConfirmed:
            break
        case .qrAuthoritative(let total):
            result.total = total
        case .fuelLineStands(let total):
            result.total = total
        }
        if let qrDate = qrDateString(from: anchor.date) {
            result.date = qrDate
        }
    }

    /// Formats a fiscal-QR date as the day-first string `ConfirmDate.parse`
    /// accepts (`dd.MM.yyyy`). The QR timestamp is a local wall-clock time with
    /// no zone in the payload, so it is formatted in the same zone the anchor
    /// was parsed in (the caller's `.current`), which reproduces the exact date
    /// the `t` field carried.
    private static func qrDateString(from date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.day, .month, .year], from: date)
        guard let day = components.day, let month = components.month, let year = components.year else {
            return nil
        }
        return String(format: "%02d.%02d.%04d", day, month, year)
    }

    // MARK: - The total finder's helpers

    /// A value line that begins with `-` is a subtraction line (a VAT amount or
    /// a discount), never a total candidate. `NumberScanner.value` silently
    /// drops the sign - that is what the discount magnitude path wants - so the
    /// guard lives here in the total finder, not in the scanner: receipt-018
    /// prints `ИТОГ` beside `-3555.89` (its `СУММА НДС` amount, one row lower)
    /// while the real total `=19719.00` sits above the label.
    func isSubtractionLine(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        // Strip the same value-lead symbols `NumberScanner.value` strips, so a
        // `= -0.80`-shaped line is recognised regardless of the prefix.
        for token in ["=", "≡", "#", "_", "₽", "฿", "₴", "€", "$"] {
            trimmed = trimmed.replacingOccurrences(of: token, with: "")
        }
        return trimmed.trimmingCharacters(in: .whitespaces).hasPrefix("-")
    }

    /// The discounted total: when the labelled total minus a printed discount
    /// equals another label-paired candidate, the charged figure is the
    /// discounted one. A discount is the list price minus the charged price, so
    /// `total - discount == charged`; a match within half a cent is exact for
    /// the corpus's two-decimal money.
    func discountedTotal(of total: Double, candidates: [Double], lines: [OCRLine]) -> Double? {
        for discount in ExtractionCrossCheck.discountLines(in: lines) {
            let amount = NSDecimalNumber(decimal: discount).doubleValue
            for candidate in candidates where abs((total - amount) - candidate) < 0.005 {
                return candidate
            }
        }
        return nil
    }

    /// The modal value across the receipt's value lines - the redundancy the
    /// net-versus-gross fix leans on. Only a single, strictly-dominant value
    /// printed at least twice is returned; a tie or an all-unique document
    /// abstains.
    func redundantValue(in lines: [OCRLine]) -> Double? {
        var counts: [Double: Int] = [:]
        for line in ReceiptNoiseFilter.candidateLines(lines) {
            guard NumberScanner.isValueLine(line.text),
                  !isSubtractionLine(line.text),
                  let value = NumberScanner.value(in: line.text) else { continue }
            counts[value, default: 0] += 1
        }
        guard let maxCount = counts.values.max(), maxCount >= 2 else { return nil }
        let modes = counts.filter { $0.value == maxCount }.map(\.key)
        return modes.count == 1 ? modes[0] : nil
    }

    /// Whether a value is printed more than once among the candidate value
    /// lines. A labelled total the receipt repeats is the total; one printed
    /// once, while another value is repeated, is the net-versus-gross shape.
    func isRepeatedValue(_ value: Double, in lines: [OCRLine]) -> Bool {
        var count = 0
        for line in ReceiptNoiseFilter.candidateLines(lines) {
            guard NumberScanner.isValueLine(line.text),
                  !isSubtractionLine(line.text),
                  let other = NumberScanner.value(in: line.text) else { continue }
            if abs(other - value) < 0.005 { count += 1 }
        }
        return count > 1
    }

    func grandTotal(_ lines: [OCRLine]) -> Double? {
        var primary: [Double] = []
        var payment: [Double] = []
        for (index, line) in lines.enumerated() {
            guard let kind = TotalLabel.classify(line.text) else { continue }
            guard let value = pairedValue(forLabelAt: index, in: lines) else { continue }
            switch kind {
            case .primary: primary.append(value)
            case .payment: payment.append(value)
            }
        }
        // Both sessions fixed receipt-017's discount on the same day by
        // different mechanisms, and trunk's is the better one: with a discount
        // the primary `ИТОГ` is a pre-discount subtotal, so the PAYMENT line -
        // what was actually charged - breaks the tie. That subsumes the
        // subtract-the-discount path this branch had.
        let hasDiscount = !ExtractionCrossCheck.discountLines(in: lines).isEmpty
        let labelled = modal(primary: primary, payment: payment, hasDiscount: hasDiscount)
        // THE NET-VERSUS-GROSS CASE, and why the redundancy check runs even when
        // a label DID resolve. On the Estonian layout the `KOKKU` label shares a
        // baseline with the KÄIBEMAKSUTA **net** (receipt-001: `100,98`), while
        // the gross `125,22` sits one baseline up and is printed FOUR times. A
        // labelled total that a strictly-dominant repeated value outranks - and
        // that is smaller than it, which is what net-versus-gross always looks
        // like - loses to the value the receipt keeps repeating. A labelled
        // total that is itself the repeated value is untouched, which is the
        // ordinary receipt.
        if let redundant = redundantValue(in: lines),
           let labelled, redundant > labelled,
           !isRepeatedValue(labelled, in: lines) {
            return redundant
        }
        if let labelled { return labelled }
        // Kept from this branch, because trunk has no equivalent: when no
        // labelled total resolves (an unbreakable tie, or no label paired a
        // value at all), fall back to the modal value across the receipt's own
        // value lines. The gross total is the value a receipt prints most often
        // - receipt-001's `125,22` four times, receipt-038's `79,32` four times
        // - while the net and the VAT print once or twice. Only a single,
        // strictly-dominant value printed at least twice is trusted; anything
        // else abstains (hard rule 13).
        return redundantValue(in: lines)
    }

    func pairedValue(forLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let label = lines[index]
        // Same-baseline value to the right (the reading-order fix: Vision emits
        // value before label, so array order cannot be trusted).
        var best: (distance: CGFloat, value: Double)?
        for (otherIndex, line) in lines.enumerated() where otherIndex != index {
            guard line.boundingBox.minX > label.boundingBox.minX,
                  abs(line.midY - label.midY) < 0.012,
                  NumberScanner.isValueLine(line.text),
                  // Two sessions found this bug independently on the same day.
                  // `isSubtractionLine` also strips currency symbols, so it is
                  // the wider test; `isNegativeAmount` is the shared home. Both
                  // run, because each has tests pinning it.
                  !isSubtractionLine(line.text),
                  !NumberScanner.isNegativeAmount(line.text),
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

    func adjacentValue(_ line: OCRLine) -> Double? {
        // Both predicates, for the reason given at the other call site.
        guard NumberScanner.isValueLine(line.text),
              !isSubtractionLine(line.text),
              !NumberScanner.isNegativeAmount(line.text) else { return nil }
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
    ///
    /// A discount line changes which side breaks the tie. With no discount the
    /// primary label is the canonical total and wins. With a discount the
    /// primary (ИТОГ) is a pre-discount subtotal - receipt-017 prints `ИТОГ
    /// 961.80` then `СКИДКА -0.80` and the charged `961.00` on the payment
    /// line - so the payment line, which records what was actually charged, is
    /// preferred instead.
    func modal(primary: [Double], payment: [Double], hasDiscount: Bool) -> Double? {
        let candidates = primary + payment
        guard !candidates.isEmpty else { return nil }
        let counts = Dictionary(grouping: candidates, by: { $0 }).mapValues(\.count)
        let maxCount = counts.values.max() ?? 0
        let modes = counts.filter { $0.value == maxCount }.map(\.key)
        if modes.count == 1 { return modes[0] }
        // Tie on count: prefer the value the preferred side named most often.
        // That preference is itself allowed to tie; when it does, abstain.
        let preferred = hasDiscount ? payment : primary
        let preferredCounts = Dictionary(grouping: preferred, by: { $0 }).mapValues(\.count)
        let topPreferred = modes.map { preferredCounts[$0] ?? 0 }.max() ?? 0
        let winners = modes.filter { (preferredCounts[$0] ?? 0) == topPreferred }
        return winners.count == 1 ? winners[0] : nil
    }
}
