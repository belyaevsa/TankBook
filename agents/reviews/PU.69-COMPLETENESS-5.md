# PU.69 completeness review, fifth pass - row angle by a fast Hough transform, with a confidence

Run of `agents/briefs/REVIEW-COMPLETE-PU.69-5.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Read-only except this file. Scope per the brief: **the one string review 4 left, and nothing
else** - "verify that string, and that no '2.7 ms' for PU.69 remains in `docs/TASKS.md` or
`docs/EXTRACTION.md`." Items 1-5 and 7 were MET in `agents/reviews/PU.69-COMPLETENESS-3.md`,
carried by review 4, and are carried again here on the same footing review 4 used: the only file
in the diff touched since review 4 verified the tree is `docs/TASKS.md` (mtime 05:46:24);
`docs/EXTRACTION.md` (05:35:58), `PumpFastHough.swift` (04:50:39), `PumpRowDeskew.swift`
(04:59:09), `PumpRowDeskewTests.swift` (04:58:36) and `PumpRowDeskewCorpusTests.swift`
(05:35:42) are all byte-identical in time to what review 4 examined. No behaviour-carrying
source moved, so there was nothing to rebuild or re-run, and no measurement question arose:
I ran no builds, no tests and no `PumpReadTool`, and the machine-load caveat does not apply.

**Evidence I generated myself** (all read-only):

- `grep -n "8\.4 -> 2\.9-3\.1\|2\.9-3\.1 ms" docs/TASKS.md docs/EXTRACTION.md`: the span prints
  exactly twice - `docs/TASKS.md:1072` (the Measured sentence) and `docs/EXTRACTION.md:1120` -
  plus once more inside the row's closure sentence (same line 1072).
- `grep -n "2\.7" docs/TASKS.md docs/EXTRACTION.md`: five hits, **all the unrelated row id
  `P2.7`** (`docs/TASKS.md:759, 788, 880, 955, 1011`); zero hits in `docs/EXTRACTION.md`
  (`grep -c` prints 0, exit 1). The targeted residue grep
  `grep -n "8\.4 -> 2\.7\|2\.7 ms" docs/TASKS.md docs/EXTRACTION.md` exits **1** - no match.
  For belt and braces, `grep -n "2\.7"` over the four code files in the diff also exits **1**.
- `grep -n "ms/row\|ms per row" /tmp/agentlogs/pu69-*.log`: the deskew timing artefact set is
  unchanged since review 4 enumerated it - **2.8** (`pu69-corpus-no-interp.log:33`), **8.4**
  (`pu69-corpus-release-oldsweep.log:374`), **2.9** (`pu69-corpus-release.log:377`), **3.1**
  (`pu69-corpus-with-interp.log:386`). No new log has appeared (newest pu69 artefact is still
  `pu69-mutation-fusion.log`, 04:59). 2.7 is in no artefact, and after this fix it is in no doc.
- Read the PU.69 row cell (`docs/TASKS.md:1072`, awk extraction) and `docs/EXTRACTION.md:1105-1132`
  directly; compared the row's Measured sentence and the EXTRACTION paragraph against review 4's
  verbatim quotes - identical, so the 05:46 edit changed the closure sentence and nothing else
  in the row.
- `python3 scripts/tasks-index.py --check` exit **0**; `python3 scripts/scenario-index.py --check`
  exit **0** ("PASS: 528 rows") - both still green after the 05:46 row edit.
- `git status --porcelain` for the commit-hygiene carry-over below.

## The residual - the closure sentence's "8.4 -> 2.7 ms": MET (closed)

`docs/TASKS.md:1072`, in the "Completeness review 1 INCOMPLETE, closed" narrative, now reads:

> "The refusal-path latency promise is re-homed to PU.67's gate (it only exists where the retry
> runs); **this row's evidence is the per-row step measured above, 8.4 -> 2.9-3.1 ms.**"

This takes **both** remedies review 4 offered in one: the number is corrected to the captured
span, and "measured above" points the reader at the Measured sentence that names the logs.
Digit-for-digit against the artefacts: 2.9 at `pu69-corpus-release.log:377`, 3.1 at
`pu69-corpus-with-interp.log:386`, 8.4 at `pu69-corpus-release-oldsweep.log:374`; the 2.8 stays
correctly outside the span, attributed to the no-refinement variant in the Measured sentence
(`pu69-corpus-no-interp.log:33`). The row no longer contradicts itself - all three of its latency
printings (Measured sentence, closure sentence, `docs/EXTRACTION.md:1120-1121`) say 8.4 -> 2.9-3.1
with the same "shipped estimator" scoping. Every printed deskew number in the two docs now traces
to a named log. Review 4's sole PARTIAL is closed; its own words stand - no conclusion changes,
the speedup is 2.7-3.0x on captured numbers alone, and no new measurement was needed.

## Carried items (unchanged, not re-litigated)

Items 1-5 and 7 stand as review 3 ruled them MET and review 4 carried them: the A1/A7/A8 rulings
(96 px strip under A1's named fallback; `rowSize`/`largeTurn` kept for OUTPUT sizing only;
height + width padding satisfying A8 by never wrapping, pinned by `transformDoesNotWrap` and its
red mutation), the Algorithm-1 fidelity and sign convention, the refinement-pin judgment, the
47/47 livePath floor on the composite tree, the two red floors as pump-275 corpus state (the
owner's annotator has it open with its `reviewed` flag cleared - 67 stills / 181 cells instead of
68 / 183 - not this diff), F6's AUROC 0.653 / 0.689 / 0.700 on the TRAIN split, the leak argument
(`decideAt` never calls deskew), the app-path-live check re-homed to PU.67's re-measure with the
row text saying so plainly, and the full Checks-cell walkthrough. The one sentence review 3's
item 7.5 waited on and review 4 held PARTIAL is the MET above.

## Verdict: COMPLETE

Every item MET. The orchestrator may commit - subject to the hygiene note below, which blocks the
commit's contents, not this row's verdict. No gap needs a new row.

Found and not fixed, with owners named (all carried from review 4, re-confirmed against the
current tree):

- **Commit hygiene (orchestrator, blocking for the commit):** `Spike/ReceiptSpike/fixtures/
  corpus.sqlite` is still **staged** (`git status`: `MM`) with `windows.json` and the three
  `pump-live/` files modified - owner-annotator state, none of it PU.69's. Unstage the sqlite;
  commit only the six PU.69 files (`PumpFastHough.swift`, `PumpRowDeskew.swift`,
  `PumpRowDeskewTests.swift`, `PumpRowDeskewCorpusTests.swift`, `docs/EXTRACTION.md`,
  `docs/TASKS.md`); do not let the working-tree `windows.json` ride along (its pump-275 state is
  what reddens the two floors; on the committed corpus they are green per PU.78's evidence).
  Note `docs/TASKS.md` also carries the concurrent PU.78/PU.72/PU.81 edits - stage the file
  knowingly, per the owner's sequencing for those rows.
- **PU.67's open row** still describes the retired sweep in its body; its dated 2026-09-24 note
  corrects the record, and the row text should be updated when it reopens (its re-measure also
  discharges PU.81's guard and the re-homed refusal-path latency in one run).
- **Review 1's fix 7** (a formal owner OK for the power-of-two input padding in place of the
  note's FHT2DS/2DT plan) remains the orchestrator's call; reviews 1-4 all judged it needs none -
  it is the published base algorithm's own `n = 2^q` domain (note §2.2), disclosed in the row.
- Non-blocking, unchanged: the full package suite (`pu69-swifttest.log`, 04:00, 2285 tests)
  predates the final four unit tests - accepted on review 3's fingerprint argument plus its own
  10/10 run; the new code's four lint warnings are the file's own precedent species; two test
  comments duplicate accuracy scores that CLAUDE.md would prefer as links (both carry authority
  pointers).
