# PU.73 completeness review 2 - the dp bit, second pass

Run 2026-09-24 against the working tree at `b34821a9` + the uncommitted PU.73 diff. Reviewer:
reviewing agent, `agents/briefs/REVIEW-COMPLETE-PU.73-2.md`. Read-only except this file.

**What I ran** (nothing written to the repo but this file; scratch script in `/tmp`):

- `.venv/bin/python -m pytest -q` in `ml/pump-reader`: **exit 0, 64 passed in 14.04 s** - the
  brief's claimed count, in my hands.
- `python3 scripts/tasks-index.py --check`: **exit 0**. `python3 scripts/scenario-index.py --check`:
  **exit 0, 531 rows**.
- `git diff` / `git show` / `grep` / file reads; byte-comparison of the 15 archived metrics files
  against `.out/pu73-*/metrics.json`; `torch.load` (read-only) of six checkpoints for their `head`
  keys and weight shapes; `du` on the three `.mlpackage`s.
- **One measurement of my own** (`/tmp/pu73-review2-margin.py`, CPU, deterministic; the machine may
  have been loaded by concurrent runs, which affects wall time only): the mean/median raw top1-top2
  pattern-log-likelihood margin (the law's nat space) on the train pool (`.out/real/cells.npz`,
  25 085 cells) for four checkpoints - to settle the direction of the row's "~6 % sharper" claim.
  Output quoted under item 3 below. I did **not** run `swift run PumpReadTool`, `scripts/gate.sh` or
  any Swift suite: no Swift file is in this row's diff and the tier logs are the measurement.

**Scope, as briefed**: the diff under review is `ml/pump-reader/src/pump_reader/{train.py,model.py,
export.py,score.py}`, `tests/test_segment_loss.py` (new, 5 tests), `tests/test_model.py` (now 4 new
tests, two added since review 1), the PU.73 row and its doc trail. Ignored as instructed:
`temperature.py` / `test_temperature.py` (PU.72, uncommitted - its one-line head read at
`temperature.py:148` verified present and correct), the PU.78/PU.81 Swift edits, the corpus drift.

---

## Second pass: review 1's list 1-11, as closed - verified

