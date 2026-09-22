# PU.57 - Re-gate the row detector on the metric the read stage consumes

Row: `docs/TASKS.md` -> PU.57. Source: `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §5
item 4. **This row ships no model and trains nothing.**

## Where you may write

`ml/pump-reader/detector/measure.swift`, `docs/EXTRACTION.md` (the detector gate, inside decision
10's amendments), `ml/pump-reader/REPORT.md` (a dated PU.57 section), `ml/pump-reader/tests/`
(a test for the ordering rule if you put the rule in Python - say where you put it and why).
**Nothing under `Spike/`, `ios/Sources`, `ios/App/Resources` or `tools/pump-annotate/`.**
Scratch: `ml/pump-reader/.out/pu57/`.

## What exists (read first, in order)

1. `ml/pump-reader/REPORT.md` -> the PU.33 section (how the detector was measured: recall@0.5,
   recall@0.7, median IoU, false rows/photo, photos-with-any-row, photos-with-every-row) and the
   PU.48 section (the candidate's table, and the gate it passed).
2. `ml/pump-reader/detector/measure.swift` - what it computes and prints today.
3. `agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §1 (detector case) and §5 item 4 - the
   argument: the read stage consumes framing, not overlap, and round 4 measured that framing alone
   moves digit accuracy by a third.
4. `docs/EXTRACTION.md` -> decision 10 and its amendments - where the gate is written down.

Confirm the numbers before writing the doc: re-run `measure.swift` on both models yourself
(`ios/App/Resources/DigitRows.mlmodel` and `ml/pump-reader/.out/det/pu48/DigitRows-pu48.mlmodel`)
against the heldout stills and reproduce the table. If your numbers differ from the report's, yours
are the ones that count - say so.

## What to build

1. **`measure.swift` reports the gate's numbers first**: median IoU and recall@IoU 0.7 as the
   primaries, false rows/photo beside them, recall@0.5 kept as a secondary. One summary line a
   human can paste into the report, plus the per-still lines it already prints.
2. **The gate, written into `docs/EXTRACTION.md`** under decision 10: a detector candidate ships
   only when **median IoU and recall@0.7 both hold or rise** and **false rows/photo does not rise
   by more than 0.05**; recall@0.5 is reported but never decides. State the reason in one sentence
   (the read stage consumes framing) and cite PU.48 as the evidence.
3. **The proof**: re-score PU.48's candidate under the new gate and record in `REPORT.md` that it
   would have been **REFUSED** (recall@0.7 0.734 -> 0.706, median IoU 0.797 -> 0.772, false rows
   0.632 -> 0.824), against the old gate that passed it on recall@0.5 0.869 -> 0.877.

Out of scope: training a detector, shipping a model, the slicer, the law.

## Tests you must add

A test for the ordering rule, with a synthetic pair of predictions against the same truth: one set
of **tight** boxes (high IoU, fewer false rows) and one **loose but overlapping** set that scores
higher on recall@0.5 and lower on recall@0.7 and median IoU. The new gate must prefer the tight
one; assert also that the OLD rule (recall@0.5 alone) would have preferred the loose one - that
contrast is the row's point, not a formality.
**Named mutation**: make the gate read recall@0.5 as its primary - the ordering test goes red.
Paste red-then-green.

## Checks

`ml/pump-reader/.venv/bin/pytest -q ml/pump-reader/tests` exit 0 with count (if the rule is in
Python); `swift ml/pump-reader/detector/measure.swift ...` exit 0 twice with both tables;
`swiftlint lint` from the repo ROOT exit 0 (`measure.swift` is a script, not in a target - say
whether lint covers it). Verify by exit code.

## Vacuous traps

Changing the number the report prints without changing the gate the doc states. Re-training
anything. Declaring PU.48 refused without re-measuring both models yourself. A synthetic pair so
extreme that both gates order it the same way (then it proves nothing).

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green, both measured tables, the
gate text as it now reads in `EXTRACTION.md`, and anything found and not fixed.
