# PU.72 research note - calibrating the eight sigmoids so the law's nat windows survive a retrain

*A run of `agents/briefs/RESEARCH-TO-CODE.md` for `PU.72` (`docs/TASKS.md:1071`). Product owner,
2026-09-23: "review the published research to apply it into the code, instead of coming up with our
own solution." Read-only except this file; every measured number below comes from scratch scripts
in `/tmp/pu72-cal/` (`fit.py`, `held.py`, `fit-results.json`) run against existing artifacts -
checkpoints `.out/train-r{6,7,8,9,10-s0,11-control-s0}/segmentnet.pt`, pools
`.out/{real,real-r7,real-r8,real-r9,real-r10,real-r11-control}/cells.npz`,
`ios/.build/pump-reader-out/slices.json`, and the frozen splits. `heldout2` was not touched.
Populations counted at HEAD `b42f38da`. Evidence rule: every claim cites a paper section/equation,
a `file:line`, or a measured number; inference is labelled.*

## 1. The citations, checked

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Guo, Pleiss, Sun, Weinberger, *On Calibration of Modern Neural Networks*, ICML 2017, arXiv:1706.04599 | arXiv abs page fetched: title, four authors, "ICML 2017" comment, v1 14 Jun 2017 / v2 3 Aug 2017, exact. Full text fetched (ar5iv): §2 eq. (3) ECE with M bins, §4.1 Platt/binning for binary heads, §4.2 eq. (9) temperature scaling, §5 Table 1, §S2 the entropy derivation. | **Correct as cited.** Method read first-hand. |
| Platt 1999, *Probabilistic Outputs for Support Vector Machines…* | Not on arXiv. OpenAlex `W1618905105` fetched: title exact, single author John C. Platt, 1999, ~4.9k citations; venue field empty in the record. The book chapter (Smola, Bartlett, Schölkopf, Schuurmans eds., *Advances in Large Margin Classifiers*, MIT Press, pp. 61-74) is confirmed by two fetched reference lists that carry it: Guo et al.'s own, and Lin et al. 2007's. **The 1999 original was not fetched**; its method below is Lin et al.'s rendering (their eqs. (1)-(2), Appendix C) plus Guo §4.1's, stated as second-hand. Year appears as 1999 (OpenAlex, Guo) and 2000 (Lin et al.) - the MIT Press volume's imprint; cite as Platt 1999. | **Correct as cited; method second-hand, labelled.** |
| (found by this run) Lin, Lin, Weng, *A Note on Platt's Probabilistic Outputs for Support Vector Machines*, Machine Learning 2007, DOI 10.1007/s10994-007-5018-6 | Found via OpenAlex title search while verifying Platt; full text fetched as PDF (12 pp): eqs. (1)-(6), Theorems 1-3, Algorithm 1, Tables I-II, Appendix C pseudocode (in LIBSVM since 2.6). | **Verified first-hand.** This is the implementable Platt: it fixes the non-convergence and overflow of Platt's own pseudocode. |
| (found by this run) Nixon, Dusenberry, Jerfel, Nguyen, Liu, Zhang, Tran, *Measuring Calibration in Deep Learning*, arXiv:1904.01685 (v2 2020) | **Caution, recorded because it cost a fetch:** the id I first recalled from memory, `1904.01672`, is an unrelated HCI paper (virtual globes). Title search on the arXiv API returned `1904.01685`; abs page and full text (ar5iv) fetched: §2.1 ECE as Guo implements it, §3.1 max-prob-only blindness, §4.1 class conditionality, §4.2 ACE, §4.3 SCE (every probability), §4.4 norm, §5.2-5.4 the metric-choice experiments, Fig. 1 right (the T minimizing ECE is not the T minimizing CE). Venue not in the fetched record; commonly cited as CVPR Workshops 2019 (unverified here, labelled). | **Verified first-hand under the corrected id.** |
| (found by this run) Henning, Hofmann, Schulte, Fraser, Friedrich, *How to Estimate Whether You Have Found Several Needles in a Haystack: Measuring Calibration in Multi-Label Text Classification*, arXiv:2609.26468 (v1 22 Sep 2026) | arXiv API title search; PDF fetched and read in full: §2.1 eqs. (1)-(5) (per-label ECE_c), §3 joint binning conceals per-label miscalibration, §4 adaptive_ML binning and eq. (7) ECE_ML (b=10, b_min=5), §6 rank robustness over b, b_min in {5,10,20} and the focal-loss/oversampling calibration results. | **Verified first-hand.** The multi-label ECE instrument this note adopts. |
| (found by this run) Schwinger et al., *Uncertainty Calibration of Multi-Label Bird Sound Classifiers*, arXiv:2511.08261, ICAART 2026 (comment field) | arXiv API search result; abstract only: per-class calibration varies; "a small labelled calibration set is sufficient to significantly improve calibration with Platt scaling, while global calibration parameters suffer from dataset variability". | **Verified at abstract level.** Cited for the per-label-vs-global evidence only. |
| (found by this run) Ding, Han, Liu, Niethammer, *Local Temperature Scaling for Probability Calibration*, ICCV 2021, arXiv:2008.05105 | arXiv API search result; abstract only: per-input temperature CNN for multi-label segmentation, post-hoc, accuracy unchanged. | **Verified at abstract level.** Cited as a considered-and-rejected departure (§4 A5). |

