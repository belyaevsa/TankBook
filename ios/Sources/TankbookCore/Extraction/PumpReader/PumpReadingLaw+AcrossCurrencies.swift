import Foundation

// Currency supports the read and never blocks it (docs/EXTRACTION.md): the
// law under every measured currency when the given one closes nothing, and the
// top read handed to the form when none does.
extension PumpReadingLaw {
    /// The bundled price bands, for the currencies the capture was not given
    /// a band for.
    static let bundledBands: FuelPriceBandPack? = try? FuelPriceBandStore.bundledPack()

    /// The reading the app shows (docs/EXTRACTION.md -> "Currency supports the
    /// read and never blocks it"): the law under `currency` first; when that
    /// commits nothing, under every other measured currency, taking the
    /// values most of the closing currencies agree on (a tie goes to
    /// `PumpDisplayConventions.measuredCurrencies` order); when nothing closes
    /// anywhere, `currency`'s abstention carrying the top read as
    /// `unclosed`, under the `.unclosed` caution.
    public static func resolveAcrossCurrencies(
        windows: [PumpLocatedWindow],
        currency: CurrencyCode?,
        priceBand: FuelPriceBand? = nil
    ) -> PumpDisplayReading {
        let own = resolve(windows: windows, currency: currency, priceBand: priceBand)
        if own.committedCount > 0 { return own.closed(under: currency) }
        var groups: [(key: String, readings: [PumpDisplayReading])] = []
        for other in PumpDisplayConventions.measuredCurrencies where other != currency {
            let reading = resolve(windows: windows, currency: other,
                                  priceBand: bundledBands?.currencyBand(currency: other))
            guard reading.committedCount > 0 else { continue }
            let key = [reading.liters, reading.unitPrice, reading.total]
                .map { $0.value.map { "\($0)" } ?? "-" }.joined(separator: "|")
            let closed = reading.closed(under: other)
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].readings.append(closed)
            } else {
                groups.append((key, [closed]))
            }
        }
        // `max(by:)` returns the last of equal maxima; the first group formed wins a tie.
        if let best = groups.reversed().max(by: { $0.readings.count < $1.readings.count }) {
            return best.readings[0]
        }
        guard own.reason != .litersAllZero, let top = topRead(windows, currency: currency) else { return own }
        return PumpDisplayReading(liters: own.liters, unitPrice: own.unitPrice, total: own.total,
                                  reason: own.reason, caution: .unclosed, unclosed: top)
    }

    /// The least margin, in nats, every cell of a window needs before its top
    /// read is handed to the form unclosed. Seven-segment digits the reader is
    /// sure of sit at 5 or more; a window it is guessing at (a TFT screen's
    /// artwork read as segments) has cells under 1.
    static let unclosedMinMargin = 2.0

    /// Each transaction window's top digits at its most likely decimal
    /// placement: the cell the classifier marked, else the currency's first
    /// convention (the euro row for a currency with none). A window with an
    /// unsure cell, or whose value no fill could show, gives no value. Nil
    /// when no window gives one.
    static func topRead(_ windows: [PumpLocatedWindow], currency: CurrencyCode?) -> PumpUnclosedRead? {
        var conventions = PumpDisplayConventions.forCurrency(currency)
        if !conventions.isMeasured { conventions = .forCurrency(CurrencyCode(rawValue: "EUR")) }
        func value(_ field: PumpField) -> Decimal? {
            guard let window = windows.first(where: { $0.field == field }),
                  !window.cells.isEmpty, window.cells.count <= maxCells,
                  window.cells.allSatisfy({ $0.ranked.count < 2 || $0.margin >= unclosedMinMargin }) else { return nil }
            let integer = window.cells.reduce(0) { $0 * 10 + $1.top.digit }
            let decimals = window.cells.firstIndex(where: \.decimalPoint).map { window.cells.count - 1 - $0 }
                ?? conventions.decimals(field, cells: window.cells.count).first ?? 0
            let value = Decimal(integer) / pow(Decimal(10), decimals)
            let number = NSDecimalNumber(decimal: value).doubleValue
            switch field {
            case .liters: return number >= minLiters && number < 500 ? value : nil
            case .total: return number >= minTotal ? value : nil
            default: return number > 0 ? value : nil
            }
        }
        let read = PumpUnclosedRead(liters: value(.liters), unitPrice: value(.unitPrice), total: value(.total))
        return read.liters == nil && read.unitPrice == nil && read.total == nil ? nil : read
    }
}
