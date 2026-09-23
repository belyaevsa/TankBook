import Foundation
import Testing
@testable import TankbookCore

/// The decode law on the corpus's annotated strings: a "perfect but not
/// certain" reader (0.97 on every true segment state) whose only judge is the
/// arithmetic, scored by the same pump scorer as the rules parser against
/// `expected.csv` (decision 6: the receipt is the truth). This is the ceiling
/// the law gives a perfect classifier, and the fragility pass below is what it
/// does to a single misread.
@Suite("PU.21 pump reading law")
struct PumpReadingLawTests {

    // MARK: - Ratchet constants (measured 2026-09-19; move only upward)

    private static let committedFloor = 294
    private static let precisionFloor = 0.996
    /// Cells the corpus itself declares unreadable as the receipt's value:
    /// a display that rounds or truncates what the receipt prints, or a
    /// DISCOUNTED fill whose paid price is not the one on the board.
    /// `pump-031` pays 32.50 after a discount while the pump shows 32.58, so
    /// the law reads the display and the CSV disagrees by construction.
    /// `pump-300` (pays 2.034 against a 2.019-2.219 board) and `pump-266`
    /// (pays 1.839 against a 1.919 board) were the same shape and left this
    /// list when decision 11 stopped the board standing in for the paid
    /// price - they now commit total + volume on the price they imply.
    private static let declaredArtefacts: Set<String> = [
        "pump-031", "pump-065", "pump-073",
    ]

    // MARK: - Unit rules

    @Test("a certain cell ranks its digit first with a wide margin")
    func certainCellRanksItsDigit() {
        for digit in 0...9 {
            let cell = PumpCellReading(certainDigit: digit, decimalPoint: false)
            #expect(cell.top.digit == digit)
            #expect(cell.margin > 2)
        }
    }