## 2. The methods as published

### 2.1 Temperature scaling - Guo §4.2 eq. (9), fit protocol §4 preamble and §4.2

`q = max_k softmax(z/T)^(k)`, a single `T > 0`; "T is optimized with respect to NLL on the
validation set"; "because the parameter T does not change the maximum of the softmax function, the
class prediction remains unchanged… temperature scaling does not affect the model's accuracy"
(§4.2). The §4 preamble is the split rule: "Each method requires a hold-out validation set… We
assume that the training, validation, and test sets are drawn from the same distribution." §S2
derives T as the unique maximum-entropy solution under a mean-logit constraint. Measured (§5,
Table 1, ECE with M=15): e.g. CIFAR-100 ResNet-110 16.53% -> 1.26%, ImageNet DenseNet-161 6.28% ->
1.99%; temperature beat vector and matrix scaling everywhere except Reuters, and matrix scaling
"will overfit to a small validation set" (§5). §5 also: "temperature scaling is by far the fastest
method, as it amounts to a one-dimensional convex optimization problem… the optimal temperature can
be found in 10 iterations".

For our head - eight independent sigmoids, no softmax - the per-label reading of eq. (9) is
`p'_i = sigma(z_i / T)` with one shared T. Two properties this note proves for that reading (proofs
in §3.1, checked numerically in §5): pairwise digit log-posterior differences scale by exactly
1/T, so the constrained decoder's ranking is invariant; and every nat-space comparison downstream
scales homogeneously.

### 2.2 Platt scaling - Platt 1999 as rendered by Lin et al. 2007 eqs. (1)-(2), Algorithm 1

