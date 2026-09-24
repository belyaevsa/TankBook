# PU.72 completeness review - calibrate the classifier so the law's windows survive a retrain

*Run of `agents/briefs/REVIEW-COMPLETE-PU.72.md` (a copy of `REVIEW-PU-COMPLETENESS.md`), 2026-09-24.
Reviewing agent; read-only except this file. The diff under review: `ml/pump-reader/src/pump_reader/
temperature.py` (new), `ml/pump-reader/tests/test_temperature.py` (new), the erratum at the end of
`agents/research/PU.72.md`, and the PU.72 row (`docs/TASKS.md:1075`). The concurrent PU.78 edits
(`PumpReadingLaw.swift`, the pump tests, `PumpPhotoGate.swift`, `docs/EXTRACTION.md`) were excluded;
I verified none of them carries a hidden PU.72 claim: `git diff` over the Swift files contains zero
occurrences of "temperature", and neither `ios/Sources`, `ios/App/Sources`, `score.py`, `export.py`
nor `train.py` mentions it at all.*

**What I ran myself** (the machine may have been loaded by the concurrent PU.78 work; everything
reproduced exactly):

- `.venv/bin/python -m pytest -q -p no:cacheprovider` in `ml/pump-reader`: **53 passed, exit 0**
  (matches the gate evidence; `test_temperature.py` contributes 4).
- `.venv/bin/python -m pump_reader.temperature .out/train-r6-real/segmentnet.pt .out/real/cells.npz
  --out /tmp/pu72-review-r6.json`: **exit 0**, output byte-identical to `/tmp/pu72-r6-temperature.json`
  (T 0.5682, cells 25085, NLL 0.08081 -> 0.05885, ECE_conf15 0.0346 -> 0.0005, ECE_perlabel10
  0.0358 -> 0.0102, ECE_ML 0.0822 -> 0.0505, digitFlips 0).
- **My own independent re-derivation of the erratum** (`/tmp/pu72-review-ece.py`, written for this
  review; imports nothing from `temperature.py` - my own NLL, my own grid fit, my own Guo ECE, my
  own Henning ECE_ML with quantile bins; only the `SegmentNet` architecture is reused, as it must
  match the checkpoint).
- **Five mutations of the module in `/tmp/pu72-mut`** (copies; the repo was not written), because
  the gate evidence contains no mutation record.
- I did not need `swift run PumpReadTool`; no app-path number was missing, because no app-path
  number is claimed.

## The erratum, verified independently - the erratum is right, the note's original ECE columns are wrong

My own code, on the r6 train pool (`.out/real/cells.npz`, 25 085 cells), with my own fitted T
(0.5683; the fourth-digit difference from the module's 0.5682 is optimiser granularity - my grid
search vs its golden section):

| quantity | note §5.2 original | erratum / module | my independent re-derivation | verdict |
|---|---|---|---|---|
| ECE_conf15 before -> after | 0.2766 -> 0.0042 | 0.0346 -> 0.0005 | **0.0346 -> 0.0005** | erratum right; note exactly 8x too large (0.2766/8 = 0.03458) |
| ECE_ML before -> after | 0.4131 -> 0.4449 (worsens) | 0.0822 -> 0.0505 (improves) | **0.0822 -> 0.0504** | erratum right; my 4th-decimal difference is bin-edge handling (quantile cuts vs `array_split`) |
| ECE_perlabel10 before -> after | 0.0358 -> 0.0102 | unchanged by the erratum | (not re-derived; both sources agree) | consistent |
| NLL before -> after (train) | - | 0.08081 -> 0.05885 | **0.08081 -> 0.05885** | exact match |
| T | 0.5682 | 0.5682 | **0.5683** | match |

The erratum's diagnosis of its own scratch bugs also checks out against the scratch itself:
`/tmp/pu72-cal/fit.py:82` computes `n = len(p)` on the `(n, 8)` array (the 8x inflation), and
`/tmp/pu72-cal/fit.py:135` computes `abs(yk[g].mean() - ps[g].mean())` where `g` indexes the
one-sided subset `ps` (the wrong-label pairing). The F4 heldout-NLL figures come from
`/tmp/pu72-cal/held.py:40-41`, whose stable BCE form is identical to the module's
(`temperature.py:43-44`), so the erratum's claim that F4 stands on a correct function is
corroborated at source level (I did not rebuild the 873-cell heldout pool itself).