    @Test("pump-009: zero-padded Gilbarco strings resolve to 40.00 x 50.95 = 2038.00")
    func pump009Resolves() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "02038,00"),
                Self.window(.liters, "00040,00"),
                Self.window(.unitPrice, "050,95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.liters.value == Decimal(string: "40"))
        #expect(reading.unitPrice.value == Decimal(string: "50.95"))
        #expect(reading.total.value == Decimal(string: "2038"))
        #expect(reading.total.provenance == .read)
    }

    @Test("pump-003: a KZT total the display rounds is derived, never read")
    func pump003DerivesTheTotal() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20886.3"),
                Self.window(.liters, "85.25"),
                Self.window(.unitPrice, "245.0"),
            ], currency: CurrencyCode(rawValue: "KZT"))
        #expect(reading.liters.value == Decimal(string: "85.25"))
        #expect(reading.unitPrice.value == Decimal(string: "245"))
        // Oracle: expected.csv says 20886.25, the receipt's value.
        #expect(reading.total.value == Decimal(string: "20886.25"))
        #expect(reading.total.provenance == .derived)
    }

    @Test("video-004: a KGS price to one decimal closes with no mark seen on any row")
    func kgsOneDecimalPrice() {
        // The Gilbarco Veeder-Root som head shows `2955,04` / `29,58` / `99,9`; the
        // slicer saw no mark on any of them, so the placement comes from the
        // conventions alone. 29.58 x 99.9 = 2955.042.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "295504"),
                Self.window(.liters, "2958"),
                Self.window(.unitPrice, "999"),
            ], currency: CurrencyCode(rawValue: "KGS"))
        #expect(reading.unitPrice.value == Decimal(string: "99.9"))
        #expect(reading.liters.value == Decimal(string: "29.58"))
        #expect(reading.total.value == Decimal(string: "2955.04"))
    }

    @Test("pump-031: a discount that breaks the arithmetic commits nothing wrong")
    func pump031Abstains() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "0032,58"),
                Self.window(.liters, "0016,80"),
                Self.window(.unitPrice, "1,939"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        // 16.80 x 1.939 = 32.575 -> 32.58 closes on the DISPLAY value; the
        // receipt says 32.50 after the discount. The law reads what the pump
        // shows; this is one of the declared artefacts the ratchet excludes.
        #expect(reading.total.value == nil || reading.total.value == Decimal(string: "32.58"))
    }

    @Test("an idle pump commits nothing")
    func idlePumpAbstains() {
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "0.00"),
                Self.window(.liters, "0.00"),
                Self.window(.unitPrice, "1.889"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.committedCount == 0)
    }

    @Test("a single misread cell is repaired when exactly one substitution closes the arithmetic")
    func oneCellRepairs() {
        // pump-015: 15.89 x 1.889 = 30.02; the price read as 1.884 under glare.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "30.02"),
                Self.window(.liters, "15.89"),
                Self.window(.unitPrice, "1.884"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.unitPrice.value == Decimal(string: "1.889"))
        if case .repaired(let index, let from, let to)? = reading.unitPrice.provenance {
            #expect(index == 3 && from == 4 && to == 9)
        } else {
            Issue.record("expected a repaired price, got \(String(describing: reading.unitPrice.provenance))")
        }
    }

    @Test("a total cell the beam does not carry is repaired from a seven-segment partner")
    func totalCellRepairs() {
        // 12.50 x 4.30 = 53.75; the total's leading `5` read as `6`, and the
        // beam for that cell is [6, 8, 0] - the true `5` is a confusion
        // partner of `6` but ranks fourth, so only the repair tier can close
        // it, and the total is the field the substitution has to land in.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "63,75", leadingRanked: [6, 8, 0, 5]),
                Self.window(.liters, "12,50"),
                Self.window(.unitPrice, "4,30")
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.total.value == Decimal(string: "53.75"))
        #expect(reading.liters.value == Decimal(string: "12.5"))
        #expect(reading.unitPrice.value == Decimal(string: "4.30"))
        if case .repaired(let index, let from, let to)? = reading.total.provenance {
            #expect(index == 0 && from == 6 && to == 5)
        } else {
            Issue.record("expected a repaired total, got \(String(describing: reading.total.provenance))")
        }
    }

    @Test("an operand that only reaches the total inside the truncation slack does not make the exact read abstain")
    func exactOperandBeatsSlackOperand() {
        // 10.00 x 2.009 = 20.09 exactly; the price's `9` has `8` as a beam
        // neighbour, and 10.00 x 2.008 = 20.08 is one cent off - inside
        // `closingSlack`, because a head may floor its product. The exact
        // price must still commit: a slack-only operand close is not evidence
        // that the display's price is ambiguous.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20,09"),
                Self.window(.liters, "10,00"),
                Self.window(.unitPrice, "2,009", ranked: [9, 8], at: 3)
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.liters.value == Decimal(string: "10"))
        #expect(reading.unitPrice.value == Decimal(string: "2.009"))
    }

    @Test("roles never swap to close the arithmetic")
    func rolesNeverSwap() {
        // Liters and price swapped on the display would still multiply out;
        // the law must not read 1.889 L at 15.89 /L.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "30.02"),
                Self.window(.liters, "1.889"),
                Self.window(.unitPrice, "15.89"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.liters.value != Decimal(string: "15.89"))
    }

    // MARK: - PU.51: the law says why it abstained

    @Test("PU.51: a committed reading carries no reason")
    func committedReadingHasNoReason() {
        // Oracle: pump-009's zero-padded Gilbarco strings commit all three.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "02038,00"),
                Self.window(.liters, "00040,00"),
                Self.window(.unitPrice, "050,95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.committedCount == 3)
        #expect(reading.reason == nil)
        #expect(reading.liters.reason == nil)
        #expect(reading.unitPrice.reason == nil)
        #expect(reading.total.reason == nil)
    }

    @Test("PU.51: a partial read names the field that refused")
    func partialReadCarriesFieldReason() {
        // Oracle: synthetic. 10.00 x 2.000 = 20.00 exactly, so the operands
        // commit; the total's last cell is ambiguous between `0` (20.00) and
        // `1` (20.01, which the slack admits), so only the total abstains.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20,00", ranked: [0, 1], at: 3),
                Self.window(.liters, "10,00"),
                Self.window(.unitPrice, "2,000"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.committedCount == 2)
        #expect(reading.reason == nil)
        #expect(reading.total.value == nil)
        #expect(reading.total.reason == .ambiguous)
    }

    @Test("PU.51: no liters window")
    func reasonNoLitersWindow() {
        // Oracle: the law's first guard; no fixture leaves the role unassigned.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.unitPrice, "2,00")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .noLitersWindow)
    }

    @Test("PU.51: all-zero liters is an idle pump")
    func reasonLitersAllZero() {
        // Oracle: pump-016/pump-017's idle heads, liters 0.00.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "0.00"),
                Self.window(.liters, "0.00"),
                Self.window(.unitPrice, "1.889"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .litersAllZero)
    }

    @Test("PU.51: no total window")
    func reasonNoTotalWindow() {
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.liters, "10,00"), Self.window(.unitPrice, "2,00")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .noTotalWindow)
    }

    @Test("PU.51: no price window and no board to stand in")
    func reasonBoardFoundNoPrice() {
        // Oracle: a Wayne head's price lives on a board; with no board at all
        // the board tier has nothing to try, so it finds no price.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.liters, "10,00"), Self.window(.total, "20,00")],
            currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .boardFoundNoPrice)
    }

    @Test("PU.51: a price outside the currency's band")
    func reasonPriceOutOfBand() {
        // Oracle: synthetic. 10.00 x 9.999 = 99.99 closes exactly, but the
        // band admits 0.5...2.0, so the price candidates are removed before
        // the judge ever sees them.
        let band = FuelPriceBand(low: 0.5, high: 2.0)
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "99,99"),
                Self.window(.liters, "10,00"),
                Self.window(.unitPrice, "9,999"),
            ], currency: CurrencyCode(rawValue: "EUR"), priceBand: band)
        #expect(reading.reason == .priceOutOfBand)
    }

    @Test("PU.51: a row with more cells than the law reads is unknown")
    func reasonCellUnknown() {
        // Oracle: synthetic. The law's `maxCells` guard makes nine cells a
        // banner, not a display row, so the liters window yields no candidate
        // string at all - a cell problem, not an arithmetic one.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20,00"),
                Self.window(.liters, "123456789"),
                Self.window(.unitPrice, "2,000"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .cellUnknown)
    }

    @Test("PU.51: nothing closed the arithmetic")
    func reasonNothingClosed() {
        // Oracle: synthetic. The product (20.00) is nowhere near the shown
        // total (50.00) and no single confusion partner reaches it.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "50,00"),
                Self.window(.liters, "10,00"),
                Self.window(.unitPrice, "2,000"),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .nothingClosed)
    }

    @Test("PU.51: two repairs close and disagree, so the read is ambiguous")
    func reasonAmbiguous() {
        // Oracle: synthetic. 10.00 x 2.008 = 20.08; the price's last `8` can
        // repair to `0` (2.000 -> 20.00) and the total's last `0` to `8`
        // (20.08), two distinct closing triples. The rankings keep both closing
        // digits out of the beam, so only the repair tier can find them.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "20,00", ranked: [0, 1, 2, 8], at: 3),
                Self.window(.liters, "10,00"),
                Self.window(.unitPrice, "2,008", ranked: [8, 3, 4, 0], at: 3),
            ], currency: CurrencyCode(rawValue: "EUR"))
        #expect(reading.reason == .ambiguous)
    }

    // MARK: - PU.54: the price becomes optional (decision 11)

    @Test("PU.54: total + volume commit with no price when the implied price is in band",
          .pumpFixturesPresent)
    func pairCommitsWhenImpliedPriceInBand() throws {
        // Oracle: pump-042's CSV asserts 11.34 L and 20.00 EUR and its display
        // shows four board cells and no unit price; 20.00 / 11.34 = 1.764 is
        // inside the EUR band, so the pair commits and the board is a
        // validation the pair does not adopt.
        let reading = try Self.resolveFixture("pump-042-dresser-wayne-circlek-ee-preset-20eur.jpg")
        #expect(reading.liters.value == Decimal(string: "11.34"))
        #expect(reading.total.value == Decimal(string: "20"))
        #expect(reading.unitPrice.value == nil)
        #expect(reading.committedCount == 2)
        #expect(reading.reason == nil)
        // The nearest board cell is 1.784 against 1.764 implied - past rounding,
        // inside validation: a discount the form names.
        #expect(reading.unitPrice.reason == .priceDisagrees)
        if case .shownPriceDiffers? = reading.caution {} else { Issue.record("expected shownPriceDiffers") }
    }

    @Test("PU.54: the pair abstains with a named reason when the implied price is out of band")
    func pairRefusesOutOfBand() {
        // Synthetic: 10.00 L for 99.99 implies 9.999 a litre, outside the EUR
        // band's 0.4-3.0. An implied price the band cannot bound is not
        // committed.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "99,99"), Self.window(.liters, "10,00")],
            currency: CurrencyCode(rawValue: "EUR"),
            priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .priceOutOfBand)
    }

    @Test("PU.54: the pair guard does not resurrect an idle pump's zero read")
    func pairRefusesIdlePump() {
        // Oracle: pump-016/pump-017's idle heads, litres 0.00 and a board, no
        // price window. The pair guard must still refuse the zero read.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "0.00"), Self.window(.liters, "0.00"),
                      Self.window(.board, "1,869")],
            currency: CurrencyCode(rawValue: "EUR"),
            priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .litersAllZero)
    }

    @Test("PU.54: a shown price that disagrees does not change the committed total or volume")
    func pairIgnoresDisagreeingShownPrice() {
        // Synthetic: 10.00 L for 20.00 implies 2.00; a board shows 1.98 (a
        // loyalty discount, inside the validation tolerance). The pair commits
        // total + volume and carries the disagreement - the shown price never
        // overwrites the paid pair.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10,00"),
                      Self.window(.board, "1,980")],
            currency: CurrencyCode(rawValue: "EUR"),
            priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.liters.value == Decimal(string: "10"))
        #expect(reading.total.value == Decimal(string: "20"))
        #expect(reading.unitPrice.value == nil)
        #expect(reading.unitPrice.reason == .priceDisagrees)
        #expect(reading.caution == .shownPriceDiffers(shown: Decimal(string: "1.98")!, implied: Decimal(2)))
    }

    @Test("PJ.500: a shown price that agrees with the implied one carries no caution")
    func pairWithAgreeingShownPriceIsNotCautioned() {
        // Synthetic: 10.00 L for 20.00 implies 2.000; the board shows 2.008, 0.4 %
        // off - too far to close the triple, close enough to agree.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10,00"),
                      Self.window(.board, "2,008")],
            currency: CurrencyCode(rawValue: "EUR"),
            priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 2)
        #expect(reading.caution == nil)
        #expect(reading.unitPrice.reason == nil)
    }

    @Test("PU.54: an in-band pair with no validating shown price abstains")
    func pairRefusesUnvalidated() {
        // Synthetic: 10.00 L for 20.00 implies 2.00, inside the EUR band, but
        // no price is shown to validate it. With no third number to check
        // against, the pair abstains rather than commit a possible misread.
        let reading = PumpReadingLaw.resolve(
            windows: [Self.window(.total, "20,00"), Self.window(.liters, "10,00")],
            currency: CurrencyCode(rawValue: "EUR"),
            priceBand: FuelPriceBand(low: 0.4, high: 3.0))
        #expect(reading.committedCount == 0)
        #expect(reading.reason == .priceUnvalidated)
    }

    @Test("PU.54: a loyalty-discounted board is not taken as the paid price",
          .pumpFixturesPresent)
    func discountedBoardIsNotThePaidPrice() throws {
        // pump-300 pays 27.87 for 13.70 L (2.034 a litre) while the board reads
        // 2.019 / 2.069 / 2.079 / 2.219; pump-266 pays 66.74 for 36.29 L (1.839)
        // against a 1.919 board. Both were declared artefacts while the
        // board-as-price tier closed on a price the customer did not pay; the
        // pair now commits total + volume on the price they imply.
        let pump300 = try Self.resolveFixture("pump-300-wayne-circlek-liitrid-1370l-board-ee.jpg")
        #expect(pump300.liters.value == Decimal(string: "13.7"))
        #expect(pump300.total.value == Decimal(string: "27.87"))
        #expect(pump300.unitPrice.value == nil)
        let pump266 = try Self.resolveFixture("pump-266-wayne-circlek-pump3-3629l-discounted-price-board-ee.jpg")
        #expect(pump266.liters.value == Decimal(string: "36.29"))
        #expect(pump266.total.value == Decimal(string: "66.74"))
        #expect(pump266.unitPrice.value == nil)
    }

    // MARK: - The oracle-string harness

    @Test("the law over the annotated strings clears the committed and precision floors",
          .pumpFixturesPresent)
    func oracleStringsRatchet() throws {
        let score = try Self.scoreOracle(mutate: nil)
        print("PU.21 oracle strings: committed \(score.committed), correct \(score.committedCorrect), "
              + "precision \(score.precision), coverage \(score.coverage) of \(score.numericTotal); "
              + "wrong: \(score.wrong.sorted())")
        #expect(score.committed >= Self.committedFloor)
        #expect(score.precision >= Self.precisionFloor)
        let unexpected = score.wrong.filter { name in
            !Self.declaredArtefacts.contains { name.hasPrefix($0) }
        }
        #expect(unexpected.isEmpty, "confident-wrong outside the declared artefacts: \(unexpected)")
    }

    @Test("under single-digit misreads the arithmetic path repairs far more than it commits wrong",
          .pumpFixturesPresent)
    func fragilityUnderMisreads() throws {
        var rng = SeededGenerator(seed: 21)
        var wrong = 0
        var repaired = 0
        var committed = 0
        for _ in 0..<5 {
            let score = try Self.scoreOracle(mutate: { field, cells in
                Self.mutateOneCell(field: field, cells: cells, rng: &rng)
            }, mutateOnlyWherePriceShown: true)
            committed += score.committed
            wrong += score.committed - score.committedCorrect
            repaired += score.repaired
        }
        let wrongRate = Double(wrong) / Double(max(committed, 1))
        print("PU.21 fragility: committed \(committed), wrong \(wrong) (\(wrongRate)), repaired \(repaired)")
        // The rate depends on which cells the seed mutates: over 114 fixtures
        // seeds 1/2/21 read 5.7 / 4.8 / 3.9 %, over 116 seeds 1/2/3/21 read
        // 6.8 / 6.5 / 8.5 / 9.1 %. The ceiling is set above every seed
        // measured so a grown corpus cannot fail it by reshuffling the draw;
        // bringing the rate itself down is PU.24's next round. Since decision
        // 11 this measures the THREE-FIELD path only (`mutateOnlyWherePriceShown`):
        // a pair commit has no arithmetic judge, so a confident misread on a
        // price-less display is caught only by the currency band, which is not
        // what this ceiling was calibrated for.
        #expect(wrongRate <= 0.10)
        #expect(repaired > 0)
    }

    // MARK: - The named mutations (PU.14 §6 row 1), as tests that pin the seams

    @Test("without the ambiguity window a beam alternative that also closes blocks the read")
    func ambiguityWindowIsLoadBearing() {
        // Two closing triples exist for pump-015's strings: the true one and a
        // total beam alternative (30.03) 7 nats down. The window is what
        // separates "ambiguous" from "the beam's tail".
        let closed = PumpReadingLaw.closingTriples(
            liters: PumpReadingLaw.candidates(Self.window(.liters, "15.89"), decimals: [2]),
            prices: PumpReadingLaw.candidates(Self.window(.unitPrice, "1.889"), decimals: [3]),
            totals: PumpReadingLaw.candidates(Self.window(.total, "30.02"), decimals: [2]),
            truncated: [])
        #expect(closed.count >= 2, "the beam must offer a second closing triple for this test to mean anything")
        let committed = PumpReadingLaw.commit(closed, repair: nil)
        #expect(committed.total.value == Decimal(string: "30.02"))
        let best = closed.max { $0.logPosterior < $1.logPosterior }!
        let tail = closed.filter { $0 .logPosterior < best.logPosterior }
        #expect(tail.allSatisfy { best.logPosterior - $0.logPosterior > PumpReadingLaw.ambiguityWindow })
    }

    @Test("the read window keeps a two-substitution fabrication from committing")
    func readWindowIsLoadBearing() {
        // pump-010 before the preset tier: 13.17 x 75.99 = 1000.79 closes on a
        // total beam alternative 1000.80 - two unlikely substitutions that the
        // read window (6 nats) rejects and the preset tier then resolves.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "1000.00"),
                Self.window(.liters, "13.17"),
                Self.window(.unitPrice, "75.95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "75.95"))
        #expect(reading.total.value == Decimal(string: "1000"))
    }

    @Test("a placement that contradicts the seen decimal mark loses to one that agrees")
    func decimalMarkIsAPrior() {
        // Without a band, `050,95` could be 50.95 or 509.5 and both close
        // (2038.00 read, or 20380 as a truncated total); the mark decides.
        let reading = PumpReadingLaw.resolve(
            windows: [
                Self.window(.total, "02038,00"),
                Self.window(.liters, "00040,00"),
                Self.window(.unitPrice, "050,95"),
            ], currency: CurrencyCode(rawValue: "RUB"))
        #expect(reading.unitPrice.value == Decimal(string: "50.95"))
    }

}

