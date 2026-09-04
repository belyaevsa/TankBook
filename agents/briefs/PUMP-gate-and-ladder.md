# Pump B1 + B2: fix the instrument, then let the digits through

Design and implement, in that order. Code first, exploration second.

This is tracks **B1** and **B2** of `diagnostics/EXTRACTION-PLAN.md`. Four independent analyses
back it: `diagnostics/RESEARCH-pump-{vision,kimi,pro,qwen}.md`. Read the plan and at least
`RESEARCH-pump-pro.md` and `RESEARCH-pump-kimi.md` before writing code; they carry the per-fixture
evidence this brief only summarises.

## Where you work

    /Users/sbelyaev/repos/fuel-counter-ios/.claude/worktrees/rv48   (branch rv48-local-extraction)

Write only inside it. **Never `cd` to the main checkout** - another session is live there.
**Run no `git` command**; leave the work uncommitted. Do not touch `docs/TASKS.md`,
`agents/briefs/`, any `expected.csv`, or any fixture image.

**Never `pgrep -f`** - your brief is your command line, so it matches you. Use `pgrep -x`.

## The state

Pump scores **53/261 cells (20%)** and the mode ships **off** behind a 95% gate. Receipts, in the
same parser, score **187/220 (85%)** after four days of work today.

**The 20% is not the number.** Of the 261 cells, `currency` (66) is read from a printed `€`/`РУБЛИ`
marker and is nearly free; `fuelKind` (17) is a column `docs/EXTRACTION.md` says a pump parser must
**never** fill - and the parser fills it anyway and is scored on it. On the three numbers the mode
exists to read, the score is **4/178 (2.2%)**, and the arithmetic cross-check passes **0/66**.

Regenerate evidence any time (this is the pump dump; it uses the Spike CLI, a separate package):

    cd Spike/ReceiptSpike && swift run ReceiptSpike fixtures/pump --dump-text

`diagnostics/pump-ocr-dump.txt` is the committed copy.

---

## B1. Re-scope the gate. Do this FIRST, and do not skip it

The gate is measuring the wrong thing, and all four analysts reached that independently.

**Recall inverts hard rule 13.** It scores a correct `nil` as a miss and a confident-wrong value as
a hit. On a pump the wrong value is not a bad suggestion - it is a wrong fill-up in the user's
history forever, and `expected.csv` deliberately leaves cells EMPTY where the photograph does not
carry the value. Worse: `pump-016` and `pump-017` are **idle pumps** whose ground truth is `0.00`,
so recall actively rewards returning a zero-litre fill - the exact bug hard rule 15 forbids.

Three changes:

1. **Score the pump class on its 178 numeric cells.** `fuelKind` must not be scored for pumps: the
   spec forbids inferring it, so scoring it rewards a violation. Do not edit `expected.csv` - the
   fuelKind ground truth stays as documentation of the paired receipts; the SCORER stops counting
   it for this class. Decide and state whether `currency` stays in the headline number or moves to
   a reported-separately line; argue it either way, but make it explicit.
2. **Add precision alongside recall.** Precision = of the numeric fields the parser returns
   **non-nil**, the fraction that are correct. Coverage = the fraction of numeric cells it commits
   to. Report all three; a class summary that hides precision is what let 20% look like progress.
3. **Re-base `PumpPhotoGate`** on precision plus a coverage floor rather than raw recall. The
   shape the analyses converged on: **commit only what is uniquely pinned; ship when
   committed-value precision is at or above ~99% and coverage clears a floor** (propose the floor;
   the analyses suggest 60-85% and the number is a product decision - state your recommendation and
   why, do not pretend it is derived).

The gate's contract is documented in `Spike/ReceiptSpike/fixtures/pump/README.md` ("The flag's
contract") and in `PumpPhotoGate.swift`'s own comments. **Update both in the same change**, and say
plainly that the threshold's *meaning* changed, not just its number. The mode stays **off**; nothing
in this brief turns it on.

**Receipts must not move.** They are at 187/220 and every change here is pump-scoped. If the receipt
number moves at all, that is a bug in your change.

---

## B2. The tokenizer, then a pump-shaped ladder

### The wall, verified in the source

`NumberScanner.decimals(in:)` (`Extraction/NumberScanner.swift:13`) matches
`(\d{1,3}(?:[ .]\d{3})*|\d+)[.,](\d{1,3})` - **the separator is mandatory**. A seven-segment display
routinely drops it, so Vision returns `12522`, `208863`, `8525`, `2450` at confidence 1.00 and the
tokenizer **discards them**. The digits are read and thrown away one layer down. That is why the
class is at 2.2%.

`numbers(in:)` does return bare integers, but the pump path never reaches it in a useful shape,
because - the second finding - **the pump path is the receipt parser with two switches**
(`FuelExtractor.extract` only skips fuel kind and enables `DigitRepair` for `source == .pump`).
Its operand pairing wants an `×`; `loneMarkers` wants an `L` or `/L`; the total finder wants an
`ИТОГ`/`SUMMA` label with a value on its baseline. **A pump prints three bare numbers under three
labels, in a fixed layout, with no operator.**

