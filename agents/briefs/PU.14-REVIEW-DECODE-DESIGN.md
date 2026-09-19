# PU.14-REVIEW-DECODE-DESIGN - review the end-to-end decode and gate design BEFORE it is built

**Read-only.** You write exactly ONE file: `agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md`. No
code. No `/tmp`.

## What this is

The pump reader (`docs/EXTRACTION.md` → "The pump reader" - read first) has a classifier that
emits 8 segment probabilities per glyph cell (`ml/pump-reader/src/pump_reader/model.py`,
`REPORT.md` for its numbers: per-segment ~0.83 on aligned real cells, per-glyph 0.40, per-window
~0). What is NOT built yet is `docs/TASKS.md` → **PU.5**: row assignment (which window is total /
volume / price), decimal recovery (the display drops the point; `volume × price = total` picks
the placement), digit repair, and wiring into `PumpPhotoGate` (`ios/Sources/TankbookCore/Config/
PumpPhotoGate.swift`: precision ≥ 0.99 on committed numeric cells, coverage ≥ 0.60), then into
the `.pump` extraction source and the Confirm pre-fill (hard rules 13 and 15 in `CLAUDE.md`: a
value is a suggestion the user edits; typing is a peer path; a confident wrong value is worse
than nil).

What exists that the decode must compose with: `ios/Sources/TankbookCore/Extraction/CrossCheck.swift`
(the four-outcome arithmetic cross-check), `DigitRepair.swift` (P2.13: a fixed seven-segment
confusion table used to repair a digit so the cross-check closes), `PumpExtractor.swift` (the
Vision-OCR pump parser, kept as is), `ExtractionAssembler.swift`, `ConfirmPrefill.swift`, and the
corpus scorer in `ios/Tests/TankbookCoreTests/AccuracyRatchetTests.swift` with
`Spike/ReceiptSpike/fixtures/pump/expected.csv` (blank cells are unscored; two idle pumps show
0.00; three fixtures show a grade board not a transaction price).

## What to review, with a concrete proposal each

1. **The decoder's output contract.** Given 8 sigmoids per cell, what should the reader hand to
   the decoder: the argmax digit, a ranked list of digits with posteriors, or the raw 8
   probabilities? Show how each interacts with `DigitRepair` (fixed table today) and the
   cross-check. Propose the interface (Swift types) and the abstain rule per glyph.
2. **Decimal recovery.** The display shows `2038,00` / `0040,00` / `050,95` (pump-009) or drops
   the point entirely on some makes; prices have 2 or 3 decimals by country; totals get
   truncated (`3765,7`). Define the candidate set and the search: which placements are tried,
   how the "unique solution" rule works with a per-glyph posterior, what "not unique → nil" does
   to coverage. Use the corpus (`expected.csv`) to estimate how often the arithmetic is
   ambiguous (pump-003 has 12 valid solutions; pump-031 does not multiply out by design).
3. **Row assignment.** Layout (total above volume above price on most heads; boards of four
   prices; Russian labels) vs arithmetic vs the classifier's own confidence. What should happen
   on an idle pump (0.00 / 0.00), on a preset-amount fill (total round, volume derived), and on
   a four-price board where none matches (pump-051)?
4. **`PumpPhotoGate` semantics for a reader that abstains per glyph.** The gate scores
   "committed cells"; define committed for the new reader (a field is committed when …), and
   whether precision-on-committed + coverage-floor is still the right pair, or whether the gate
   needs a per-field abstention rate and a "no confident-wrong on the named fixtures" clause.
   Say how the ratchet test should be extended so the reader lands on the same ratchet as the
   rules parser (53/320 today).
5. **Interaction with the cloud arm and manual entry.** The gateway (`/extract`) reads pumps
   at 31/46 with confident swaps. When both the reader and the cloud return, who wins, what is
   shown, and how does hard rule 15 (two doors) hold on the Confirm screen? Read
   `docs/JOURNEYS.md` J4 and `docs/ERRORS.md` for the pump-photo rows before answering.
6. **Sequencing.** PU.5 is filed as one row. Split it into rows that each move one measurable
   number, in order, with the number each moves.

## Report

`agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md`: the proposals with types and rules, worked on at
least four named fixtures (pump-009, pump-003, pump-031, pump-051), the gate definition, the
row split, and **"What I would need to know or have"** - ranked questions to the product owner
(e.g. is a per-field abstention acceptable UX, is the 0.60 coverage floor per field or per
photo, which countries' decimal conventions must v1 handle).
