import CoreGraphics
import Foundation

// RV.48 stage three - the label-value helpers `loneMarkers` calls. Kept in an
// extension so the FuelExtractor struct stays under the lint body-length limit
// while the geometry these read (midX/midY/minX) stays with the extractor's
// own value-finding.

extension FuelExtractor {

    /// The value a per-unit label names, in order of specificity: the
    /// self-describing form ("1,754 EUR/L" carries its value inline), the
    /// reference-block form ("цена за ед." with the value to the right), then
    /// the pump form (the value directly below the "/L" label, same column).
    func pricePerUnitValue(forLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let label = lines[index]
        // Gap 1: "1,754 EUR/L", "1,839 EUR/L", "Pump 5 Hind 1,799 EUR/L" - the
        // value sits immediately before the per-unit marker, so a pump number
        // ("5") elsewhere on the line is never mistaken for the price.
        if let inline = inlinePricePerUnit(label.text) { return inline }
        // Gap 4: "цена за ед." in the reference block states its value to the
        // RIGHT on the same baseline (receipt-023/030), never below. The "/L"
        // style labels below keep the pump form - on receipt-001 the receipt
        // total "125,22" sits above-right of "EUR/L" while its price is below.
        if label.text.uppercased().contains("ЦЕНА ЗА ЕД") {
            return valueRight(ofLabelAt: index, in: lines)
        }
        // The pump form: the value sits directly below its "/L" label, in the
        // same column - never above it, where the row's sum lives.
        var best: (distance: CGFloat, value: Double)?
        for (otherIndex, other) in lines.enumerated() where otherIndex != index {
            let distance = label.midY - other.midY
            guard distance > 0, distance < 0.02,
                  NumberScanner.isValueLine(other.text),
                  let value = NumberScanner.value(in: other.text) else { continue }
            if best == nil || distance < best!.distance {
                best = (distance, value)
            }
        }
        return best?.value
    }

    /// A value line to the RIGHT of a label on (approximately) its baseline.
    /// Nil when nothing sits there - a column layout keeps the value BELOW its
    /// header, never beside it.
    func valueRight(ofLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let label = lines[index]
        var best: (distance: CGFloat, value: Double)?
        for (otherIndex, other) in lines.enumerated() where otherIndex != index {
            guard other.boundingBox.minX > label.boundingBox.minX,
                  abs(other.midY - label.midY) < 0.02,
                  NumberScanner.isValueLine(other.text),
                  let value = NumberScanner.value(in: other.text) else { continue }
            let distance = abs(other.midY - label.midY)
            if best == nil || distance < best!.distance {
                best = (distance, value)
            }
        }
        return best?.value
    }

    /// The volume a quantity label names. Two layouts, split by label so the
    /// two never collide: "Колич." (a label-value row) states its value to the
    /// RIGHT, while "единиц" (a column header) states it directly BELOW in its
    /// own column - and on receipt-023/044 the receipt total also sits to the
    /// right of "единиц", so reading sideways there would return the sum.
    func quantityValue(forLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let upper = lines[index].text.uppercased()
        if upper.contains("КОЛИЧ") {
            return valueRight(ofLabelAt: index, in: lines)
        }
        return valueBelowColumn(ofLabelAt: index, in: lines)
    }

    /// A value directly BELOW a column header in the same column (receipt-023's
    /// "единиц" -> "20.00", receipt-044's -> "25.00"). Bounded in x so the
    /// receipt total in a neighbouring column can never be read as the quantity.
    func valueBelowColumn(ofLabelAt index: Int, in lines: [OCRLine]) -> Double? {
        let label = lines[index]
        var best: (distance: CGFloat, value: Double)?
        for (otherIndex, other) in lines.enumerated() where otherIndex != index {
            let dy = label.midY - other.midY
            guard dy > 0, dy < 0.1,
                  abs(other.midX - label.midX) < 0.1,
                  NumberScanner.isValueLine(other.text),
                  let value = NumberScanner.value(in: other.text) else { continue }
            if best == nil || dy < best!.distance {
                best = (dy, value)
            }
        }
        return best?.value
    }

    /// The unit price a self-describing line carries inline: "1,754 EUR/L".
    /// The value is the number immediately before the per-unit marker, which is
    /// what keeps the pump number in "Pump 5 Hind 1,799 EUR/L" out of it.
    func inlinePricePerUnit(_ text: String) -> Double? {
        let pattern = /(\d+(?:[.,]\d+)?)\s*(?:EUR\s*)?\/\s*[ЛL]/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return Double(match.1.replacingOccurrences(of: ",", with: "."))
    }
}
