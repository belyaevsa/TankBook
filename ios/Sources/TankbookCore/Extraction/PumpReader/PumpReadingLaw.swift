import Foundation

/// The decode law: from ranked digits per cell to three committed-or-abstained
/// fields, with `volume x price = total` as the only judge.
///
/// The rules, each measured on the corpus (agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md):
/// - A field's digits come from the cells; its decimal placement comes from the
///   currency's display conventions, so every field is a small candidate set.
/// - A triple commits only when EXACTLY one combination closes the arithmetic
///   within the cross-check tolerance; fields the surviving triples agree on
///   commit alone, the rest abstain (`nil`, hard rule 13).
/// - When nothing closes, one single-cell substitution from the seven-segment
///   confusion table, tried in posterior order, may close it (`.repaired`) -
///   and only if exactly one does.
/// - A total the display truncates (RUB heads show `3765,7`) is never read; it
///   is derived from volume x price, which reproduces the receipt.
/// - Liters, price and total never swap roles to close the arithmetic; an idle
///   pump (zero liters) commits nothing.
public enum PumpReadingLaw {
    /// How many ranked digits per cell enter the search; three covers the
    /// posterior mass a seven-segment misread leaves.
    public static let beamWidth = 3
    /// The strings kept per field after the beam, by joint log-posterior.
    public static let stringsPerField = 12
    /// One cent plus rounding: a product that the display rounded or truncated
    /// to two decimals lands within this of the shown total.
    static let closingSlack = 0.011
    /// Closing triples this far (in nats of joint log-posterior) below the
    /// best are not alternatives, they are the beam's long tail: a certain
    /// cell's runner-up costs about 3.5 nats, so a triple that needs two or
    /// more unlikely substitutions to close never blocks a commit, while a
    /// genuinely ambiguous read (two triples within the window) still abstains.
    static let ambiguityWindow = 3.0
    /// A closing triple this far below the plain top read of the three windows
    /// is not a reading of the display but a fabrication assembled from the
    /// beam's tails; a single misread cell costs about 3.5 nats, so one
    /// substitution passes and two do not.
    static let readWindow = 6.0
    /// What a decimal placement pays for contradicting the mark the
    /// classifier saw - more than the ambiguity window, so a seen mark decides
    /// between two placements that both close, less than the read window, so
    /// a missed mark never blocks the arithmetic.
    static let decimalMarkPenalty = 4.0