**Consequence, and a hole the erratum leaves open:** the erratum's first sentence invalidates "its
ECE columns in §5.2" - that is **both** the train and the heldout tables - but it recomputes only
train r6/r7/r8. **No corrected heldout ECE numbers exist anywhere** (the note's 0.1725 -> 0.0803 /
0.3857 -> 0.4025 etc. at `agents/research/PU.72.md:246-249` are invalid and unreplaced), and r9 /
r10-s0 / r11-control have no module-recomputed numbers at all. See item 7, sentence S2, and the fix
list.

## Item 1 - Fidelity to the published method: **MET** for the module; the closure path departs from the note's own protocol (scored under item 7)

`temperature.py` against the note's fence (A1-A8, `agents/research/PU.72.md:153-205`):

- **A1 shared T over eight sigmoids**: one scalar, `sigma(z/T)` (`temperature.py:129`). MET.
- **A2 fit on the TRAIN pool only**: the CLI takes a pool path; the runs used `.out/real*` train
  pools; nothing reads heldout (`temperature.py:158-166`). MET.
- **A3 fit by NLL, report ECE, never fit it**: `fit_temperature` minimises `nll` only
  (`temperature.py:48-59`); the three ECEs appear solely in `report` (:126-139). MET.
- **A4 three variants, tail-weighted among them**: Guo M=15 mass-weighted (:62-74), per-label
  fixed-width (:77-90), Henning ECE_ML unweighted bins, b=10, b_min=5 (:93-114). MET.
- **A5 per-label Platt / local T rejected**: absent from the module. MET.
- **A6 golden-section on log T over [log 0.05, log 20], 200 iters; stable loss forms**: exactly
  that (`temperature.py:48-59`), and `nll` never forms `log(0)` (:43-44). MET.
- **A7 no regularized Platt targets**: plain 0/1 labels (:165). MET.
- **The flip counter mirrors the Swift decoder exactly**: `digit_ranks` (:117-123) uses the same
  ten pattern constants as `PumpSegmentsModel.digitPatterns` (`PumpSegmentsModel.swift:18-22`,
  bit-for-bit identical), the same `[1e-6, 1-1e-6]` clamp on the first seven bits
  (`PumpSegmentsModel.swift:60`), and log-odds scoring - which differs from the Swift log-posterior
  (`PumpSegmentsModel.swift:61-67`) by a pattern-independent constant, so the argmax, which is all
  a "digit flip" is, agrees by construction. MET.

