# PU.69 completeness review, fourth pass - row angle by a fast Hough transform, with a confidence

Run of `agents/briefs/REVIEW-COMPLETE-PU.69-4.md` (template `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Read-only except this file. Scope per the brief: **the two one-line residuals review 3 left, and
nothing else** - items 1-5 and 7 were MET in `agents/reviews/PU.69-COMPLETENESS-3.md` and are
carried, soundly: the only edits since review 3 verified the tree are the two fixes themselves
(`PumpRowDeskewCorpusTests.swift`, `docs/TASKS.md`, `docs/EXTRACTION.md`, all mtime 05:35); the
behaviour-carrying sources `PumpFastHough.swift` (04:50), `PumpRowDeskewTests.swift` (04:58) and
`PumpRowDeskew.swift` (04:59) are untouched since before review 3's own 10/10 run, and the
corpus-test edit is comment-only (every line-number citation review 3 made in that file still
holds: Wilson print `:44-47`, F6 test `:62-95`, its empty-set expectation `:94`).

**Evidence I generated myself** (all read-only; no builds, no test runs, no `PumpReadTool` - both
residuals are text-and-artefact questions, so there was nothing to measure and the machine-load
caveat does not arise):

- `grep -n "PU\.70"` over the four code files in the diff: **no match, exit 1**.
- `grep -n "ms/row\|ms per row" /tmp/agentlogs/pu69-*.log` and an exhaustive
  `grep -l "PU.69 deskew" /tmp/agentlogs/*.log`: the only deskew timing lines anywhere are
  **2.8** (`pu69-corpus-no-interp.log:33`), **8.4** (`pu69-corpus-release-oldsweep.log:374`),
  **2.9** (`pu69-corpus-release.log:377`), **3.1** (`pu69-corpus-with-interp.log:386`). No new
  artefact has been captured since 04:59 (`pu69-mutation-fusion.log`), i.e. review 3's option (b)
  - a quiet-machine log reading 2.7 - was not taken; the fix claim is option (a), the printed span.
- Read the full PU.69 row cell (`docs/TASKS.md:1072`, awk + tr extraction) and
  `docs/EXTRACTION.md:1105-1132` directly.
- `python3 scripts/tasks-index.py --check` exit **0**; `python3 scripts/scenario-index.py --check`
  exit **0** ("PASS: 528 rows") - the 05:35 row edit did not disturb either index.
- `swiftlint lint --no-cache` on the edited `PumpRowDeskewCorpusTests.swift`: exit **0**, four
  warnings, all the pre-existing species review 3 already accepted (`line_length` 133 at `:48`,
  single-letter `identifier_name` at `:48,89`); the comment reflow added none.
- `git status` / mtimes for the commit-hygiene carry-over below.

## Residual 1 - the stale PU.70 comment: MET (closed)

`ios/Tests/TankbookCoreTests/PumpRowDeskewCorpusTests.swift:58-61` now reads: "PU.69's F6: whether
the estimator's confidence separates a good angle (within 1 deg of the drawn one) from a bad one
(more than 2 deg off), on the TRAIN split, **where a threshold on it would be fitted**." Row-free,
present tense, states the purpose without naming a consumer - exactly the alignment review 3 asked
for with the sibling at `PumpRowDeskew.swift:60-61` ("exposed for a threshold fitted on the train
split", verified still row-free). No `PU.70` remains in any of the four code files (grep exit 1).
The `PU.69` / `agents/research/PU.69.md` F-number pointers in the same file's comments follow the
tree's standing row-id precedent, which reviews 1-3 accepted; the violation was specifically naming
a `[cut]` row (`docs/TASKS.md:1073`) as the test's purpose, and that text is gone. CLAUDE.md
current-truth rule satisfied.

## Residual 2 - the printed latency floor: PARTIAL (two of three occurrences fixed, one survives)

**Fixed, verified digit-for-digit against the artefacts:**

- `docs/TASKS.md:1072`, the Measured sentence: "**8.4 -> 2.9-3.1 ms per row across the logged
  Release runs of the shipped estimator (the no-refinement variant read 2.8), some with training
  running (FHT: `/tmp/agentlogs/pu69-corpus-release.log`, `pu69-corpus-with-interp.log`,
  `pu69-corpus-no-interp.log`; the 8.4 ms sweep: `pu69-corpus-release-oldsweep.log`)**" - this is
  review 3's option (a) in full: the span matches the captured shipped-estimator runs exactly
  (2.9 at `release.log:377`, 3.1 at `with-interp.log:386`), the 2.8 is correctly excluded from the
  span and attributed to the no-refinement variant (`no-interp.log:33`), the 8.4 is attributed to
  the sweep (`oldsweep.log:374`), and every log is named individually rather than by glob. The
  brief's fourth-pass claim holds for this sentence.
- `docs/EXTRACTION.md:1120-1121`: "**8.4 -> 2.9-3.1 ms per row** (the logged Release runs of the
  shipped estimator, some with training running)." Same span, consistent scoping ("shipped
  estimator" excludes the 2.8 variant), no 2.7 anywhere in the file (grep).

**Not fixed - the same defect, third occurrence, same row.** `docs/TASKS.md:1072`, in the
"Completeness review 1 INCOMPLETE, closed" narrative near the end of the cell:

> "The refusal-path latency promise is re-homed to PU.67's gate (it only exists where the retry
> runs); **this row's evidence is the per-row step, 8.4 -> 2.7 ms.**"

- **2.7 is in no artefact.** My exhaustive grep (above) confirms review 3's finding on the final
  log set: the only deskew timings ever captured are 8.4 / 2.9 / 3.1 / 2.8. The 2.7 traces to the
  orchestrator's original uncaptured gate run (review 3 reconstructed its provenance; nothing new
  has been captured since).
- **The sentence is present tense, not a historical quote.** It states what the row's evidence IS
  ("this row's evidence is the per-row step, 8.4 -> 2.7 ms"), so it cannot be defended as a record
  of what an earlier draft printed - and review 3's fix 2 named `docs/TASKS.md:1072` as a location
  printing the untraceable floor. It still does.
- **The row now contradicts itself.** Two thirds of the same cell above, the Measured sentence says
  2.9-3.1 with the logs named; the closure sentence says 2.7. A reader cannot tell which is the
  row's number, and one of them matches nothing.

This is the whole of the gap. Review 3's fix 2 exists because printed numbers must match their
artefacts; the fix closed the two occurrences review 3 quoted and missed this one. No conclusion
changes - the speedup is 2.7-3.0x on captured numbers alone, the re-home to PU.67 is unaffected,
and no new measurement is needed.

## Carried items (unchanged, not re-litigated)

Items 1-5 and 7 stand as review 3 ruled them MET, including the refinement-pin judgment (its item
5), the A1/A7/A8 rulings, the 47/47 livePath floor on the composite tree, the two red floors as
pump-275 corpus state, and the Checks-cell walkthrough. The single sentence review 3's item 7.5
was waiting on ("the printed floor needs the one-word reconciliation") is the PARTIAL above.

## Verdict: INCOMPLETE

One one-word fix; nothing else stands between this row and COMPLETE.

1. **Align the surviving 2.7 with the captured span.** `docs/TASKS.md:1072`, closure sentence:
   "this row's evidence is the per-row step, 8.4 -> 2.7 ms" - change to "8.4 -> 2.9-3.1 ms" (or
   drop the number and point at the Measured sentence, e.g. "the per-row step measured above").
   Then re-dispatch this review (fresh copy, same row); the re-run needs to verify that one string
   and nothing else. No gap here needs a new row.

Found and not fixed, with owners named (all carried from review 3, re-confirmed against the
current tree):

- **Commit hygiene (orchestrator, blocking for the commit, not for this row's verdict):**
  `Spike/ReceiptSpike/fixtures/corpus.sqlite` is still **staged** (`git status`: `MM`) with
  `windows.json` and the three `pump-live/` files modified - owner-annotator state, none of it
  PU.69's. Unstage the sqlite; commit only the six PU.69 files (`PumpFastHough.swift`,
  `PumpRowDeskew.swift`, `PumpRowDeskewTests.swift`, `PumpRowDeskewCorpusTests.swift`,
  `docs/EXTRACTION.md`, `docs/TASKS.md`); do not let the working-tree `windows.json` ride along
  (its pump-275 state is what reddens the two floors; on the committed corpus they are green per
  PU.78's evidence).
- **PU.67's open row** still describes the retired sweep in its body; its dated 2026-09-24 note
  corrects the record, and the row text should be updated when it reopens (its re-measure also
  discharges PU.81's guard and the re-homed refusal-path latency in one run).
- **Review 1's fix 7** (a formal owner OK for the power-of-two input padding in place of the
  note's FHT2DS/2DT plan) remains the orchestrator's call; reviews 1-3 all judged it needs none -
  it is the published base algorithm's own `n = 2^q` domain (note §2.2), disclosed in the row.
- Non-blocking, unchanged: the full package suite (04:00) predates the final four unit tests -
  accepted on review 3's fingerprint argument plus its own 10/10 run; the new code's four lint
  warnings are the file's own precedent species; two test comments duplicate accuracy scores that
  CLAUDE.md would prefer as links (both carry authority pointers).