| # | Closure claimed | Verified |
|---|---|---|
| 1-3 | Row names the renderer as the control's divergence, dp-AUC mode/provenance, sizes, latency, what was not done | **Yes.** `docs/TASKS.md:1079`: "r6's steps / pool / real-frac on TODAY'S renderer (`dataset.py`'s palette and technology priors moved since r6 - `--priors` recorded 'default' = 0.80/0.15/0.05, not r6's 0.85/0.10/0.05 ...)". I re-checked the constants: `dataset.py:43` is 0.80/0.15/0.05 today and `git show d781416c:...dataset.py:43` is 0.85/0.10/0.05; the grey-palette constants exist (`dataset.py:50,53,56`). The 0.03 digit gap is real: r6 `final_val_per_digit_accuracy` 0.8132 vs control-s0 0.7838 (both `metrics.json`, read this run). dp-AUC population: "864 cells (5-crop TTA, the app's path; 184 windows, 183 dp-positive, from `slices.json` re-cut at 03:52 - the note's 873 was the previous cut)". Sizes gap 24 328 / 64 KB, flatten 36 104 / 88 KB, coord 24 616 - packages measured: control 64 KB, flatten 88 KB, shipped 64 KB. Latency: "immaterial - nothing ships and no Swift path changed". Not done, stated plainly: A11 hand-box pool + step 0, A6 mean reduction with the claim softened, tier scoring skipped for the three F2-failed arms. |
| 4 | `docs/EXTRACTION.md` PU.73 paragraph | **Present** (`docs/EXTRACTION.md:1127-1136`), with PU.78's M4 "stays unearned" and PU.84 named - but its ceiling sentence is wrong against its own paragraph; see item 6 below. |
| 5 | R1/R2/R3 filed | **Yes.** PU.82 (`docs/TASKS.md:1084`, "Owner's call first"), PU.83 (`:1085`, `no-scenario: training tooling`), PU.84 (`:1086`, "Owner's call"); scenario cells present, `scenario-index --check` exit 0. The flatten-s2 re-score sits in PU.73's own row twice ("re-score flatten s2 after PU.74 lands"; "the flatten-s2 re-score is PU.74's") - review 1 accepted "a line in PU.73's row" as the alternative. Note: PU.74's row and `agents/research/PU.74.md` do not carry it, so the orchestrator's running PU.74 brief must. |
| 6 | 15 metrics files + REPORT section | **Yes.** All 15 in `ml/pump-reader/runs/2026-09-24/pu73-metrics/`, each **byte-identical** to its `.out/pu73-*/metrics.json` (compared this run). `REPORT.md:2261-2277` carries the round section; every number in its table matches the dpauc/tier logs (checked cell by cell, item 3). |
| 8 | Tests pin M4-M7, mutations red, suite 64 | **Yes.** `dp_pos_weight_vector` factored out (`train.py:121-127`) and pinned (`test_segment_loss.py:37-41`); CLI defaults pinned via `build_parser` (`train.py:130-133`, `test_segment_loss.py:44-47`); CoordConv non-vacuous (`test_model.py:51-72`); flatten head pinned (`test_model.py:75-84`). All four mutation logs read: each shows the named test FAILED, "1 failed, 4 passed" (`/tmp/agentlogs/pu73-mutation-M{4,5,6,7}.log`). M5's design is sound: the test keeps the coord net's own random coordinate-channel weights, so zeroing or bypassing the coords makes the outputs collapse to the plain stem and the `not allclose` assert goes red. Suite restored: 64 passed, exit 0 (my run). |
| 9 | `metrics.json` records head/loss fields | **Yes, in code**: `train.py:293-294` writes `head`, `dp_pos_weight`, `focal_gamma`, `focal_alpha`, `loss_reduction`. The 15 archived files predate the change and lack the fields (checked: all `None`) - expected, and arm identity is durable via filenames + the REPORT table; future runs are self-describing, which is what review 1's fix 9 asked. |
| 10 | A6 recorded as a departure | **Yes, in all three records**: the row ("the claim is 'focal loss with a mean reduction is a no-op', not the published method measured"), `REPORT.md:2271` ("focal gamma 2 (mean reduction)"), `EXTRACTION.md:1132` ("focal loss (mean reduction)"). The code is honest about it: `train.py:294` hardcodes `"loss_reduction": "mean"`. No owner quote is attached to the skip; review 1's own recommendation was "record it", the row no longer claims the published method was measured, and the recorded claim is exactly what ran - acceptable without a separate owner sign-off (observation below). |
| 11 | A12: T per candidate | **Yes.** `/tmp/agentlogs/pu73-temperatures.log`: control-s0 0.5871, flatten-s0 0.5344, s1 0.5368, s2 0.5345, all 0 digit flips; r6 0.568 from PU.72's `runs/2026-09-24/temperature.json` (0.5682); `temperature.json` written beside each of the four checkpoints (mtimes 06:56). The row reports all of it with the F5 caveat. I verified the caveat's direction by direct measurement (below) - it holds. |

---

## Item 1 - fidelity to the published method: **PARTIAL** (two review-1 asks still unrecorded)

**Faithful, re-verified against the papers as the note cites them:**

- Focal loss eq. (5) shape with A4's split: the modulating factor `(1 - p_t) ** gamma` and the alpha
  term are built from the HARD target, the CE term keeps the smoothed target (`train.py:135-150`;
  `hard` captured before smoothing at `train.py:266-269`). Gamma 0 / no alpha / unit weight reduces
  to `BCEWithLogitsLoss()` exactly - the paper's own eq. (4) statement - pinned by
  `test_segment_loss.py:6-15` and red under review 1's M3 (reduction swap) and M1 (factor removal).
- A2(i) dp-only reweighting: `dp_pos_weight_vector` puts the weight on bit 7 alone and is a no-op at
  7 bits (`train.py:121-127`, `test_segment_loss.py:37-41`, M4 red).
- A7 flatten: `Flatten` + `Linear(1536, 8)`, everything upstream identical (`model.py:54,64`);
  36 104 params, 88 KB package - measured.
- A8 CoordConv: constant `i`,`j` buffers scaled to [-1,1] over 48x32 (`model.py:56-58`), concatenated
  before the stack (`:62`), first conv widened 3→5 keeping k=3 (`:48`), GAP and `Linear(64,8)` kept;
  zeroed coordinate weights reproduce the plain stem (Liu et al. §3) pinned at
  `test_model.py:31-48`, and the pin is no longer vacuous (`test_model.py:51-72`, M5 red). 24 616
  params - review 1's recount, consistent with the +288 arithmetic.
- A3 heldout discipline: selection on train-side dp AUC, heldout scored once per candidate - the
  log structure (`pu73-round-{a,b}-dpauc.log`) matches.
