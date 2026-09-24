# PU.73 completeness review - the dp bit trained for its imbalance, the segment layout kept

Run 2026-09-24 06:10-06:55 EEST against the working tree at `eaf8e9d7` + the uncommitted PU.73 diff.
Reviewer: reviewing agent, `agents/briefs/REVIEW-COMPLETE-PU.73.md`.

**The tree moved during this review**: the orchestrator committed PU.78 (`8253bca0`) and PU.81
(`b34821a9`) at ~06:45, so the PU.73 diff now sits on `b34821a9`. I re-checked after both: the diff
under review is byte-identical to what I read (`git diff --stat ml/pump-reader/` - export 1, model 29,
score 1, train 41, test_model 31, plus the untracked `test_segment_loss.py`), and every line number
cited below still addresses the tree. The corpus drift is still uncommitted (pump-275's `reviewed`
cleared, 67 heldout stills / 181 cells), so the row's tier numbers are still against the current
tree. PU.72's uncommitted `temperature.py` is untouched and out of scope, as the brief says.

**What I ran** (read-only on the repo; I wrote nothing but this file):

- `git diff` / `git show` / `git log`, `grep`, `sed`, file reads; `stat` for artifact mtimes.
- `.venv/bin/python -m pytest -q` in `ml/pump-reader`: **exit 0, 60 passed in 12.89 s**
  (`/tmp/agentlogs/pu73-review-pytest.log`). Collection per file: `test_segment_loss.py` 3,
  `test_model.py` 3 (1 existing + this row's 2), `test_temperature.py` 6 (PU.72's).
- `python3 scripts/tasks-index.py --check` **exit 0**; `python3 scripts/scenario-index.py --check`
  **exit 0, 528 rows**.
- **Seven mutations**, applied to a COPY of `ml/pump-reader/{src,tests}` under
  `/var/folders/34/.../T/opencode/pu73-mut/` and run with the repo venv via `PYTHONPATH` - the repo
  tree was never edited (`diff -r` of the copy against `ml/pump-reader/src` is empty afterwards, and
  `git status` is unchanged by this review). Full log: `/tmp/agentlogs/pu73-review-mutations.log`,
  with clean exit codes in `-mutation-M1-exit.log`, `-mutation-M3-exit.log`,
  `-mutation-restored.log`.
- **Two measurements re-run by me**, because a number in the row had no artifact behind it:
  `/tmp/pu73/dpauc.py` and `dpauc_tta.py` (the note's own surviving scratch scripts, read-only on the
  repo, output below), and a population count replicating their filter over both corpus states.
  These are CPU-light and deterministic; **the machine may have been loaded** by concurrent runs,
  which affects wall time only, not these numbers.
- I did **not** run `swift run PumpReadTool`, `scripts/gate.sh`, or any Swift suite: PU.73 touches no
  Swift file, and the four tier runs in the gate evidence are the measurement.

---

## The headline: the refusal is correct and correctly stated - but three of the note's listed
adaptations were not carried out, and the round is not the round the row says it is

**The refusal is right.** Verified arithmetic from `/tmp/agentlogs/pu73-round-{a,b}-dpauc.log`:

| arm | dp AUC, 3 seeds | mean | vs control mean 0.6824 | seed spread | verdict |
|---|---|---|---|---|---|
| control (gap head, unit weight, gamma 0) | 0.6773 / 0.6799 / 0.6900 | 0.6824 | - | 0.0127 | baseline |
| `--dp-pos-weight 3.52` | 0.6896 / 0.6971 / 0.6910 | 0.6926 | **+0.0102** | 0.0075 | inside the control's spread, ranges overlap at 0.6896-0.6900 → **F2 no-op** ✓ |
| `--focal-gamma 2` | 0.6788 / 0.6805 / 0.6812 | 0.6802 | **-0.0022** | 0.0024 | **F2 no-op** ✓ |
| `--head coord` | 0.6950 / 0.6741 / 0.6827 | 0.6839 | **+0.0015** | 0.0209 | **F2 no-op** ✓ |
| `--head flatten` | 0.7316 / 0.7259 / 0.7214 | 0.7263 | **+0.0439** | 0.0102 | ranges disjoint from the control's → a real gain, correctly NOT closed by F2, so it went to the tier gate ✓ |