`Pr(y=1|x) ~ P_{A,B}(f) = 1/(1+exp(A f + B))` with `f` the classifier's non-probabilistic output
(Lin eq. 1); `(A,B)` minimize the regularized cross-entropy `F(z) = -SUM [t_i log p_i + (1-t_i)
log(1-p_i)]` with targets `t_i = (N+ +1)/(N+ +2)` for positives and `1/(N- +2)` for negatives
(Lin eq. 2; Platt's regularized targets, the small-sample device). Lin Theorem 1: F is convex,
strictly iff the f_i are not all equal. Lin Algorithm 1 (Appendix C): Newton with backtracking,
`maxiter=100`, `minstep=1e-10`, `sigma=1e-12`, init `A=0, B=log((prior0+1)/(prior1+1))`; the stable
loss forms eqs. (5)/(6) never form `1-p` and never take `log(0)`. Platt's own Levenberg-Marquardt
pseudocode "may not converge" (Lin §2.1) and overflowed 589 times per run on `shuttle` (Lin Table
II) - implement Lin's, not Platt's. Guo §4.1 states the same method for neural nets ("Platt scaling
learns scalar parameters a,b… optimized using the NLL loss over the validation set"), citing
Niculescu-Mizil & Caruana 2005 for the NN rendering. Temperature scaling is "a single-parameter
variant of Platt Scaling" (Guo abstract): T is Platt with `A = 1/T, B = 0`.

### 2.3 Measuring calibration on eight sigmoids - Nixon §4, Henning §4

Guo's ECE (eq. 3) bins the *predicted class's* confidence only; Nixon §3.1 shows that blinds the
metric to the other K-1 probabilities, and §4.3 gives SCE, the per-class-probability version
("unlike ECE… SCE is guaranteed to be zero if and only if the model is calibrated"). For
independent binary heads the per-label object is Henning's eq. (5) `ECE_c`; Henning §3 shows that
binning all labels jointly "can conceal miscalibration of individual labels" (their Fig. 4), and
§4 gives the imbalance-robust scheme: adaptive_ML binning (bin positives and negatives separately,
b/2 adaptive bins each, minimum bin size b_min; they use b=10, b_min=5) and eq. (7)
`ECE_ML = (1/C) SUM_c (1/M_c) SUM_m |acc(B_cm) - pbar(B_cm)|` - an **unweighted** mean over bins,
which is what gives the confident-wrong tail the same weight as the mass. Henning §6: model
rankings are identical across all nine (b, b_min) in {5,10,20}^2, so the scheme's hyperparameters
are not a tuning knob. Nixon §5's recommendations (class-conditional, adaptive, L2) and §5.4's
Table 5 (32 metrics order 8 recalibration methods differently) are the reason this note reports
three ECE variants and fits by NLL instead (§4 A3).

### 2.4 What the multi-label calibration literature found on sigmoid heads

Schwinger et al. (abstract): on four multi-label bioacoustic classifiers, per-class calibration
differs substantially, Platt scaling from a small calibration set improves calibration
significantly, and **global** calibration parameters suffer from dataset variability. Ding et al.
(abstract): per-input (local) temperature beats global on multi-label segmentation. Both are
evidence about *which* parameterization, not about our domain; §4 names what we take and what we
reject.

## 3. The mapping onto this code

Line numbers at HEAD `b42f38da`.

### 3.1 The seam the method lands in, and the exactness theorem that constrains it

`PumpSegmentsModel.probabilities(cell:)` (`ios/Sources/TankbookCore/Extraction/PumpReader/
PumpSegmentsModel.swift:41-52`) returns the eight exported sigmoids; `rank` (:59-71) clamps to
`[1e-6, 1-1e-6]` (:60) and builds each digit's log-posterior `SUM_i [on ? log p_i : log(1-p_i)]`;
`PumpReadingLaw` consumes those log-posteriors and the nat constants `readWindow = 6.0`
(`PumpReadingLaw.swift:38`), `ambiguityWindow = 3.0` (:33), `decimalMarkPenalty = 4.0` (:43), the
preset tier's `0.5` (:102), against `closingSlack = 0.011` (:27) which lives in value space, not
nats. Calibration is applied in `probabilities(cell:)` as `p'_i = sigma(logit(p_i)/T)` (the row's
"applied in PumpSegmentsModel"), with T read from the model's own metadata (§3.3).

**Theorem (this note; the multi-label analogue of Guo §4.2's accuracy-invariance, and stronger).**
For any two digit patterns d1, d2, `LL(d1) - LL(d2) = SUM_i (on1_i - on2_i) z_i`, because
`log sigma(z) - log(1-sigma(z)) = z`. Under a shared T every `z_i -> z_i/T`, so every pairwise
difference scales by `1/T > 0`: the ranking over the ten patterns, the beam order
(`PumpReadingLaw.candidates`, :353-387), the `stringsPerField` cut, and the `decimalPoint >= 0.5`
test are all invariant; every margin scales by `1/T`. Consequently **every nat-space comparison in
the law is homogeneous in `1/T`**: with all nat constants restated as `w' = w / T`, the shipped
model's commit/abstain/repair decisions are identical (up to float rounding and the clamp seam
below). Measured: 0 digit flips on all six train pools under each model's own fitted T (§5 table).
Caveats, each a named seam: (a) the `1e-6` clamp - after sharpening, 163-343 of ~200k probabilities
cross it per pool; measured 0 flips, but the implementer asserts, not assumes; (b) `PumpReader.
averaged` (`PumpReader.swift:580-587`) averages probabilities across crops and does **not** commute
with `sigma(z/T)` - calibration must be applied per crop inside `probabilities(cell:)`, and the
Python measurement path (`score.py classify_cells`, `--tta` averaging at :303) must apply the same
order or the two decoders diverge, which their shared docstring forbids; (c) `PumpFrameFusion`'s
elementwise median (`PumpFrameFusion.swift:156`) **does** commute (median of a monotone transform);
(d) `PumpReader.markProbability`'s probability-space constants (`slicerMarkConfidence = 0.95`, the
`0.49` silence, `PumpReader.swift:232-249`): the `cellMarked` branch `max(p, 0.95)` is invariant;
the `rowMarked` branch `min(p, 0.49)` changes the stored value on 33/25085 r6 cells after
sharpening, but that value feeds only the `>= 0.5` test downstream (`PumpReadingTypes.swift:95`),
so no decision changes.

**Constants retired:** none by calibration alone. If the windows are restated in calibrated nats
(§5.3), the four nat literals (`6.0`, `3.0`, `4.0`, `0.5`) become derived per-model values
`w/T_shipped` instead of literals - that restatement, not the calibration, is what retires them,
and §5.3's invariance anchor is the test that it retired nothing observable. The probability-space
constants (0.95 / 0.49 / 0.5 / 1e-6) are not retired and are exactly the seams (a)-(d).

### 3.2 The existing "calibration" module is not this method - and must not lend it its name

`ml/pump-reader/src/pump_reader/calibrate.py` + `calibration.py` + `calibration.json` are PU.18's
**renderer geometry** calibration: quantiles of cell aspect, ink phase, digit frequency and dp rate
measured over the corpus so the *synthetic renderer* draws corpus-like cells (`calibrate.py:1-32`,
`calibration.py:1-8`). Nothing in them touches model probabilities; they are not Platt scaling,
not temperature scaling, not any calibration in Guo's sense. The name collision is a live hazard:
a reader of `calibration.json` who meets PU.72's temperature will assume one instrument where there
are two. The row's fit therefore lands in a new module with a new name - `temperature.py`, writing
`temperature.json` beside `segmentnet.pt`/`metrics.json` - and `calibrate.py` keeps its meaning.

### 3.3 Where T is stored, and the sibling that must agree

`export.py` already writes Core ML metadata (`mlmodel.version = git sha`, :73); the shipped
`ios/App/Resources/PumpSegments.mlpackage` carries `userDefined` keys today (verified by loading
the package with coremltools: `conversion_date`, `source`, …). Store `T` there
(`mlmodel.user_defined_metadata["temperature"]`), read it in `PumpSegmentsModel.init` from
`model.modelDescription.metadata`, and mirror it in `runs/<date>/metrics.json` and in the Python
scorers (`score.py`, `glyph.decode_constrained`'s callers) so every path that prints a margin
prints the calibrated one. A bundle without the key is T=1 - but per `docs/DEFECT-PATTERNS.md`'s
silently-reachable-fallback pattern, that default must be loud: `PumpSegmentsModel` logs/throws in
tests when a model exported after this row lacks the key.

## 4. Adaptations, named (the fence)

Each is a departure from the published method; anything the implementer adds beyond this list needs
the product owner's OK.

- **A1. Shared T over eight independent sigmoids, not over a softmax.** Guo's eq. (9) scales a
  softmax vector, where one T is the whole method because the simplex ties the classes together.
  Our heads are independent; a shared T is a *choice*, and the choice is bought by the §3.1
  theorem: shared T is exactly the parameterization under which the law's decisions are invariant
  and the nat unit is standardized by one scalar per model. Guo §5's own evidence supports the
  scalar ("vector scaling recovers essentially the same solution as temperature scaling - the
  learned vector has nearly constant entries… network miscalibration is intrinsically low
  dimensional").
- **A2. Fit on the TRAIN pool, in-sample.** Guo §4 fits on a hold-out validation set drawn from the
  same distribution as test. Our train pool is the classifier's own training material (decision 9,
  `PumpReaderTestSupport.swift:47-56`: "a number measured on it is memorisation"); heldout is the
  frozen ratchet and `heldout2` is "no constant is tuned against" (`docs/EXTRACTION.md` decision 9,
  2026-09-23 amendment). There is therefore **no unbiased split this row is allowed to fit on**;
  the row's train fit is taken with its bias measured, not hidden: §5 F2/F4 show the in-sample fit
  sharpens (T<1) and does not transfer to heldout for the shipped model. Same posture as PU.68's
  A2 (label the certificate in-sample); the label here is the two ECE tables per fit.
- **A3. Fit by NLL; report ECE, never fit it.** Nixon Fig. 1 right measures that the T minimizing
  a calibration error is not the T minimizing cross-entropy, and §5.4 that metric choice reorders
  recalibration methods. The law consumes log-probability margins, i.e. an NLL-scale quantity, so
  NLL is the coherent objective; the three ECE variants (§5) are reports.
- **A4. Three ECE variants reported, tail-weighted among them.** Guo's M=15 confidence ECE weights
  bins by mass and so under-reports the confident-wrong tail the law actually dies on; Henning's
  ECE_ML (eq. 7, b=10, b_min=5) weights every bin equally and is the variant this note treats as
  the law-relevant one; Nixon's per-label fixed-width SCE sits between. Reporting all three is the
  adaptation; picking one silently would be the invented-method failure.
- **A5. Per-label Platt (A_i, B_i) and local temperature are REJECTED, not adopted.** Platt's
  per-head form voids the §3.1 theorem (the B_i and the per-label A_i make pairwise differences
  inhomogeneous), and B_i != 0 moves the dp 0.5 threshold into the slicer-owned mark's territory
  (`PumpReader.markProbability`). Measured against it: per-label T ranges 0.386-0.753 within r6 on
  train but 0.526-1.461 on heldout, the dp head flipping sign across splits (§5 F5) - the
  instability Schwinger et al. report for global-vs-per-class parameters, in both directions at
  once. Ding et al.'s per-input T has no harness here and no published support at 32x48 cell scale.
  Both stay out unless the owner says otherwise; per-label ECE is reported instead (Henning §4's
  per-label instrument without per-label parameters).
- **A6. Lin et al.'s solver and stable loss forms, not Platt's pseudocode.** Platt's own LM loop
  may not converge and overflowed on separable data (Lin §2.1, §4 Table II); Lin Algorithm 1 is the
  published fix and is what any two-parameter fit here uses. For the one-parameter shared T,
  golden-section on `log T` over `[log 0.05, log 20]` (200 iters) converged on all six models;
  Guo §5's "one-dimensional… 10 iterations" is the same claim.
- **A7. Platt's regularized targets dropped as numerically void.** At our pool sizes (per-label
  positives 5 551-23 093 of 25 085, §5) `t+ = 1 - O(1/N+)`, `t- = O(1/N-)`; the regularization is
  Platt's small-sample device and changes nothing measurable here. Named so nobody re-adds it as
  if it mattered.
- **A8. Domain and device.** Seven-segment pump cells, an 8-head 125k-parameter CNN, iOS 18.0 /
  iPhone 12: none of this costs the method anything - temperature scaling is a scalar multiply in
  logit space, ~16 flops and two logs per label per cell, no new dependency, no C/C++ target, no
  Accelerate/Metal seam. The on-device cost is measured-adjacent in §7, labelled inference where it
  is.

## 5. What the papers measured, what we measure, and whether miscalibration explains PU.52

### 5.1 Populations, counted at `b42f38da`

Counted from `Spike/ReceiptSpike/fixtures/pump/{split.csv, windows.json, expected.csv}` with the
harness's own filter (`PumpReaderTestSupport.isHeldout` / `isReviewedTrain`,
`PumpReaderTestSupport.swift:82-88`; the scoring loop shape `PumpReaderPipelineTests.swift:205-264`:
field non-blank in `expected.csv`, minus `csvDisagrees`):