- Export/device surface unchanged as §3.2 predicted: `export.py:49` and `score.py:337` gained only
  the head read; the flatten candidate really went through Core ML (`.out/pu73-flatten-s0/
  PumpSegments.mlpackage`, 88 KB) and was scored through the app's own `classify`.
- **F1 (defaults reproduce the shipped training)**: the shipped LOSS and HEAD configuration is
  exactly reproducible from the defaults and pinned twice - `test_defaults_are_exactly_bce`
  (function level, M3 red) and `test_cli_defaults_are_the_shipped_training` (argparse level:
  `--dp-pos-weight 1.0, --focal-gamma 0.0, --focal-alpha None, --head gap`; M7 red). The shipped
  RUN is not reproducible (the renderer moved, no CLI switch for the grey palette) and the row now
  says exactly that, with the constants and the measured 0.03 consequence. This is the correct
  closure of review 1's 3c.

**Departures recorded**: A6 mean reduction (row + REPORT + EXTRACTION, claim softened), A11 hand-box
pool / step 0 (row, "not built", routed to the owner as PU.82), A12 (delivered as T per candidate),
tier scoring skipped for the F2-failed arms (row, with F2 named as the reason - defensible: an arm
that does not beat the control's dp AUC cannot reach the ship gate, and the row now says so rather
than leaving the reader to infer).

**Still unrecorded - both were asks in review 1's item-1 prose that its numbered fix list dropped:**

1. **A2(ii), the per-bit-alpha focal arm, was not built and no alpha arm was run, and nothing says
   so.** The note lists arm (ii) - "uniform FL over all 8 bits at per-bit alpha_t from inverse
   frequency" - as the paper-faithful variant "kept in the sweep" (`agents/research/PU.73.md:336`),
   and §3.1 prescribes "gamma and alpha swept around the paper's (2, 0.25)" (`:236-237`). The built
   `--focal-alpha` is a single scalar over all 8 bits (`train.py:135-150,186`), which is neither
   A2(i) nor A2(ii) and cannot express per-bit alpha; the focal arm ran at gamma 2 with NO alpha.
   Review 1: "Record it as not-built, or build it." Neither happened - the row names `--focal-alpha`
   as instrument but never records that the alpha sweep and the A2(ii) variant did not run. One
   clause in the row's "not done" list closes it (no re-run needed: F2's no-gain close stands on the
   candidates actually run, and the pos-weight arm already measured the inverse-frequency alpha
   0.78 equivalent for dp, w = 3.52 ⇔ alpha = w/(1+w) = 0.779, the note's own arithmetic at `:233-235`).
2. **The note's §3.4 instruction "every round command pins `--dp-crop off`" was not followed and
   could not be as written; the row does not record that.** `train.py:181` offers only `gap|none`
   (the `off` vocabulary lives in `realglyphs.py:291`), the arms ran at train.py's default `gap`,
   which in that file only selects 8-bit training - framing came from the pool, which IS the shipped
   off-framing r6 export (all 15 archived metrics: `"real": ".out/real"`, `real_cells: 25085`,
   `dp_crop: "gap"`; verified). Review 1 established "no harm done" but asked for one clause saying
   the instruction was not followable; PU.83 owns the vocabulary fix but the round's own record is
   still silent. One clause in the row closes it.

Neither gap disturbs the F2/F3 verdicts; both are records the next round will read. Item 1 is
PARTIAL until the two clauses exist.

## Item 2 - wired into the app path: **MET**

