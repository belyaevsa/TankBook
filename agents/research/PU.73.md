# PU.73 research note - the dp bit: focal loss, and a head that keeps the layout

*A run of `agents/briefs/RESEARCH-TO-CODE.md` for `PU.73` (`docs/TASKS.md:1076`). Product owner,
2026-09-23: "review the published research to apply it into the code, instead of coming up with our
own solution." Read-only except this file; every measured number below comes from scratch scripts
in `/tmp/pu73/` (`dpauc.py`, `dpauc_tta.py`, `probe.py`, `probe2.py` - volatile, re-runnable from
their descriptions here) run against existing artifacts - the shipped checkpoint
`ml/pump-reader/.out/train-r6-real/segmentnet.pt`, the pools `.out/{real, real-r11-gap,
real-r11-control}/`, the heldout slices `ios/.build/pump-reader-out/slices.json` (regenerated
2026-09-23 19:43 by `PumpReaderHarnessTests.swift:321`), and the corpus files as committed at
HEAD `5b09f520` (`git show`, never the working tree: a concurrent annotator session holds
uncommitted `windows.json`/`corpus.sqlite` changes, and a concurrent agent holds uncommitted
`PumpReadingLaw.swift` changes - law line numbers below are HEAD's). No code was written, no
builds run, no tests executed, `heldout2` not touched. Evidence rule: every claim cites a fetched
paper section/equation, a `file:line`, or a number measured in this run; inference is labelled.*

## 0. First, what this run measured - the row's premise is stale, and the ceiling is measurable

The row says dp's AUC on real cells is 0.52-0.55 (`docs/TASKS.md:1076`, citing `REPORT.md`). Those
numbers are real but they are PRE-round-6 measurements and candidates: 0.52 was PU.11 F2 on a
synthetic-only model (`REPORT.md:294-295`), 0.548 was round 4 after the comma re-render
(`REPORT.md:334-335`), 0.5511 was the round-11 `--dp-crop gap` candidate scored through
off-framing slices (`REPORT.md:1263-1266`). **The shipped round-6 model, measured this run on
today's heldout slices (186 count-matched windows, 873 cells, 185 dp-positive), reads dp at AUC
0.6452 (single crop) / 0.6569 (5-crop TTA, the app's path - `PumpReader.averaged`,
`PumpReader.swift:580-587`)**, with digit-only accuracy 0.9313 / 0.9370 on the same cells. The
implementer re-runs this at the build commit; the instrument is `score.py`'s own `dp_auc`
(`score.py:461-479`, Mann-Whitney `_auc` at `:52-59`), and this run's scratch scripts reproduce
its slicing and decoding exactly.

Second, the binding constraint is measurable, and it is not the loss or the head. A **linear
probe** (logistic regression on flattened cell pixels, group-split so no fixture or its records
leak across folds) bounds what ANY classifier can extract from the crop the reader feeds:

| probe population | features | dp AUC |
|---|---|---|
| shipped r6 train pool (25 085 cells, `off` crop = the reader's framing), fixture-grouped split | raw luminance | 0.776 |
| same | polarity-normalised ink (`realglyphs.ink_centroid`'s rule, `realglyphs.py:185-200`) | 0.796 |
| same probe, fit on the FULL pool, tested on the 873 heldout cells | luminance / ink | **0.626 / 0.604** |
| probe trained and 5-fold-tested INSIDE heldout (by still) | luminance / ink | 0.556 / 0.645 |
| r11 `gap` pool (19 800 cells, mark inside the crop by construction, `DP_GAP_FRACTION` 0.4, `realglyphs.py:182`), fixture-grouped split | luminance / ink | **0.948 / 0.917** |
| the shipped CNN itself: on its own pool (in-sample) | - | 0.932 |
| the shipped CNN itself: on heldout (the rows above) | - | 0.645 / 0.657 |

Read together (inference, labelled): the shipped CNN has already extracted everything that
transfers LINEARLY from train pool to heldout (0.645-0.657 vs the probe's 0.604-0.626), and the
transferable signal under the shipped framing sits around 0.6-0.65 however it is modelled, while
the same linear probe nearly solves dp when the crop contains the mark (0.92-0.95). Why the crop
usually does not: the slicer's cell rect ends at the digit run's right edge (`rect.x = phase +
(index-1)*pitch`, width = pitch, phase anchored on digit-run ends,
`PumpGlyphSlicer.swift:330-381`), the mark sits in the inter-cell gap AFTER the glyph, and "a
crop that stops at the cell's right edge never shows it" (`realglyphs.py:179-181`). What survives
inside the host cell is indirect: the row's ink band includes the comma so a dp-carrying cell's
digit sits in the top ~85 % (`REPORT.md:310-318`), the comma's tail crosses into the NEXT cell's
left edge labelled dp = 0 (`REPORT.md:316-318`), and some mark ink bleeds into the rightmost
columns (measured: corner-ink fraction p90 0.338 for dp+ vs 0.268 for dp- in the r6 pool,
`/tmp/pu73/probe.py`). Those phase/bleed cues are what the 0.78 in-pool and 0.63 transferred
probe AUCs are made of.

Consequence for the row, stated up front so the sweep is not judged against an impossible bar:
focal loss and a layout-keeping head are the right published instruments for the row as scoped,
and both rounds are worth running exactly as the row prescribes - but the measured ceiling says
the expected heldout dp-AUC gain is bounded in the 0.65 -> ~0.75 range (inference from the probe
numbers: the nonlinear headroom above the linear transfer bound is what the CNN's in-sample 0.93
vs linear 0.78 gap suggests could partially transfer), NOT the 0.9+ that would make PU.78's M4
hard dp check viable. The lever that measurably reaches 0.9+ is what pixels the classifier sees
(gap framing), and r11 measured that changing the TRAINING framing alone regresses the pipeline
(annotated 97 -> 64 committed, live 36 -> 21, `REPORT.md:1273-1277`) because the reader feeds
off-framing crops at inference (`PumpReader.swift:222`, `cropCell:572`). Re-framing the READER is
outside this row's seam and needs its own decision (§4-A9, §7-3).

## 1. The citations, checked

| Citation as the row/brief gives it | Fetch result | Verdict |
|---|---|---|
| Lin, T.-Y., Goyal, P., Girshick, R., He, K., Dollár, P. (2017). *Focal Loss for Dense Object Detection.* ICCV 2017, arXiv:1708.02002 | arXiv abs page fetched: title exact; authors Tsung-Yi Lin, Priya Goyal, Ross Girshick, Kaiming He, Piotr Dollár; v1 7 Aug 2017, v2 7 Feb 2018; cs.CV. Venue not on the abs page - confirmed independently via Crossref `10.1109/ICCV.2017.324`: "2017 IEEE International Conference on Computer Vision (ICCV)", IEEE, Oct 2017, same five authors (Crossref renders Dollár as "Dollar"). **Full text read** via ar5iv (v2): §3 eqs. (1)-(5), §3.3 prior init, §4/§4.1 RetinaNet + training protocol, §5 Tables 1-2, Fig. 4, Appendix A eqs. (6)-(8)/Table 3, Appendix B eqs. (9)-(11). | **Correct as cited.** Method read first-hand. |
| CoordConv, Liu et al. 2018, arXiv:1807.03247 (the brief's head suggestion) | arXiv abs page fetched: *An Intriguing Failing of Convolutional Neural Networks and the CoordConv Solution*; authors Rosanne Liu, Joel Lehman, Piero Molino, Felipe Petroski Such, Eric Frank, Alex Sergeev, Jason Yosinski (Uber AI Labs); Comments field: "Published in NeurIPS 2018"; v1 9 Jul 2018, v2 3 Dec 2018. **Full text read** via ar5iv (v2): §3 the layer, §4.1-4.3 the coordinate tasks, §5 ImageNet/detection/GAN/RL, §S3 Table S1, §S5 the ImageNet recipe. | **Correct as cited** (short name; "Liu et al. 2018" is Rosanne Liu - not the Huimin Li / Songlin Tang author set an earlier draft of this note guessed from memory; the guess was wrong and the fetch is why the rule exists). |
| "a flatten/fully-connected head as in LeNet-style digit classifiers" (the brief's alternative) | Primary source: LeCun, Bottou, Bengio, Haffner, *Gradient-based learning applied to document recognition*, Proceedings of the IEEE 86(11):2278-2324, 1998 - **verified bibliographically** via Crossref `10.1109/5.726791` (title, four authors, venue, volume, pages, year). The PDF (yann.lecun.com, 955 KB, 46 pp.) downloaded but is **not text-extractable in this environment** (no `pdftotext`; `pypdf` returns mojibake - a PS-era conversion without a ToUnicode map). Its architecture is therefore NOT described from the primary text here. The flatten/FC-head pattern is instead cited from inside the fetched CoordConv text, where it appears in print: §4.2's best-generalizing conv baseline is "a stack of alternating convolution and max-pooling layers, followed by a fully-connected layer and an output layer", and Table S1 spells it ("3x3,16 - MP - ... - FC 64 - FC 2") against the global-pooling variant that fails the quadrant split. | **Bibliographically verified; body not read.** Pattern sourced through the fetched CoordConv text, stated as such. |
| Published per-cell seven-segment head treatments (this run's search) | arXiv API title search `ti:"seven-segment"`: 0 entries; abstract search `"seven segment display" AND recognition`: 0 entries. Crossref bibliographic search `seven-segment display digit recognition convolutional neural`: no on-topic hits (oscilloscope-hardware and handwritten-digit papers). The fetched AMR family (PU.78 note §2.6-2.7: Laroca et al. 2021 Fast-OCR/CDCC-NET; Salomon/Laroca/Menotti 2022) recognises whole ROWS as sequences - PU.77's seam - not per-cell segment bits. | **Null result recorded**: no fetched paper treats a per-cell eight-sigmoid segment head; the head nomination rests on the two rows above. |
| PU.78's dp findings (the brief's cross-reference) | `agents/research/PU.78.md` §3-M4: dp AUC 0.52-0.55 (stale per §0 above); a hard dp-consistency refusal would catch the 4 wrong photos 099/137/251/275 and refuse 4 CORRECT heldout photos (pump-014 total, pump-062 liters, pump-112 price, pump-180 price), ~11 of 45 cells at photo-level refusal; blocked on PU.73, `decimalMarkPenalty` stays soft (its A9). | Carried into §4-A10 and §5.4. |

Caution carried from PU.68/PU.72 (it cost those runs fetches): every id above was fetched by id or
verified by Crossref, never recalled.

## 2. The methods as published

### 2.1 Focal loss - Lin et al., §3, eqs. (1)-(5); protocol §3.3, §4.1

CE for one binary output (eq. 1): `CE(p,y) = -log(p)` if `y=1`, `-log(1-p)` otherwise; with
`p_t = p` if `y=1` else `1-p` (eq. 2), `CE(p_t) = -log(p_t)`. The paper's diagnosis (§3): even
easily classified examples (`p_t >> .5`) incur non-trivial loss, and "when summed over a large
number of easy examples, these small loss values can overwhelm the rare class."

Balanced CE (eq. 3, §3.1): `CE(p_t) = -alpha_t log(p_t)` with weight `alpha` for class 1 and
`1-alpha` for class -1; "alpha may be set by inverse class frequency or treated as a hyperparameter
to set by cross validation." Their measurement (Table 1a, COCO, gamma=0): alpha=.10 -> 0.0 AP
(over-weighting the negative side destroys training), alpha=.50 -> 30.2, **alpha=.75 -> 31.1**
(best CE), alpha=.999 -> 28.7.

Focal loss (eq. 4, §3.2): `FL(p_t) = -(1-p_t)^gamma log(p_t)`, gamma >= 0; "when gamma=0, FL is
equivalent to CE" (the implementation's own reduction check). Two stated properties: misclassified
examples keep ~full loss (factor -> 1 as p_t -> 0); the factor decays as p_t -> 1 (at gamma=2,
p_t=0.9 is down-weighted 100x, p_t~0.968 1000x, while misclassified examples are scaled by at most
4x). The form actually used (eq. 5): **`FL(p_t) = -alpha_t (1-p_t)^gamma log(p_t)`** - "we adopt
this form ... it yields slightly improved accuracy"; the loss layer "combines the sigmoid operation
... with the loss computation" for numerical stability (torch's `sigmoid_focal_loss` / a
`BCEWithLogitsLoss`-shaped implementation is the same device).

Recommended values (§4.1, §5.1, Table 1b): **gamma = 2, alpha = 0.25** for all main experiments;
"RetinaNet is relatively robust to gamma in [0.5, 5]"; alpha interacts with gamma and "should be
decreased slightly as gamma is increased" (best alpha per gamma: .75 at gamma=0, .50 at gamma=0.5,
.25 at gamma=1/2/5); alpha=.5 at gamma=2 costs 0.4 AP. The ablation chain (Table 1b, §5.1): plain
CE diverges without the prior init; CE + prior init 30.2 AP; alpha-balanced CE 31.1; **FL gamma=2
34.0 (+2.9 over balanced CE)**; FL beats the best OHEM variant 36.0 vs 32.8 at ResNet-101
(Table 1d). Headline results (Table 2, COCO test-dev): RetinaNet-101-800 **39.1 AP** (vs best
two-stage 36.8), ResNeXt variant 40.8.

Prior initialization (§3.3, §4.1): set the final classification layer's bias to
`b = -log((1-pi)/pi)` with `pi = .01` so early-training loss from the frequent class does not
destabilize; "results are robust to the exact value". Normalization (§4.1): the focal loss is
**summed over all ~100k outputs of an image and normalized by the number of POSITIVE anchors**,
not by total count, "since the vast majority of anchors are easy negatives and receive negligible
loss values under the focal loss". Analysis (Fig. 4, §5.1): increasing gamma barely changes the
positive-example loss CDF but concentrates nearly all negative loss on hard negatives. Footnote 1:
the multi-class extension "is straightforward and works well"; the paper's own head emits **K.A
independent sigmoid outputs per location** (§4, Classification Subnet) and applies FL to each -
structurally the same shape as our eight sigmoids. Appendix A (eqs. 6-8, Table 3): `FL*` with
`p_t* = sigma(gamma x_t + beta)` performs equivalently (33.8-33.9 vs 34.0 AP) - "the exact form of
the focal loss is not crucial". Appendix B: derivatives, eqs. (9)-(11).

### 2.2 Why gamma=2 / alpha=0.25 may not transfer to 8 sigmoids with ~20.6 % positive dp

The brief's question, answered from the fetched text and this run's counts:

1. **The imbalance ratio is three orders of magnitude milder.** The paper's setting is "~100k
   locations" per image at foreground:background ~1:1000 (§3). Our dp is 20.6 % of corpus cells
   (`calibration.json:121` `dp_rate.all` 0.2061 - the row's number; the renderer samples synthetic
   dp at exactly this rate, `dataset.py:194-201`), 22.1 % of the shipped train pool (5 551/25 085,
   counted this run from `.out/real/cells.npz`), 21.2 % of the heldout count-matched cells
   (185/873), ~24.9 % of synthetic renders (measured this run over 3 000 samples, including the
   8 % dp-only prior, `dataset.py:79-80`). That is ~1:3.5, not 1:1000. alpha=0.25 DOWN-weights the
   positive class; at 1:3.5 the inverse-frequency alpha the paper itself offers as the alternative
   rule (§3.1) is ~0.77-0.81 (1 - the field rates 0.187-0.228 in `calibration.json:117-122`), i.e.
   the opposite side of 0.5. Their Table 1a shows what the wrong
   side does at extreme imbalance (alpha=.10 -> 0.0 AP); the mirrored risk here is that alpha=.25
   suppresses the rare class further. The gamma=2/alpha=.25 optimum is an interaction fitted at
   1:1000 ("alpha should be decreased slightly as gamma is increased", §4.1); the pair must be
   swept at OUR ratio, not imported.
2. **Part of our positive class is not learnable from the pixels.** Every RetinaNet anchor's label
   is achievable from its input. Our dp label comes from the annotated TEXT (`parse_cells` puts the
   dp bit on the cell before a separator, `score.py:90-108`) while the mark's ink sits in the gap
   outside the host cell's rect (§0; `realglyphs.py:179-181`; `PumpGlyphSlicer.swift:371-381`).
   For those cells `p(dp | pixels)` is bounded near the prior, and focal loss - which by design
   "performs the opposite role of a robust loss" (§2, Robust Estimation) - concentrates gradient on
   exactly these unlearnable positives. At 1:1000 with clean labels that focus is the point; at
   1:3.5 with a noise floor it is a documented hazard (inference from their §2 contrast, labelled).
3. **Per-bit priors differ wildly; one shared alpha fits none.** The pool's per-bit positive rates
   (counted this run): a 0.745, b 0.908, c 0.921, d 0.691, e 0.394, f 0.633, g 0.600, dp 0.221.
    Inverse-frequency alpha is < 0.5 for six of the eight bits - "rebalancing" them would
   down-weight their positives. The paper applies one alpha to a head whose outputs are all
   equally rare (object classes at anchor scale); our eight outputs are not one population
   (§4-A2 names the two faithful options).
4. **Repo training context differs from theirs**: label smoothing 0.05 is load-bearing here
   (`train.py:132-135`: synthetic data is separable, plain BCE saturates and the model is
   "confidently wrong on real cells"; smoothing keeps the abstention frontier ranked); the paper
   trains with hard targets, SGD, 90k iters. Combining FL with smoothed targets is not in the
   paper (§4-A4 specifies the combination).

### 2.3 CoordConv - Liu et al., §3 (the layer), §4-5 (where it helps and where it does not)

The layer (§3): concatenate to the conv input two (optionally three) CONSTANT, untrained channels -
`i` (row index, rank-1 rows), `j` (column index), optionally
`r = sqrt((i-h/2)^2 + (j-w/2)^2)` - linearly scaled to `[-1, 1]`, then apply a standard conv.
Parameter count `(c+d) c' k^2` vs `c c' k^2` (d = 2 or 3 coordinate channels); "almost all
experiments use 1x1 filters with CoordConv" (§3 footnote 2); weights to coordinates zeroed =>
exactly ordinary convolution, so the layer "allows networks to learn either complete translation
invariance or varying degrees of translation dependence, as required by the end task" (§3). The
published ImageNet recipe (§S5): one extra 1x1 CoordConv layer at the stem taking a 6-channel
tensor (RGB + i + j + r) and emitting 8 channels.

Evidence FOR, where position matters (§4, §5): coordinate classification/regression/rendering -
conv "fails spectacularly" (best conv 86 % test accuracy on the uniform split, zero generalization
on the quadrant split) while CoordConv is perfect with 7.5k-9.5k params, 150x faster (§4.1-4.3,
Figs. 4-6); Faster R-CNN on MNIST detection +24 % IOU (§5). Evidence AGAINST for plain
classification (§5): ResNet-50 + stem CoordConv on ImageNet improves top-5 by 0.04 %, "not
statistically significant" (p=.11, §S5) - "classification is more about what is in the image than
where it is". The GAP-specific datum (§4.2, §S3 Table S1): on the quadrant-split coordinate
REGRESSION task, the conv architecture ending in global pooling fails (≈5 px error, delicate to
tune) while (a) conv + FC layers wins the uniform split and (b) a single CoordConv layer + conv +
GP wins BOTH splits - i.e. the paper's own ablation pairs "pooling discards position" with
"coordinate channels restore it", the two repairs §4 nominates.

Applicability here (inference, labelled): dp is the "where it is" bit - the mark lives at a fixed
place relative to the cell (bottom-right / below-baseline phase cue, §0) - so this is the task
shape CoordConv's positive results cover, not the ImageNet shape. Their mechanism claim applies
verbatim to `SegmentNet`'s GAP (`model.py:45`): after coordinate channels, "ink at bottom-right"
becomes a learnable CHANNEL identity, which GAP preserves, instead of a spatial position, which
GAP destroys.

### 2.4 The flatten/FC head (the pattern inside the fetched texts)

`SegmentNet` today: 3 conv blocks (16/32/64, BN, ReLU, 2x2 max-pool, `model.py:18-24`) map
(N,3,48,32) to (N,64,6,4); `x.mean(dim=(2,3))` (`model.py:45` - the row cites `model.py:44`, the
GAP is one line lower) collapses the 6x4 grid; `Linear(64,8)` (`model.py:41`) reads the pooled
vector. The flatten alternative replaces the two lines with `Flatten` + `Linear(6*4*64, 8)` =
`Linear(1536, 8)`: every one of the 24 spatial positions keeps its own weights, so "ink at
bottom-right" is directly addressable. This is the head the fetched CoordConv text prints for
small vision classifiers (§4.2, Table S1, "FC 64 - FC 2"), and the family LeNet-5 belongs to
(LeCun et al. 1998 - bibliographically verified, body not readable here, §1). Costs measured from
the architecture (arithmetic, not profiled): head 520 -> 12 296 params (+11 776), model 24 328 ->
36 104 params (both counted this run via `model.count_parameters`), +11 776 MACs against the
feature stack's ~4.20 M MACs/cell (+0.28 %). Its published weakness is equally in the fetched
text: FC heads are translation-SENSITIVE - Table S1's conv+FC model wins the uniform split and
"completely fails on the quadrant split", and §4.2 lists fully-connected layers among the factors
they could not isolate. Our training data jitters cells by +-2 px (`train.py:75-79`) and the
slicer's phase varies per class (centroid medians 0.57-0.74, `REPORT.md:1249-1252`), so a
flatten-FC head must learn that jitter as invariance from data (inference, labelled).

## 3. The mapping onto this code

Line numbers at HEAD `5b09f520`. Two independent rounds, exactly as the row scopes them
("round per change (focal/pos_weight; head)"), plus the data lever the row names ("on hand
boxes").

### 3.1 Round A - the loss (`train.py`)

`loss_fn = nn.BCEWithLogitsLoss()` at `train.py:185`, applied at `:216` to
`model(xs)[:, :n_bits]` against label-smoothed targets (`:214-215`). Round A replaces this ONE
construction with a published variant, flags on the existing CLI:

- **A-arm 1, balanced CE (eq. 3) as `pos_weight`**: `BCEWithLogitsLoss(pos_weight=w)` with w on
  the dp bit only. Correspondence to the paper (arithmetic): `pos_weight=w` equals alpha-balanced
  CE with `alpha = w/(1+w)` up to the global factor `(1-alpha)`, which scales the effective LR -
  state which convention a logged number uses. Inverse-frequency values for dp: w = 3.52 (pool
  0.221) or w = 3.85 (calibration 0.2061); the paper's own best CE alpha=.75 maps to w = 3.0.
- **A-arm 2, focal loss (eq. 5)**: `FL = -alpha_t (1-p_t)^gamma log(p_t)` per output, gamma and
  alpha swept around the paper's (2, 0.25) per §2.2, computed from LOGITS with the sigmoid fused
  (their §3.2 stability note; torch's `torchvision.ops.sigmoid_focal_loss` or 10 lines in-house -
  the repo has no torchvision dependency today, `ml/pump-reader/pyproject.toml`, so an in-house
  stable form is the expectation), normalized per §4.1: sum over outputs of the batch divided by
  the number of positive TARGETS (per bit or global - §4-A6). Modulating factor from the HARD
  target, CE term against the smoothed target as today (§4-A4).
- Prior init (§3.3) is a one-line change to the head's bias init IF the arm keeps it:
  `b_i = -log((1-pi_i)/pi_i)` with the pool's per-bit priors (§2.2-3 rates; dp: pi=0.2213 ->
  b=-1.26). Optional per §4-A5.
- Validation loss stays plain BCE (`train.py:94`, `_metrics`) so round-to-round val curves remain
  comparable; the reported dp metrics are per-bit accuracy (already printed,
  `train.py:116`) plus dp AUC on real cells from §5's instrument.
- **Retires**: nothing. Unweighted BCE remains the gamma=0/alpha=.5/w=1 control, and the
  equivalence `FL(gamma=0) == CE` (their §3.2) is the round's named mutation test.

### 3.2 Round B - the head (`model.py`, `export.py`; Swift untouched)

- **B-arm 1, flatten/FC (§2.4)**: `model.py:45-46` become `x = torch.flatten(x, 1)` +
  `self.classifier = nn.Linear(1536, 8)` (`:41`). 36 104 params, ~144 KB float32 weights - inside
  the <=500 KB / ~125k-param budget the module docstring sets (`model.py:9`).
- **B-arm 2, CoordConv stem (§2.3)**: register constant i, j (and optionally r) coordinate grids
  scaled to [-1,1] over 48x32 as buffers; concatenate in `forward` before `self.features` and make
  the first conv `Conv2d(3+d, 16, 3, padding=1)` (`model.py:20,:37`). +288 params (d=2) / +432
  (d=3) -> 24 616 / 24 760 total; GAP and `Linear(64,8)` stay. The 1x1-stem variant of §S5 (a
  separate CoordConv 1x1, 3+d -> 8, before the stack) is the paper's ImageNet recipe if the
  first-conv variant underperforms - same layer, same source, named here so it is not an
  unlisted departure.
- **Export**: `export.py` needs no structural change - `_SigmoidNet` wrapping (`:34-42`),
  `torch.jit.trace` (`:55`) and `ct.convert(... minimum_deployment_target=ct.target.iOS18)`
  (`:57-70`) carry constant buffers, flatten and GEMM as ordinary ops (inference from the trace
  mechanism; `tests/test_export_roundtrip.py:59` already asserts Core ML == torch probabilities
  and is the gate that catches a conversion surprise). The exported input ("glyph" 1x3x48x32) and
  output ("segments", 8 probabilities, order a-g dp, `export.py:61-72`) are UNCHANGED.
- **Device**: `PumpSegmentsModel.swift` is untouched in both arms - same input, same output
  contract (`:41-52`), same decoder (`rank:59-71`, `decode:74-81` with the dp >= 0.5 test at `:78`
  and `PumpReadingTypes.swift:95`). No Swift change, no Core ML op outside iOS 18, no
  Accelerate/Metal/C++ seam, no Vision involvement.
- **Retires**: nothing on the device. In `model.py`, arm 1 retires the GAP line (`:45`) - the
  row's named defect - and keeps everything upstream identical, which is what makes the round
  controlled.

### 3.3 The data lever the row names: "on hand boxes" (`realglyphs.py` + the Swift export)

The r7-r11 pools are dominated by tracker-boxed video frames: the shipped r6 pool is **25 085
cells = 1 823 still cells (143 stills) + 23 262 frame cells from 42 records** (counted this run
from `.out/real/manifest.json` `cell_meta`), and only **76 cells come from owner-verified frames
(2 records)** - the hand-boxed subset of that pool is **1 899 cells, 7.6 %** (dp rate 0.2196).
PU.66 round 3 measured, for the detector, that removing tracker-boxed frames is "the largest
single improvement in the table" (median IoU 0.779 -> 0.790, live 25 -> 35 off / 34 -> 52 on
refusal; `docs/TASKS.md` PU.66), and its verdict "the recipe is hand boxes and the limit is their
count" is why the row says hand boxes. The classifier-side lever does not exist yet:

- `realglyphs.db_windows` (`realglyphs.py:81-93`) admits every train frame that is not
  `tracking: bad` and not `skipped`. A `--hand-only` flag restricts frame windows to
  `frames.verified = 1` (the DB column exists: 279 verified frames, 273 of them train, counted
  this run read-only from the WORKING-TREE `Spike/ReceiptSpike/fixtures/corpus.sqlite` - the
  annotator session is moving it, §5.1's drift warning applies), mirroring the detector
  export's precedent (`detdata.py:205-209`). ~10 lines.
- **Step 0 of the round is the re-export**: the standing `train-slices.json` was cut 2026-09-21,
  before the reader's read phase and corpus batch 7 (`REPORT.md:1353-1356` - r11's "found and not
  fixed", "the re-export is ... the first thing round 12 needs"); `PUMP_TRAIN_EXPORT=1 swift test
  --filter PumpTrainSliceExportTests` (`realglyphs.py:296`). After it, the hand-only pool is
  stills + up to 273 verified frames' windows; expect low thousands of cells (labelled estimate;
  the implementer counts at the build commit - a brief counts its population, and this one cannot
  count strips that do not exist yet).
- The cost is named, not hidden: hand-only shrinks real cells ~13x against the r6 pool at today's
  verified count, and `--real-frac 0.3` (`train.py:138`) then draws the same share from a much
  smaller set (repetition per epoch rises). The control round (same pool, unweighted BCE, current
  head) is what separates "the loss/head change did X" from "the hand-box pool did X" - r11's own
  decomposition protocol (`REPORT.md:1284-1308`).

### 3.4 A trap in the current defaults, and the consumers that must not move

`train.py:143` defaults `--dp-crop` to **gap**, `realglyphs.py:291` defaults it to **none** - the
two ends of r11's A/B left as defaults, disagreeing with each other and with the shipped framing
(`off`, the reader's crop). A round that forgets the flag trains on gap-framed cells against
off-framed inference (measured regression, `REPORT.md:1273-1277`) or on cleared dp bits whose
untrained 8th output still fires (per-glyph 0.186 vs 0.892 digit-only, `REPORT.md:1268-1271`).
Every round command pins `--dp-crop off` explicitly until the owner decides otherwise (§7-1).

dp's consumers, all unchanged by this row: the slicer's own mark geometry outranks the bit
(`markProbability` - `cellMarked` -> max(p, 0.95), `rowMarked` -> min(p, 0.49), else p as-is,
`PumpReader.swift:239-248`); `singleDecimalMark` keeps only the strongest when several fire
(`:250-266`); the law's placement hint stays the SOFT `decimalMarkPenalty = 4.0`
(`PumpReadingLaw.swift:43` at HEAD) per PU.78-A9. Note the structural consequence (inference,
labelled): the classifier's bit is consulted only on rows where the slicer's mark search - which
runs at half the digit threshold precisely to catch faint marks (`PumpGlyphSlicer.swift:50-62`) -
found nothing, i.e. on the faintest-mark rows, which is the hard end of an already
ceiling-bounded signal (§0). A dp AUC gain will therefore show up on the tiers only through the
rows the slicer misses.

## 4. Adaptations, named and justified (the fence)

Each is a departure from the published method; a departure the implementer adds that is not on
this list needs the product owner's OK.

| # | Paper | We do | Why |
|---|---|---|---|
| A1 | FL applied to K.A independent sigmoids per anchor (their §4 Classification Subnet, footnote 1) | FL applied per output of the 8 independent sigmoids | **Not a departure** - stated so it stays one: our head shape is their head shape; no softmax/multi-class reinterpretation is needed or allowed. |
| A2 | One alpha over all outputs (uniform rarity) | Two arms, both listed: (i) reweighting restricted to the dp bit (a-g unweighted), (ii) uniform FL over all 8 bits at per-bit alpha_t from inverse frequency | Their alpha suits one rare-class population; our per-bit priors span 0.22-0.92 (§2.2-3), and uniform inverse-frequency alpha would DOWN-weight positives of six bits. The row's title scopes the problem to dp; arm (ii) keeps a paper-faithful variant in the sweep. Train-side selection (§5.3). |
| A3 | alpha/gamma selected on COCO minival, reported on test-dev (their §5) | gamma x alpha x pos_weight selected ONLY on train-side measurements (pool dp AUC, synthetic val, per-bit accuracy); heldout is run ONCE per selected candidate as the gate | Decision 9 (`PumpReaderTestSupport.swift:57-67`): heldout is the frozen ratchet; tuning on it is forbidden. This mirrors their minival/test-dev split with our train/heldout split. |
| A4 | Hard targets | Label smoothing 0.05 kept (`train.py:132-135`); the modulating factor `(1-p_t)^gamma` and alpha_t use the HARD target, the log term the smoothed one | Smoothing is a load-bearing repo decision (the abstention frontier); the paper never combines them, so the combination is specified here rather than invented at the keyboard. |
| A5 | Prior init pi=.01, final-layer bias `b=-log((1-pi)/pi)` (their §3.3, §4.1) | Optional arm; if used, pi = the pool's per-bit positive priors (dp 0.2213 -> b=-1.26), not .01 | Their pi targets a 1:1000 divergence they observed; every round r6-r11 trained to completion with finite final val losses under plain BCE (`REPORT.md` round sections, `runs/*/metrics/*.json`), so no divergence remedy is owed, and pi=.01 at a 0.22 prior would start the dp head ~3x sharper than the data warrants. |
| A6 | Loss summed over ~100k outputs, normalized by positive-anchor count (their §4.1) | Sum over the batch's 8 x N outputs, normalized by the count of positive TARGETS - per bit (8 normalizers) in arm A2(i); global in A2(ii); NOT torch's default mean reduction | Their normalization is part of the method (it sets the effective LR against the rare class); torch `mean` silently deviates by the positive rate. The exact choice is logged in `metrics.json` with the run. |
| A7 | Conv+FC classifier head (CoordConv §4.2/Table S1 pattern; LeNet-5 family, bibliographic only) | B-arm 1: Flatten + Linear(1536,8), everything upstream identical | The direct published repair for "pooling discards position"; primary LeNet text not readable here (§1), so the pattern is cited from the fetched CoordConv text - named as an adaptation of sourcing, not of method. |
| A8 | CoordConv: coordinate channels i, j (, r) scaled to [-1,1], 1x1 in nearly all their experiments, stem-layer in their ImageNet recipe (§3, §S5) | B-arm 2: constant i, j (, r optional) buffers concatenated at the INPUT, first conv widened 3->3+d (k=3, not 1x1); GAP kept | Their stem recipe, applied to a 24k-param net; keeping the 3x3 first kernel avoids adding a layer to a budget-sized model. FC's translation sensitivity (their Table S1 quadrant failure) is the reason B-arm 2 exists beside B-arm 1: our cells carry +-2 px jitter (`train.py:75-79`) and per-class phase spread (`REPORT.md:1249-1252`). |
| A9 | - | NO inference-time re-framing in this row: the reader keeps the slicer's cell rect (`PumpReader.swift:222,:572`), training keeps `--dp-crop off` | The gap crop measurably carries the dp signal (probe 0.92-0.95, §0) but r11 measured that training on it while the reader feeds off-crops costs the pipeline 33 annotated and 15 live cells (`REPORT.md:1273-1277`). Widening the READER's crop (or a dp-only second crop) is a Swift reader change outside this row's seam, touching every bit's framing - an owner decision with its own controlled round (§7-3 names the seam). |
| A10 | - | The dp decision threshold stays 0.5 on the device (`PumpSegmentsModel.swift:78`, `PumpReadingTypes.swift:95`); no per-model dp offset ships in this row | One change per round. Known consequence (standard Bayes-threshold shift under alpha-weighting; inference, labelled): a reweighted model fires dp more often at a fixed 0.5, which moves `singleDecimalMark` and the law's placement hints; the tiers judge it. If a candidate's tiers regress through dp over-firing ONLY, a per-model dp threshold/offset stored in metadata beside PU.72's T is the follow-up - and it is a departure needing the owner's OK, not an implementer's fix. PU.78-M4's hard dp check stays blocked regardless until dp earns it (its 4-correct-heldout-refusals measurement). |
| A11 | - | Training pool restricted to hand boxes: still windows + `frames.verified` frame windows (new `realglyphs --hand-only`, precedent `detdata.py:205-209`), after the step-0 re-export | The row's own words ("the classifier sweep r7-r11 on hand boxes"); PU.66 round 3's measured detector verdict. Cost named: r6-era hand subset is 1 899 of 25 085 cells (7.6 %, counted §3.3); every round carries a same-pool control so the pool change never masquerades as a loss/head gain. |
| A12 | - | Candidates are scored under PU.72's calibration discipline: each exported candidate carries its own train-fitted temperature T (metadata, `agents/research/PU.72.md` §3.3), and the law's nat windows are restated per model (w/T) before tier comparison; if PU.72 has not landed at build time, the fallback is reporting the median committed-cell margin (raw nats) beside every tier number | The row's own ordering ("after PU.72's calibration so a margin shift is not mistaken for a gain"). PU.72 is still open at HEAD (no `temperature.py` in the tree); PU.72 §3.1's theorem (shared T rescales every margin by 1/T, rankings invariant) is what makes "live went up" attributable to reading changes rather than scale. |
| A13 | Their domains: COCO objects (FL), coordinate transforms/GAN/detection (CoordConv) | Seven-segment pump cells, 8-sigmoid 24k-param CNN, iOS 18 / iPhone 12 via Core ML | Nothing in either method is distribution-bound; the on-device surface is unchanged (§3.2) - no new op, no C/C++ target, no Accelerate/Metal seam. The domain cost is the label-achievability gap of §2.2-2, which no loss fixes. |

## 5. What the papers measured, and what we expect on our corpus

### 5.1 Populations, counted at HEAD `5b09f520` (files and filters named)

Counted by `/tmp/pu73/` scripts from `git show 5b09f520:Spike/ReceiptSpike/fixtures/pump/
{split.csv, windows.json, expected.csv}` with the harness's own filter (`isHeldout` /
`isReviewedTrain`, `PumpReaderTestSupport.swift:82-88`; scored-cell rule = field non-blank in
`expected.csv` minus `csvDisagrees`, `measureLive` at `PumpReaderPipelineTests.swift:546-608`,
the `csvDisagrees` skip at `:574-578`):

- **Split**: 328 stills - 256 train / 68 heldout / 4 heldout2 (heldout2 = pump-322/323/327/328,
  frozen, consumed by no filter).
- **Heldout reviewed (live tier)**: 68 stills, **183 scored cells** - equals
  `PumpPhotoGate.readerNumericTotal` (`PumpPhotoGate.swift:95`), the cross-check that the filter
  is the harness's. App path today: **45 committed / 45 correct** (`readerCommitted`/
  `readerCommittedCorrect`, `:86,:91`; `livePath` floor `= readerCommitted`,
  `PumpReaderPipelineTests.swift:56-58,:97-101`; precision floor 0.99, `:58`). Wilson 95 %
  two-sided **[0.9213, 1.0000]**, one-sided lower 0.9433 (PU.68's instrument,
  `PumpPrecisionBounds`; the brief's "45-47": 45 is the app path, 47 was the pre-PU.63
  `readPhoto` path).
- **Heldout annotated tier (gateMirror)**: **112 committed / 112 correct** at `b42f38da`+ (PU.79
  close, `docs/TASKS.md` PU.79); floors `committedFloor` 112 / `precisionFloor` 0.96
  (`PumpReaderPipelineTests.swift:28-29,:279-280`). Wilson 95 % two-sided **[0.9668, 1.0000]**
  (computed this run).
- **Reviewed train split (the certify population)**: **255 stills, 680 scored cells** at HEAD
  (PU.72 counted the same at `b42f38da`; PU.68's build counted 244/670). Last recorded certify
  run: 124 committed / 117 correct in-sample, Wilson 95 % two-sided **[0.8881, 0.9724]**
  (computed this run) - the implementer re-runs `PUMP_CERTIFY=1` at the build commit.
- **dp-AUC population (glyph tier)**: heldout reviewed stills x count-matched transaction windows
  (`score.py --only-count-correct` rule at `score.py:399-400`, boxes from
  `ios/.build/pump-reader-out/slices.json`): **186 windows, 873 cells, 185 dp-positive (21.19 %)**
  - equals PU.72 §5.1's count at `b42f38da`; slices.json is a build artifact (regenerated
  2026-09-23 19:43) and is re-cut at the build commit.
- **Training data**: synthetic renders (round-6 recipe: 15 000 steps, 120 000 renders,
  `--real-frac 0.3`, smoothing 0.05, `REPORT.md:416-430`; `train.py:123-145` defaults) with dp
  sampled at the calibrated corpus rate 0.2061 (`dataset.py:194-201`, `calibration.json:121`),
  measured 24.87 % dp-positive over 3 000 samples this run (incl. the 8 % dp-only prior,
  `dataset.py:79-80`); real glyphs: shipped r6 pool **25 085 cells, dp 22.13 %** (5 551),
  143 stills + 42 records, hand-boxed subset 1 899 (7.6 %) - all counted this run from
  `.out/real/{cells.npz, manifest.json}`.
- **Working-tree drift warning**: the annotator's uncommitted `windows.json`/`corpus.sqlite` move
  the reviewed counts (PU.78 §5 recorded the same hazard); every number above is the COMMITTED
  corpus at `5b09f520`, and the implementer re-counts with the same filter at the build commit
  and prints both.

### 5.2 What the papers measured

Lin et al.: COCO trainval35k, ablations on minival, headline on test-dev; ResNet-50/101-FPN,
SGD, 90k iters; the ablation chain 30.2 (init) -> 31.1 (balanced CE) -> 34.0 (FL gamma=2) AP,
OHEM comparison 36.0 vs 32.8, state of the art 39.1/40.8 test-dev AP (Tables 1-2). Their positives
were ~10^5 per image against ~10^2 - the 1:1000 regime. Liu et al.: Not-so-Clevr 3 136 examples
(§2), ImageNet ResNet-50 x5 runs (no significant gain, §5/§S5), MNIST Faster R-CNN (+24 % IOU,
§5), Atari A2C (6 of 9 games better, 1 slightly worse, §5) - coordinate-position tasks gain
dramatically, translation-invariant classification does not.

### 5.3 What we expect on our corpus, and the round protocol

Protocol (r10/r11 precedent, `REPORT.md:1208-1308`): step 0 re-export (`PUMP_TRAIN_EXPORT=1`,
§3.3); one control per pool (hand-box pool, `--dp-crop off`, unweighted BCE, current head, 3
seeds); then ONE change per round against that control, 3 seeds each (r11's seed spread on live
was 19-30 - a single seed cannot separate candidates); every candidate exported, scored with
`PUMP_MODEL=` (`PumpReaderPipelineTests.swift:76-79`) on BOTH tiers (gateMirror annotated,
livePath app path) under PU.72 discipline (A12), dp AUC on the §5.1 glyph population via
`score.py`'s `dp_auc`, model size and Release per-cell latency (row gate). Hyperparameter
selection inside a round is train-side only (A3).

Expectations, labelled inference over §0's measurements unless stated:

| quantity | expectation | basis |
|---|---|---|
| dp AUC, heldout real cells (from 0.645/0.657) | Round A: +0.00 to +0.05; Round B: +0.00 to +0.10; neither plausibly exceeds ~0.75 without a framing change | The shipped CNN already matches the linear transfer bound (0.645-0.657 vs 0.604-0.626, §0); headroom is the nonlinear part of the in-pool gap (0.78 linear vs 0.93 CNN) that survives the train->heldout shift, and the shift itself cost the probe ~0.15-0.17 AUC |
| dp firing rate at 0.5 | Round A raises it (alpha/pos_weight shifts the operating point); watch `singleDecimalMark` and the law's placement hints on the tiers | A10; standard threshold-shift under reweighting |
| Digit-only accuracy (0.9313/0.9370 heldout) | Round A: risk of small loss if dp gradients crowd the shared trunk; Round B arm 1 (FC): risk from translation sensitivity under +-2 px jitter; arm 2 (CoordConv): near-neutral for digits (coordinates can be zeroed out - their §3) | Table S1 quadrant failure; `train.py:75-79`; A7/A8 |
| Annotated tier 112 / live 45 | Must not fall (row gate: "ships only on live up at zero wrong readings"); a candidate that raises dp AUC but drops either tier is refused, r11 precedent | `REPORT.md:1288-1308` |
| Hand-box pool effect, isolated by the control | Unknown sign; PU.66 says tracker boxes hurt the DETECTOR's framing; for the classifier the effect is smaller and the 13x data cut may dominate | §3.3 counts; PU.66 round 3 (`docs/TASKS.md`) - labelled inference |
| dp AUC >= 0.9 on heldout under off framing | Should be treated as a LEAK until proven otherwise (that is gap-framing-level performance while the mark is measurably outside the crop) | §0 probes; falsifier F4 below |

### 5.4 Falsifiers, named in advance

- **F1 (implementation).** The named mutation: with gamma=0 (and alpha_t=1 / w=1) the Round-A loss
  must equal today's BCE to float tolerance - the paper's own eq. (4) statement - red before the
  equivalence is restored. For B-arm 2: zeroing the coordinate-channel weights must reproduce the
  control model's outputs exactly (their §3: CoordConv with zeroed coordinate weights "is
  translation invariant and thus mathematically equivalent to ordinary convolution").
- **F2 (no-gain close).** If, across 3 seeds, no Round-A or Round-B candidate moves heldout dp AUC
  above the control's by more than the seed spread, the row closes as a measured no-op WITH the
  probe ceiling (§0) recorded as the reason - not as "try harder". That outcome is a legitimate
  row result and points the owner at §7-3 (framing) as the only measured lever left.
- **F3 (tier gate).** Any candidate that loses a live or annotated commit, or adds any wrong
  reading at the shipped setting, is refused regardless of dp AUC (row gate; r11 precedent).
- **F4 (leak).** A heldout dp AUC >= 0.9 under off framing, or any dp AUC measured on train cells
  reported as heldout, is a scoring defect: re-check the split filter (`isHeldout`) and the slices
  provenance before believing it.
- **F5 (margin masquerade).** A "live up" that disappears when the candidate is re-scored under
  its own fitted T with windows restated (A12) was a margin-scale shift, not a gain - the exact
  confusion PU.72 exists to prevent.
- **F6 (digit cost).** dp AUC up while digit-only accuracy on the §5.1 glyph population falls by
  more than the seed spread: the trade is net-negative for the law (digits are what the arithmetic
  closes on; dp only places the mark) - refused even if the tiers happen to hold.

## 6. Cost

- **Latency (Release only - the row gate re-measures in `pump-read`'s `timingsMs`; today's Release
  baseline: decision 13-73 ms, read 112-164 ms on a Mac, classifier inference low-ms per cell -
  `docs/TASKS.md` PU.75, PU.72 §7 citing PU.38):** Round A adds ZERO inference cost (loss is
  training-only; exported graph unchanged). Round B arm 1: +11 776 MACs/cell (+0.28 % of the
  ~4.20 M feature MACs - arithmetic from the layer shapes, not profiled). Arm 2: +442 k MACs/cell
  (+10.5 %, the widened first conv) - both far below the per-cell Core ML overhead; neither
  touches the 5-TTA-crop count (PU.75's batching row owns that).
- **Bundle:** today 64 KB (`.mlpackage`, 24 328 params, measured this run). Arm 1: 36 104 params
  ≈ 144 KB float32 weights, package est. ~110-150 KB (inference from r6's param/size ratio);
  arm 2: ~65 KB. Budget <= 500 KB / ~125k params (`model.py:9`) holds with room for both.
- **Training:** ~960-1040 s per 15 000-step run on this Mac (`REPORT.md:1345`); the full sweep
  (control + 2 loss arms + 2 head arms, 3 seeds) is ~15-20 runs ≈ 4-6 h CPU, plus the step-0
  re-export and pool builds.
- **New code to maintain:** Round A ~40-60 lines (`train.py` flags + a stable fused focal
  implementation + normalization + `metrics.json` fields for gamma/alpha/w/normalizer); Round B
  ~30 lines (`model.py` head variants behind a `--head` flag); `realglyphs --hand-only` ~10
  lines; tests: the F1 equivalences, an export-roundtrip per head (the existing
  `test_export_roundtrip.py` shape), and the dp-AUC instrument invocation. **No C/C++ target, no
  Accelerate/Metal/Vision change, no Swift change** unless the owner later approves A10's
  metadata dp threshold (~15 lines in `PumpSegmentsModel`, the PU.72-T pattern).

## 7. Findings recorded, not fixed here

1. **The `--dp-crop` defaults disagree** (`train.py:143` "gap" vs `realglyphs.py:291` "none") and
   neither is the shipped framing ("off"). No row owns the defaults; until one does, every round
   command pins the flag (§3.4). A future round that forgets reproduces r11's regression or the
   firing-untrained-8th-output defect silently.
2. **The dp label's unreachability is a corpus-geometry fact, not a model defect**: the mark lives
   in the gap, the cell rect ends at the digit's ink (`PumpGlyphSlicer.swift:371-381`,
   `realglyphs.py:179-181`), and the classifier is consulted exactly where the slicer's own mark
   search came up empty - the faintest marks (`PumpReader.swift:244-248`,
   `PumpGlyphSlicer.swift:50-62`). Recorded so the next reader of "dp AUC 0.65" does not re-run
   this row's probes to find the ceiling.
3. **The measured lever this row may not pull**: inference-time gap framing (widen the reader's
   dp crop, or a second dp-only crop per cell). Evidence FOR: gap-framed cells are ~linearly
   separable (probe 0.92-0.95, §0) and the r11 gap-trained model's dp bit accuracy on heldout was
   0.7572 (`REPORT.md:1263-1266`). Evidence AGAINST: r11's pipeline regression when training and
   inference framings disagree (`REPORT.md:1273-1277`). Seam if the owner wants a row:
   `PumpReader.cropCell` (`:572`) / `averaged` (`:580-587`) and the slicer's rect construction -
   a Swift reader change affecting every bit's framing, needing its own controlled round and the
   PU.73 fence's owner sign-off. Filed here, not built.
4. **Verified-frame supply is the hand-box pool's limit**: 273 train verified frames exist in the
   DB today vs the 2 records that reached the r6-era pool (§3.3); owner frame verification grows
   every hand-box round's material (PU.66 round 3's verdict: "the limit is their count").
5. **The row text's dp-AUC premise (0.52-0.55) is stale** against the shipped model (0.645/0.657,
   §0); when the orchestrator ticks or rewrites the row, the fresh numbers and their population
   (186/873/185) belong in it.
6. `PumpReadingLaw.swift` carries a concurrent agent's uncommitted changes (PU.81, +50/-33 at
   this writing); every law line number cited here is HEAD `5b09f520`'s.
