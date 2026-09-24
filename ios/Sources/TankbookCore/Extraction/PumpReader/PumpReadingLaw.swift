import Foundation

/// The decode law: from ranked digits per cell to three committed-or-abstained
/// fields, with `volume x price = total` as the only judge.
///
/// The rules, each measured on the corpus (agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md):
/// - A field's digits come from the cells; its decimal placement comes from the
///   currency's display conventions, so every field is a small candidate set.
/// - A triple commits only when EXACTLY one combination closes the arithmetic
///   exactly: the shown total is the product rounded or floored to the cent,
///   never a value near it - a one-cent misread of a two-decimal total leaves a
///   one-cent residual, so any tolerance at the resolution admits exactly the
///   error the check exists to catch (the check-digit paradigm,
///   agents/research/PU.78.md §2.1). Fields the surviving triples agree on
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
        guard let literWindow = byField[.liters]?.first else { return .abstained(.noLitersWindow) }
        guard let priceWindow = byField[.unitPrice]?.first else {
            return resolveWithoutPrice(literWindow: literWindow, totalWindow: byField[.total]?.first,
                                       boards: byField[.board] ?? [], conventions: conventions,
                                       priceBand: priceBand)
        }
        let totalWindow = byField[.total]?.first

        let plausibleLiters: (Candidate) -> Bool = { $0.value >= minLiters && $0.value < 500 }
        let plausiblePrice: (Candidate) -> Bool = { priceBand?.contains($0.value) ?? ($0.value > 0) }
        let plausibleTotal: (Candidate) -> Bool = { $0.value >= minTotal }
        // The unfiltered candidate sets are kept so an abstention can name a
        // cause finer than "nothing closed": a field with no candidate at all
        // is unreadable cells, a price whose candidates the band removed is the
        // band. The filtered sets below are what the verdict uses, unchanged.
        let rawLiters = candidates(literWindow, decimals: conventions.volumeDecimals)
        let rawPrice = candidates(priceWindow, decimals: conventions.priceDecimals)
        let rawTotals = (totalWindow.map { candidates($0, decimals: conventions.totalDecimals) } ?? [])
        let rawTruncated = (totalWindow.map {
            candidates($0, decimals: conventions.truncatedTotalDecimals)
        } ?? [])
        let literCands = rawLiters.filter(plausibleLiters)
        let priceCands = rawPrice.filter(plausiblePrice)
        let totalCands = rawTotals.filter(plausibleTotal)
        let truncatedCands = rawTruncated.filter(plausibleTotal)
        let sets = CandidateSets(rawLiters: rawLiters, rawPrice: rawPrice, rawTotals: rawTotals,
                                 rawTruncated: rawTruncated, prices: priceCands)

        // An idle pump shows 0.00 liters: nothing to read.
        if literWindow.cells.allSatisfy({ $0.top.digit == 0 }) { return .abstained(.litersAllZero) }
        // No total on the display: the arithmetic has no judge, so the pair
        // is not committed - a confident wrong pair is worse than nil.
        guard totalWindow != nil else { return .abstained(.noTotalWindow) }

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

        // The repair tier: one substituted cell in any of the three fields.
        // The main tier above already tries one beam alternative per cell, so
        // this tier is for a cell whose true digit the beam does not carry at
        // all - a seven-segment confusion the classifier ranked fourth or
        // lower. The total is included: a wrong total cell is as likely as a
        // wrong volume or price, and the arithmetic still has to close to the
        // cent (no tolerance widening), so a total-side repair is held to the
        // same judge as the read.
        var repairs: [(Triple, PumpFieldProvenance, PumpField)] = []
        for (field, window) in [(PumpField.liters, literWindow), (.unitPrice, priceWindow), (.total, totalWindow!)] {
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
                    let tc = (field == .total
                        ? candidates(repaired, decimals: conventions.totalDecimals).filter(plausibleTotal)
                        : totalCands).filter { $0.substitutions == 0 }
                    let found = closingTriples(liters: lc, prices: pc, totals: tc,
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
            return .abstained(diagnoseNothingClosed(sets, priceBand: priceBand))
        }
        let near = repairs.filter { bestRepair.0.logPosterior - $0.0.logPosterior <= ambiguityWindow }
        let distinct = Set(near.map { "\($0.0.liters)|\($0.0.price)|\($0.0.total)" })
        guard distinct.count == 1 else { return .abstained(.ambiguous) }
        return commit([bestRepair.0], repair: (bestRepair.1, bestRepair.2))
    }

    /// The candidate sets a diagnosis needs: the raw sets before the
    /// plausibility filters, and the filtered price set the band shapes. Kept
    /// together so a refusal can name a cause finer than "nothing closed"
    /// without a long parameter list.
    struct CandidateSets {
        let rawLiters: [Candidate]
        let rawPrice: [Candidate]
        let rawTotals: [Candidate]
        let rawTruncated: [Candidate]
        let prices: [Candidate]
    }

    /// Names the most specific cause the candidate sets show for a reading that
    /// closed nowhere. A field with no candidate string at all is unreadable
    /// cells; a price row whose candidates the currency's band removed is the
    /// band; anything else is the arithmetic failing to close. The order
    /// matters: an empty raw set is a cell problem whether or not a band exists.
    static func diagnoseNothingClosed(_ sets: CandidateSets,
                                      priceBand: FuelPriceBand?) -> PumpAbstentionReason {
        // `totalWindow` is non-nil by the time this runs; both raw total sets
        // empty means the total row produced no candidate string.
        let totalsUnreadable = sets.rawTotals.isEmpty && sets.rawTruncated.isEmpty
        if sets.rawLiters.isEmpty || sets.rawPrice.isEmpty || totalsUnreadable {
            return .cellUnknown
        }
        if priceBand != nil, sets.prices.isEmpty {
            return .priceOutOfBand
        }
        return .nothingClosed
    }

    /// A preset amount is a round number of currency units: 20.00, 1000.00.
    static func isRoundAmount(_ value: Double) -> Bool {
        abs(value - value.rounded()) < 0.0005 && value >= 5
    }

    // MARK: - Decision 11: the price is optional

    /// The no-price branch. On a Wayne head the transaction price is one of the
    /// board cells, but the board is not always the paid price - pump-300's
    /// loyalty discount pays 2.034 against a 2.019-2.219 board - so decision 11
    /// makes the price optional: a board cell stands in only on a CLEAN close
    /// (no substituted cell), and otherwise the pair commits on the price it
    /// implies when a shown price validates it (`docs/EXTRACTION.md` decision 11).
    static func resolveWithoutPrice(literWindow: PumpLocatedWindow, totalWindow: PumpLocatedWindow?,
                                    boards: [PumpLocatedWindow], conventions: PumpDisplayConventions,
                                    priceBand: FuelPriceBand?) -> PumpDisplayReading {
        if let totalWindow,
           let clean = cleanBoardClose(literWindow: literWindow, totalWindow: totalWindow,
                                       boards: boards, conventions: conventions, priceBand: priceBand) {
            return clean
        }
        let shown = boards.compactMap { topCandidate($0, decimals: conventions.priceDecimals)?.value }
        switch pairOutcome(literWindow: literWindow, totalWindow: totalWindow, shownPrices: shown,
                           conventions: conventions, priceBand: priceBand) {
        case .committed(let reading): return reading
        case .refused(let reason): return .abstained(reason)
        }
    }

    /// What the pair tier produced: a total + volume commit, or the reason it
    /// refused (which the no-price branch carries on the whole reading).
    enum PairOutcome {
        case committed(PumpDisplayReading)
        case refused(PumpAbstentionReason)
    }

    /// The highest-posterior candidate of a window - its plain top read, with
    /// the decimal placement the seen mark prefers. Substituted digits rank
    /// below the top read, so this never carries one.
    static func topCandidate(_ window: PumpLocatedWindow, decimals: [Int]) -> Candidate? {
        candidates(window, decimals: decimals).max { $0.logPosterior < $1.logPosterior }
    }

    /// A board cell stands in for the price only on a CLEAN close: the top read
    /// of every field, no substituted cell. A close that needs a substitution
    /// is the arithmetic fabricating a price the customer did not pay
    /// (pump-300 pays 2.034 against a 2.019-2.219 board, and a beam
    /// substitution made the board-as-price tier close on a total of 27.67).
    /// Exactly one distinct clean close commits; none or several return nil so
    /// the pair below decides.
    static func cleanBoardClose(literWindow: PumpLocatedWindow, totalWindow: PumpLocatedWindow,
                                boards: [PumpLocatedWindow], conventions: PumpDisplayConventions,
                                priceBand: FuelPriceBand?) -> PumpDisplayReading? {
        guard !boards.isEmpty else { return nil }
        let liters = candidates(literWindow, decimals: conventions.volumeDecimals)
            .filter { $0.value >= minLiters && $0.value < 500 && $0.substitutions == 0 }
        let totals = candidates(totalWindow, decimals: conventions.totalDecimals)
            .filter { $0.value >= minTotal && $0.substitutions == 0 }
        var triples: [Triple] = []
        for board in boards {
            let prices = candidates(board, decimals: conventions.priceDecimals)
                .filter { (priceBand?.contains($0.value) ?? ($0.value > 0)) && $0.substitutions == 0 }
            triples += closingTriples(liters: liters, prices: prices, totals: totals, truncated: [])
                .filter { $0.substitutions == 0 }
        }
        let distinct = Set(triples.map { "\($0.liters)|\($0.price)|\($0.total)" })
        guard distinct.count == 1, let only = triples.first else { return nil }
        return commit([only], repair: nil)
    }

    /// How far a shown price may sit from the implied one and still validate
    /// the pair. pump-266's loyalty discount pays 1.839 against a 1.919 board
    /// (4.3 % below), so the tolerance clears a real discount; a larger gap is
    /// not a discount but a different number - pump-120's misread total implies
    /// 2.344 against a 1.409 board. The band alone is not a sufficient guard on
    /// the heldout live path (measured: 6 of 8 pair commits land inside the
    /// coarse currency band and are wrong), so this tolerance is load-bearing.
    static let pairValidationTolerance = 0.05

    /// The pair tier: with no usable price, total + volume commit when the
    /// price they IMPLY (`total / volume`) falls inside the currency's band and
    /// a price the display shows validates them (agents/research/PU.78.md, M2):
    /// 1. AGREEMENT is exact: the total is litres x a shown price, rounded or
    ///    floored to the cent. A near miss is a misread, not agreement.
    /// 2. Otherwise a shown price within `pairValidationTolerance` validates a
    ///    pair that was paid at a different price (a loyalty discount): it
    ///    commits with `.shownPriceDiffers`, and the shown price never
    ///    overwrites the paid one. With none near, `.priceUnvalidated`
    ///    (decision 11, hard rule 13).
    static func pairOutcome(literWindow: PumpLocatedWindow, totalWindow: PumpLocatedWindow?,
                            shownPrices: [Double], conventions: PumpDisplayConventions,
                            priceBand: FuelPriceBand?) -> PairOutcome {
        // An idle pump shows 0.00 liters: the guard must not resurrect a zero
        // read as a pair.
        if literWindow.cells.allSatisfy({ $0.top.digit == 0 }) { return .refused(.litersAllZero) }
        guard let totalWindow else { return .refused(.noTotalWindow) }
        // No band: an unbounded implied price is not a guard, so the pair
        // refuses exactly where the missing price did.
        guard let band = priceBand else { return .refused(.boardFoundNoPrice) }
        guard let liters = topCandidate(literWindow, decimals: conventions.volumeDecimals),
              let total = topCandidate(totalWindow, decimals: conventions.totalDecimals),
              liters.value >= minLiters, liters.value < 500, total.value >= minTotal else {
            return .refused(.cellUnknown)
        }
        let implied = total.value / liters.value
        guard band.contains(implied) else { return .refused(.priceOutOfBand) }
        let litersField = PumpFieldReading(value: decimal(liters.value), provenance: .read,
                                           logPosterior: liters.logPosterior)
        let totalField = PumpFieldReading(value: decimal(total.value), provenance: .read,
                                          logPosterior: total.logPosterior)
        let bandShown = shownPrices.filter { band.contains($0) }
        if bandShown.contains(where: { closesExactly(liters: liters.value, price: $0, total: total.value) }) {
            return .committed(PumpDisplayReading(liters: litersField, unitPrice: .abstained,
                                                 total: totalField, reason: nil))
        }
        let nearest = shownPrices.min { abs($0 - implied) < abs($1 - implied) }
        guard let shown = nearest, abs(shown - implied) <= pairValidationTolerance * implied else {
            return .refused(.priceUnvalidated)
        }
        return .committed(PumpDisplayReading(
            liters: litersField, unitPrice: .abstained(.priceDisagrees), total: totalField, reason: nil,
            caution: .shownPriceDiffers(shown: decimal(shown), implied: decimal(implied))))
    }

    /// A product floored to the cent. The nudge keeps a product that is a whole
    /// number of cents in binary noise (e.g. 20.999999999) from flooring a cent low.
    static func cents(floorOf value: Double) -> Double {
        floor(value * 100 + 1e-7) / 100
    }

    /// Whether `total` is `liters x price` rounded or floored to the cent - the
    /// exact agreement a pair needs with a shown price.
    static func closesExactly(liters: Double, price: Double, total: Double) -> Bool {
        let rounded = (liters * price * 100).rounded() / 100
        return abs(rounded - total) < 0.0005 || abs(cents(floorOf: liters * price) - total) < 0.0005
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
        /// Whether the product ROUNDS to the shown total, rather than only
        /// flooring to it. The floor branch exists for a head that floors its
        /// own product; a triple that closes only by flooring must not block
        /// one whose product rounds to the shown total.
        let exactClosing: Bool
    }

    /// The exact tier: the top read, or the top read with ONE cell substituted
    /// across the three windows. Two substitutions can assemble a closing
    /// triple out of a miscounted window (a fill shrunk tenfold that still
    /// multiplies out), and did on real cells.
    static let maxSubstitutions = 1
    /// No fill is under half a litre or under one unit of currency.
    static let minLiters = 0.5
    static let minTotal = 1.0
    /// No pump display shows more cells in one window than this; a longer row
    /// is a banner, and its digits would not even fit an `Int`.
    static let maxCells = 8

    /// The beam over the cells' ranked digits, then every allowed decimal
    /// placement of each string.
    static func candidates(_ window: PumpLocatedWindow, decimals: [Int]) -> [Candidate] {
        guard !window.cells.isEmpty, window.cells.count <= maxCells, !decimals.isEmpty else { return [] }
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
                let floored = cents(floorOf: l.value * p.value)
                for t in totals where t.value > 0 {
                    // The pump computed this product, so the shown total is it
                    // rounded or floored to the cent (the head's rounding mode
                    // is not known per head). A preset fill's volume is derived
                    // from the round total, so its product misses by up to half
                    // a volume step times the price - a bound from the volume
                    // display's resolution, not a tolerance on the total.
                    let rounds = abs(product - t.value) < 0.0005
                    let closes = presetSlack
                        ? abs(product - t.value) <= 0.005 * p.value
                        : rounds || abs(floored - t.value) < 0.0005
                    if closes {
                        out.append(Triple(liters: l.value, price: p.value, total: t.value,
                                          totalDerived: false,
                                          logPosterior: l.logPosterior + p.logPosterior + t.logPosterior,
                                          substitutions: l.substitutions + p.substitutions + t.substitutions,
                                          exactClosing: rounds))
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
                                          substitutions: l.substitutions + p.substitutions + t.substitutions,
                                          exactClosing: true))
                    }
                }
            }
        }
        return out
    }

    /// Commits what the closing triples agree on; a field they disagree on
    /// abstains. Exactly one triple commits all three.
    static func commit(_ all: [Triple], repair: (PumpFieldProvenance, PumpField)?) -> PumpDisplayReading {
        guard let best = all.max(by: { $0.logPosterior < $1.logPosterior }) else {
            return .abstained(.nothingClosed)
        }
        // The total is the anchor. When the best close's product ROUNDS to the
        // shown total, a competing triple that reaches the SAME total only by
        // flooring is a false close of an operand (its price or volume sits a
        // hair off, and the rounding operand is the read). A competitor whose
        // TOTAL differs means the display's total itself is ambiguous, so it
        // stays and the field abstains.
        let contenders = best.exactClosing
            ? all.filter { $0.exactClosing || abs($0.total - best.total) >= 0.0005 }
            : all
        let triples = contenders.filter { best.logPosterior - $0.logPosterior <= ambiguityWindow }
        func field(_ values: [Double], derived: Bool, role: PumpField) -> PumpFieldReading {
            guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.0005 }) else {
                return .abstained(.ambiguous)
            }
            let provenance: PumpFieldProvenance = derived ? .derived
                : (repair.map { $0.1 == role ? $0.0 : .read } ?? .read)
            return PumpFieldReading(value: decimal(first), provenance: provenance,
                                    logPosterior: derived ? 0 : best.logPosterior)
        }
        let derived = triples.allSatisfy(\.totalDerived)
        let liters = field(triples.map(\.liters), derived: false, role: .liters)
        let unitPrice = field(triples.map(\.price), derived: false, role: .unitPrice)
        let total = field(triples.map(\.total), derived: derived, role: .total)
        // A reading that committed nothing is ambiguous here by construction:
        // it was handed closing triples, so the refusal is their disagreement.
        let reason: PumpAbstentionReason? =
            (liters.value == nil && unitPrice.value == nil && total.value == nil) ? .ambiguous : nil
        return PumpDisplayReading(liters: liters, unitPrice: unitPrice, total: total, reason: reason)
    }
}
