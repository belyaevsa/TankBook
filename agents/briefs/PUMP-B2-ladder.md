# Pump B2: let the digits through, then pin them - a pump-shaped ladder

Design and implement. Code first, exploration second.

**B1 is done and committed** (`0411753`): the gate now measures **precision on committed numeric
fields plus a coverage floor** over the **178 numeric cells**, not recall over a 261-cell mixture.
Today's measured state is **5 correct of 44 committed (11% precision) at 25% coverage**, and the
mode ships off. Your job is the reading, not the metric.

## This is a re-dispatch, and here is what the last run left you

A previous agent on the combined B1+B2 brief finished B1, started B2, and was **killed by the
system for memory pressure** partway in. Its partial B2 is preserved, uncommitted, outside the
tree:

    /private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/c6d99bbc-abd7-4f8c-921b-6a49c91db750/scratchpad/b2-partial/
        PumpExtractor.swift        (261 lines)
        PumpExtractorTests.swift
        NumberScanner.swift        (its edit)
        FuelExtractor.swift        (its edit)

**Read it before you design anything.** It is not authoritative and it was mid-flight, but it had
reached real conclusions worth keeping or consciously rejecting - a label-anchored role assignment
that reads a value to the LEFT of its label on the same baseline (`SUMMA` at x=0.71, its total
`12522` at x=0.44) or BELOW it in the same column (the Gilbarco `€/L` price), a plausible-fill floor
of **2 litres** rather than 5 (`pump-014` is a real 3.92 L fill and the pumps print
`Vmin 2 LIITRIT`), and a text-only fallback for line arrays with no geometry.

**Why it failed, which is your first task**: it rerouted `source == .pump` through the new extractor
**before reconciling the existing pump tests**, and `DigitRepairTests` went red - `pump-013` and
`pump-015` returned nil where the old path repaired them end to end. Whatever you build must keep
those green or explain, in the report and in a comment, why their expectation legitimately changed.

Copy what you want from the partial into the worktree yourself; do not assume it is already there.

## Where you work

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout.** **Run no `git` command** - leave the work
uncommitted. Do not touch `docs/TASKS.md`, `agents/briefs/`, any `expected.csv`, or any fixture
image. **Never `pgrep -f`** (it matches your own brief); use `pgrep -x`.

**Memory matters this run.** The machine killed the last agent. Do not run `xcodebuild`, do not
boot a simulator, and prefer `swift test --filter` while iterating - the full suite only when you
are done.

## The wall, verified in the source

`NumberScanner.decimals(in:)` (`Extraction/NumberScanner.swift:13`) matches
`(\d{1,3}(?:[ .]\d{3})*|\d+)[.,](\d{1,3})` - **the separator is mandatory**. A seven-segment display
routinely drops it, so Vision returns `12522`, `208863`, `8525`, `2450` at confidence 1.00 and the
tokenizer discards them. The digits are read and thrown away one layer down.

And the pump path is **the receipt parser with two switches** (`FuelExtractor.extract` only skips
fuel kind and enables `DigitRepair` for `source == .pump`): operand pairing wants an `×`,
`loneMarkers` wants an `L`, the total finder wants a labelled value on a baseline. **A pump prints
three bare numbers under three labels in a fixed layout with no operator.**

Evidence: `diagnostics/pump-ocr-dump.txt` (all 66 fixtures, committed), the four analyses in
`diagnostics/RESEARCH-pump-*.md`, and `Spike/ReceiptSpike/fixtures/pump/README.md`, which records
what each fixture proved and will stop you proposing something already falsified.

## What to build

- **Separator-liberal tokens on the pump source only.** A bare digit run is a candidate with an
  **unknown decimal scale**. Receipt behaviour must not change.
- **Scale search, pinned by physics and the band.** Search the powers of ten that satisfy
  `volume x price ~= total` within the existing tolerance, then bound each operand: volume by a
  plausible fill (the partial's floor of 2 L and a tank-sized ceiling), price by the band pack the
  receipt path already ships (`FuelPriceBands.seed.json`, keyed by currency and era - a pump has a
  currency marker and usually no date, so say what you do then). **If more than one scale
  assignment survives, abstain.** `pump-003` loses all three separators and each needs a different
  divisor; a wrong scale is the worst outcome in this class.
- **Label and make anchors.** The make (`GILBARCO VEEDER-ROOT`, `Wayne`, `DRESSER`, `TOKHEIM`,
  `ADAST`, `ТОПАЗ`) and the labels (`SUMMA`/`LIITRIT`/`HIND/1L`, `РУБЛИ`/`ЛИТРЫ`/`ЦЕНА`, `€/L`)
  survive in nearly every dump **including the bad ones**. Use them to assign a number to a role by
  geometry, not by magnitude. Make may select a template hint; it must never select a parser.
- **The board is not the transaction.** Four grade prices whose order means nothing, and on several
  fixtures the charged price is on no board. A board price may rank a candidate; it may never
  become the unit price alone.
- **Keep the cross-check and `DigitRepair`.** The cross-check is what picks the right price out of
  four on `pump-005`; P2.13's repair is already pump-scoped and has passing tests you must not
  break.
- **Refuse the non-fills.** `pump-016`/`017` are idle (all zeros) and must return nothing.

## What NOT to build

No image work (cropping, upscaling, second-pass recognition - that is track B3 and two analysts
disagree about whether it even helps). No per-vendor parser tree. No trained model, no second OCR
engine, no confidence threshold (Vision misreads at confidence 1.00 - `pump-004`). **Nothing that
raises the number by guessing**: every ambiguity abstains, and under the new gate an abstention
costs you coverage while a wrong value costs you precision, which is the point.

## Tests

- `cd ios && swift test` is **1336 tests in 131 suites** right now. It must still pass and the
  count must rise. `DigitRepairTests` in particular must stay green.
- Per-fixture unit tests over `[String]` line arrays quoted from the dump: `pump-001` (separator
  lost on two of three), `pump-003` (all three lost, different divisors -> abstain unless the band
  pins it), `pump-005` (four board prices; the cross-check picks the last), `pump-010` (preset:
  `13.17 x 75.95 = 1000.26` against a printed `1000.00`, so the arithmetic legitimately does NOT
  close and must not be "repaired"), `pump-016` (idle -> nothing), `pump-034` (charged price on no
  board), `pump-057` (matched to `receipt-046`, so the paper is independent truth).
- **Mutation-check every load-bearing rule** and report each: the mutation, the test that failed,
  and confirmation the file was restored byte-identical. Vacuous traps: asserting non-nil rather
  than the VALUE; a scale-search test whose candidates admit only one scale anyway; an abstention
  test that would pass with the whole path disabled.
- Re-measure and update `Spike/ReceiptSpike/fixtures/high-water.json` (numbers **and** a `_note`)
  and `PumpPhotoGate`'s measured constants - `measuredCommitted`, `measuredCommittedCorrect`,
  `measuredNumericHits`. The ratchet asserts them against the live score, so it will tell you.

## The baseline gate - judged by exit code

    cd ios && swift build      # 0
    swiftlint lint             # from the REPO ROOT, 0 errors
    cd ios && swift test       # 0, count risen

Report all three from `echo $?`.

## If you run short of budget

The tokenizer plus the scale search is the majority of the gain - land that, with its tests, before
the label anchors. Save as you go; the last run lost its B2 entirely.

## Report back

The three exit codes and the test count; pump precision, coverage and numeric hits before and after;
**the receipt number, which must still be 187/220**; which fixtures moved and which correctly
abstain; what you took from the preserved partial and what you rejected; how you kept
`DigitRepairTests` green; every mutation check; and anything you chose not to do.