- **heldout reviewed: 68 stills, 183 scored numeric cells** - equals
  `PumpPhotoGate.readerNumericTotal` (`PumpPhotoGate.swift:95`), the cross-check that the filter is
  the harness's. Glyph-level heldout population for ECE: **186 count-matched transaction windows,
  873 cells** (`ios/.build/pump-reader-out/slices.json` crossed with `windows.json`, windows whose
  slicer cell count equals the label's glyph count - `score.py --only-count-correct`'s rule,
  `score.py:399-400`), measured in `/tmp/pu72-cal/held.py`.
- **train: 256 stills / 683 scored cells; train reviewed (the `PUMP_CERTIFY` population):
  255 stills / 680 cells.** PU.68's build counted 244/670 at its commit; the corpus grew since.
- **train real-glyph pool of the shipped round 6: 25 085 cells** from 5 677 of 8 527 windows
  (`.out/real/manifest.json`); per-bit positives `[18677, 22777, 23093, 17327, 9889, 15873, 15059,
  5551]` (a-g, dp) - the Platt-target denominators and the fit population.
- **heldout2: 4 stills** (`split.csv`), not read by this note.

### 5.2 The measurements (scratch `/tmp/pu72-cal/`, venv python, CPU)

Train pool, per model, shared T fitted by NLL on that model's own pool; "after" = probabilities
rescaled by that T:

