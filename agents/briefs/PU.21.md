# PU.21 - the decode law in Swift, scored on oracle strings

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.21. **Authority:** `docs/EXTRACTION.md` →
"The pump reader" incl. the decisions; **the design is `agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md`
§1 (types, abstain rule, DigitRepair and cross-check interaction), §2 (decimal recovery: candidate
set, search, the four worked fixtures, the ablation of load-bearing priors, fragility), §4.1 (what
"committed" means) and §6 row 1** - read all of it; it was measured on the corpus, and it names the
mutations. Decision 6 in force: **the receipt is the truth** - `expected.csv` stays the oracle, a
truncated display total (`pump-003` `20886.3` vs 20886.25) is never committed as read; the law
abstains on the total and DERIVES it from volume × price, which reproduces the receipt.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/` - new files only (`PumpReadingLaw.swift`,
`PumpReadingTypes.swift`, `PumpSegmentDecoder.swift` if you split it, `PumpFieldConventions.swift`);
`ios/Tests/TankbookCoreTests/PumpReadingLaw*.swift` (new). You may add golden vectors under
`ios/Tests/TankbookCoreTests/Fixtures/` if a directory of that kind exists; otherwise inline. **Do
not touch** `PumpGlyphSlicer.swift`, `PumpPanelLocator.swift`, `PumpQuadWarp.swift`,
`PumpSegmentsModel.swift` (it already carries the constrained decode - reuse `PumpSegmentsModel.decode`
and `digitPatterns`, do not duplicate), `PumpExtractor.swift`, `DigitRepair.swift` (read its
confusion table; if you need a seam, ADD an overload, never change the existing one), anything in
`ios/App/`, `ml/`, `Spike/`. **Three other agents are working in this checkout** (the locator, row
assignment, the Python model) - never move or revert a file you did not create. No `/tmp`.

## Write code first, explore second

## What already exists

- `PumpSegmentsModel.decode(_:) -> Read` (digit, dp, margin, probabilities) and
  `PumpSegmentsModel.digitPatterns`. The law consumes 8 probabilities per cell; build
  `PumpCellReading.ranked` (all ten digits by log-likelihood) from the same rule.
- `DigitRepair.swift` (P2.13): the seven-segment confusion table and the repair search; read how
  `FuelExtractor` calls it (`FuelExtractor.swift:123-137`).
- `CrossCheck.swift`: the four-outcome arithmetic cross-check and its tolerances.
- `FuelPriceBands.seed.json` + `FuelPriceBandProvider`: the per-currency price band (a
  load-bearing prior in the review's ablation - 14 of 95 fixtures go ambiguous without it).
- The pump scorer in `AccuracyRatchetTests.swift` / `CorpusPumpScorer` (search for it): B1's
  precision-on-committed over `expected.csv`'s numeric cells, blanks unscored.
- `Spike/ReceiptSpike/fixtures/pump/windows.json`: the strings the harness mode reads
  (`text` per window, `field`, `csvDisagrees`, `notOnDisplay` - see `_about`).

## What to build

1. **Types** as the review's §1 sketch (`PumpCellProbabilities`, `PumpGlyphCandidate`,
   `PumpCellReading`, `PumpWindowReading`, `PumpFieldProvenance` with `.read / .repaired / .derived`,
   `PumpFieldReading` with `value: Decimal?` = the abstention, `PumpDisplayReading`,
   `PumpLocatedWindow` with a `field` role - row assignment is PU.23's, so the harness supplies
   the role from the annotation).
2. **Conventions** per currency/make: digit count per field, decimals per field (volume 2; price
   2 or 3 by currency - EUR 3, RUB/KZT 2 - from the band pack), truncated-total families (the
   `3765,7` shape). Seed them beside the price bands, not as literals in the law.
3. **`PumpReadingLaw.resolve(windows:currency:beamWidth:)`** as §2.2: for each field the
   candidate set is the beam over the top-k digits per cell × the decimal placements the
   conventions allow; a triple is committed only when exactly ONE combination closes
   `volume × price = total` within the cross-check tolerance; a single-cell substitution from
   the confusion table, ordered by the cells' posteriors, may close it (`.repaired`, at most one
   substitution, the review's exact tier); a truncated total is `.derived`, never `.read`;
   ambiguity → `nil` for the fields that are ambiguous; idle pumps (0.00 / 0.00) → nil on all
   three; a preset-amount fill (round total, derived volume) resolves the way §3's hard case
   says. Permutation ban: liters/price/total never swap roles to close the arithmetic.
4. **Oracle-string harness** (a Swift Testing suite gated like the other PU harnesses): for
   every fixture in `windows.json`, build `PumpCellReading`s from the annotation string with
   probability 0.97 on the true segments and 0.03 elsewhere (a "perfect but not certain" reader),
   run the law, score with the SAME pump scorer as the rules arm against `expected.csv`, and
   print: committed, committed-correct, precision, coverage, confident-wrong by name.
5. **Fragility**: a second harness pass mutates one digit per fixture (the review's §2.5 method,
   seeded, 20 mutations per fixture) and reports the commit-wrong rate and the repair rate.

## Tests (each names its oracle; the review names the mutations)

- Golden decode vectors: for every digit, the 0.97/0.03 vector decodes to it; a `9` with segment
  `e` at 0.45 decodes to 9 (oracle: `digitPatterns`).
- `pump-009` (`02038,00 / 00040,00 / 050,95`), `pump-003` (12 valid placements → the conventions
  + band leave one; total derived 20886.25), `pump-031` (does not multiply out by design →
  abstain, nothing committed wrong), `pump-051` (four board prices, none matches → the transaction
  price is nil, volume and total still read) - each as a named test with the review's expected
  outcome (oracle: `expected.csv` + the review's worked section).
- Ratchet: oracle-string committed ≥ 281 of 320, precision ≥ 0.989, confident-wrong ⊆ the declared
  artefacts {pump-031, pump-065, pump-073} (oracle: the review's measurement; the constants move
  only up).
- **Named mutations, each must go red:** (a) swap the volume and price decimal conventions →
  `pump-108` commits the 10×-shrunk triple; (b) remove the uniqueness requirement → a swapped
  triple commits on the fragility pass; (c) drop the permutation ban → a fixture closes with
  roles swapped. Paste the red output for each.

## Vacuous traps

A harness that scores on the strings it was given instead of `expected.csv`; a "unique" check
that only counts placements of one field; repair that searches all cells jointly (that is not the
review's exact tier and inflates the commit-wrong rate - §2.5).

## Checks (by exit code)

`cd ios && swift build` → 0; `swiftlint lint` from the repo ROOT → 0; `cd ios && swift test` → 0
with the new suites' counts non-zero and totals above 2127/262. No app-target change → say so.

## Standing fences

Never stash / checkout / move; never commit; `pgrep -x` only; not alone in the checkout; no `/tmp`.

## Report back

Exit codes, counts, run-or-only-written, the three red mutations verbatim, the oracle-string table
(committed / correct / precision / coverage / confident-wrong names), the fragility numbers, and
anything found and not fixed.