    public static func resolve(
        windows: [PumpLocatedWindow],
        currency: CurrencyCode?,
        priceBand: FuelPriceBand? = nil
    ) -> PumpDisplayReading {
        let conventions = PumpDisplayConventions.forCurrency(currency)
        let byField = Dictionary(grouping: windows, by: \.field)
        guard let literWindow = byField[.liters]?.first else { return .abstained }
        guard let priceWindow = byField[.unitPrice]?.first else {
            // No price window of its own: on a Wayne head the transaction price
            // is one of the board cells, and only the arithmetic can say which.
            // Exactly one board cell may close the triple.
            let boards = byField[.board] ?? []
            guard !boards.isEmpty else { return .abstained }
            let readings = boards.map { board -> PumpDisplayReading in
                let rest = windows.filter { $0.field != .board }
                return resolve(windows: rest + [PumpLocatedWindow(field: .unitPrice, cells: board.cells)],
                               currency: currency, priceBand: priceBand)
            }
            let closed = readings.filter { $0.committedCount == 3 }
            return closed.count == 1 ? closed[0] : .abstained
        }
        let totalWindow = byField[.total]?.first

        let plausibleLiters: (Candidate) -> Bool = { $0.value >= minLiters && $0.value < 500 }
        let plausiblePrice: (Candidate) -> Bool = { priceBand?.contains($0.value) ?? ($0.value > 0) }
        let plausibleTotal: (Candidate) -> Bool = { $0.value >= minTotal }
        let literCands = candidates(literWindow, decimals: conventions.volumeDecimals).filter(plausibleLiters)
        let priceCands = candidates(priceWindow, decimals: conventions.priceDecimals).filter(plausiblePrice)
        let totalCands = (totalWindow.map { candidates($0, decimals: conventions.totalDecimals) } ?? [])
            .filter(plausibleTotal)
        let truncatedCands = (totalWindow.map {
            candidates($0, decimals: conventions.truncatedTotalDecimals)
        } ?? []).filter(plausibleTotal)

        // An idle pump shows 0.00 liters: nothing to read.
        if literWindow.cells.allSatisfy({ $0.top.digit == 0 }) { return .abstained }
        // No total on the display: the arithmetic has no judge, so the pair
        // is not committed - a confident wrong pair is worse than nil.
        guard totalWindow != nil else { return .abstained }

        let topRead = [literWindow, priceWindow, totalWindow!].reduce(0.0) { sum, window in
            sum + window.cells.reduce(0.0) { $0 + $1.top.logPosterior }
        }
        let closed = closingTriples(liters: literCands, prices: priceCands,
                                    totals: totalCands, truncated: truncatedCands)
            .filter { topRead - $0.logPosterior <= readWindow && $0.substitutions <= maxSubstitutions }
        if !closed.isEmpty {
            return commit(closed, repair: nil)
        }
        // A preset-amount fill: the total is the round amount the customer
        // chose and the volume is derived, so the product misses the total by
        // up to half a volume step times the price. Only a round total opens
        // this tier, and only the plain top read may close it.
        let preset = closingTriples(liters: literCands, prices: priceCands,
                                    totals: totalCands.filter { isRoundAmount($0.value) },
                                    truncated: [], presetSlack: true)
            .filter { topRead - $0.logPosterior <= 0.5 }
        if preset.count == 1 {
            return commit(preset, repair: nil)
        }

        // The repair tier: one substituted cell in liters or price.
        var repairs: [(Triple, PumpFieldProvenance, PumpField)] = []
        for (field, window) in [(PumpField.liters, literWindow), (.unitPrice, priceWindow)] {
            for (index, cell) in window.cells.enumerated() {
                let read = cell.top.digit
                for partner in DigitRepair.confusablePartners(of: read) {
                    var cells = window.cells
                    cells[index] = PumpCellReading(certainDigit: partner, decimalPoint: cell.decimalPoint)
                    let repaired = PumpLocatedWindow(field: field, cells: cells)
                    // The substituted cell is the one substitution this tier
                    // allows: every other cell stays at its top read.
                    let lc = (field == .liters
                        ? candidates(repaired, decimals: conventions.volumeDecimals).filter(plausibleLiters)
                        : literCands).filter { $0.substitutions == 0 }
                    let pc = (field == .unitPrice
                        ? candidates(repaired, decimals: conventions.priceDecimals).filter(plausiblePrice)
                        : priceCands).filter { $0.substitutions == 0 }
                    let found = closingTriples(liters: lc, prices: pc,
                                               totals: totalCands.filter { $0.substitutions == 0 },
                                               truncated: truncatedCands.filter { $0.substitutions == 0 })
                    for triple in found {
                        repairs.append((triple, .repaired(cellIndex: index, fromDigit: read, toDigit: partner), field))
                    }
                }
            }
        }
        // The same two windows as the read tier: nothing far below the top
        // read, and nothing ambiguous near the best repair.
        guard let bestRepair = repairs.max(by: { $0.0.logPosterior < $1.0.logPosterior }),
              topRead - bestRepair.0.logPosterior <= readWindow else {
            return .abstained
        }
        let near = repairs.filter { bestRepair.0.logPosterior - $0.0.logPosterior <= ambiguityWindow }
        let distinct = Set(near.map { "\($0.0.liters)|\($0.0.price)|\($0.0.total)" })
        guard distinct.count == 1 else { return .abstained }
        return commit([bestRepair.0], repair: (bestRepair.1, bestRepair.2))
    }

    /// A preset amount is a round number of currency units: 20.00, 1000.00.
    static func isRoundAmount(_ value: Double) -> Bool {
        abs(value - value.rounded()) < 0.0005 && value >= 5
    }