| model | cells | T_train | bit acc | mean conf | ECE_conf15 before->after | ECE_perlabel10 before->after | ECE_ML before->after | digit flips | clamp crossings | max abs z |
|---|---|---|---|---|---|---|---|---|---|---|
| r6 (shipped) | 25085 | 0.5682 | 0.9807 | 0.9378 | 0.2766 -> 0.0042 | 0.0358 -> 0.0102 | 0.4131 -> 0.4449 | 0 | 286 / 200680 | 9.65 |
| r7 | 25349 | 0.5554 | 0.9795 | 0.9365 | 0.2782 -> 0.0153 | 0.0366 -> 0.0097 | 0.4127 -> 0.4449 | 0 | 343 | 10.09 |
| r8 | 28428 | 0.5622 | 0.9800 | 0.9358 | 0.2840 -> 0.0176 | 0.0370 -> 0.0113 | 0.4162 -> 0.4477 | 0 | 163 | 9.42 |
| r9 | 30559 | 0.5731 | 0.9793 | 0.9369 | 0.2715 -> 0.0094 | 0.0356 -> 0.0109 | 0.4168 -> 0.4478 | 0 | 245 | 10.25 |
| r10 s0 | 40755 | 0.5712 | 0.9775 | 0.9339 | 0.2764 -> 0.0124 | 0.0353 -> 0.0094 | 0.4153 -> 0.4466 | 0 | 225 | 9.35 |
| r11 control | 22003 | 0.7218 | 0.9499 | 0.8959 | 0.2482 -> 0.0181 | 0.0332 -> 0.0113 | 0.3656 -> 0.3900 | 0 | 0 | 9.63 |

