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
}