// MARK: - Helpers

extension PumpReadingLawTests {
    struct OracleScore {
        var numericTotal = 0
        var committed = 0
        var committedCorrect = 0
        var repaired = 0
        var wrong: Set<String> = []
        var precision: Double { committed > 0 ? Double(committedCorrect) / Double(committed) : 0 }
        var coverage: Double { numericTotal > 0 ? Double(committed) / Double(numericTotal) : 0 }
    }

    static func window(_ field: PumpField, _ text: String) -> PumpLocatedWindow {
        PumpLocatedWindow(field: field, cells: cells(for: text))
    }

    /// A window whose leading cell carries an explicit ranking, so a test can
    /// put the true digit outside the beam (`beamWidth`) and exercise the
    /// repair tier. The remaining cells are certain.
    static func window(_ field: PumpField, _ text: String, leadingRanked: [Int]) -> PumpLocatedWindow {
        window(field, text, ranked: leadingRanked, at: 0)
    }

    /// The same, with the ranking on any cell and a controlled posterior gap,
    /// so a test can put a runner-up inside the ambiguity window.
    static func window(_ field: PumpField, _ text: String, ranked: [Int], at index: Int) -> PumpLocatedWindow {
        var cells = cells(for: text)
        guard !ranked.isEmpty, cells.indices.contains(index) else {
            return PumpLocatedWindow(field: field, cells: cells)
        }
        let candidates = ranked.enumerated().map { rank, digit in
            PumpGlyphCandidate(digit: digit, logPosterior: -Double(rank))
        }
        cells[index] = PumpCellReading(probabilities: [], ranked: candidates,
                                       decimalPoint: cells[index].decimalPoint)
        return PumpLocatedWindow(field: field, cells: cells)
    }