Heldout (873 cells), same metrics; T_held fitted on heldout **as a diagnostic only** (A2 forbids
shipping it):

| model | bit acc | mean conf | T_held | ECE_conf15 before->after(T_held) | ECE_perlabel10 before->after | ECE_ML before->after | NLL before->after(T_held) |
|---|---|---|---|---|---|---|---|
| r6 | 0.9487 | 0.9028 | 0.7978 | 0.1725 -> 0.0803 | 0.0440 -> 0.0345 | 0.3857 -> 0.4025 | 0.14912 -> 0.14350 |
| r11 ctrl | 0.9477 | 0.8917 | 0.7175 | 0.2608 -> 0.0589 | 0.0480 -> 0.0309 | 0.3759 -> 0.4005 | 0.15746 -> 0.14590 |

Train-fitted T applied to heldout: r6 -> NLL 0.15559 (worse than uncalibrated 0.14912),
ECE_conf15 0.1799 (worse), ECE_perlabel10 0.0341 (better), ECE_ML 0.4190 (worse). r11 ctrl ->
NLL 0.14590, ECE_conf15 0.0567, ECE_perlabel10 0.0305, ECE_ML 0.4002 (its train T and heldout T
agree, so for that model the fit transfers).

Findings:

- **F1 - the miscalibration is two-sided, not Guo-style overconfidence.** The bulk is
  *under*confident (acc 0.981 vs mean conf 0.938 in-sample; 0.949 vs 0.903 on heldout r6) - the
  label-smoothing signature (`train.py:132-135`) - while the saturated tail is overconfident
  (ECE_ML ~0.41, which *worsens* under sharpening). One shared T moves one side at the other's
  expense; that trade is the table above. Guo's population (overconfident ResNets on CIFAR, §3) is
  not our population.
- **F2 - every fitted T_train is below 1** (0.555-0.722): the NLL-optimal in-sample correction is
  sharpening, the opposite sign of the published use, and it inflates every margin by 1/T ~
  1.39-1.80x. A law window restated in calibrated nats is correspondingly larger in raw-nat terms
  (6.0 -> 10.56 calibrated nats at T_6 = 0.5682).
- **F3 - T_train is stable across the rounds where live collapsed**: 0.555-0.573 for r6-r10, a ~3%
  spread, against live drops of 11 -> 4 -> 2 (REPORT.md rounds 8-9) and 39 -> 19-36 (round 11 seed
  table). The r11 control's 0.7218 differs together with its pool and its accuracy (0.9499), not
  alone. **Measured inter-round confidence-scale drift is a few percent; it cannot account for
  drops of that size.**
- **F4 - the train fit does not transfer to heldout for the shipped model** (T 0.5682 vs 0.7978),
  and applying it worsens heldout NLL and both mass-weighted ECEs while improving the per-label
  fixed-width one - the metric-dependence Nixon §5.4 predicts. For the r11 control the two fits
  agree (0.7218 vs 0.7175). So "fit on train, apply on device" is, for the shipped model, a
  measured-wrong absolute calibration on the population the law judges; it survives only as the
  unit standardizer of §5.3.
- **F5 - per-label temperatures are unstable across populations** (r6: train 0.386-0.753, heldout
  0.526-1.461, dp flipping sign), the evidence behind rejecting A5's alternatives.
- **F6 - the exactness seams hold**: 0 digit flips on all six pools; fusion median commutes; the
  mark constants change no decision; the TTA mean does not commute (order pinned in §3.1(b));
  clamp crossings counted, flips zero, to be asserted in the row's tests.

### 5.3 Which split fits T, how ECE is measured, how the windows are re-derived

- **Fit:** the TRAIN split's real glyph cells of the model's own pool (the row's rule; A2 names the
  cost). Never heldout, never heldout2. One shared T per exported model, NLL objective (A3), Lin's
  stable forms (A6), stored with the model (§3.3).
- **ECE before/after:** on train, over the pool's 8 x n binary predictions, all three variants
  (§2.3); on heldout, over the 873 count-matched cells' 8 x 873 predictions, same three, with the
  train-fitted T (transfer) and - diagnostic only - the heldout-fitted T. Per-label ECE_c printed
  beside each (Henning §4). Bins: Guo M=15 for the confidence variant; 10 fixed-width per label;
  adaptive_ML b=10, b_min=5 for ECE_ML, with Henning §6's robustness noted so nobody tunes b.
