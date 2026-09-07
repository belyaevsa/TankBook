# RV.125 - a confidently wrong receipt total, and `main` is red on it

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

**This row is the only red on `main`.** `RV56TotalTests.noReceiptTotalIsConfidentlyWrong` fails:

```
receipt-052-gazpromneft-tver-gdrive95-fuelcard-pair-ru.jpeg: got 649.92, want 2249.92
```

## What is measured, and what is NOT

**Measured facts. Trust these.**

- The fixture is real: one Gazpromneft Tver G-Drive 95 fuel-card fill, **32.000 L at 70.31 =
  2249.92 RUB**, with its matched pump photo at `pump-073-...`.
- Vision reads the price line as **`20.31 X 32.000` at confidence 1.00**. The true price is
  **70.31**. This is a fresh instance of hard rule 15's standing observation that Vision misreads a
  digit at confidence 1.00 - **confidence tells you nothing here.**
- Vision reads **`=2249.92` TWICE**, both correct, both confidence 1.00.
- **`649.92` appears nowhere in the OCR text.** It is exactly `20.31 x 32.000`, so it is computed.
- `FuelExtractorTotalFinder.swift:60` already treats **`=`** as a total-marking token, so the
  printed total is not invisible to the finder for lack of a label.
- `DigitRepair` (`ios/Sources/TankbookCore/Extraction/DigitRepair.swift`) exists precisely for this
  family: it repairs an operand against a confusion table when the repaired product reproduces the
  printed total. **`20.31 -> 70.31` with `32.000` reproduces `2249.92` exactly.**

**My hypothesis, which I could NOT confirm - do not build on it until you have checked it.**
I believed the extractor "prefers a derived product over a printed total". I could not prove that,
and one observation actively complicates it: running the Spike harness over this fixture
(`cd Spike/ReceiptSpike && swift run ReceiptSpike <folder>`) extracts **nothing at all** - liters,
unit price and total all `–`, only `fuelKind 95`. The failing test uses a different configuration:

```swift
let pack = try FuelPriceBandStore.bundledPack()
let extractor = FuelExtractor(bandProvider: DefaultFuelPriceBandProvider(pack: pack))
let ocr = try VisionTextRecognizer.recognizeText(in: url, languages: ["en-US","de-DE","pl-PL","cs-CZ","ru-RU"])
let result = extractor.extract(lines: ocr, source: .receipt)
```

**So your FIRST task is to find out why 649.92 wins, under that exact configuration.** Report the
mechanism before you change anything. Four of the orchestrator's diagnoses have been wrong and every
one was caught by an agent that checked instead of assuming.

## Why this defect matters more than its size

The wrong value is **arithmetically consistent**: `20.31 x 32.000 = 649.92` closes perfectly, so the
cross-check **confirms** it rather than catching it. A wrong number that satisfies the very check
built to detect wrong numbers is the worst shape a capture defect takes, and hard rule 13 then has
the user editing a figure that looks authoritative. The printed total was available, correct, and
read twice.

## Design questions ALREADY CLOSED

1. **`receipt-052` stays in the corpus.** Removing it deletes the only evidence this can happen. If
   your fix cannot make the invariant hold, say so and stop - do not drop the fixture.
2. **`CorpusScorer.tolerance` is not widened.** Widening it until 649.92 counts as 2249.92 is the
   softening this project forbids; the ratchet exists because that was tried before.
3. **The product path is not deleted.** It is what rescues a receipt whose printed total is
   obscured, and [RV.56]'s invariant must keep holding for those too.
4. **Do not tune anything against this one file.** A rule that fixes `receipt-052` and nothing else
   is a hardcode. Whatever precedence you choose must be stated as a rule and hold across the class.

## What to build

- The mechanism, first, in your report.
- Then a **precedence rule** between a printed total and a derived one, written into
  `docs/EXTRACTION.md` (**the authority for the recognition pipeline**) as part of the change.
  Consider - do not assume - the signal that was available and unused here: **two identical,
  independent, high-confidence reads of the same printed value**, against a product built from a
  line that contradicts them. Agreement between two reads is evidence; a product agreeing with
  itself is not.
- Consider whether `DigitRepair` should have fired here and did not, and say why. If it is
  applicable, using it is the cheaper fix than a new precedence rule - it already encodes "the
  printed total is the anchor".

## Explicitly out of scope

- The pump class and `PumpPhotoGate` - `pump-073` scored fine and its constants did not move.
- Adding fixtures, or re-scoring other classes.
- [RV.114] (scoring the new corpus) and [RV.113] (the Drivvo importer).

## Docs to read before writing (in order)

1. `docs/EXTRACTION.md` - the pipeline, the four cross-check outcomes, the named failure modes
   (**the authority for this task**).
2. `CLAUDE.md` - hard rules 4, 13, 15.
3. `Spike/ReceiptSpike/README.md` - the accuracy gate workflow.
4. `docs/TESTING.md` -> L5.

## Checks

Baseline: **iOS 1631 tests / 181 suites with exactly ONE failure - the one above.** `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**, localization gate 0 (771 keys, 100% RU). Other rows may
land while you work; **re-measure the baseline yourself** and report what you found.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, **never subsetted**. The target is **zero failures**. Report the
   number, and report the corpus scores the L5 suites print.
4. **The high-water marks are re-measured, never softened.** If your change moves receipt hits,
   record the new number in `Spike/ReceiptSpike/fixtures/high-water.json` and the compression
   registry (`CorpusCompressionTests.swift:45`) **upward**, with the run that produced it. If hits
   FALL anywhere, that is a regression and the fix is wrong.
5. Release build not required unless you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L5**: `noReceiptTotalIsConfidentlyWrong` passes over the whole receipts class **including
  receipt-052**, with the tolerance unchanged.
- **L1**: a fixture where the printed total is genuinely **absent** still resolves from the product -
  the rescue path must survive.
- **L1**: a receipt where the printed total is present but genuinely differs from the fuel product
  (a **mixed receipt**, hard rule 4 - fuel amount is not the grand total) does not regress. This is
  the case a naive "printed always wins" rule breaks, and it is a hard rule, so it must be tested.
- **L1**: the precedence rule stated as a rule, asserted directly, not inferred from one image.

### Vacuous traps, named

- Removing `receipt-052`, which deletes the evidence.
- Widening the tolerance.
- Asserting the total is 2249.92 **on this one file** rather than that the precedence rule holds.
- Trusting Vision's confidence - it was **1.00** on the misread.
- "Printed always wins", which breaks hard rule 4's mixed receipts.
- Recording a *lower* high-water mark to make a run green.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

**The mechanism first** - why 649.92 wins under the failing test's configuration, and why the Spike
harness extracts nothing from the same image. Then every check with the **exit code you observed**,
whether each test was **run or only written**, and the corpus scores before and after. Name any
closed decision you think is wrong and stop there rather than absorbing it.
