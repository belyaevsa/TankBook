import Foundation

extension FuelExtractor {
    /// The volume of an unmarked operand pair, re-read against the total when
    /// the band's pick does not close. Nothing on `9.05 x 57.000` says which
    /// operand is the volume, and the band alone picks the operand that looks
    /// like a price - but when a thumb hides the price's leading digit
    /// (receipt-057 reads `69.05` as `9.05`), the band's pick is the volume
    /// that makes `total / volume` an impossible price. Each operand is tried
    /// as the volume; one is taken only when it alone implies a price inside
    /// the band that the OTHER operand reproduces with its leading digits lost
    /// (`69.05` read as `9.05`) - the shape an occluded or clipped price leaves,
    /// and the only evidence strong enough to overturn the band's pick when a
    /// currency's band is wide. The price is then the document's own printed figure when the
    /// arithmetic confirms one, else nil - never a bare quotient
    /// (`derivedUnitPrice`, hard rule 13).
    ///
    /// Nil - the band's reading stands - when the pair closes, when a discount
    /// line could explain the gap, when both or neither operand fits, or when
    /// the pair is not the document's single unmarked operand line.
    func volumeAgainstTotal(
        _ lines: [OCRLine], liters: Double?, price: Double?, total: Decimal?,
        currency: CurrencyCode?, fuelKind: FuelKind?, date: Date?
    ) -> (liters: Double, price: Double?)? {
        guard let liters, let price, let total, let provider = bandProvider,
              let (pair, _) = OperandPair.single(in: lines),
              !pair.leftText.hasVolumeMarker, !pair.rightText.hasVolumeMarker,
              !pair.leftText.hasPriceMarker, !pair.rightText.hasPriceMarker,
              let band = provider.band(currency: currency, fuelKind: fuelKind, date: date) else { return nil }
        let amount = NSDecimalNumber(decimal: total).doubleValue
        guard amount > 0, abs(liters * price - amount) > max(0.02, amount * 0.005),
              ExtractionCrossCheck.discountLines(in: lines).isEmpty else { return nil }
        func cents(_ value: Double) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value) }
        let fitting = [(pair.left, pair.right), (pair.right, pair.left)].filter { volume, other in
            guard volume > 0, other > 0 else { return false }
            let implied = amount / volume
            return band.contains(implied) && cents(implied).hasSuffix(cents(other)) && cents(implied) != cents(other)
        }.map(\.0)
        guard fitting.count == 1, let volume = fitting.first, volume != liters else { return nil }
        return (volume, derivedUnitPrice(total: total, liters: volume, in: lines))
    }
}

extension FuelExtractor {
    /// Whether the fuel operands' product, not the figure printed beside them,
    /// is the fuel line's amount: the two disagree beyond rounding, and the
    /// grand total less the product of every other operand line reproduces the
    /// product. Without that independent accounting either read could carry
    /// the misread digit, and the printed figure keeps its precedence.
    func productOutranksPrintedFuelLine(_ printed: Double, product: Double, in lines: [OCRLine]) -> Bool {
        guard abs(printed - product) > max(0.02, product * 0.005),
              let grand = grandTotalRead(lines)?.value,
              let fuelIndex = OperandPair.fuelOperandIndex(in: lines) else { return false }
        let others = lines.enumerated().reduce(0.0) { sum, item in
            guard item.offset != fuelIndex, let pair = OperandPair(line: item.element.text) else { return sum }
            return sum + pair.left * pair.right
        }
        return abs(grand - others - product) <= max(0.02, product * 0.005)
    }
}

extension FuelExtractor {
    /// Whether a volume must yield to the price and the total it contradicts:
    /// the three do not multiply up, nothing on the document explains the gap
    /// (no discount line, no other priced item), and the total rests on more
    /// than one read. Two independent reads outvote one - a Vision `4` read as
    /// `1` on `43.25L` (receipt-083 on iOS) - so the volume abstains and the
    /// user types it. It is never replaced by the quotient.
    func volumeContradictedByCorroboratedTotal(_ lines: [OCRLine], liters: Double?, price: Double?,
                                               total: Decimal?) -> Bool {
        guard let liters, let price, let total, liters > 0, price > 0 else { return false }
        let amount = NSDecimalNumber(decimal: total).doubleValue
        guard abs(liters * price - amount) > max(0.02, amount * 0.005),
              ExtractionCrossCheck.discountLines(in: lines).isEmpty,
              ExtractionCrossCheck.nonFuelListSum(in: lines, liters: liters, unitPrice: price) == 0,
              let read = grandTotalRead(lines), abs(read.value - amount) <= max(0.02, amount * 0.005)
        else { return false }
        return isCorroboratedTotal(read.value, labelReads: read.labelReads, in: lines)
    }
}