- **Window re-derivation on train, in calibrated nats:** run the `PUMP_CERTIFY` arm
  (`PumpReaderPipelineTests.trainSplitRiskBound`, :125-157, the reviewed-train `measureLive`) with
  calibrated probabilities, sweep `(readWindow, ambiguityWindow, decimalMarkPenalty)` - all three
  scale together as `w/T` by §3.1, so the sweep is one scalar on the shipped triple plus, if the
  owner wants, their ratios - selecting on train only (max precision subject to committed >= the
  current train committed count, 124/117 at the PU.68 build, recount at the build commit), heldout
  and heldout2 printed as measurement. **The invariance anchor:** at `w' = w / T_shipped` the
  shipped model's decisions are identical by the §3.1 theorem, so livePath 45/45
  (`PumpPhotoGate.readerCommitted = 45`), gateMirror 112/112 (`committedFloor`,
  `PumpReaderPipelineTests.swift:28`) and the oracle ratchet 763 / 0.9987 must reproduce exactly;
  any movement is a seam bug (clamp, TTA order, mark constants), not a result.

### 5.4 Does miscalibration explain PU.52? - partially, and not the part the row hopes

`agents/reviews/PU.52-REVIEW-WHY-IT-LOWERED-qwen.md` §1 names two couplings: the classifier's
nat-threshold coupling ("a retrain shifts each cell's runner-up posteriors by fractions of a nat…
a few hundredths of a nat moved their best close across the window", per-still on pump-080/119/
139/180) and the detector's geometry coupling (recall@0.5 up while median IoU 0.797 -> 0.772 and
live 43 -> 36). REPORT.md rounds 8-11 carry the same pattern (live 11 -> 4 -> 2; round 10's three
seeds 32-34 correct of 33-35 committed against the shipped 29/29; round 11's 19-36 against 39).
Against that, this note's measurements say:

- The **scale** half of the threshold coupling is real but small: F3 puts inter-round T drift at
  ~3% for exactly the rounds that collapsed live. A per-model T removes a 3% scale difference; it
  cannot move a 3x commit count.
- The **boundary-proximity** half (closes sitting hundredths of a nat from a window) is not a
  calibration phenomenon at all: it is the window's position relative to a margin *distribution*,
  and §3.1's theorem says a shared T moves every margin and every window by the same factor - it
  cannot separate a close that sits near a boundary from one that does not.
- The **wrong-commit** half (pump-031, pump-096 gaining wrong commits under a retrain; the clip
  class) is ranking and content, and shared T preserves ranking (theorem; F6). Calibration is
  silent on it.
- The detector half is geometry; calibration never touches it.

**Verdict, labelled inference over the measured F3/F4:** miscalibration explains the part of PU.52
that is "the nat unit means something different per model" - which is real, which is what the row
should fix, and which is worth a few percent of margin scale - and does not explain the live
collapse, whose measured size exceeds the measured drift by an order of magnitude. The row is
therefore correctly scoped as *unit standardization plus honest calibration reporting*, and its
"the row is proven when a retrain no longer lowers live for calibration alone" is testable exactly
as written: after this row, a retrain's live number can no longer move *through the nat unit*; if
it still falls (F3 says it will, by the other mechanisms), the fall is diagnosed as accuracy or
geometry, which is PU.56's ledger and PU.55's re-scope, not this row's debt.

### 5.5 Falsifiers, named in advance

- **F-impl (exactness).** With T applied and windows at `w/T`, livePath, gateMirror and the oracle
  ratchet must reproduce 45/45, 112/112, 763/0.9987 bit-for-bit in committed values; a mutation
  that applies T after `averaged()` or after the clamp must go red on the digit-flip assertion
  (measured 0 flips today).
- **F-premise.** If any future round's fitted T differs from the shipped model's by more than the
  live drop it accompanies can be attributed to (F3's yardstick: ~3% against a 3x drop), the
  standardization is doing less than the row's prose claims and the row's report must say so.
- **F-transfer.** Already true and recorded: for the shipped model, train-fitted T worsens heldout
  NLL and mass-ECE (F4). Any claim that this row makes the device's probabilities calibrated in
  absolute terms is falsified by §5.2's heldout table; the row's claim is the weaker, true one.
- **F-benefit.** The row's payoff measurement: a candidate model's train `measureLive` precision at
  the shared calibrated window vs at its own raw-fitted window. If the calibrated comparison never
  orders candidates differently from the raw one across a round's seeds, the standardization buys
  nothing measurable and the row closes as reporting-only.

## 6. What the papers measured vs what we expect here

Guo measured ECE 4-16% uncalibrated falling to ~1-2% after temperature scaling on vision/NLP
benchmarks with thousands of validation images per fit (§5 Table 1). Nixon measured that metric
choice reorders methods (§5.4). Henning measured per-label ECE_ML of 3-15% on BERT-scale
multi-label text with 10^4-10^5 calibration instances per label (§6 Tables 2, 8, 10). Schwinger
measured Platt from "a small labelled calibration set" helping multi-label sigmoid heads. Our fit
population is 25 085 in-sample cells (200 680 binary predictions) for the shipped model - ample for
one scalar, but **in-sample**, so the expected heldout ECE after calibration is not Guo's ~1%:
§5.2 measures 0.0803 (conf-ECE) / 0.0345 (per-label) / 0.4025 (ECE_ML) at the *heldout-fitted* T
and worse at the train-fitted one. The expected honest output of this row is therefore: shipped
model bit-identical (anchor), per-model T logged, three ECE tables per split per model, and a
round-7 candidate whose live number can no longer move through the nat unit - not a precision gain.
A precision gain from this row alone would contradict §3.1's theorem and should be treated as a
bug.

## 7. Cost

- **Latency.** Device: eight `logit` + eight `sigma(z/T)` per cell, ~32 flops and 16 logs against a
  Core ML inference that PU.38 measured in the low milliseconds per cell in Release; the addition
  is nanoseconds - inference from the op count, not measured; the row re-measures the Release
  per-cell number in `pump-read`'s `timingsMs` and reports it, per the tranche's rule that latency
  numbers are Release numbers.
- **Bundle.** One double in the mlpackage's `user_defined_metadata` (the mechanism is already in
  the shipped package) plus ~10 lines of Swift in `PumpSegmentsModel`; no new dependency, no C/C++
  target, no Accelerate/Metal seam (A8).
- **New code to maintain.** `temperature.py` fit CLI (~60 lines incl. Lin's stable forms and the
  golden-section), the metadata write in `export.py` (~5 lines), the Swift apply + missing-key
  loudness (~15 lines), the exactness regression test (~30 lines), and the three-variant ECE
  report in the fit's output (~80 lines shared with the harness print). The name collision with
  PU.18's `calibration.*` (§3.2) is a permanent reading cost this note pays once so the code never
  does.

## Erratum (orchestrator, 2026-09-24, while building the row)

Two of this note's calibration-error functions in `/tmp/pu72-cal/fit.py` were wrong, so its ECE
columns in §5.2 (and finding F1's "the saturated tail is overconfident, ECE_ML ~0.41, worsens under
sharpening") do not stand:

- `ece_conf` weighted each bin by `sel.sum() / len(p)` on an `(n, 8)` array - `len` is `n`, not
  `8n` - so every confidence ECE is 8x too large (r6 train: 0.2766 printed, 0.0346 correct).
- `ece_ml` indexed the FULL label column with indices into the one-sided subset
  (`yk[g]` where `g` indexes `ps = pk[yk == side]`), pairing each bin with the wrong labels.

Recomputed with `ml/pump-reader/src/pump_reader/temperature.py` (the row's module; the fitted T, the
NLL figures and the zero digit flips are unaffected and reproduce exactly): r6 train
ECE_conf15 0.0346 -> 0.0005, ECE_perlabel10 0.0358 -> 0.0102, **ECE_ML 0.0822 -> 0.0505** (improves,
not worsens); r7 and r8 the same shape (ECE_ML 0.0824 -> 0.0503). F4 (the train-fitted T worsens the
shipped model's heldout NLL, 0.14912 -> 0.15559) used the NLL function, which is correct, and stands -
so the row's decision (a comparison unit for candidates, not a correction shipped to the device) is
unchanged.

**Heldout, recomputed (the §5.2 heldout table's ECE columns are invalid for the same two bugs).**
With the module's corrected functions over the reviewed heldout split's count-matched cells (864
cells, 184 windows at `b42f38da`+; the note counted 873 at an earlier corpus), each model's
TRAIN-fitted T applied: r6 - NLL 0.14737 -> 0.15367 (worse: F4 stands), ECE_conf15 0.0214 -> 0.0226,
ECE_perlabel10 0.0435 -> 0.0335, ECE_ML 0.1270 -> 0.0974; r11-control - NLL 0.15587 -> 0.14429,
ECE_conf15 0.0321 -> 0.0066, ECE_perlabel10 0.0477 -> 0.0307, ECE_ML 0.1404 -> 0.1155. Diagnostic
heldout-fitted T: r6 0.7971, r11-control 0.7171. All six models' train fits (T, NLL, three ECEs, flips)
are committed in `ml/pump-reader/runs/2026-09-24/temperature.json`.
