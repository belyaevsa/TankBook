# PU.54 - The price becomes optional: total + volume commit on their own

Row: `docs/TASKS.md` -> PU.54. The ruling it implements: `docs/EXTRACTION.md` -> **decision 11**
(product owner, 2026-09-22). The measurement that motivates it: PU.51's histogram - of the stills
that commit nothing on the live path, **26 refuse with `boardFoundNoPrice`**, the single largest
refusal in the corpus.

**Baseline on this commit (82398950), the numbers you must move or hold:** live
**43 committed / 43 correct / 1.000 / 14 of 68 photos**; annotated **104 / 103 / 0.990 / 30**.
Report both before and after, from your own runs.

## Where you may write

`ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingLaw.swift`, `PumpReadingTypes.swift`
(a reason case if one is needed), `PumpReader.swift` (only to thread the band), the app call
sites that build a `FuelPriceBand` if they exist (`grep -rn "FuelPriceBand" ios/`),
`ios/Tests/TankbookCoreTests/PumpReadingLawTests.swift`, `PumpReaderPipelineTests.swift`,
`ml/pump-reader/REPORT.md` (a dated PU.54 section), `docs/EXTRACTION.md` ONLY if decision 11's
text needs a correction you can justify. **Nothing under `Spike/`** (the corpus is fixed at this
commit - read it, never write it), nothing in `tools/pump-annotate/`, nothing in `ml/pump-reader/src`.
Scratch: `ios/.build/pump-reader-out/pu54/`.

## What exists (read first, in order)

1. `docs/EXTRACTION.md` -> decision 11 - the ruling, in the product owner's words, including what
   the guard must be and what a shown price becomes.
2. `PumpReadingLaw.swift` - `resolve(windows:currency:priceBand:)`: `guard let priceWindow` at
   ~line 52 is the refusal; the board tier below it; `plausiblePrice` at ~line 70 is where
   `priceBand` is consulted today (and `priceBand` arrives `nil` from every current call site).
3. `FuelPriceBand.swift` and `FuelPriceBandPack.swift` - the band, the pack, and how a band is
   looked up for a currency and fuel. Say what the pack needs to answer "the plausible band for
   EUR petrol" and whether a fuel kind is available at this point in the pipeline (it may not be -
   if not, use the currency-wide band and say so).
4. `PumpReadingTypes.swift` - `PumpDisplayReading`, `PumpFieldReading`, `PumpAbstentionReason`
   (PU.51). A two-field commit must still carry a reason for the field that abstained.
5. `PumpReaderPipelineTests.swift` - both tiers, the floors, the per-make table and the abstention
   histogram it prints.
6. `docs/SCHEMA.md` -> `FillUp` - why total + volume is a complete entry and the price is derived.

Confirm before changing: reproduce the baseline numbers above, and print the current
`boardFoundNoPrice` count yourself. If it is not ~26, say so and stop.

## What to build

1. **Commit `total` + `liters` with no price.** When there is no price window and the board tier
   does not resolve, the law may still commit the two fields it has - **only if** the implied
   price `total / liters` falls inside the plausible `FuelPriceBand` for the currency. Outside the
   band it abstains with a named reason (`priceOutOfBand` exists). With no band available at all,
   the read must still abstain - an unbounded implied price is not a guard.
2. **Thread the band.** `priceBand` is a parameter that arrives `nil`; give `PumpReader`'s public
   entry points a band (from the pack, by currency) and pass it through. Name every call site you
   changed.
3. **A shown price, or a board cell near the implied one, becomes a VALIDATION.** Agreement raises
   confidence (keep committing as today). Disagreement must NOT refuse and must NOT overwrite: the
   committed fields stay total + volume, and the reading carries the disagreement so the form can
   raise the F2 confirm. `pump-300` (pays 2.034, board 2.019/2.069/2.079/2.219) and `pump-266`
   (pays 1.839, board 1.919) are the fixtures - both are loyalty discounts and both are currently
   in `PumpReadingLawTests.declaredArtefacts`. If your change makes either commit correctly, REMOVE
   it from that list and say so; that shrinkage is a result, not a side effect.

Out of scope: the orientation search (PU.53), the strip band trim (PU.58), the detector, the
slicer's count, the annotator.

## Tests you must add

`PumpReadingLawTests`:
- a two-field commit lands when the implied price is in band (oracle: name a still whose CSV
  asserts total and liters and whose display shows no price, from `expected.csv` + `windows.json`);
- it abstains, with a named reason, when the implied price is out of band (construct the strings);
- `pump-016`/`pump-017` (idle heads, all-zero litres) still refuse - the guard must not resurrect
  a zero read;
- a shown price that disagrees with the implied one does not change the committed total or volume.
**Named mutation**: drop the band check from the two-field path - the out-of-band test must go red.
Paste red-then-green.

`PumpReaderPipelineTests`: report **live committed / correct / precision / photos** and the
abstention histogram before and after. The claim to test: `boardFoundNoPrice` falls to near zero,
the committed count rises by roughly the stills it frees, and **precision stays at or above 0.99**.
If precision falls below 0.99, the row does not ship - say so with the wrong cells named.

## Checks

`scripts/gate.sh`; `swift test --filter "PumpReadingLawTests|PumpReaderPipelineTests|PumpRowGeometryTests|PumpReaderHarnessTests"`
with counts; `swiftlint lint` from the repo ROOT exit 0. Verify by exit code. The package suite has
pre-existing failures from other rows (PaddleOCR, CorpusAB, RV.277, RV.49) - name them, do not
chase them.

## Vacuous traps

Committing two fields with no band check (that is how a misread ships). A band so wide it accepts
anything - state the band you used for each currency you touched. Reporting the committed count
without precision beside it. Treating a disagreeing shown price as the truth and overwriting the
paid price.

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green verbatim, **the before/after
table (live committed, correct, precision, photos; the abstention histogram)**, the band values
used, whether `pump-300`/`pump-266` left the artefact list, and anything found and not fixed.