    /// Cells from an annotation string: digits are cells, a separator marks
    /// the decimal point on the cell before it, leading spaces are skipped.
    static func cells(for text: String) -> [PumpCellReading] {
        var out: [PumpCellReading] = []
        for ch in text {
            if let d = ch.wholeNumberValue {
                out.append(PumpCellReading(certainDigit: d, decimalPoint: false))
            } else if ch == "," || ch == ".", let last = out.popLast() {
                out.append(PumpCellReading(certainDigit: last.top.digit, decimalPoint: true))
            }
        }
        return out
    }

    static func mutateOneCell(field: PumpField, cells: [PumpCellReading],
                              rng: inout SeededGenerator) -> [PumpCellReading] {
        guard !cells.isEmpty, field == .liters || field == .unitPrice else { return cells }
        let index = Int(rng.next() % UInt64(cells.count))
        let current = cells[index].top.digit
        let partners = DigitRepair.confusablePartners(of: current)
        guard !partners.isEmpty else { return cells }
        let partner = partners[Int(rng.next() % UInt64(partners.count))]
        var out = cells
        out[index] = PumpCellReading(certainDigit: partner, decimalPoint: cells[index].decimalPoint)
        return out
    }

    /// Resolves one corpus still from its annotated strings and the bundled
    /// currency-wide band, exactly as the oracle harness does.
    static func resolveFixture(_ name: String) throws -> PumpDisplayReading {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.windowsURL.deletingLastPathComponent().appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        guard let ann = root[name] as? [String: Any], let want = expected[name] else {
            Issue.record("no fixture named \(name)")
            return .abstained
        }
        var windows: [PumpLocatedWindow] = []
        for raw in ann["windows"] as? [[String: Any]] ?? [] {
            guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                  let text = raw["text"] as? String, !text.isEmpty else { continue }
            if raw["legibility"] as? String == "partial" { continue }
            windows.append(Self.window(field, text))
        }
        return PumpReadingLaw.resolve(
            windows: windows, currency: want.currency,
            priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })
    }

    static func scoreOracle(mutate: ((PumpField, [PumpCellReading]) -> [PumpCellReading])?,
                            mutateOnlyWherePriceShown: Bool = false) throws -> OracleScore {
        let expected = try CorpusScorer.loadExpected(
            PumpReaderTestSupport.windowsURL.deletingLastPathComponent().appendingPathComponent("expected.csv"))
        let data = try Data(contentsOf: PumpReaderTestSupport.windowsURL)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pack = try FuelPriceBandStore.bundledPack()
        var score = OracleScore()
        for (name, value) in root.sorted(by: { $0.key < $1.key }) {
            guard name != "_about", let ann = value as? [String: Any],
                  let want = expected[name] else { continue }
            // The annotation's usable windows, before mutation.
            let rawWindows = (ann["windows"] as? [[String: Any]] ?? []).filter { raw in
                guard let fieldName = raw["field"] as? String, PumpField(rawValue: fieldName) != nil,
                      let text = raw["text"] as? String, !text.isEmpty else { return false }
                // A window read through glare is the annotator's best guess,
                // not a fact the law may repair the other fields against.
                return raw["legibility"] as? String != "partial"
            }
            // Decision 11: a display with no price window commits a pair on the
            // band alone, with no arithmetic to repair a misread - so the
            // arithmetic path's fragility is measured on the displays that DO
            // show a price, which is what the repair tier exists for.
            let priceShown = rawWindows.contains { ($0["field"] as? String) == "unitPrice" }
            var windows: [PumpLocatedWindow] = []
            for raw in rawWindows {
                guard let fieldName = raw["field"] as? String, let field = PumpField(rawValue: fieldName),
                      let text = raw["text"] as? String else { continue }
                var cells = Self.cells(for: text)
                if let mutate, !mutateOnlyWherePriceShown || priceShown {
                    cells = mutate(field, cells)
                }
                windows.append(PumpLocatedWindow(field: field, cells: cells))
            }
            let reading = PumpReadingLaw.resolve(
                windows: windows, currency: want.currency,
                priceBand: want.currency.flatMap { pack.currencyBand(currency: $0) })
            let cells: [(reading: PumpFieldReading, want: Double?)] = [
                (reading.liters, want.liters), (reading.unitPrice, want.unitPrice), (reading.total, want.total),
            ]
            for cell in cells {
                let field = cell.reading
                let got = field.value.map { NSDecimalNumber(decimal: $0).doubleValue }
                guard let wantValue = cell.want else { continue }
                score.numericTotal += 1
                guard let got else { continue }
                score.committed += 1
                // A derived total is the exact product; where the corpus asserts
                // the display's truncated value instead of the receipt's
                // (pump-018 `2499,8`), the product is right to the display's
                // own precision. PU.13 §4 names these cells.
                let derived: Bool = { if case .derived? = field.provenance { return true }; return false }()
                let slack = derived ? 0.1 : CorpusScorer.tolerance
                if abs(got - wantValue) < slack {
                    score.committedCorrect += 1
                    if case .repaired? = field.provenance { score.repaired += 1 }
                } else {
                    score.wrong.insert(name)
                }
            }
        }
        return score
    }
}

/// A tiny deterministic generator for the fragility pass.
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
}