And F3 refuses flatten correctly (all four tier logs read, every number in the row verified against
them): s0 annotated 116/114 + live 44/42, s1 107/106 + 43/40, s2 123/121 + **56/54**; the wrong
cells are pump-092 (litres 3.0 for 30.0, total 191.55 for 1915.5, in all three seeds), pump-041
(unitPrice 1.794 for 1.784, all three), pump-055 (total 108.88 for 108.68, s0 and s2), pump-062
(total 39.95 for 39.55, s1). s2 is live **up** (56 vs 47) and still refused because it is 54/56 -
exactly the row's gate ("ships only on live up at zero wrong readings") and the note's F3 ("adds any
wrong reading ... refused regardless of dp AUC"). The control is refused too (live 42 < 47).
**No-ship is stated plainly**, in the first words of the result cell: "**Run 2026-09-24, nothing
ships**" (`docs/TASKS.md:1076`), and the shipped artifact confirms it - `ios/App/Resources/
PumpSegments.mlpackage` is not in `git status`, and no Swift file is in this row's diff.

**What is not right** is the record of how that result was reached. Three of the note's own listed
adaptations (A6's normalization and its `metrics.json` logging, A11's hand-box pool, A12's
calibration discipline) were not carried out and are not disclosed as departures; the round is
described as "r6's recipe" when the control demonstrably does not reproduce the shipped model; and
four of the row's "pinned" claims are not pinned by any test - I mutated them and the suite stayed
green. None of this changes the refusal, and none of it needs a re-run of the tiers. It needs
corrections, two small code additions, and two owner calls.

---

## Item 1 - fidelity to the published method: **MISSING** (three unlisted departures)

**1a. The loss reduction departs from Lin et al. §4.1 and from the note's own A6.**
`train.py:136` returns `ce.mean()` - torch's default mean reduction over all 8 x N outputs. The
note's A6 (`agents/research/PU.73.md:340`) specifies the opposite in terms: "Sum over the batch's
8 x N outputs, normalized by the count of positive TARGETS - per bit (8 normalizers) in arm A2(i);
global in A2(ii); **NOT torch's default mean reduction**", because "their normalization is part of
the method (it sets the effective LR against the rare class)". §6 (`:464-466`) lists "normalization"
as code the row owes. The published section departed from: **Lin et al. 2017, §4.1** ("we normalize
by the number of positive anchors"), which A6 restates.

Materiality, stated honestly: AdamW (`train.py:213`) is largely invariant to a constant loss scale,
so the arm probably trained close to what the paper's normalization would give - but "probably" is
not a measurement, and the row's conclusion is "*focal loss* is a measured no-op". What was measured
is a mean-reduced focal loss at 1:3.5 imbalance with the modulating factor ~4x smaller than the
paper's normalization gives it. The focal arm did move the model (final val loss 0.2076 vs the
control's 0.1462, dp bit accuracy 0.879 vs 0.8822, digit accuracy 0.7644 vs 0.7838 -
`.out/pu73-focal-s0/metrics.json`), so the factor was active; it is the normalization that is not
the published one. Fix: implement A6 (per-bit normalizer for the dp-only arm, global for a uniform
arm) behind a flag defaulting to today's `mean`, and re-run the 3 focal seeds (~50 min at the
observed 1003 s/run), **or** record the departure in the row and the note with the owner's OK and
soften "focal loss is a measured no-op" to "mean-reduced focal loss at our imbalance ratio is".

**1b. A6's logging half, and §6's `metrics.json` fields, do not exist.** The note requires "the exact
choice is logged in `metrics.json` with the run" (`:340`) and "`metrics.json` fields for
gamma/alpha/w/normalizer" (`:465-466`). `train.py:270-289` writes `steps, spill_prob, contrast_prob,
framing, dp_crop, priors, real, real_cells, real_frac, seed, wall_seconds, train_size, val_size,
initial_*, final_*, history` - **no `head`, no `gamma`, no `alpha`, no `pos_weight`, no normalizer**.
Verified on the artifacts: every `.out/pu73-*/metrics.json` lacks them. Consequence: **the row's
"pos-weight 3.52" and "focal gamma 2" are unverifiable from anything in the tree.** The `head` is
recoverable from `segmentnet.pt` (`train.py:267`), the loss hyperparameters are recoverable from
nothing durable. This is the difference between a reproducible round and a remembered one, and it is
why 1a cannot be checked after the fact either.

**1c. A11 / §3.3 step 0 - the hand-box pool - was not built and not run, and the row does not say
so.** The row's own premise cell scopes it: "This is the classifier sweep r7-r11 **on hand boxes**"
(`docs/TASKS.md:1076`). The note lists it as adaptation **A11** (`:345`: "Training pool restricted to
hand boxes ... new `realglyphs --hand-only`, precedent `detdata.py:205-209`", with the cost named and
"every round carries a same-pool control so the pool change never masquerades as a loss/head gain")
and makes the re-export **step 0 of the round** (`:295-301`). Measured against the tree:
`grep -c hand ml/pump-reader/src/pump_reader/realglyphs.py` → **0** (no `--hand-only`), and all 15
runs trained on `"real": ".out/real"` with `real_cells: 25085` - the r6-era pool whose hand-boxed
subset the note counted at **1 899 cells, 7.6 %** (`:283`). Each arm IS compared with a control on
the same pool, so the A/B structure the note wanted is intact and the F2/F3 verdicts are valid **for
the pool that was used**; but the row answers a narrower question than it poses, and reads as closing
the hand-box one.

**This departure needs the owner**, and here is my judgment on why the note's ceiling argument does
not settle it by itself: §0's ceiling (`:31-70`) is about *framing* - the mark sits in the inter-cell
gap, outside the reader's crop - and is measured on the r6 off-crop pool (probe 0.626/0.604
transferred) against the gap-framed pool (0.948/0.917). It bounds what a loss or head can do **on a
given pool**; it says nothing about whether a pool with 13x fewer, owner-verified cells changes the
transfer, which is exactly what PU.66 round 3 measured for the detector ("removing tracker-boxed
frames is the largest single improvement in the table", `docs/TASKS.md:1065`). So: either the owner
accepts the r6-pool sweep as this row's answer, with the reason recorded (the ceiling makes the
expected gain small, and the hand-box pool is 13x smaller at today's verified count), or the hand-box
arm is drafted as its own row (drafted below, R1).

**Everything else in the method is faithful**, and I checked it rather than assumed it:

- eq. (5)'s shape, `FL = -alpha_t (1-p_t)^gamma log(p_t)`, with the modulating factor from the HARD
  target and the CE term against the smoothed one - A4 exactly - at `train.py:127-135` (`hard`
  captured at `:246` before smoothing at `:247-248`, and passed to the loss at `:249`). ✓
- The dp-only arm A2(i): `pos_weight[7] = args.dp_pos_weight` (`train.py:215-216`), ones elsewhere. ✓
- `--focal-alpha` is a single scalar over all 8 bits, which is neither A2(i) (dp-restricted) nor
  A2(ii) (per-bit `alpha_t` from inverse frequency). Since the row ran focal at gamma 2 with no
  alpha (per its own text), no arm depends on this; but the instrument as built cannot run A2(ii),
  and the note lists A2(ii) as the paper-faithful variant "kept in the sweep" (`:336`). Record it as
  not-built, or build it - it is ~5 lines.
- CoordConv per Liu et al. §3 as A8 specifies: constant `i`,`j` buffers scaled to [-1,1] over 48x32,
  registered as buffers (`model.py:56-58`), concatenated before the stack (`:61-62`), first conv
  widened 3→5 keeping k=3 (`:48`, `:50`), GAP and `Linear(64,8)` kept (`:54`, `:64`). No `r`
  channel - A8 lists it as optional. ✓
- The flatten head per §2.4/A7: `Flatten` + `Linear(1536,8)`, everything upstream identical
  (`model.py:54`, `:64`). ✓
- Export/device surface unchanged as §3.2 predicted: `export.py:49` and `score.py:337` only gained
  the head read; the flatten candidate really did go through Core ML (`.out/pu73-flatten-s0/
  PumpSegments.mlpackage` exists, **88 KB** vs the control's and the shipped model's **64 KB**) and
  was scored through the app's own path. No Swift change, no new op. ✓
- Parameter counts, which I recomputed: gap **24 328**, flatten **36 104** (+11 776), coord
  **24 616** (+288) - the note's §2.4/§3.2 arithmetic exactly. ✓

---

## Item 2 - wired into the app path, not only the harness: **MET** (by construction, for a no-ship row)

Nothing ships, so the correct test of this item is that the app path is untouched *and* that the
candidates were measured on it rather than in a harness. Both hold:

- No Swift file is in this row's diff. `git status --short ios/` shows only `PumpPhotoGate.swift`
  (PU.78's 45→47), `PumpReadingLaw.swift` and `PumpReadingLawTests.swift` (PU.78/PU.81),
  `PumpReaderPipelineTests.swift` (PU.78's floor 112→118), and the untracked
  `PumpReadingLawExactTests.swift` (PU.78). The shipped `ios/App/Resources/PumpSegments.mlpackage`
  is unmodified, so `PumpDisplayCapture.classify` and `CapturePipeline` run exactly what they ran
  before this row, in Debug and in Release.
- The candidates were scored **on the app path**: `PUMP_MODEL=` (`PumpReaderPipelineTests.swift:78-80`)
  points `livePath` at a candidate `.mlpackage`, and the four tier logs are `livePath` runs -
  "PU.63 live path (the app's classify)". So the flatten arm's +0.044 dp AUC was carried all the way
  to the phone's entry point and refused there, not refused in Python. This is the opposite of the
  "docs naming behaviour with no call site" shape.
- The new instrument (`--head`, the loss flags) is training-side only by design and is not reachable
  from the app; that is correct for a row whose outcome is a refusal, and the checkpoint's `head`
  key is read by every loader in the tree: `export.py:49`, `score.py:337`, `temperature.py:148`
  (PU.72's file, carrying this row's one-line head read as the brief says). No other checkpoint
  loader exists (`grep SegmentNet\(|torch.load` over `ml/`).
- Legacy checkpoints are handled: `.out/train-r6-real/segmentnet.pt` and this row's own
  control/posw/focal checkpoints have **no `head` key** (they were written before `train.py:267`
  gained it - I checked the `torch.load` key sets), and `state.get("head", "gap")` defaults them
  correctly. Their state dicts are gap-shaped (`features.0.0.weight (16,3,3,3)`,
  `classifier.weight (8,64)`), while flatten's is `(8,1536)` and coord's stem is `(16,5,3,3)` with a
  `coords` buffer - so the recorded head and the weights agree in every artifact, and a wrong
  default would crash on `load_state_dict` rather than silently mis-score.

---

## Item 3 - measured on the app path, on the named population: **PARTIAL**

MET: `livePath` ran for all four candidate configurations; the committed/correct counts are in the
gate evidence and I verified every one against the logs; `PumpPhotoGate`'s reader constants are
untouched by this row (47/47/183 at `PumpPhotoGate.swift:86,91,95`, `committedFloor` 118 at
`PumpReaderPipelineTests.swift:30`, both PU.78's) and therefore still describe the shipped
model; **zero new wrong readings on the app path**, because nothing shipped.

Four gaps:

**3a. The row's baseline number is real but uncited, and the population moved without either
document saying so.** The row compares the arms "against the shipped r6's 116/116 annotated and
47/47 live". That baseline exists - `/tmp/agentlogs/pu69-swifttest.log:5242` ("committed 116,
correct 116, precision 1.000 ... of 181") and `:5274` ("committed 47, correct 47, precision 1.000
... of 181") - and it is the right one: it ran at 04:00 with no `PUMP_MODEL`, i.e. the shipped model,
**after** `PumpReadingLaw.swift`'s last edit (01:42) and before the candidate runs (05:40-06:05), so
candidates and baseline share a tree and a law. Cite it; the row currently gives a number with no
artifact.

The dp-AUC population needs one clause too. I re-ran the note's own surviving instruments and
reproduced the row's baseline exactly:

```
dpauc.py     (single crop): 67 stills, 184 windows, 864 cells, 183 dp+ (0.2118),
                            dp_auc 0.6408, digit_only_acc 0.9363   [shipped train-r6-real]
dpauc_tta.py (5-crop TTA) : 67 stills, 184 windows, 864 cells, 183 dp+ (0.2118),
                            dp_auc 0.6527, digit_only_acc 0.9410   [shipped train-r6-real]
```

So the row's "**0.653**" is the **TTA** figure - the app's path - and it is correct. But it is not
the note's 0.6452/0.6569, and the reason is that the population moved: `ios/.build/pump-reader-out/
slices.json` was re-cut at **2026-09-24 03:52**, after the note ran (its scripts are dated
00:48-01:01) and before the arms were scored (04:56, 05:31). Under the note's file the population was
186 windows / 873 cells / 185 dp+; under the current one it is 184 / 864 / 183, identically for the
HEAD snapshot and the working tree (pump-275 is `reviewed` in both but contributes no count-matched
window in the current `slices.json`). Good news: baseline and arms are on the **same** 864 cells, so
every comparison in the row is internally valid. The row should say which - "864 cells
(`slices.json` re-cut 03:52; the note's 873 was the previous cut), TTA" - because as written the
reader cannot tell whether 0.653 and 0.677 are the same mode on the same cells. They are; nothing
records it.

**3b. A12 - PU.72's calibration discipline - was applied in neither of its two branches, and the row
does not mention it.** The row's Checks cell promises the round runs "after PU.72's calibration so a
margin shift is not mistaken for a gain". A12 (`:346`) gives the fallback for exactly this situation:
"if PU.72 has not landed at build time, the fallback is **reporting the median committed-cell margin
(raw nats) beside every tier number**". PU.72 has not landed (its row is `[ ]`, `temperature.py` is
uncommitted). `grep -i "margin|nat|temperat|calibrat"` over all four tier logs → **no matches**; the
row's result cell has no margin figure either. This matters for one specific claim in the row:
"the retrained control 111/109 and 42/42 (**retraining on today's code and pool already loses
ground**)". Committed-cell counts under fixed nat windows (`PumpReadingLaw.swift:39` `readWindow` 6.0,
`:34` `ambiguityWindow` 3.0, `:44` `decimalMarkPenalty` 4.0) are exactly the quantity a margin-scale shift moves
without any reading changing - the confusion F5 (`:442-444`) and PU.72 exist to prevent. The refusal
does not depend on it (F3 refuses on wrong readings, and the control is refused for losing commits
whether that is scale or reading), but the *explanation* the row offers does. Fix: report the median
committed-cell margin for the shipped model, the control and one flatten seed (the harness already
has the nat margins; `PumpReadTool` prints them per cell), or fit T with the `temperature.py` that is
sitting in the tree and restate the windows, or delete the causal claim and leave the numbers.

**3c. "r6's recipe" is not r6's recipe, and the control proves it.** The row says "r6's recipe,
3 seeds per arm". Compare the artifacts:

| | `train-r6-real` (shipped) | `pu73-control-s0` (same seed 0, same pool, same steps) |
|---|---|---|
| final val digit accuracy | **0.8132** | **0.7838** |
| final val loss (plain BCE) | 0.12329 | 0.146247 |
| dp bit accuracy | 0.8822 | 0.8822 |
| annotated / live on this tree | 116/116, 47/47 (`pu69-swifttest.log:5242,5274`) | 111/109, 42/42 (`pu73-tiers-control-s0.log`) |
| `metrics.json` keys | no `dp_crop`, no `priors` (predates both flags) | `dp_crop: "gap"`, `priors: "default"` |

Same seed, same 15 000 steps, same pool, same `real_frac` 0.3, same contrast 0.15 - and a 3-point
digit-accuracy and 5-live-cell gap. The cause is identifiable and the row does not name it: the
**synthetic renderer changed** between r6's training commit (`d781416c`, 2026-09-20 02:05, the last
commit before r6's 02:39 checkpoint) and HEAD. `git diff d781416c..HEAD -- dataset.py` shows
`TECHNOLOGY_PRIORS` moving 0.85/0.10/0.05 → **0.80/0.15/0.05** (`dataset.py:43`) and the new
grey-LCD palette - `REAL_CONTRAST_QUANTILES` (`:50`), `GREY_PALETTE_PROB = 0.75` (`:53`), drawn at
`:146`, `DARK_ON_LIGHT_PROB = 0.94` - which PU.41 round 11a added and measured as "+2 annotated /
+7 live" for the *detector-era* pool. `train.py` exposes `--priors` (`:173`) but **no switch for the
grey palette**, and the arms recorded `priors: "default"`, i.e. the new mix, not r6's. So the shipped
recipe is not reproducible from today's CLI at all, and the control is not a reproduction of it.

The row's parenthetical is also wrong on one of its two nouns: "**today's code and pool**". The pool
is byte-identical to r6's - `.out/real/{cells.npz,manifest.json}` mtime **2026-09-20 02:25:57**, r6's
checkpoint 02:39:10, r6's metrics name `"real": ".out/real"` with the same `real_cells: 25085`, and
its manifest lacks the `dp_crop` / `cap_fixture` / `hard_weight` / `centred` keys that
`realglyphs.py:360-378` writes today, so it is the r6-era export. All 15 arms trained on it. Only
the code moved. Fix: strike "and pool", name the renderer as the cause with the two constants, and
say what that means for the sweep - every arm inherits a renderer the control shows is ~0.03 digit
accuracy worse than the shipped one, so "+0.044 dp AUC over control" is a statement about today's
renderer, not about r6's. (It is not a statement that can be turned into a ship decision anyway -
flatten is refused - but the row reads as if the round were recipe-faithful, and a future round will
copy it.)

**3d. `--dp-crop` was left at train.py's default, against the note's explicit instruction.** §3.4
(`:308-315`) says "Every round command pins `--dp-crop off` explicitly until the owner decides
otherwise", and files the default disagreement as finding §7-1. The instruction is impossible as
written - `train.py:162` offers only `gap|none`, there is no `off` (the `off` choice lives in
`realglyphs.py:291`, which is where framing is actually decided, and the pool was cut before that
flag existed). The arms ran at train.py's default `gap`, which in that file only means "train all 8
bits" (`dp_bits = args.dp_crop != "none"`, `train.py:186-187`) - so the framing came from the pool,
which is the shipped off-framing, and the arms are consistent with each other and with r6's 8-bit
training (r6's dp bit accuracy is 0.8822, not 0.5, so dp was trained). **No harm done, but the note's
instruction was not followed and the row does not record that it could not be.** One clause closes
it, and §7-1's finding (below, R2) is what actually owns the trap.

---

## Item 4 - no regression elsewhere: **MET**

- **Receipt leak**: unchanged by construction - no Swift file, no reader, no decision rule moved.
  The leak is a property of `PumpDisplayCapture`/the display decision, which this row does not touch.
- **Annotated floor and the law's oracle ratchet**: unchanged, same reason. `PumpReadingLaw.swift`
  and the law suites carry PU.78/PU.81's uncommitted work, which I was told to ignore and did; the
  candidate tier runs failed the floors (116 < 118, 44 ≠ 47) *because they are candidates*, and the
  shipped configuration still reads 116/116 and 47/47 on this tree (`pu69-swifttest.log:5242,5274`).
- **Latency**: no hot path is touched. Round A adds zero inference cost by construction (the loss is
  training-only and the exported graph is byte-shape identical: control package 64 KB = shipped
  64 KB). Round B's flatten would have added +11 776 MACs/cell (+0.28 %) and 24 KB of package - the
  note's §6 arithmetic, which I confirmed from the parameter counts - and it is refused, so no
  Release number is owed for the app. See item 7 for the Checks cell's promise.
- **Debug vs Release**: the candidate tier runs and the shipped baseline were both measured with
  Debug `swift test`, i.e. the same configuration on both sides of every comparison. Correct for a
  refusal; a Release number would only be owed by a ship (PU.67's row is the precedent).
- **ML suite**: exit 0, 60 passed, in my hands as well as the orchestrator's.

---

## Item 5 - tests that would fail: **PARTIAL** (3 of 7 mutations went red; 4 stayed green)

There is **no mutation log in the gate evidence** for this row (`/tmp/agentlogs/` has
`pu72-mutation-*`, `pu78-mutation-*`, `pu69-mutation-*` and nothing for pu73), so I ran the mutations
myself, in a copy of the package outside the repo, with the repo venv. Verbatim from
`/tmp/agentlogs/pu73-review-mutations.log`:

| # | Mutation | Result | Evidence |
|---|---|---|---|
| M1 | `train.py:132` focal factor → `torch.ones_like(p_t)` (gamma ignored) | **RED** ✓ | `FAILED tests/test_segment_loss.py::test_focal_down_weights_easy_examples - assert (tensor(0.0025) / tensor(0.0025)) < 0.01`; `1 failed, 7 passed`; **pytest exit 1** |
| M2 | `train.py:128` drop `pos_weight=` from the BCE call | **RED** ✓ | `FAILED ...::test_dp_pos_weight_touches_only_the_dp_bit - assert 0.1732867956161499 < 1e-06`; **pytest exit 1** |
| M3 | `train.py:136` `ce.mean()` → `ce.sum() / hard.sum()` (the note's A6 reduction) | **RED** ✓ | `FAILED ...::test_defaults_are_exactly_bce - assert False ... allclose(tensor(2.7635), tensor(0.8204))`; **pytest exit 1**. This is the proof that the shipped-default equivalence is pinned against a reduction change - and simultaneously the proof that the code chose `mean`, i.e. 1a |
| restored | copy back | **GREEN** ✓ | `3 passed`, **pytest exit 0** |
| M4 | `train.py:216` `pos_weight[7] = ...` → `pos_weight[:] = ...` (weight on all 8 bits) | **GREEN** ✗ | `8 passed`. The "dp alone" wiring the row promises is unpinned: `test_dp_pos_weight_touches_only_the_dp_bit` builds its own weight vector and never exercises `train.py` |
| M5 | `model.py:48,61-62` CoordConv stops widening the stem and stops concatenating coords | **GREEN** ✗ | `8 passed`. `test_coord_with_zero_coordinate_weights_is_the_plain_stem` is **vacuous**: with the concat removed, the coord model *is* the plain stem, so the equivalence it asserts holds trivially. The row's "CoordConv with zeroed coordinate weights equals the plain stem, pinned" is not pinned against CoordConv being absent |
| M6 | `model.py:54,64` flatten head silently becomes the gap head | **GREEN** ✗ | `8 passed`. No test fails if `--head flatten` trains and exports the shipped architecture - the arm the row's entire +0.044 rests on |
| M7 | `train.py:170` `--dp-pos-weight` default 1.0 → 3.52 | **GREEN** ✗ | `8 passed`. The row's "defaults = the shipped unweighted BCE, **pinned by `test_segment_loss.py`**" is true of the loss *function* (M1-M3) and false of the *CLI defaults*: `test_segment_loss.py` constructs `segment_loss(...)` directly, and nothing asserts the argparse values. (`--head`'s default IS indirectly pinned: `test_export_roundtrip.py:45` loads a smoke checkpoint into `SegmentNet()`, so a non-gap default fails `load_state_dict`.) |

M4-M7 are the "test that stays green when its behaviour is removed" shape. **The measurements are
nevertheless sound** - I verified the artifacts directly rather than trusting the tests:
`.out/pu73-flatten-s0/segmentnet.pt` has `head="flatten"` and `classifier.weight (8,1536)`,
`-s2` the same, `.out/pu73-coord-s0` has `head="coord"`, `features.0.0.weight (16,5,3,3)` and a
`coords` buffer, and the exported flatten package is 88 KB against the control's 64 KB. So the arms
ran what they claim; the suite just would not notice if they had not.

Fixes, all small and none needing a re-run:
1. `test_model.py`: assert `SegmentNet("coord").coords.shape == (1,2,48,32)`, its range within
   [-1,1], `features.0.0.weight.shape[1] == 5`, and that a coord net with **non-zero** coordinate
   weights differs from the plain stem (that is the assertion M5 cannot survive).
2. `test_model.py`: assert `SegmentNet("flatten").classifier.weight.shape == (8,1536)` and that a
   flatten net's output differs from a gap net's on the same input (kills M6).
3. `test_segment_loss.py` or `test_train_smoke.py`: assert the argparse defaults
   (`--dp-pos-weight 1.0`, `--focal-gamma 0.0`, `--focal-alpha None`, `--head gap`) - e.g. via
   `train.main`'s parser or a `--smoke` run whose `metrics.json` records them, which 1b asks for
   anyway (kills M7).
4. Factor `train.py:214-216` into a named function (`dp_pos_weight_vector(n_bits, w)`) and assert it
   returns ones except index 7 (kills M4).

---

## Item 6 - docs reconciled: **PARTIAL**

- `docs/TASKS.md:1076` - the row is ticked `[x]`, its result cell is dense and its numbers are
  accurate (I checked every one against the logs); `tasks-index.py --check` and
  `scenario-index.py --check` both exit 0. But it carries the four inaccuracies above ("r6's recipe",
  "code and pool", the uncited 0.653/baseline, the unrecorded A12 and A11 departures) and drops two
  Checks-cell promises silently (item 7).
- `docs/EXTRACTION.md` - **no PU.73 content at all**; the only mention is PU.78's parenthetical
  "(read quality, PU.73)" at `:1104`. Nothing in the pump reader section is *stale* because of this
  row (there is no dp-AUC or head claim in that file - I grepped), so no correction is owed. But the
  note's §7-2 finding was written for this file and has nowhere else to live: "the dp label's
  unreachability is a corpus-geometry fact, not a model defect ... Recorded so the next reader of
  'dp AUC 0.65' does not re-run this row's probes" (`:478-483`). PU.78, a measurement row that also
  shipped a refusal of its M3, got a paragraph at `:1095-1108`. PU.73 owes one of ~5 sentences: the
  shipped model's measured dp AUC (0.641 single crop / **0.653 on the app's 5-crop TTA path**, over
  864 heldout count-matched cells), the ceiling and its cause (the mark sits in the inter-cell gap,
  outside the reader's cell rect - a linear probe reaches 0.92-0.95 on gap-framed cells and
  0.60-0.63 transferred under the shipped framing), the flatten result and its refusal (+0.044 dp AUC
  and +0.010 digit accuracy, every seed adding wrong readings), and the consequence that **PU.78's
  hard dp-consistency check stays unearned** (its note blocked M4 on this row; 0.73 against a ~0.75
  ceiling is not 0.9). Without that last clause nothing in the tree records that M4 was ever blocked,
  let alone why it stays so - `grep -c M4 docs/TASKS.md` → 0.
- `docs/ERRORS.md`, `docs/JOURNEYS.md` J4/F2 - correctly untouched: the user sees nothing different.
- **The note's §7 findings are filed nowhere.** §7-1 (the `--dp-crop` defaults disagree and "no row
  owns the defaults") and §7-3 (inference-time gap framing, "the only measured lever left", with the
  seam named: `PumpReader.cropCell` / `averaged` and the slicer's rect construction) exist only in
  `agents/research/PU.73.md`, which is untracked. §7-4 (verified-frame supply) is already covered by
  PU.66's round-3 verdict. Rows drafted below (R2, R3).
- **Durability.** The sweep's per-run records live only in gitignored `.out/pu73-*/metrics.json` and
  volatile `/tmp/agentlogs/pu73-*.log`. The repo's own precedent is the opposite: `runs/2026-09-22/
  metrics/*.json` is **tracked** (44 files under `runs/`), PU.41's Checks cell asks for "the three
  seeds' table in REPORT.md beside round 10's", and `REPORT.md` has no section for this round (not
  modified in the working tree). Cheap fix: copy the 15 `metrics.json` to
  `ml/pump-reader/runs/2026-09-24/metrics/` and add a short REPORT.md round section with the two
  tables from this review - otherwise the next classifier round starts from a /tmp file that a reboot
  removes.
- **CLAUDE.md comment rules**: the touched files carry current truth only, no before/after stories,
  no mutable counts, and the promises they make are the ones the tests hold
  (`train.py:122-125` states the gamma-0/unit-weight equivalence that M3 proves is pinned;
  `model.py:36-41` describes the three heads as built). One observation, not a defect for this row:
  `train.py:163` and `model.py:36` name the task id ("PU.73 Round A", "PU.73 Round B"), which
  CLAUDE.md forbids in code comments - but `ml/pump-reader/src` already carried **36** such
  references at HEAD and has 42 in the working tree (PU.72's and PU.73's additions make up the six),
  so this is a repo-wide decision about the ML package's convention, not something PU.73
  introduced or should fix alone. Flagging it so the owner can decide once.
- Include the untracked artifacts in the commit: `agents/research/PU.73.md`,
  `agents/briefs/RESEARCH-PU.73.md`, `agents/briefs/REVIEW-COMPLETE-PU.73.md` and this review -
  `train.py:163` and `model.py:36` cite the note by path.

---

## Item 7 - everything the row promised, sentence by sentence (`docs/TASKS.md:1076` Checks cell)

| Promise | Verdict | Note |
|---|---|---|
| "Round per change (focal/pos_weight; head)" | **MET** | 15 runs: control, posw, focal, flatten, coord x 3 seeds, all in `.out/pu73-*`, one change per round against a same-pool control as §5.3 prescribes |
| "each scored on annotated AND live" | **PARTIAL** | Only flatten (3 seeds) and the control (1 seed) were; posw, focal and coord were not, and no export exists for coord (no `.out/pu73-coord-s0/PumpSegments.mlpackage`). §5.3 says "every candidate exported, scored with `PUMP_MODEL=` on BOTH tiers". The row's wording discloses what ran ("The flatten seeds and one control scored on both tiers") but not that it is a departure, and F2 does not by itself authorize skipping the tiers - it closes the *row* on a no-gain finding. Defensible (an arm that does not beat the control's dp AUC cannot meet the ship gate), but it needs the reason in the row rather than the reader's inference |
| "after PU.72's calibration so a margin shift is not mistaken for a gain" | **MISSING** | Neither A12 branch: no per-candidate T, no median committed-cell margin beside the tier numbers (3b). PU.72's own row says this comparison "moved into PU.73's checks" pending the owner's call, so this was the place it was supposed to happen |
| "dp AUC on real cells reported" | **MET** | Per seed, per arm, over a stated cell count; the mode (single crop vs TTA) and the population's provenance unstated (3a) |
| "ships only on live up at zero wrong readings" | **MET** | Nothing ships; no arm met it; the refusal is F3-correct and the arithmetic checks out (headline table) |
| "model size and Release per-cell latency reported" | **MISSING** (size), **PARTIAL** (latency) | Neither appears in the row. Both are cheap: I measured **gap 24 328 params / 64 KB package, flatten 36 104 / 88 KB, coord 24 616** (not exported). Latency: no candidate ships and no Swift path changed, so no Release number is owed - but the row must *say* that instead of dropping the promise (PU.78's row is the precedent: "Latency: immaterial by construction - ...") |
| Result cell: "the checkpoint records its head and every loader reads it" | **MET** | `train.py:267`; `export.py:49`, `score.py:337`, `temperature.py:148`; legacy keyless checkpoints default to gap and are exercised by r6 and by this row's own Round-A artifacts. Not pinned by a test (a `state["head"]` mutation would stay green), but a wrong default crashes rather than mis-scores |
| Result cell: "CoordConv with zeroed coordinate weights equals the plain stem, **pinned**" | **PARTIAL** | The test exists (`test_model.py:31-48`) and passes, but M5 shows it also passes with CoordConv removed - it is not a pin |
| Result cell: "defaults = the shipped unweighted BCE, **pinned by `test_segment_loss.py`**" | **PARTIAL** | The loss equivalence is pinned (M1/M2/M3 red). The CLI defaults are not (M7 green), and "the shipped ... BCE" is true of the loss only - the shipped *training run* is not reproducible from today's defaults (3c) |
| Result cell: "r6's recipe" / "today's code and pool" | **PARTIAL** | 3c: the renderer moved (priors + the grey palette, one of them with no switch); the pool did not |
| Result cell: "re-score flatten s2 after PU.74 lands" | **MET as a follow-up**, but it is not filed | PU.74 is an open row; nothing in it or in PU.73's row makes the re-score a step of either. One clause in PU.74's row, or a line in PU.73's, so the promise outlives this file |

---

## Rows drafted here (the template's rule: a gap the row cannot close becomes a row, never dropped)

**R1 - the classifier's hand-box pool (A11, PU.73's undelivered arm).** *(J4 pump display photo)*
PU.73's premise scoped the sweep "on hand boxes"; the run trained on `.out/real`, whose hand-boxed
subset is 1 899 of 25 085 cells (7.6 %, note §3.3), and `realglyphs.py` has no `--hand-only`. PU.66
round 3 measured for the detector that removing tracker-boxed frames is the largest single
improvement in its table, and 273 train frames are owner-verified today against the 2 records that
reached the r6-era pool (note §7-4). **Checks**: `realglyphs --hand-only` restricting frame windows
to `frames.verified = 1` (precedent `detdata.py:205-209`); step 0 re-export first
(`PUMP_TRAIN_EXPORT=1 swift test --filter PumpTrainSliceExportTests`), the note's §3.3 reason being
that the standing `train-slices.json` predates the read phase and batch 7; pool size and dp rate
reported; one control per pool plus the flatten arm, 3 seeds each, scored on both tiers with A12's
margin median; the pool's effect isolated by the control, never attributed to the head. **Owner call
first**: whether to run it at all, given PU.73's measured ceiling (note §0) and the 13x data cut.

**R2 - the `--dp-crop` defaults disagree and no row owns them (note §7-1).** *(no-scenario: tooling)*
`train.py:162` defaults to `gap` and offers only `gap|none`; `realglyphs.py:291` defaults to `none`
and offers `off|gap|none`; the shipped framing is `off`, decided by the pool, not by train.py's flag.
A round that forgets which file it is in trains on gap-framed cells against off-framed inference
(r11's measured −33 annotated / −15 live) or on cleared dp bits whose untrained 8th output still
fires (0.186 vs 0.892 digit-only). PU.73 hit the trap's edge and stepped off it only because the pool
was r6's. **Checks**: one vocabulary across the two files, or two differently-named flags
(`--dp-bits` for train.py's 7-vs-8 choice, `--dp-crop` for realglyphs' framing); the default is the
shipped framing; `metrics.json` and the pool manifest each record what was used; a test that a
pool built `off` and a train run at the default agree.

**R3 - inference-time gap framing for the dp bit (note §7-3, the only measured lever left).**
*(J4 pump display photo)* Owner decision, not an implementer's fix: the dp mark usually sits outside
the reader's cell crop, so a probe on gap-framed cells reaches 0.948/0.917 while the shipped framing
transfers at 0.626/0.604 (note §0). Widening `PumpReader.cropCell` (`PumpReader.swift:572`) /
`averaged` (`:580-587`), or a dp-only second crop per cell, touches **every bit's** framing and needs
its own controlled round - r11 measured that changing the training framing alone costs 33 annotated
and 15 live cells. **Checks**: a Swift reader change with the framing decision recorded in
`docs/EXTRACTION.md`; training and inference framings pinned equal by a test; both tiers, both
framings, 3 seeds; dp AUC and digit accuracy on the 864-cell population; bundle and Release
per-cell latency. If the owner declines, the decline belongs in the row and in EXTRACTION.md's new
paragraph, because it is what closes PU.78's M4 for good.

---

## What the orchestrator must do before this row can be committed

Text-only, ~20 minutes, no re-run:

1. **Row corrections** (`docs/TASKS.md:1076`): strike "and pool" and name the renderer as the cause
   of the control's divergence (`dataset.py:43,50,53,146` since `d781416c`; `--priors` recorded
   "default" = 0.80/0.15/0.05, not r6's 0.85/0.10/0.05; no CLI switch for the grey palette); replace
   "r6's recipe" with "r6's steps/pool/real-frac on today's renderer, which the control measures
   0.03 digit accuracy below r6's own"; cite the baseline log
   (`/tmp/agentlogs/pu69-swifttest.log:5242,5274`); state the dp-AUC mode and population provenance
   (0.653 = 5-crop TTA, the app's path; 864 cells / 184 windows / 183 dp+ from `slices.json` re-cut
   03:52, the note's 873 being the previous cut).
2. **Report the model sizes** (gap 24 328 / 64 KB, flatten 36 104 / 88 KB, coord 24 616) and the
   latency sentence ("immaterial: nothing ships, no Swift path changed; the flatten head would have
   added +11 776 MACs/cell, +0.28 %, and 24 KB").
3. **Say plainly what was not done and why**: the hand-box pool (A11 / step 0) - not built,
   `realglyphs` has no `--hand-only`; A12's calibration discipline - neither branch; A6's positive
   normalization - `mean` used instead; A6/§6's `metrics.json` fields - absent, so the arms'
   gamma/alpha/pos_weight are not recoverable from the artifacts; tier scoring for the posw, focal
   and coord arms - skipped, with F2 named as the reason; §5.3's per-candidate export - not done for
   coord.
4. **The `docs/EXTRACTION.md` paragraph** (item 6), including that PU.78's hard dp check stays
   unearned and what the measured ceiling is.
5. **File R1, R2, R3** (or record the owner's decline of R1 and R3 in the row), and put the
   "re-score flatten s2 after PU.74" promise somewhere that outlives this file.
6. **Preserve the sweep**: the 15 `metrics.json` into `ml/pump-reader/runs/2026-09-24/metrics/` and a
   short REPORT.md round section.
7. **Commit the untracked artifacts** the code cites by path.

Code, ~30 minutes, no re-run:

8. The four test additions from item 5 (M4-M7 must go red).
9. `metrics.json` records `head`, `dp_pos_weight`, `focal_gamma`, `focal_alpha` and the reduction
   (A6/§6) - then the next round's arms are self-describing.

Needs a re-run, or the owner's OK to skip:

10. **A6's normalization** (1a): implement it behind a flag and re-run the 3 focal seeds (~50 min),
    or record the departure and soften the "focal loss is a measured no-op" claim. My recommendation:
    record it. The arm's dp AUC (0.6802 mean) sits *below* the control's, and a normalization that
    raises the effective LR by ~4x is not going to turn a −0.002 into a gain that clears a 0.013 seed
    spread - but the row must stop claiming the published method was measured.
11. **A12** (3b): the margin median for the shipped model, the control and one flatten seed (cheap -
    `PumpReadTool` already prints per-cell margins), or T per candidate from the `temperature.py` in
    the tree, or delete the "loses ground" causal claim.

**Owner calls**: R1 (run the hand-box arm, or accept the r6-pool sweep as this row's answer with the
reason recorded); R3 (the gap-framing lever, which is also what retires PU.78's M4); and, once, the
ML package's task-id comment convention (item 6).

---

## Verdict

**INCOMPLETE.**

Items 2 and 4 are MET. Item 3 is PARTIAL (3a-3d). Item 5 is PARTIAL (four green mutations, and no
mutation evidence in the gate at all). Item 6 is PARTIAL (no EXTRACTION.md record, §7-1/§7-3 unfiled,
the sweep's metrics only in /tmp and gitignored `.out`). Item 7 is PARTIAL through the sentences in
its table. **Item 1 is MISSING**: three departures the note lists as adaptations and the code does
not implement - A6's positive-target normalization (**Lin et al. 2017 §4.1**), A6/§6's `metrics.json`
logging of the loss choice, and A11/§3.3's hand-box pool and step-0 re-export - plus A12's
calibration discipline, which the row's own Checks cell promises and neither branch of A12 delivers.

None of this overturns the result. The refusal is correct under F2 and F3 on arithmetic I
recomputed, the no-ship is stated plainly, the app path is untouched, and the flatten arm's +0.044
dp AUC is real and reproducible from the checkpoints and the exported packages. What is not yet true
is the row's account of *what was run*: it describes a recipe-faithful, calibration-disciplined,
hand-box sweep with pinned defaults, and the tree describes a same-pool control-relative sweep on
today's renderer, with the loss hyperparameters recorded nowhere and four of its "pinned" claims
unpinned. Items 1-9 above are text and tests; 10-11 are the two measurements the note asked for and
the row owes either the run or the recorded departure.

Re-dispatch a fresh copy of `REVIEW-COMPLETE-PU.73.md` once 1-9 are in the tree and 10-11 are either
run or recorded with the owner's OK.
