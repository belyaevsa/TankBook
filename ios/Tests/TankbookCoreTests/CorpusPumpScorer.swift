import Foundation
@testable import TankbookCore

// B1 (2026-09-04) - the pump class's re-scoped scorer and score shape, kept out
// of `CorpusABScorer` so that file stays under its length limit. The pump class
// is scored on its 178 numeric cells only; `currency` is reported separately and
// `fuelKind` is never scored (a pump parser must not produce it).

/// The pump class's score under the re-scoped metric (B1). Three numbers over
/// the 178 numeric cells, plus currency reported separately:
///
/// - `recall` = `numericHits / numericTotal` - the OLD metric, kept for
///   legibility but no longer the gate. It counts a correct `nil` as a miss and
///   a confident-wrong value as a hit, which is exactly backwards on a pump.
/// - `precision` = `committedCorrect / committed` - of the numeric fields the
///   parser returned non-nil, the fraction that are correct. This is what a
///   "never a wrong fill-up" gate must actually be.
/// - `coverage` = `committed / numericTotal` - the fraction of numeric cells the
///   parser commits to. A correct refusal (idle pump, factor-of-ten tie) lowers
///   this rather than counting as a wrong value.
struct PumpScore: Equatable, Sendable {
    let name: String
    let numericHits: Int
    let numericTotal: Int
    let committed: Int
    let committedCorrect: Int
    let currencyHits: Int
    let currencyTotal: Int

    var recall: Double { numericTotal > 0 ? Double(numericHits) / Double(numericTotal) : 0 }
    var precision: Double { committed > 0 ? Double(committedCorrect) / Double(committed) : 0 }
    var coverage: Double { numericTotal > 0 ? Double(committed) / Double(numericTotal) : 0 }

    /// The recall view the ratchet guards (hits may not fall, total may not
    /// shrink) - numeric cells only.
    var scoredClass: ScoredClass { ScoredClass(name: name, hits: numericHits, total: numericTotal) }
}

extension CorpusScorer {
    /// Scores the pump class under the re-scoped metric. The headline is the
    /// 178 numeric cells (`liters`, `unitPrice`, `total`); `currency` is
    /// reported separately and `fuelKind` is never scored, because a pump
    /// parser must not produce it (docs/EXTRACTION.md -> "Never infer fuel kind
    /// from a pump photo"). Recall alone was lying: it scores a correct `nil`
    /// as a miss and a confident-wrong value as a hit, and on the two idle
    /// pumps the ground-truth `0.00` means recall actively rewards logging a
    /// zero-litre fill (hard rule 15 forbids it). Precision and coverage are
    /// the honest pair: precision punishes a wrong committed value, coverage
    /// measures how much the parser will commit to, and a correct refusal is
    /// reflected as non-coverage rather than as a wrong value.
    static func scorePump(name: String, images: [String],
                          records: [String: ExtractionRecord],
                          expected: [String: ExpectedRow]) -> PumpScore {
        var numericHits = 0
        var numericTotal = 0
        var committed = 0
        var committedCorrect = 0
        var currencyHits = 0
        var currencyTotal = 0
        for image in images {
            guard let want = expected[image] else { continue }
            let record = records[image] // nil => never attempted => all miss
            for (got, wantValue) in numericCells(record, want) {
                numericTotal += 1
                guard let got else { continue }
                committed += 1
                if abs(got - wantValue) < tolerance {
                    numericHits += 1
                    committedCorrect += 1
                }
            }
            if let wantCurrency = want.currency {
                currencyTotal += 1
                if record?.currency == wantCurrency { currencyHits += 1 }
            }
        }
        return PumpScore(name: name, numericHits: numericHits, numericTotal: numericTotal,
                         committed: committed, committedCorrect: committedCorrect,
                         currencyHits: currencyHits, currencyTotal: currencyTotal)
    }

    /// The three numeric cells a row asserts, as (got, want) pairs. An empty
    /// expected cell is skipped entirely (never scored, never a miss).
    private static func numericCells(_ record: ExtractionRecord?,
                                     _ want: ExpectedRow) -> [(got: Double?, want: Double)] {
        var cells: [(got: Double?, want: Double)] = []
        if let wantValue = want.liters { cells.append((record?.liters, wantValue)) }
        if let wantValue = want.unitPrice { cells.append((record?.unitPrice, wantValue)) }
        if let wantValue = want.total { cells.append((record?.total, wantValue)) }
        return cells
    }
}