The unlisted departure is not in the method but in the **closure protocol**: the note pre-authorises
"the row closes as reporting-only" only behind F-benefit's measurement (`agents/research/PU.72.md:
351-354`: a candidate's train `measureLive` precision at the shared calibrated window vs its own
raw-fitted window, across a round's seeds). That measurement was never run; the row closed
reporting-only on the strength of F4 and the §3.1 theorem instead. Full judgement below, item 7.

## Item 2 - Wired into the app path: **MISSING as a fact - and the brief is right that this is the design**

Nothing ships to the app. Verified, not assumed: `grep -rni temperature` over `ios/Sources`,
`ios/App/Sources`, `score.py`, `export.py`, `train.py` returns zero hits; `PumpSegmentsModel.swift`
is untouched (no metadata read, no `sigma(z/T)` in `probabilities(cell:)`,
`PumpSegmentsModel.swift:41-52`); `export.py` writes no `temperature` key; no `.mlpackage` was
re-exported. `PumpDisplayCapture.classify` and `CapturePipeline` behave identically in Debug and in
Release because no code on either path changed. The instrument is reachable only from
`python -m pump_reader.temperature` and its tests - the harness-only shape the template calls
MISSING - and whether that is legitimate here is the row-specific judgement, answered under item 7
and the verdict: legitimate as to the *correction*, a departure needing the owner's OK as to the
*standardizer* the note planned to ship (§3.1, §3.3, §5.3).

## Item 3 - Measured on the app path, on the named population: **PARTIAL - app-path measurement absent by design; harness measurement reproduces exactly**

Say it plainly: **nothing ships to the app, so there is no app-path measurement and there cannot be
app-path movement.** The live-path floor was not re-run for this row and did not need to be: the
diff touches no Swift file. (The tree's current constants - `readerCommitted`/`readerCommittedCorrect`
47 (`PumpPhotoGate.swift:86,91`), `committedFloor` 118 (`PumpReaderPipelineTests.swift:30`) - are
the concurrent PU.78's movement, owned by that row's review, not this row's.)

Over the population the row *did* name (the TRAIN pools): gate evidence covers r6/r7/r8
(`/tmp/pu72-r6-temperature.json`, `/tmp/pu72-r7.json`, `/tmp/pu72-r8.json`; T 0.5682/0.5554/0.5622,
0 digit flips each, cells 25 085/25 349/28 428 matching the note's §5.1/§5.2 counts). I re-ran r6
end to end: byte-identical. **Zero new wrong readings**: 0 digit flips is the strongest form of
that for a decision-neutral change. Gaps: (a) the note claims 0 flips on **six** pools
(`agents/research/PU.72.md:110`), but only three were re-run with the shipped module - r9, r10-s0
and r11-control rest on the invalidated scratch for everything except T/NLL/flips; (b) no heldout
run of the module exists (see the erratum hole above); (c) PU.68 has landed, but the row reports no
precision point estimate (T, NLL, ECE and flips are not binomial precisions), so no Wilson interval
is owed.

## Item 4 - No regression elsewhere: **MET by construction, with the ML suite re-run**

The diff is Python-only (plus the research note's erratum and the TASKS row). No Swift, no app
target, no backend, no UI: the receipt leak, the annotated floor and the oracle ratchet cannot move
through it, and the concurrent PU.78 movement in the tree (live 45 -> 47, annotated 112 -> 118,
oracle 774/0.9987 per its row text) belongs to PU.78's review. The ML tier itself: 53/53, exit 0,
re-run by me. Latency: no hot path changed; the note's §7 device-latency clause is moot for a
reporting-only outcome, and the tranche's "latency numbers are Release numbers" rule has nothing to
bind. One committer obligation to note: the tree mixes PU.72 with PU.78, so the baseline Swift gate
(`scripts/gate.sh`) that TESTING.md requires before a commit will be run over the combined tree;
PU.72's own diff contributes nothing to it.

## Item 5 - Tests that would fail: **PARTIAL - the fit and the invariance are pinned; the two ECE bug classes from the erratum are not**

The gate evidence names no mutation, so I ran five myself on copies in `/tmp/pu72-mut` (repo
untouched), pytest per mutation, output verbatim:

| mutation | what it simulates | result |
|---|---|---|
| `ece_confidence` weights by `sel.sum() / (len(p) // 8)` | **re-introduces erratum bug 1** (the 8x inflation) | `4 passed in 1.25s` - **GREEN, not caught** |
| `ece_ml` uses `pk[group].mean()` (full column, subset indices) | **re-introduces erratum bug 2** (wrong-label pairing) | `4 passed in 1.20s` - **GREEN, not caught** |
| `fit_temperature` returns `1.0` | fit dead | `FAILED test_fit_recovers_a_known_temperature`, `1 failed, 3 passed` - red |
| `digit_ranks` rounds probabilities to 1 decimal before ranking | invariance broken (the F-impl class) | `FAILED test_a_shared_temperature_changes_no_digit_ranking`, `FAILED test_report_is_well_formed_and_flips_nothing`, `2 failed, 2 passed` - red |
| `report` swaps the NLL before/after order | report incoherent | `FAILED test_report_is_well_formed_and_flips_nothing`, `1 failed, 3 passed` - red |

Why the two greens are structural: the only ECE test
(`test_temperature.py:39-42`) uses a perfectly-calibrated certain predictor, whose per-bin error is
exactly 0 - every weighting and every indexing scheme multiplies or averages zeros. The suite pins
the fit, the ranking invariance and the report's coherence, but **the functions the erratum was
about are pinned by nothing**; the erratum's bugs were caught by the orchestrator's manual
re-derivation (and now by mine), not by any test that would fail on their return. Fix: one fixture
with small hand-computable nonzero, asymmetric ECE values (or a golden pin of the r6 erratum
numbers), mutated red for both bug classes, log kept.

## Item 6 - Docs reconciled: **PARTIAL**

- `docs/EXTRACTION.md`: no PU.72 mention, in the file or in the PU.78 diff. For a reporting-only
  outcome that changes no pipeline behaviour and no numbered decision, silence is defensible; the
  instrument's home is the research note plus the TASKS row. **But** the moment PU.73 "judges
  candidates" in this unit, the comparison unit belongs wherever candidate judgement is specified;
  today that is only PU.73's Checks phrase "after PU.72's calibration" (`docs/TASKS.md:1076`).
- `docs/TASKS.md:1075`: the Built text carries the result, the numbers (T, flips, ECE_ML, the NLL
  transfer figure) and the erratum - verified accurate against the artifacts and my re-derivation,
  including "4 pytest cases, the ML suite 53/53". What it does not carry is a plain list of the
  dropped Checks promises; see item 7.
- `docs/ERRORS.md`, `docs/JOURNEYS.md` J4/F2: correctly untouched - no user-visible change.
- CLAUDE.md comment rules in the touched files: `temperature.py`'s docstring states current truth,
  distinguishes itself from `calibrate.py` (the note §3.2 hazard), and cites the research note by
  path and section - the established idiom of this subtree (`dataset.py:3,18,122`, `calibrate.py:53`,
  `calibration.py:1` all cite PU rows); no completion evidence, no dates, no before/after story.
  The test comments explain the non-obvious clamp constraint (`test_temperature.py:22-23`). MET.
- The research note itself: the erratum is appended and signed, but §5.2's heldout ECE columns and
  the r9/r10/r11 train ECE columns remain invalid in place with no replacement numbers (the erratum
  recomputed only r6/r7/r8 train). A note whose invalidated half is not restated or struck is not
  reconciled. Fix item 5 below.
- `ml/pump-reader/README.md` / `REPORT.md`: no mention of `temperature.py` or the fitted T values.
  The README is renderer-scoped (it never listed `score.py`/`train.py` either), so this is
  consistent drift, not introduced by this row; noted, not required.

## Item 7 - Everything the row promised, sentence by sentence (`docs/TASKS.md:1075`, Checks cell)

- **S1a "A temperature fitted on the TRAIN split per exported model"** - **PARTIAL**. Fitted and
  module-verified for r6/r7/r8; r9, r10-s0 and r11-control have T values only from the note's
  scratch table (T unaffected by the erratum, but not re-run with the shipped module). "Per
  exported model" reads strictly against 13 exported mlpackages in `.out/` (`train-r6-real` through
  `train-r11-step3-s0`); the note measured six pools in scratch, the module re-ran three.