Nothing ships: no Swift file is in the diff, `ios/App/Resources/PumpSegments.mlpackage` is
untouched (64 KB, identical to the control's export), so `PumpDisplayCapture.classify` and
`CapturePipeline` run exactly what they ran before, Debug and Release alike. The candidates were
nevertheless measured ON the app path - the four tier logs are `livePath` runs ("PU.63 live path
(the app's classify)") via `PUMP_MODEL=`, so the flatten arm's +0.044 was carried to the phone's
entry point and refused there. **The head is recorded and read everywhere a checkpoint is loaded**:
written at `train.py:287`; read at `export.py:49`, `score.py:337`, `temperature.py:148` - these are
all the loaders in the tree (`grep torch.load` over `ml/`; `test_export_roundtrip.py:44-45` loads a
smoke checkpoint into `SegmentNet()`, which indirectly pins the gap default). Legacy handling
verified per artifact this run: r6, control, posw and focal checkpoints have NO `head` key (they
predate the save change - Round A ran 04:22-04:56, the key landed before Round B at 05:16) and their
state dicts are gap-shaped (`classifier (8,64)`, stem `(16,3,3,3)`), while flatten-s0 records
`head=flatten` with `(8,1536)` and coord-s0 `head=coord` with stem `(16,5,3,3)` - recorded head and
weights agree everywhere, and a wrong default crashes on `load_state_dict` rather than mis-scoring.

## Item 3 - measured on the app path, on the named population: **MET** (one attribution to fix, under item 6)

- Tier runs re-verified against the logs: control-s0 annotated 111/109 + live 42/42
  (`pu73-tiers-control-s0.log:10,22`), flatten s0 116/114 + 44/42, s1 107/106 + 43/40, s2 123/121
  + **56/54** (`pu73-tiers-flatten-s2.log:9,17`), all "of 181" with the gate flagging
  `readerNumericTotal is 183, the run says 181` - the pump-275 corpus drift, disclosed in the row.
  Wilson intervals print in the logs (PU.68's instrument). The `PumpPhotoGate`/floor constants
  (47/47/183, 118) are PU.78's, untouched by this row, and still describe the shipped model.
- dp AUC: every per-seed number in the row and REPORT matches the dpauc logs exactly (control
  0.6773/0.6799/0.6900; posw 0.6896/0.6971/0.6910; focal 0.6788/0.6805/0.6812; flatten
  0.7316/0.7259/0.7214; coord 0.6950/0.6741/0.6827 - 864 cells per run). Mode (5-crop TTA, the
  app's path) and population provenance (864/184/183, `slices.json` re-cut 03:52, the note's 873 the
  previous cut) are now stated, closing review 1's 3a.
- **Zero new wrong readings on the app path**: nothing shipped; the refusal is F3-correct on the
  arithmetic review 1 recomputed and I re-read (every flatten seed adds wrong readings; s2's live
  "up" 56 > 47 is refused at 54/56 - exactly the row gate).
- **A12's substance now holds, and I tested its direction rather than trusting it.** My margin
  measurement on the train pool (raw top1-top2 pattern nats, the law's space):

  | checkpoint | T | mean margin | median margin |
  |---|---|---|---|
  | r6 (shipped) | 0.568 | 3.530 | 3.178 |
  | control-s0 | 0.587 | 3.573 | 3.230 |
  | flatten-s0 | 0.534 | 3.974 | 3.515 |
  | flatten-s2 | 0.535 | 3.905 | 3.517 |

  Flatten's raw margins really are sharper - ~10-13 % over r6, so the row's direction is right and
  its T-ratio-derived "~6 %" (0.568/0.534) UNDERSTATES the scale gap: even more of s2's commit rise
  may be margin scale (F5), which strengthens the refusal exactly as the row says. Control's margins
  are ~1 % sharper than r6's yet it commits LESS (111/42 vs 116/47) - so the row's "retraining on
  today's renderer already loses ground" survives scale correction: it is a reading loss, not a
  scale artifact. F5 is served; review 1's 3b is closed.

## Item 4 - no regression elsewhere: **MET**

No Swift file, no reader, no decision rule, no gate constant is touched by this row's diff; the
receipt leak, the annotated floor and the oracle ratchet are properties of files this row does not
modify (the law/test edits in the tree are PU.78/PU.81's, ignored as briefed). Latency: nothing
ships, no hot path changed, and the row says so in the PU.78-precedent form; the flatten head's
+11 776 MACs/cell (+0.28 %) is in the note's §6, which the row cites, and its +24 KB package is
derivable from the sizes the row reports. Debug-vs-Release: both sides of every comparison ran the
same configuration; a Release number is owed only by a ship. ML suite exit 0 in my hands.

## Item 5 - tests that would fail: **MET**

Seven mutations across the two reviews, all red, all logged: M1-M3 (review 1,
`/tmp/agentlogs/pu73-review-mutations.log` + the `-exit` logs) and M4-M7 (this pass's gate evidence,
read verbatim - M4 `test_dp_pos_weight_vector_weights_only_the_dp_bit` FAILED; M5
`test_coord_head_really_adds_coordinates` FAILED with the outputs collapsed to the plain stem; M6
`test_flatten_head_keeps_the_layout` FAILED on `(8,64) != (8,1536)`; M7
`test_cli_defaults_are_the_shipped_training` FAILED on `3.52 != 1.0`). Restored suite: **64 passed,
exit 0**, run by me. Every behavioural promise in the new docstrings has its failing-when-broken
test: `segment_loss`'s "exactly BCEWithLogitsLoss" (`train.py:136-139` ↔ `test_segment_loss.py:6`),
`dp_pos_weight_vector`'s "dp alone" (`train.py:121-123` ↔ `:37`), `build_parser`'s "defaults can be
asserted" (`train.py:130-131` ↔ `:44`), CoordConv's §3 equivalence and the flatten layout
(`model.py:36-41` ↔ `test_model.py:31,51,75`). The head-key write (`train.py:287`) remains unpinned
by a test - review 1 accepted that (a wrong default crashes rather than mis-scores) and it is not
among M1-M7; unchanged.

## Item 6 - docs reconciled: **PARTIAL** (three text defects, all small)

1. **`docs/EXTRACTION.md:1128-1130` contradicts its own paragraph and the row.** "a linear probe
   puts the ceiling of what any classifier can take from the reader's cell crop near there [0.653]"
   - but two sentences later the same paragraph reports a classifier taking **0.726**, and the row
   says "a ceiling **near 0.75** for any loss or head" (`docs/TASKS.md:1079`), matching the note
   (§0: linear transfer 0.604-0.626; the ~0.75 bound is the note's labelled inference for nonlinear
   heads, and flatten landed at 0.726 under it). The probe bounds what transfers LINEARLY; "any
   classifier ... near 0.653" is falsified by the round itself. Fix one sentence: the probe bounds
   linear transfer (~0.63), the note's ceiling for any loss or head is ~0.75 - the flatten arm
   reached 0.726 - and nothing approaches the 0.9 PU.78's hard dp check would need. This is the
   authority doc for the pipeline; the next round (PU.84's owner decision included) will quote it.
2. **Dangling pointer in the row**: "owner's call, **R1 below**" (`docs/TASKS.md:1079`). There is no
   R1 in `TASKS.md` - R1 was review 1's draft-row label, filed as PU.82 (which the row's own
   follow-ups sentence names). Replace "R1 below" with "PU.82 below"; a closed row must be readable
   without the review file.
3. **The 0.653 attribution**: "the note measured the shipped model's heldout dp AUC at 0.653" - the
   note measured **0.6452/0.6569** on the previous (873-cell) cut (`agents/research/PU.73.md:24-26`);
   0.653 is the re-measurement on the re-cut 864-cell population, first run by review 1
   (`dpauc_tta.py` re-run, 0.6527, quoted in `agents/reviews/PU.73-COMPLETENESS.md`). The row's
   later sentence gets the population right; the opening clause should attribute 0.653 to the
   build-commit re-measurement, not the note. (Review 1's own file must then be committed - its fix
   7 already asks for that.)
4. Cosmetic: focal s1 dp AUC is 0.680 in the row and 0.681 in `REPORT.md:2271` (log: 0.6805 - a
   rounding boundary). Align one way.

Everything else reconciled: the row's numbers all verify against the artifacts (this review checked
every one); `REPORT.md:2261-2277` is consistent with the logs and the row (modulo the rounding);
PU.82/83/84 are well-formed rows with scenarios; `tasks-index`/`scenario-index` exit 0;
`docs/ERRORS.md`/`docs/JOURNEYS.md` correctly untouched (the user sees nothing different); the new
code comments are current-truth, present-tense, and their promises are the ones the tests hold -
the task-id references (`train.py:177`, `model.py:36`) are the ML package's convention, left as is
and named in the brief.

## Item 7 - everything the row promised, sentence by sentence: **MET** (subject to items 1 and 6)

- "Round per change (focal/pos_weight; head)" - **MET**: 15 runs, 5 arms x 3 seeds, all in
  `.out/pu73-*` with their train logs, one change per round against a same-pool control.
- "each scored on annotated AND live" - **MET as closed**: the skip for the three F2-failed arms is
  now disclosed with its reason in the row (review 1 asked for exactly that).
- "after PU.72's calibration so a margin shift is not mistaken for a gain" - **MET**: T per
  candidate reported, F5 caveat in the row, direction verified by measurement (item 3).
- "dp AUC on real cells reported" - **MET**: per seed, per arm, mode and population stated.
- "ships only on live up at zero wrong readings" - **MET**: nothing ships; refusal arithmetic
  re-checked; no-ship stated in the result cell's first words.
- "model size and Release per-cell latency reported" - **MET**: sizes exact (re-measured from the
  packages), latency immaterial with the reason; the MACs detail lives in the cited note §6.
- Result-cell claims - head recorded and read by every loader (**MET**, verified per artifact);
  CoordConv equivalence "pinned" (**MET** now - M5 red); "defaults = the shipped unweighted BCE,
  pinned" (**MET** - M3/M7 red; the run-level non-reproducibility is separately and correctly
  disclosed as the renderer divergence); "re-score flatten s2 after PU.74 lands" (**MET** as a
  filed line in this row, review 1's alternative branch - carry it into PU.74's build brief).

---

## Observations (not blocking)

- **A6's owner sign-off**: review 1's fix 10 was phrased "re-run, or the owner's OK to skip", while
  its own recommendation was "record it". The recording is done and accurate in three documents,
  and the row no longer claims the published method was measured, so no false statement remains;
  but if the owner has blessed the skip, one quoted word in the row (as PU.82/PU.84 carry "owner's
  call") would close the loop the way this tranche closes everything else.
- The row's "~6 % sharper" comes from the T ratio; my direct measurement says ~10-13 % on the train
  pool. Understating the scale gap is conservative for the refusal. If anyone re-scores flatten s2
  under PU.74, the measured margins (table in item 3) are the number to restate windows with.
- `test_cli_defaults_are_the_shipped_training` slightly overclaims in its NAME - the defaults are
  the shipped loss/head flags, not the shipped training (the renderer moved, as the row says).
  Rename opportunistically or leave; the row's disclosure prevents real confusion.
- **Commit hygiene for the orchestrator**: the commit should carry the untracked artifacts the code
  and row cite by path - `agents/research/PU.73.md`, `agents/briefs/RESEARCH-PU.73.md`,
  `agents/briefs/REVIEW-COMPLETE-PU.73.md` (and `-2`), both review files,
  `ml/pump-reader/runs/2026-09-24/`, `tests/test_segment_loss.py` - while `temperature.py`,
  `test_temperature.py` and `runs/2026-09-24/temperature.json` belong to PU.72's commit, not this
  row's. `runs/2026-09-23/` is PU.72's as well.

## What is needed before this row can be committed

Text only, minutes, no re-run, no code:

1. `docs/EXTRACTION.md:1128-1131` - rewrite the ceiling sentence (probe bounds linear transfer
   ~0.63; the note's ceiling for any loss or head ~0.75; flatten measured 0.726; nothing near the
   0.9 PU.78's M4 needs).
2. `docs/TASKS.md:1079` - "R1 below" → "PU.82 below".
3. `docs/TASKS.md:1079` - attribute 0.653 to the build-commit re-measurement on the re-cut slices
   (review 1's `dpauc_tta` re-run), not to the note; align the focal-s1 rounding with
   `REPORT.md:2271`.
4. `docs/TASKS.md:1079`, "not done" list - add the two unrecorded non-runs: the note's A2(ii)
   per-bit-alpha focal variant (not built; `--focal-alpha` is a single scalar; the focal arm ran
   gamma 2 with no alpha - the inverse-frequency alpha for dp is what the pos-weight 3.52 arm
   already measured) and the note §3.4 `--dp-crop off` pin (not followable as written - `train.py`
   offers `gap|none`; the arms ran at its default `gap` = 8-bit training; framing came from the
   off-framed r6 pool; PU.83 owns the vocabulary).

## Verdict

**INCOMPLETE** - narrowly, on text alone.

Items 2, 3, 4, 5, 7: **MET**. Item 1: **PARTIAL** (two of review 1's prose asks - the A2(ii) and
`--dp-crop` records - never made its numbered list and are still unrecorded). Item 6: **PARTIAL**
(the EXTRACTION ceiling sentence contradicts its own paragraph and the row; the "R1 below" dangling
pointer; the 0.653 attribution). Everything the second pass was dispatched to verify - closures 1-11
- verifies: the refusal remains correct under F2/F3 on arithmetic re-checked against every log, the
no-ship is stated plainly, the defaults pin the shipped loss/head configuration with mutations red,
the head is recorded and read at every loader, the sweep is durably archived byte-identical, A12's
discipline is delivered and its direction confirmed by direct margin measurement. Fix the four text
items and re-dispatch; no measurement, code change or owner call stands between this row and
COMPLETE except the owner calls the row already routes (PU.82, PU.84).
