# REVIEW-PU-COMPLETENESS – is this pump row actually done?

*The template. Every run gets its own copy, `agents/briefs/REVIEW-COMPLETE-<row>.md`. Dispatched to a
reviewing agent **after every row in the PU.67 tranche is built and gated, before it is committed**
(product owner, 2026-09-23: *"the agent reviewer each time validates the completeness of the
implementation"*). It is to a pump row what `REVIEW-SCENARIO.md` is to a journey: a row is not done
because its code compiles and its tests pass – it is done when what the row promised is in the tree,
wired, measured and written down. The orchestrator commits only on a `COMPLETE` verdict.*

## Fill these in for the run

- **Row:** `PU.73` – the decimal-point bit, trained for its imbalance; the segment layout kept
  (`docs/TASKS.md`, ticked in the tree pending THIS review - read its result text)
- **Research note:** `agents/research/PU.73.md`
- **The diff under review:** `ml/pump-reader/src/pump_reader/{train.py,model.py,export.py,score.py}`,
  `ml/pump-reader/tests/test_segment_loss.py` (new), `ml/pump-reader/tests/test_model.py` (two new
  tests), the PU.73 row. IGNORE `temperature.py` (PU.72, uncommitted; it carries a one-line head read
  from this row) and the PU.78 / PU.72 / PU.81 edits elsewhere.
- **The orchestrator's gate evidence:** ML pytest (run `.venv/bin/python -m pytest -q` in
  `ml/pump-reader` yourself - it is fast); `/tmp/agentlogs/pu73-round-a.log`, `pu73-round-b.log`
  (training), `pu73-round-a-dpauc.log`, `pu73-round-b-dpauc.log` (heldout dp AUC),
  `pu73-tiers-{flatten-s0,flatten-s1,flatten-s2,control-s0}.log` (both tiers). The checkpoints are
  in `ml/pump-reader/.out/pu73-*`.

**Row-specific:** nothing ships, so items 2-3 read: is the refusal correct under the note's F2/F3,
and is the no-ship outcome stated plainly? Check the defaults reproduce the shipped training exactly
(F1), that the head is recorded and read everywhere a checkpoint is loaded, and the scope choices:
the note's step 0 (a hand-box re-export of the real pool) was NOT run - Round A/B used the existing
`.out/real` pool, so each arm is compared with a control on the same pool; judge whether the row
says so, and whether that departure needs the owner.

## Third pass

Review 2 (`agents/reviews/PU.73-COMPLETENESS-2.md`) left four text items, now in the tree: the EXTRACTION ceiling
sentence rewritten (linear transfer ~0.63, the note's ceiling ~0.75, nothing near 0.9); "R1 below" -> "PU.82 below";
0.653 attributed to the build-commit re-measurement (the note's 0.657 on the old cut), focal s1 rounded as REPORT.md;
the A2(ii) per-bit-alpha variant and the `--dp-crop off` pin recorded as not done, with reasons. Verify those four only.

## Second pass (history)

Review 1 (`agents/reviews/PU.73-COMPLETENESS.md`) was INCOMPLETE; its list 1-11, as closed (verify):
1-3. The row now names the renderer as the control's divergence, the dp-AUC mode and population
     provenance, model sizes and latency, and says plainly what was not done: the hand-box pool (A11),
     the paper's positive-target normalisation (A6 - the claim is softened to "mean reduction"), tier
     scoring for the arms that failed F2.
4.   `docs/EXTRACTION.md` has a PU.73 paragraph (dp is framing-bound; PU.78's hard dp check unearned).
5.   R1/R2/R3 filed as PU.82 (owner's call), PU.83, PU.84 (owner's call); the flatten-s2 re-score is
     PU.74's (running now).
6.   The 15 `metrics.json` files are in `ml/pump-reader/runs/2026-09-24/pu73-metrics/`; REPORT.md has a
     PU.73 round section.
8.   Tests pin M4-M7 (dp-only weight vector, CLI defaults, CoordConv's coordinates, the flatten head);
     mutations red: `/tmp/agentlogs/pu73-mutation-M{4,5,6,7}.log`; ML suite 64 passed.
9.   `metrics.json` records head, dp_pos_weight, focal_gamma, focal_alpha, loss_reduction.
10.  A6 recorded as a departure instead of re-run (your recommendation).
11.  A12: T per candidate (`/tmp/agentlogs/pu73-temperatures.log`), reported in the row.
The ML package's task-id comment convention (your item 6) is left as is and named here.

## Where you may write

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **READ-ONLY except one file:**
`agents/reviews/PU.73-COMPLETENESS-3.md`. No code, no builds that write, no commits. You may run
read-only tools and the pump measurement tool (`swift run PumpReadTool`) if a number is missing –
say that you did, and that the machine may be loaded.

## What you are checking – each item MET, PARTIAL or MISSING, always with `file:line`

1. **Fidelity to the published method.** The code does what the research note says the paper does.
   Every departure is one the note lists and justifies, or one the product owner approved. An
   unlisted departure is MISSING, however good it looks – name the paper section it departs from.
2. **Wired into the app path, not only the harness.** The change reaches `PumpDisplayCapture.classify`
   and `CapturePipeline` (the path the phone runs), in Release as well as Debug. A method reachable
   only from `PumpReadTool`, a test or a `#if DEBUG` seam is the "docs naming behaviour with no call
   site" shape (`docs/DEFECT-PATTERNS.md`) – MISSING.
3. **Measured on the app path, on the named population.** The live-path floor
   (`PumpReaderPipelineTests.livePath`, the app's `classify`) ran, the committed/correct counts are
   in the gate evidence, and they match `PumpPhotoGate`'s reader constants. The row's own claimed
   movement is reported over the population the row named, with the interval beside the point
   estimate once PU.68 has landed. **Zero new wrong readings** unless the row says otherwise and the
   owner agreed.
4. **No regression elsewhere.** The receipt leak (non-pump fixtures routed as a pump) did not rise;
   the annotated floor and the law's oracle ratchet did not fall; latency, if the row touches a hot
   path, has a Release number.
5. **Tests that would fail.** Each promise has a test, and the orchestrator's mutation of it turned
   the test red (the mutation and its red output are in the gate evidence). A test that stays green
   when its behaviour is removed is PARTIAL.
6. **Docs reconciled.** `docs/EXTRACTION.md` (the pump reader section, and a numbered decision if the
   row changes one), `docs/TASKS.md` (the row's result, numbers and what was left), `docs/ERRORS.md`
   and `docs/JOURNEYS.md` J4/F2 if the user sees anything different, `CLAUDE.md` comment rules in
   every touched file (current truth only, no task ids in code comments).
7. **Everything the row promised.** Read the row's own Checks cell sentence by sentence; each
   sentence is MET, PARTIAL or MISSING. A promise quietly dropped is how PU.59's second amendment
   nearly shipped untested.

## Verdict

End with one of:
- **COMPLETE** – every item MET. The orchestrator may commit.
- **INCOMPLETE** – list each PARTIAL/MISSING item with what is needed; the orchestrator fixes it and
  re-dispatches this review (a fresh copy, same row). A gap the row cannot close becomes a new row,
  drafted here, never silently dropped.

**The standing fences appended below were written for build briefs.** Their write and stash/checkout rules apply to you; their standing checks do not. You may run the ML venv read-only.