- **S1b "stored with it"** - **MISSING**. `find ml/pump-reader/.out -name temperature.json` returns
  nothing: no fitted T sits beside any checkpoint. The artifacts are `/tmp/pu72-*.json` - volatile;
  a reboot erases the row's outputs. The Built text's "written to `temperature.json` beside the
  checkpoint" describes the CLI's default (`temperature.py:169`), not what the row's runs did (the
  gate evidence's outputs are all in `/tmp`). The note §3.3 also asked for a mirror in
  `runs/<date>/metrics.json`; `runs/2026-09-23/` holds only a pump-014 trace directory from the
  concurrent 2026-09-23 work.
- **S1c "applied in `PumpSegmentsModel`"** - **MISSING by deliberate decision**, stated in the row
  with two measured reasons. Legitimacy: item 1 and the judgement below.
- **S2 "ECE before/after on train and heldout cells"** - **PARTIAL**. Train: done for r6/r7/r8,
  reproduced by me. Heldout: the note's columns are invalidated by its own erratum and were never
  recomputed; no heldout run of the module is in the gate evidence. The promise named heldout
  explicitly; the corrected record does not contain it.
- **S3 "the law's windows restated in calibrated nats and re-derived on train, never heldout"** -
  **MISSING**. No restatement (`PumpReadingLaw.swift`'s nat literals are untouched *by this row*),
  no re-derivation sweep of `(readWindow, ambiguityWindow, decimalMarkPenalty)`. Follows from not
  shipping (restatement without application is meaningless), but the row text never says this
  promise was dropped - a reader must infer it from "changes no decision of the law".
- **S4 "the shipped round 6 keeps live 54/54 (or PU.67's count) and the oracle ratchet"** - **MET
  by construction**: zero app-path diff, so the floors cannot move through this row; they were
  consequently not re-measured in the gate evidence, which is acceptable only because item 4's
  no-Swiss-change verification holds. (The row's "54/54" was already stale when written - the count
  was 45/45 at `b42f38da`, now 47/47 under PU.78; the "(or PU.67's count)" hedge covers it.)
- **S5 "then a round-7 candidate scored under both - the row is proven when a retrain no longer
  lowers live for calibration alone"** - **MISSING, and this is the promise the row's own proof
  sentence hangs on**. No candidate was scored under both windows; the F-benefit measurement
  (`agents/research/PU.72.md:351-354`) that authorises a reporting-only closure was never run,
  though it was runnable at build time (r7-r11 checkpoints and seeds exist in `.out/`). The Built
  text redirects it ("serves as the comparison unit PU.73's candidates are judged in") but PU.73's
  Checks (`docs/TASKS.md:1076`) do not carry a two-window comparison, do not name `temperature.py`
  or `temperature.json`, and give no wiring task - the proof obligation currently has **no owner**.
  This is the criterion-7 shape exactly: a promise quietly dropped, plus a handoff the receiving
  row does not record.

## The row-specific judgement: legitimate reading, or departure needing the owner's OK?

**Split the decision in two, because the note does.**

1. **Not shipping T as a correction: legitimate, fully pre-authorised by the note.** F4 measured
   that the train-fitted T worsens the shipped model's heldout NLL (0.14912 -> 0.15559; the erratum
   confirms the NLL function was correct, and I confirmed the function's form at
   `held.py:40-41` = `temperature.py:43-44`), and the F-transfer falsifier (`agents/research/
   PU.72.md:348-350`) disclaims absolute-calibration shipping in advance: "the row's claim is the
   weaker, true one". The erratum strengthens rather than weakens this: corrected in-sample ECEs all
   improve under sharpening, but the transfer failure - the only number that speaks to shipping -
   stands. No owner OK is needed for this half.