    /// A display value as an exact decimal: at most three fraction digits,
    /// never the binary noise of `Decimal(Double)`.
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.3f", value)) ?? Decimal(value)
    }

    // MARK: - Candidates

    struct Candidate: Equatable {
        let value: Double
        let logPosterior: Double
        /// Cells whose digit is not the cell's top read.
        let substitutions: Int
    }

    struct Triple {
        let liters: Double
        let price: Double
        let total: Double
        let totalDerived: Bool
        let logPosterior: Double
        let substitutions: Int
    }

    /// The exact tier: the top read, or the top read with ONE cell substituted
    /// across the three windows. Two substitutions can assemble a closing
    /// triple out of a miscounted window (a fill shrunk tenfold that still
    /// multiplies out), and did on real cells.
    static let maxSubstitutions = 1
    /// No fill is under half a litre or under one unit of currency.
    static let minLiters = 0.5
    static let minTotal = 1.0

    /// The beam over the cells' ranked digits, then every allowed decimal
    /// placement of each string.
    static func candidates(_ window: PumpLocatedWindow, decimals: [Int]) -> [Candidate] {
        guard !window.cells.isEmpty, !decimals.isEmpty else { return [] }
        var strings: [(digits: [Int], logPosterior: Double, substitutions: Int)] = [([], 0, 0)]
        for cell in window.cells {
            var next: [(digits: [Int], logPosterior: Double, substitutions: Int)] = []
            for prefix in strings {
                for (rank, candidate) in cell.ranked.prefix(beamWidth).enumerated() {
                    next.append((prefix.digits + [candidate.digit],
                                 prefix.logPosterior + candidate.logPosterior,
                                 prefix.substitutions + (rank == 0 ? 0 : 1)))
                }
            }
            next.sort { $0.logPosterior > $1.logPosterior }
            strings = Array(next.prefix(stringsPerField))
        }
        // The decimal mark the classifier saw is a hint for the placement, not
        // a constraint: a placement that contradicts a seen mark pays a
        // penalty, one that agrees pays nothing, and a window with no mark
        // seen leaves every placement equal.
        let markIndex = window.cells.firstIndex(where: \.decimalPoint)
        var out: [Candidate] = []
        for string in strings {
            let integer = string.digits.reduce(0) { $0 * 10 + $1 }
            for d in decimals {
                var penalty = 0.0
                if let markIndex, markIndex != window.cells.count - 1 - d {
                    penalty = decimalMarkPenalty
                }
                out.append(Candidate(value: Double(integer) / pow(10, Double(d)),
                                     logPosterior: string.logPosterior - penalty,
                                     substitutions: string.substitutions))
            }
        }
        return out
    }

    /// Every (liters, price, total) combination whose arithmetic closes. A
    /// truncated total closes when the product, cut to the display's decimals,
    /// matches - and the committed total is then the product itself.
    static func closingTriples(liters: [Candidate], prices: [Candidate],
                               totals: [Candidate], truncated: [Candidate],
                               presetSlack: Bool = false) -> [Triple] {
        var out: [Triple] = []
        for l in liters {
            for p in prices {
                let product = (l.value * p.value * 100).rounded() / 100
                let slack = presetSlack ? closingSlack + 0.005 * p.value : closingSlack
                for t in totals where t.value > 0 {
                    // Exact at the display's precision: the pump computed this
                    // product, so it matches to the cent (one cent of slack for
                    // the head's rounding mode). The Confirm cross-check's 0.5 %
                    // tolerance is for receipts and would let a misread digit
                    // "close"; here it would only manufacture ambiguity.
                    if abs(product - t.value) <= slack {
                        out.append(Triple(liters: l.value, price: p.value, total: t.value,
                                          totalDerived: false,
                                          logPosterior: l.logPosterior + p.logPosterior + t.logPosterior,
                                          substitutions: l.substitutions + p.substitutions + t.substitutions))
                    }
                }
                for t in truncated where t.value > 0 {
                    // The display cut the product to one decimal: floor or round.
                    let floored = floor(product * 10) / 10
                    let rounded = (product * 10).rounded() / 10
                    if abs(floored - t.value) < 0.001 || abs(rounded - t.value) < 0.001 {
                        out.append(Triple(liters: l.value, price: p.value, total: product,
                                          totalDerived: true,
                                          logPosterior: l.logPosterior + p.logPosterior + t.logPosterior,
                                          substitutions: l.substitutions + p.substitutions + t.substitutions))
                    }
                }
            }
        }
        return out
    }

    /// Commits what the closing triples agree on; a field they disagree on
    /// abstains. Exactly one triple commits all three.
    static func commit(_ all: [Triple], repair: (PumpFieldProvenance, PumpField)?) -> PumpDisplayReading {
        guard let best = all.max(by: { $0.logPosterior < $1.logPosterior }) else { return .abstained }
        let triples = all.filter { best.logPosterior - $0.logPosterior <= ambiguityWindow }
        func field(_ values: [Double], derived: Bool, role: PumpField) -> PumpFieldReading {
            guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.0005 }) else {
                return .abstained
            }
            let provenance: PumpFieldProvenance = derived ? .derived
                : (repair.map { $0.1 == role ? $0.0 : .read } ?? .read)
            return PumpFieldReading(value: decimal(first), provenance: provenance,
                                    logPosterior: derived ? 0 : best.logPosterior)
        }
        let derived = triples.allSatisfy(\.totalDerived)
        return PumpDisplayReading(
            liters: field(triples.map(\.liters), derived: false, role: .liters),
            unitPrice: field(triples.map(\.price), derived: false, role: .unitPrice),
            total: field(triples.map(\.total), derived: derived, role: .total))
    }
}
