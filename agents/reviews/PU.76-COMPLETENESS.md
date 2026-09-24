# PU.76 completeness review

Run 2026-09-24 against the uncommitted PU.76 spike diff. Scope is the seven spike files named in
`agents/briefs/REVIEW-COMPLETE-PU.76.md`, the note `agents/research/PU.76.md`, the report
`agents/research/PU.76-SPIKE.md`, and the named evidence logs. Read-only except this review. I ran
`.venv/bin/python -m pytest -q` in `ml/pump-reader`: **exit 0, 73 passed in 17.25 s**. I did not run
`scripts/gate.sh`; the supplied `pu76-gate.log` was inspected and its only failure is the
pre-existing `SyncWriteTriggerTests` (RV.157/RV.203) suite, which the standing fences name as
load-flaky and unrelated to this spike (`/tmp/agentlogs/pu76-gate.log:8521-8873`, 2305 tests, 4
issues all in "Debounced write trigger").

## 1. Fidelity — PARTIAL

The three things the brief pins are present and match the note's §2.1:

- **Targets §4.1** (`segnet.py:68-94`): overlap pixels negative (`count != 1 -> ids 0`), links
  same-instance, instance-balanced weights `per = total/n`, `weight = per/area` (eq. 2).
- **Loss eqs. 1-4** (`segnet.py:97-118`): `LAMBDA = 2.0` (`:34`), `OHEM_RATIO = 3` (`:35`), OHEM
  top-k negatives `n_neg = min(..., r*n_pos)` (`:106`), pixel normalised by `(1+r)*n_pos` (`:109`),
  link split into pos/neg each normalised by its weight sum (`:111-114`), link loss over positive
  pixels only (`w = weight * pos`, `:112`).
- **Decode §3.3** (`segnet.py:121-164`): pixel/link thresholds, union-find over positive pixels
  joined by a positive link in either direction (`:136-147`), one `cv2.minAreaRect` per component
  (`:154`), post-filter by short side/area (`:157`), confidence = component mean pixel probability
  (B3, `:163`).