### What to build

A pump-source path that reads the display's own shape. The pieces the analyses agree on:

- **Separator-liberal tokens.** On `source == .pump`, a bare digit run is a candidate with an
  **unknown decimal scale**, not a number to discard. Keep the receipt behaviour unchanged.
- **Scale search, pinned.** Given candidates for volume, unit price and total, search the powers of
  ten that satisfy `volume x price ~= total` within the existing tolerance, then bound each operand
  by what is physically possible: a fuel volume by tank capacity, a unit price by the band pack the
  receipt path already ships (`FuelPriceBands.seed.json`, keyed by currency and era - the pump has
  a currency marker and often a date is absent, so say what you do then). **If more than one scale
  assignment survives, abstain** - the factor-of-ten ambiguity is real (`pump-003` loses all three
  separators) and a wrong scale is the worst outcome in this class.
- **Label and make anchors.** The make logo (`GILBARCO VEEDER-ROOT`, `Wayne`, `DRESSER`, `TOKHEIM`,
  `ADAST`, `ТОПАЗ`) and the field labels (`SUMMA`/`LIITRIT`/`HIND/1L`, `РУБЛИ`/`ЛИТРЫ`/`ЦЕНА`,
  `€/L`) survive in nearly every dump **including the bad ones** - qwen's finding, and the cheapest
  accuracy available. Use the labels to assign a number to a role by geometry rather than guessing
  by magnitude.
- **The price board is not the transaction.** Four grade prices with no meaning in their order; only
  the badge identifies them, and on several fixtures the charged price is on **no** board. A board
  price may rank a candidate; it must never become the unit price on its own.
- **Keep the cross-check and `DigitRepair`** exactly as they are - the cross-check is what picks the
  right price out of four on `pump-005`, and P2.13's repair is already pump-scoped.
- **Refuse the non-fills.** An idle pump (`pump-016`, `pump-017`: all zeros) must return nothing,
  never a zero-litre fill. The zero-litres guard RV.56 just landed helps; make sure the pump path
  cannot route around it.

### What NOT to build

- **No image work.** Cropping, upscaling, deskew and second-pass recognition are track **B3** and
  are deliberately out of scope: two analysts who opened the photographs disagree about whether
  they recover the decimal point, and that is an experiment to run separately, not a thing to
  assume here.
- **No per-vendor parser tree.** One forecourt already mixes two vendors and two separator
  conventions; a vendor branch is a maintenance trap. Vendor may select a *template hint*, never a
  parser.
- **No trained model, no second OCR engine, no confidence threshold** (Vision misreads at
  confidence 1.00 - `pump-004`).
- **Nothing that raises the number by guessing.** Every ambiguity abstains.

---

## Tests

- `cd ios && swift test` is **1334 tests in 131 suites** right now - check, trunk moves. It must
  still pass and the count must rise.
- Unit tests over `[String]` line arrays quoted from the dump, per named fixture: `pump-001`
  (separator lost on two of three), `pump-003` (all three lost, different divisors), `pump-005`
  (four board prices, cross-check picks the last), `pump-010` (preset: `13.17 x 75.95 = 1000.26`
  against a printed `1000.00`, so the arithmetic legitimately does NOT close - this must not be
  "repaired"), `pump-016` (idle, must refuse), `pump-034` (charged price on no board), `pump-057`
  (matched to `receipt-046`, so the paper is independent truth).
- **Mutation-check every load-bearing rule and report each**: the mutation, the test that failed,
  and confirmation the file was restored byte-identical. Vacuous traps: asserting a value is
  non-nil rather than asserting the VALUE; a scale-search test whose candidates only admit one
  scale anyway; an abstention test that would pass with the whole path disabled.
- Re-measure and update `Spike/ReceiptSpike/fixtures/high-water.json` (numbers **and** a `_note`
  in the existing style, saying what the new denominator means), `PumpPhotoGate`, and
  `CorpusCompressionTests` if it moves.

## The baseline gate - judged by exit code

    cd ios && swift build      # 0
    swiftlint lint             # from the REPO ROOT, 0 errors
    cd ios && swift test       # 0, count risen

Report all three from `echo $?`.

## If you run short of budget

**Land B1 complete before starting B2**, and save as you go. B1 alone is worth committing: it stops
the next measurement lying. In B2, the tokenizer plus the scale search is the majority of the gain;
label anchors can follow.

## Report back

The three exit codes and the test count; the pump numbers before and after under **both** the old
metric and the new one, so the change is legible; the receipt number (must be unchanged at
187/220); which fixtures moved and which correctly abstain; your recommended coverage floor and the
argument for it; every mutation check; and anything you chose not to do.