2. **Not shipping T as the unit standardizer either, and closing reporting-only without running
   F-benefit: a departure from the note's planned build and its closure protocol.** The note's
   mapping is indicative, not optional: calibration "is applied in `probabilities(cell:)`" (§3.1,
   `agents/research/PU.72.md:99-100`), T is stored in the mlpackage metadata and read in
   `PumpSegmentsModel.init` (§3.3), the windows become derived `w/T_shipped` values with the
   invariance anchor reproducing 45/45, 112/112 and the oracle ratchet exactly (§5.3), and §7 costs
   the Swift apply at ~15 lines. Reporting-only is a named outcome, but **behind a measurement**:
   "If the calibrated comparison never orders candidates differently from the raw one across a
   round's seeds, the standardization buys nothing measurable and the row closes as reporting-only"
   (F-benefit). The build cites the theorem and F4 instead. Both are true and both narrow the
   question - the theorem proves per-model decision-neutrality, so any reordering could only come
   from cross-model scale differences, which F3 bounds at ~3% - but the note's falsifier protocol
   exists precisely so that "the measurement would almost certainly confirm it" is not accepted in
   place of the measurement. The Built text's "**by the note's measurement**" overstates what was
   measured: the note's *closure-condition* measurement was not among them. **This needs the
   owner's OK, recorded in the row - or the measurement run.** The owner has been hands-on across
   this tranche (the cycle rule, the PU.78 beam guard, the PU.79 re-frames), so the OK is cheap;
   the measurement is also cheap (existing checkpoints, `measureLive` on train, two windows).

3. **Does the row text say plainly which promises are dropped and why?** Only for one of five. The
   non-ship to the device is explicit with two measured reasons. The dropped "stored with it"
   (S1b), the never-recomputed heldout ECE (S2), the dropped window restatement (S3) and the
   dropped two-window proof (S5) are not named as dropped anywhere in the row. The template's
   criterion 7 exists for exactly this; the fix is a sentence per promise.