The sigmoid-for-2-channel-softmax reparameterisation is flagged in the module docstring
(`segnet.py:7`) and is mathematically equivalent, not a departure. B1-B8 and B9 are all named in the
report. But three departures the implementer added are **not** listed as adaptations (the note's own
fence, `PU.76.md:321`, requires the owner's OK for any departure outside B1-B8):

1. **Optimizer.** The note commits to "SGD/xavier-from-scratch schedule (§5.2)" as applied-as-is
   (`PU.76.md:352`) and the spike plan repeats "paper's schedule, xavier from scratch"
   (`PU.76.md:413`). The code uses **Adam + OneCycleLR, lr 1e-3** (`segtrain.py:109-110`). The report
   states "Adam one-cycle 1e-3" (`PU.76-SPIKE.md:24`) but never flags it as a departure from the
   note's SGD/xavier, and it is neither B1-B8 nor B9.
2. **Initialisation.** No xavier init is set; PyTorch's default (Kaiming uniform) applies
   (`segtrain.py:108-110`). Same unlisted departure from "xavier from scratch".
3. **Augmentation beyond B4.** B4 is rotations only (`PU.76.md:377-382`). The code also adds random
   scale/placement (`segtrain.py:65-69`) and photometric jitter - brightness, grayscale, Gaussian
   blur (`segtrain.py:71-76`). The report names only "rotation augmentation ... (B4)"
   (`PU.76-SPIKE.md:24`), so the scale/placement/photometric arm is undisclosed. (Also B4's "+-3 deg"
   arm from `PU.76.md:378` is dropped - code does +-6 and +-12..25 only, `segtrain.py:64` - a minor
   subset, disclosed by the report's stated fractions.)

**B7 percentile mismatch.** The note's B7 says "99th percentile of train row shorter-side and area"
(`PU.76.md:393-394`, and §4 "train-split 99th-percentile post-filter rule", `:353`). The code and
report use the **1st** percentile: `np.percentile(shorts, 1)` / `np.percentile(areas, 1)`
(`segeval.py:52-66`) and "the train split's 1st percentiles (B7)" (`PU.76-SPIKE.md:23`). The report
re-describes B7 without noting it changed the percentile from the note's 99th. (For a minimum-size
filter the 1st percentile is the sensible reading, but the note is the spec and the report should say
which one it implemented and why.)

## 2. Gate numbers — MET

- Segmenter heldout line matches the log exactly: `seg-r1-eval.log:23` (median 0.861, recall@0.7
  223/252 = 0.885, false rows 0.088 = 6/68, recall@0.5 0.976, photos all rows 65, merged 1) equals
  the report's F1 table and F4 (`PU.76-SPIKE.md:40-47`).
- The quad (B9) variant matches `seg-r1-eval-quad.log:23` (median 0.861, recall@0.7 225/252 = 0.893)
  against `PU.76-SPIKE.md:50`.
- The shipped baseline (median 0.771, recall@0.7 168/252 = 0.667, false rows 0.647, recall@0.5
  0.865, photos all rows 52, merged 3) is not in a named log, but I reproduced it exactly by scoring
  `ml/pump-reader/.out/seg/shipped-heldout.json` (dump.swift output) at conf >= 0.3 with
  `rotgate.score`: median 0.771, 168/252 = 0.667, 0.647 (44/68), 0.865, 52, 3. So the report's
  numbers are correct and the baseline is in the same rotated (convex-polygon) metric.
- Thresholds chosen on **val**, never heldout: `is_val` = every 10th train still
  (`segtrain.py:32-35`), the sweep runs over val only (`segeval.py:88-98`), the size floor is computed
  on train excluding val (`segeval.py:85`), and heldout is scored once at the chosen pair
  (`segeval.py:104-110`). The chosen pair (pixel 0.9, link 0.8) is printed at `seg-r1-eval.log:22`.
- Training numbers check: 0.913 M params and ~42 min match `seg-r1.log:1,301` (params 913273, step
  30000 at 2523 s); model size 1.8 MB matches `du` of `RowSeg.mlpackage` (1.8M).

## 3. Falsifiers F1-F6 — PARTIAL (F6 missing)

F1 (gate), F2 (framing 41), F3 (3 wrong cells, 58 correct), F4 (1/68 = 1.5 % merged) and F5 (1.8 MB
/ 7 ms, latency+iPhone named "not measured") are all reported with numbers or named
(`PU.76-SPIKE.md:38-54,60-79,101-102`). **F6 is absent**: the note's F6 is the label re-pinning check
- "if after re-pinning under one rule the hand-vs-hand still agreement does not move materially from
median 0.745 / 45 %-below-0.7" (`PU.76.md:662-665`), and B5 makes the re-pin a gate step
(`PU.76.md:384-387`, "Re-pin under ONE rule first"). The report neither reports F6's number nor names
it "not measured", and never mentions re-pinning the labels at all. This is a MISSING per the brief's
rule "every falsifier F1-F6 is either reported with its number or named as not measured."

## 4. Production seam — MET

The only production-code change is `PumpRowDetector.swift` (diff +20/-5): a `private enum Backend`
(`:29-32`), an **internal** `init(rows:)` (`:56`), and a `.rows` branch in `detect(in:)` (`:60-63`) /
`.vision` guard in the pixel-buffer path (`:74`). The only caller of `init(rows:)` is
`PumpReaderTestSupport.swift:43` (test target). No file under `ios/Sources/` or `ios/App/Sources/`
references `PumpRowSegmenterSpike` or `PUMP_SEGMENTER` (grep confirmed). The public API
(`init(contentsOf:)`, `detect(in:)`, `detect(in pixelBuffer:)`) is unchanged for the `.vision`
backend, so the app is unaffected.

## 5. Verdict follows the row's rule — MET

The report's verdict - "the family closes unless the owner decides otherwise" - follows the row's own
falsifiers: F2 (framing loss 41 >= ~15) and F3 (3 wrong readings, 58 < ~65) both fail
(`PU.76-SPIKE.md:10-14`, `PU.76.md:651-653`). The "For the owner - the choices" section
(`PU.76-SPIKE.md:94-102`) presents close / keep-and-attack-the-gaps as options and does not decide.
The striking honest finding - the segmenter's quads agree better (median IoU 0.861 vs 0.771) yet
frame *worse* for the slicer (41 vs 36) - is stated plainly (`PU.76-SPIKE.md:83-88`).

## 6. pytest

`cd ml/pump-reader && .venv/bin/python -m pytest -q` -> **73 passed, exit 0** (17.25 s). The five
`test_segnet.py` tests cover polygon IoU, stacked-row targets, decode-via-links, the merge count, and
output shape/loss finiteness, matching the report's description (`PU.76-SPIKE.md:32-34`).

## Minor (not blocking on their own)

- The apportionment table mixes committed and correct counts without a label: "detected windows, hand
  quads" 106/114 are committed (`pu76-apportion-shipped.log` 106, `-seg.log` 114), while "kept
  windows, hand quads" 85/100 and "detector boxes, hand roles" 49/59 are correct counts (logs: kept
  86/85 and 101/100; boxes 49/49 and 62/59). Framing loss 36/41 is correct-consistent (85-49, 100-59),
  so the key claim survives, but the column should say which it is.
- The Swift-parity claim ("247/252 Python rows within 0.01; pump-008 1 vs 3", `PU.76-SPIKE.md:56-58`)
  has no evidence log among the named logs; the opt-in parity suite is the only producer and its
  output was not captured anywhere I can find.

## Verdict

**INCOMPLETE.** Check 1 (fidelity) and check 3 (F6) fail. What must change:

1. Report F6 with its number, or name it "not measured" - and state whether the label re-pinning
   gate step (B5) was done or deliberately skipped.
2. List the three unlisted departures as adaptations (or get the owner's OK per `PU.76.md:321`):
   Adam+OneCycleLR in place of SGD/xavier-from-scratch, default instead of xavier init, and the
   scale/placement/photometric augmentation beyond B4's rotations.
3. Reconcile B7's percentile: the note says 99th, the code and report use the 1st - the report
   should name which it implemented and why.
4. (Minor) Label the apportionment table's committed-vs-correct choice, and cite or produce a log
   for the 247/252 Swift-parity claim.
