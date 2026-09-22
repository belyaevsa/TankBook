# PU.59 - A pair no shown price validates commits with a caution

Row: `docs/TASKS.md` -> PU.59. The ruling it implements: `docs/EXTRACTION.md` -> decision 11's
**second amendment** (product owner, 2026-09-22). Read that amendment first and read it whole -
it overrules the amendment directly above it, which PU.54 wrote and shipped.

**The situation in one paragraph.** PU.54 made the unit price optional: total + volume commit on
their own when the price they imply is inside the currency band. It then measured that the band
alone is not a validation - a currency-wide band commits every in-band pair at precision **0.831**,
because a role-assignment miss lands inside a band that wide (`pump-032` reads the price row as
litres, implying 0.647/L). Its conclusion was to require a shown price within 5 % of the implied
one, so **6 heldout stills now abstain as `.priceUnvalidated`**. The owner's ruling is that this
is the wrong half of a false choice: refusing tells the user the photo gave nothing, when total
and volume were read cleanly and only the *check* is missing; committing at 0.831 as if it were
read tells them the opposite lie. Hard rule 13 already names the third door - a derived value is
a default input, never a fact - so **the pair commits and the app says it is unchecked**.

**Baseline on this commit, the numbers you must hold or move.** Live **47 committed / 47 correct /
1.000 / 16 of 68 photos**; annotated **112 / 111 / 0.991 / 34**; `priceUnvalidated` **6**. Run
them yourself before you change a line - a number you did not produce is not a baseline.

## Where you may write