## Found and not fixed

- **No corrected heldout ECE anywhere** (the erratum invalidates §5.2's heldout table without
  replacing it) - owned by this row, fix 5 below.
- **r9 / r10-s0 / r11-control were never run through the shipped module** - their note-table ECE
  columns are invalid, their T/NLL/flips unverified since the scratch. This row, fix 3 (scope note)
  or a re-run.
- **The fitted T values exist only in `/tmp`** - this row, fix 2.
- **`/tmp/pu72-cal/held.py:89` recovers logits from 1e-9-clipped probabilities** rather than using
  raw z; negligible at these scales, scratch-only, nobody owns it. Noted for honesty.
- **`ml/pump-reader/README.md` is renderer-scoped and stale as a subtree index** ("no model is
  trained here (PU.3)" while `train.py` trains); pre-existing, no row owns it.
- The tree's PU.78 movement (47/47, 118, 774/0.9987) and the combined-tree baseline Swift gate
  before commit: PU.78's review and the committer, not this row.

## What is needed to close (all closable inside this row; none needs a new row)

1. **Owner decision, recorded in the row text**: either (a) the owner OKs the reporting-only
   closure without the F-benefit measurement - one sentence in the row naming the OK and its date -
   or (b) the measurement is run: the existing r7-r11 checkpoints as candidates, train `measureLive`
   (or its Python equivalent) precision at the shared calibrated window vs raw windows, result
   recorded whichever way it falls. If (a) and the comparison is deferred, **PU.73's Checks cell
   must carry it explicitly** in the same edit (draft: "each candidate also scored under PU.72's
   shared calibrated window (`temperature.json`) against its raw-window score; any reordering
   reported - PU.72's F-benefit, moved here with the owner's OK"), because a deferral into a row
   whose text does not name it is the silent drop again.
2. **Persist the artifacts**: run the CLI at its default `--out` (or copy) so `temperature.json`
   sits beside `segmentnet.pt` for r6/r7/r8 as the Built text already claims, and/or mirror the T
   values into `runs/<date>/metrics.json` per the note §3.3. `/tmp` is not storage.
3. **Make the row text plain**: one clause per dropped or narrowed promise - stored-with-it (fixed
   by 2), PumpSegmentsModel application and window restatement (dropped, reason: theorem + F4 +
   owner OK from 1), heldout ECE (fixed by 5), round-7 two-window scoring (moved by 1), and the
   scope of "per exported model" (r6/r7/r8 re-run with the module; r9/r10/r11 either re-run -
   minutes each - or named as note-scratch-only).
4. **Pin the ECE functions**: a test fixture with small hand-computable nonzero ECE values (or a
   golden pin of the r6 corrected numbers) such that both erratum bug classes, re-introduced as
   mutations, go red; keep the mutation log (`/tmp/agentlogs/` per PU.68/PU.78 practice). The two
   green mutations of this review (`/tmp/pu72-mut/conf8x`, `/tmp/pu72-mut/mlindex`) are the named
   mutations.
5. **Complete the erratum**: recompute the heldout ECE columns (r6, r11-control; the 873-cell
   count-matched pool per note §5.1) with the module's corrected functions and append the numbers,
   or strike the invalidated columns in place with a pointer to the erratum. The record must not
   carry invalid numbers with the correction covering only half of them.

## Verdict

# INCOMPLETE

Items: 1 MET (module) with the closure-protocol departure judged under 7; 2 MISSING as a fact -
nothing ships to the app - legitimate as to the correction, owner's OK needed as to the
standardizer; 3 PARTIAL; 4 MET; 5 PARTIAL (two of five mutations green, both the erratum's bug
classes, and no mutation record in the gate evidence); 6 PARTIAL; 7 two PARTIAL, four MISSING
sentences, one MET by construction. The implementation that exists is faithful, reproduces exactly
under independent re-derivation, and the erratum it shipped is correct - what blocks the commit is
the record, not the code: an unmeasured closure condition presented as measured, five dropped
promises of which the row names one, volatile artifacts, and ECE functions no test would defend.
Fixes 1-5 are small; re-dispatch a fresh copy of this review after they land.