- `ios/Sources/TankbookCore/Extraction/PumpReader/PumpReadingLaw.swift`, `PumpReadingTypes.swift`
- `ios/App/Sources/Capture/CapturePipeline.swift`, `ios/App/Sources/ConfirmManual/` (the prefill
  and the sheet's notice)
- the String Catalog the Confirm sheet's strings live in (find it: `grep -rn "pumpAlpha" ios/App`)
- `ios/Tests/TankbookCoreTests/PumpReadingLawTests.swift`, `PumpReaderPipelineTests.swift`, and
  the app-target unit bundle under `ios/App/Tests/` (find the confirm tests there)
- `docs/EXTRACTION.md` (the measured numbers only - **never the amendment's ruling**),
  `docs/ERRORS.md`, `docs/JOURNEYS.md` (F2), `ml/pump-reader/REPORT.md` (a dated PU.59 section)

**Nothing under `Spike/`** - the corpus is fixed at this commit, read it, never write it. Nothing
in `tools/pump-annotate/`, nothing in `ml/pump-reader/src`, no model file.
Scratch: `ios/.build/pump-reader-out/pu59/`.

## What exists (read first, in order)

1. `docs/EXTRACTION.md` -> decision 11 and BOTH its amendments. The second one is the spec.
2. `PumpReadingLaw.pairOutcome` - the branch that returns `.refused(.priceUnvalidated)`, and
   `pairValidationTolerance` (0.05) with the comment explaining what the 5 % separates.
3. `PumpReadingTypes.swift` - `PumpAbstentionReason` (the vocabulary of **refusals**; note that
   `.priceDisagrees` is already a *committed* reading carrying an F2 signal on a nil field),
   `PumpFieldReading`, `PumpDisplayReading`.
4. `ios/App/Sources/Capture/CapturePipeline.swift` - how a reading becomes a `ConfirmPrefill`,
   and the `crossCheck == .lock` line.
5. `ios/App/Sources/ConfirmManual/ConfirmPrefill.swift` - `pumpAlpha` and
   `currencyLowConfidence` are the two precedents for "a flag the sheet renders as a notice".
   Follow whichever of them the sheet renders most cleanly.
6. `docs/JOURNEYS.md` -> F2, the whole table. A cautioned pre-fill is an F2 surface.
7. `docs/ERRORS.md` -> the Confirm section and the severity vocabulary.

## What to build

1. **The law commits the pair.** `pairOutcome` stops returning `.refused(.priceUnvalidated)`.
   It commits the same liters and total it would have committed, carrying a **caution**. The
   caution is a NEW value on `PumpDisplayReading` - not a `PumpAbstentionReason`. Refusals and
   cautions are different vocabularies and PU.51's histogram has to stay readable; do not
   overload the enum. A validated pair is unchanged and carries no caution. Every other guard
   stands: `pump-016`'s idle zeros still refuse, an implied price outside the band still refuses,
   no band at all still refuses. **A caution is not a way past a guard.**
2. **The caution reaches the form.** `CapturePipeline` carries it onto `ConfirmPrefill`, and a
   cautioned reading **never sets `crossCheck = .lock`**. The fields pre-fill and stay editable
   (hard rule 13).
3. **The sheet says so.** A notice beside the reading naming the next step (hard rule 7): the
   reading was not verified against a price, check the two numbers. Amber, from the DESIGN.md
   tokens only - no ad-hoc hex (hard rule 5). EN + RU through the String Catalog, a full
   localised phrase per language, never concatenation (hard rule 10). It survives being ignored.
   No monetization anywhere near it.
4. **The ship gate splits in two.** `PumpReaderPipelineTests` reports **verified commits with
   their precision** (the 0.99 floor applies to these) and **cautioned commits as their own tier
   with their own precision** (no floor - the user was told). Never one blended number: a blend
   hides exactly what the caution exists to expose. Print both tiers and the abstention
   histogram.
5. **The docs move with it.** `docs/ERRORS.md` gains the row (message + next step + severity).
   `docs/JOURNEYS.md` F2 gains the stage, and because F2's story changed, **clear its status
   line back to unreviewed** if it carries one. `docs/EXTRACTION.md` gets your measured numbers
   under the second amendment - the ruling's text is the owner's and you do not edit it.

## Tests you must add

- `PumpReadingLawTests`: each of the 6 stills that abstained `.priceUnvalidated` now commits its
  pair and carries the caution (name them from your own baseline run, do not guess). A validated
  pair commits with no caution. `pump-016` still refuses. An out-of-band implied price still
  refuses.
- **Named mutation**: remove the caution from the committed pair. The test asserting the reading
  is cautioned goes red, AND the test asserting it does not lock goes red. Paste both, red then
  green.
- App-target unit bundle: a cautioned prefill renders the notice and does not show the lock; an
  uncautioned one is unchanged. This bundle is **its own `xcodebuild` invocation** - it is not
  what `swift test` runs, and naming two bundles in one `-only-testing` command silently runs one
  (the two-bundle rule, `CLAUDE.md`).
- `PumpReaderPipelineTests`: the two tiers, printed separately, with both precisions.
  **The verified tier must be >= 47 at 1.000** - the relaxation may not cost a verified commit.

## Checks

`scripts/gate.sh` (all five stages, exit code read per stage).
`swift test --filter "PumpReadingLawTests|PumpReaderPipelineTests|PumpRowGeometryTests|PumpReaderHarnessTests"`
with counts - a filter matching nothing prints "0 tests passed", so read the count.
The app-target unit bundle in its own invocation, count read.
`swiftlint lint` from the repo ROOT, exit 0. Verify by exit code, never by skimming.

The package suite has pre-existing failures from other rows (PaddleOCR, CorpusAB, RV.277, RV.49)
and the corpus-coverage suites may be red against fixtures added after this commit - name what
you find, do not chase it.

**Screenshots**: the cautioned Confirm sheet, dark theme, EN and RU, to
`design/screenshots/PU.59-confirm.png` and `PU.59-confirm-ru.png`. Take them outside a test run -
`simctl` and `xcodebuild test` fight over the device. You cannot see them; take them anyway, the
orchestrator opens them. RU is where this breaks: "not verified" and its next step are short
strings, and short strings expand worst.

## Vacuous traps

Reusing `.priceUnvalidated` as a commit reason. A notice only reachable in a DEBUG build. Letting
the cautioned tier into the 0.99 floor and reporting 0.831 as "the number". A caution the user
cannot act on - no next step, no way to see what was read. Loosening a guard and calling the
extra commits a win. Editing the owner's ruling in `docs/EXTRACTION.md`. Reporting a committed
count with no precision beside it.

## Report back

Exit codes per gate stage and per test bundle with counts. The mutation red-then-green verbatim.
**The before/after table**: verified committed / correct / precision / photos, cautioned
committed / correct / precision / photos, and the abstention histogram, before and after. The
6 stills that moved, by name, with what each now commits and what its CSV says. The screenshot
paths. Anything found and not fixed.
