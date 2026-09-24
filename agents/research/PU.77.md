# PU.77 research note - a row-level sequence reader: CRNN + CTC over the 96 px strips

*A run of `agents/briefs/RESEARCH-TO-CODE.md` for `PU.77` (`docs/TASKS.md:1083` at HEAD
`2050a5d3`). Product owner, 2026-09-23: "review the published research to apply it into the code,
instead of coming up with our own solution." Scope (product owner, 2026-09-24): a note is written
only for a row that changes the law, a model, or the statistics - this row changes the model.
Read-only except this file; no code written, no builds run, no tests executed. Every measured
number below comes from read-only scripts in `/tmp/pu77/` (`count.py`, `db.py`, `db2.py`,
`geom.py`, `wilson.py`, `exports.py`, `partial.py` - volatile, re-runnable from their descriptions
here) over the corpus **as committed at HEAD `2050a5d3`** (`git show HEAD:...`, never the working
tree) and over existing build artifacts (named, with their dates). **Working-tree drift warning:**
at this writing the tree holds a concurrent agent's UNCOMMITTED PU.74 build
(`PumpReadingLaw.swift` +20, `PumpReadingTypes.swift` +73/-27, `PumpReaderPipelineTests.swift`
`committedFloor` 118 -> 123, `docs/TASKS.md` PU.74 row "Built 2026-09-24"); every `file:line` below
is HEAD `2050a5d3`'s, and where the PU.74 build changes a fact both states are given. Evidence
rule: every claim cites a fetched paper section/equation, a `file:line`, or a number measured in
this run; inference is labelled.*

## 0. What this run settles, up front

1. **The method is CRNN (Shi, Bai, Yao) trained with the CTC loss (Graves et al. 2006), scaled
   down, with NO learned rectification and NO attention decoder.** The evidence is Baek et al.
   2019's controlled 24-combination study (their §4.3-4.4, summarised in §2.3 below), and the fit
   is structural: our strips are
   already homography-rectified before the reader sees them (`PumpReader.swift:204`,
   `score.py:174-213`), which is exactly the "regular" regime where Baek measures TPS
   rectification worth +1.1 % and attention worth +1.7 % at 17.1 ms against CTC's 0.1 ms
   (their Table 2). Every citation the row names is **correct as cited** (§1); no misattribution
   found.
2. **The row's two numeric bars are stale, and the note restates them at today's counts** (§6.2):
   "0.732 digit-only" is the ROUND-4 model of 2026-09-19 on count-correct windows only
   (`ml/pump-reader/REPORT.md:363-368`); on today's heldout count-matched cuts digit-only per-glyph
   accuracy runs **0.927-0.941 across the PU.73 sweep's control arms (864-cell cut) with the
   shipped r6 at 0.9313 single-crop / 0.9370 5-crop TTA on the previous 873-cell cut** (PU.73 row;
   PU.73 note §0). "commit >= 111" predates PU.78 and PU.74: the annotated tier is
   **118/118 at HEAD** (`PumpReaderPipelineTests.swift:30`) and **123/123 with the PU.74 build in
   the tree**. Per the brief's own phrasing (">= the annotated tier's count"), the operative bar is
   the tier's count at the spike's build commit.
3. **The PU.73 dp ceiling does not bind a row reader - the mark is inside its view.** PU.73's
   measured ceiling (~0.75 AUC for any loss or head; linear transfer 0.604-0.626) is a property of
   the 32x48 CELL CROP, which usually excludes the mark's ink (the mark sits in the inter-cell gap:
   `realglyphs.py:179-182`, `PumpGlyphSlicer.swift:371-381`, PU.73 note §0). The same probe on
   GAP-framed cells reads dp at **0.948 / 0.917 AUC linearly** (PU.73 note §0 table). A row-level
   reader sees the whole strip - gaps included - by construction, so the framing bound is removed
   and the gap-probe numbers are a FLOOR (linear probe, single crop) on what the strip carries.
   This is the one structural advantage the architecture has here, and §6.4-F4 names the ablation
   that proves the spike actually uses it.
4. **The published meter-reading family does NOT use sequence models**: Laroca's line detects,
   rectifies from detected corners, and classifies per digit with confidence rejection
   (§2.5). The only published sequence-model digit-string reader this run found is Yang et al.'s
   FCSRN for water meters (secondary source only, §1). A seven-segment + CTC paper does not exist
   on arXiv as searched (§2.6, null result recorded with its queries). So: the scene-text CRNN/CTC
   line is the method to apply; the AMR line is context, chiefly for its rejection discipline.
5. **The training data exists, but its real part is repetition-rich**: ~4.8k DISTINCT real strings
   (726 still transaction windows + 321 board + 492 distinct frame labels + 3,292 distinct video
   labels, counted §6.1) against CRNN's 8M synthetic words. The recipe therefore leans on the
   existing synthetic renderer (which already draws 96 px strips: `row.py:101-134`) with the real
   strips mixed in at the r6 precedent's share (`--real-frac 0.3`, `REPORT.md:416-430`), and
   Baek's measured finding - data DIVERSITY beats data COUNT (their §4.2: 2.9M diverse 81.3 % >
   8.9M single-source 80.0 %) - is why the dedup/cap rule is part of the recipe, not an afterthought.
6. **The law keeps its shape.** CTC per-position posteriors map onto the existing
   `PumpCellReading(probabilities:ranked:decimalPoint:)` constructor
   (`PumpReadingTypes.swift:84`) - the law test suite already builds cells exactly this way with
   arbitrary ranked candidates (`PumpReadingLawTests.swift:487,:568`). The nat windows are
   re-derived on TRAIN under PU.72's fitted temperature (`temperature.py`, committed at HEAD);
   nothing is tuned on heldout (decision 9, `PumpReaderTestSupport.swift:47-88`).

## 1. The citations, checked

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Shi, Bai, Yao, *An End-to-End Trainable Neural Network for Image-based Sequence Recognition*, TPAMI 2017, arXiv:1507.05717 (CRNN) | arXiv abs page fetched: title is *An End-to-End Trainable Neural Network for Image-based Sequence Recognition **and Its Application to Scene Text Recognition*** (the row truncates the subtitle); authors Baoguang Shi, Xiang Bai, Cong Yao; v1 21 Jul 2015; cs.CV. Venue via Crossref `10.1109/TPAMI.2016.2646371`: *IEEE Transactions on Pattern Analysis and Machine Intelligence*, vol 39, issue 11, published-print 2017-11-01, pages **2298-2304** (Crossref's pages; the arXiv text is the 2015 preprint). **Full text read** via ar5iv (v1): §2.1-2.4, Table 1, §3.1-3.4, Tables 2-4. | **Correct as cited** (subtitle truncated in the row; page range from Crossref, not recalled). Method read first-hand from the arXiv v1 text; the TPAMI version's body was NOT read (IEEE not fetchable here) - if a detail matters at build time, the arXiv text is the one this note quotes. |
| Graves et al., *Connectionist Temporal Classification*, ICML 2006 | **Full text read**: the official proceedings PDF fetched from `cs.toronto.edu/~graves/icml_2006.pdf` (8 pp.; footer "Appearing in Proceedings of the 23rd International Conference on Machine Learning, Pittsburgh, PA, 2006"). Authors Alex Graves, Santiago Fernandez, Faustino Gomez, Jurgen Schmidhuber (IDSIA / TUM). Venue double-checked via Crossref `10.1145/1143844.1143891`: "Proceedings of the 23rd international conference on Machine learning - ICML '06", 2006. Sections used: §2.1, §3.1-3.2, §4.1-4.2 (eqs. 1-16), §5.1-5.3, §6. | **Correct as cited.** Method read first-hand. |
| Jaderberg et al., *Spatial Transformer Networks*, NeurIPS 2015, arXiv:1506.02025 | arXiv abs page fetched: title exact; authors Max Jaderberg, Karen Simonyan, Andrew Zisserman, Koray Kavukcuoglu; v1 5 Jun 2015, v3 4 Feb 2016. Venue: the NeurIPS proceedings index (`proceedings.neurips.cc/paper/2015`) fetched and lists "Spatial Transformer Networks" with these four authors - the 2015 proceedings were named **NIPS** (the rename to NeurIPS came later); same venue the row means. **Full text read** via ar5iv (v3): §3.1-3.4, §4.1-4.2, Tables 1-2, Appendix A.4-A.5. | **Correct as cited** (venue name of the day: NIPS 2015). Method read first-hand. |
| Baek et al., *What Is Wrong With Scene Text Recognition Model Comparisons?*, ICCV 2019, arXiv:1904.01906 | arXiv abs page fetched: full title *What Is Wrong With Scene Text Recognition Model Comparisons? **Dataset and Model Analysis***; authors Jeonghun Baek, Geewook Kim, Junyeop Lee, Sungrae Park, Dongyoon Han, Sangdoo Yun, Seong Joon Oh, Hwalsuk Lee; Comments field: "**Oral paper at ICCV'19**" (venue confirmed by the arXiv record itself); v4 18 Dec 2019. **Full text read** via ar5iv (v4): §2, §3.1-3.4, §4.1-4.5, Tables 1-2, Figures 4-7. | **Correct as cited** (subtitle truncated in the row). Method read first-hand. |
| Salomon, Laroca, Menotti 2020, arXiv:2005.03106 (dial-meter work) | arXiv abs page fetched: *Deep Learning for Image-based Automatic Dial Meter Reading: Dataset and Baselines*; authors Gabriel Salomon, Rayson Laroca, David Menotti; Comments: "Accepted for presentation at the 2020 International Joint Conference on Neural Networks (IJCNN)"; Related DOI `10.1109/IJCNN48605.2020.9207318` (Crossref confirms: IJCNN 2020). **Full text read** via ar5iv (v2): §I-II (related work incl. FCSRN), §IV (baselines), §V-C (error analysis), metrics section. | **Correct as cited** (the row gives no venue; it is IJCNN 2020). Method read first-hand. |
| "Laroca's meter-reading papers" (the row's open pointer) | Resolved by arXiv API search (`all:"automatic meter reading" AND au:Laroca`, this run): the two central papers are **arXiv:1902.09600**, *Convolutional Neural Networks for Automatic Meter Reading* (Laroca, Barroso, Diniz et al.; venue via Crossref: *Journal of Electronic Imaging* 28(1):013023, 2019, `10.1117/1.jei.28.1.013023`) - **abstract fetched**, body not read; and **arXiv:2009.10181**, *Towards Image-based Automatic Meter Reading in Unconstrained Scenarios: A Robust and Efficient Approach* (Laroca, Araujo, Zanlorensi et al.; venue via Crossref: *IEEE Access*, 2021, `10.1109/access.2021.3077415`) - **full text read** via ar5iv (v5). | **Resolved and verified.** 1902.09600 is cited at abstract level only; 2009.10181 first-hand. |
| Yang, Jin, Lai, Gao, Li, *Fully Convolutional Sequence Recognition Network for Water Meter Number Reading*, IEEE Access 7:11679-11687, 2019 (found by this run, via Salomon's fetched related work §II) | Bibliography verified via Crossref `10.1109/access.2019.2891767`. **Primary text NOT fetched** (IEEE Access, no arXiv copy found); its method is described here ONLY as Salomon's fetched text describes it: a fully-convolutional sequence-recognition network for water-meter digit strings with an "Augmented Loss" for the accumulator's middle state, outperforming RNN and attention baselines "but the experiments were made in controlled images, with cropped and aligned meters" (Salomon §II, ref [19]). | **Bibliographically verified; body not read.** Description is secondary-source, labelled. If the spike wants AugLoss-style middle-state handling, that is a departure needing the owner's OK (§5-A12). |
| Seven-segment displays read by sequence models (the brief's open question) | arXiv API searches this run: `all:"seven-segment" AND all:recognition` (6 hits, none a sequence-model reader: the on-topic ones are per-digit classifiers - arXiv:1807.04888 smartphone seven-segment digit recognition, arXiv:2210.01325 Moreira's medical-device display DETECTION + per-digit reading, title-level only, not fetched); `all:"seven segment display"` (4 hits, none on-topic). The PU.73 note recorded the same null for per-cell heads (its §1, row 4), and the Qwen review recorded it for the family (`agents/reviews/PUMP-REVIEW-2026-09-23-qwen.md:714-720`). | **Null result recorded**: no published CTC/sequence reader for seven-segment pump displays was found. The recipe below applies the scene-text line to this domain; the domain transfer is a named adaptation (§5-A9), not a published result. |

Caution carried from PU.68/PU.72/PU.73 (it cost those runs fetches): every id above was fetched by
id or verified by Crossref/proceedings, never recalled.

## 2. The methods as published

### 2.1 CTC - Graves, Fernandez, Gomez, Schmidhuber, ICML 2006

**Output representation (§3.1).** A softmax output layer with `|L| + 1` units: one per label plus
one **blank** (§3.1, first paragraph). Output activations `y^t_k` are read as the probability of
label `k` at time `t`, defining a distribution over length-`T` paths `pi` in `L'^T`,
`L' = L ∪ {blank}`:

```
p(pi|x) = prod_{t=1..T} y^t_{pi_t}                                        (eq. 2)
```

with the stated conditional-independence assumption "given the internal state of the network"
(§3.1 after eq. 2). The many-to-one map `B` removes repeated labels then blanks
(`B(a-ab-) = B(-aa--abb) = aab`, §3.1), and the labelling probability is the path sum

```
p(l|x) = sum_{pi in B^{-1}(l)} p(pi|x)                                    (eq. 3)
```

**Decoding (§3.2).** The exact argmax over `l` is intractable ("we do not know of a general,
tractable decoding algorithm"). Two published approximations:
- **Best path**: `h(x) ~= B(pi*)`, `pi* = argmax_pi p(pi|x)` (eq. 4) - take the argmax at each
  time step, then collapse. Trivial to compute, "not guaranteed to find the most probable
  labelling".
- **Prefix search**: grow labelling prefixes by total probability (their Fig. 2), using modified
  forward-backward variables; "given enough time ... always finds the most probable labelling",
  exponential in the worst case. Their feasibility heuristic: split the output sequence at points
  where the blank probability exceeds a threshold (set to **99.99 %** in their experiments, §5.2),
  decode each section separately, concatenate. "Prefix search ... generally outperforms best path
  decoding. However it does fail in some cases, e.g. if the same label is predicted weakly on both
  sides of a section boundary" (§3.2) - for a 4-7 token string the section-splitting heuristic is
  unnecessary; plain prefix search over the whole strip is affordable (§4.4).

**Forward-backward (§4.1) - the machinery this row's posterior mapping reuses.** For labelling `l`,
build `l'` by inserting blanks at the ends and between every pair of labels (`|l'| = 2|l| + 1`).
Forward variable `alpha_t(s)` = total probability of `l'_{1:s}` at time `t` (eq. 5), initialised
`alpha_1(1) = y^1_b`, `alpha_1(2) = y^1_{l_1}`, `alpha_1(s) = 0 for s > 2`; recursion

```
alpha_t(s) = abar_t(s) * y^t_{l'_s}                     if l'_s = b or l'_{s-2} = l'_s
           = (abar_t(s) + alpha_{t-1}(s-2)) * y^t_{l'_s}   otherwise                 (eq. 6)
abar_t(s) = alpha_{t-1}(s) + alpha_{t-1}(s-1)                                        (eq. 7)
```

with the boundary rule `alpha_t(s) = 0` for `s < |l'| - 2(T - t) - 1`. Then

```
p(l|x) = alpha_T(|l'|) + alpha_T(|l'| - 1)                                           (eq. 8)
```

Backward variables `beta_t(s)` mirror it (eqs. 9-11). Underflow is handled by rescaling
(`C_t = sum_s alpha_t(s)`, hat-variables; §4.1 after eq. 11), and then `ln p(l|x) = sum_t ln C_t`.
The product identity (eq. 14) - `p(l|x) = sum_s alpha_t(s) beta_t(s) / y^t_{l'_s}` for ANY `t` -
is exactly the tool §4.4 uses: run the recursion on a MODIFIED target (one position substituted)
and eq. 8 returns that modified string's probability.

**Training (§4.2).** Maximum likelihood on unsegmented pairs:

```
O_ML(S, N_w) = - sum_{(x,z) in S} ln p(z|x)                                          (eq. 12)
```

differentiable through the softmax with the error signal (their eq. 16)

```
dO/dy^t_k  via  dO/du^t_k = y^t_k - (1 / (y^t_k Z_t)) sum_{s in lab(z,k)} ahat_t(s) bhat_t(s)
```

i.e. standard CTC loss; train by BPTT with any gradient method (§4). **No label smoothing, no
focal weighting, hard targets** - nothing else is published here.

**What they measured it on (§5).** TIMIT phoneme labelling: 61 phonemes + blank = 62 outputs,
4,620 train / 1,680 test utterances (184 train utterances held for early stopping), 26-dim MFCC
frames. Network: BLSTM, 100 blocks per direction, 114,662 weights; online SGD, lr 1e-4, momentum
0.9; Gaussian input noise sigma 0.6 for generalisation; weights init uniform [-0.1, 0.1]. Results
(Table 1, label error rate, means of 5 runs): CTC best-path 31.47 +- 0.21 %, CTC prefix-search
**30.51 +- 0.19 %**, against context-dependent HMM 35.21 % and BLSTM/HMM hybrid 33.84 %. Their
own generalisation caution (§6): "Good generalisation ... appears to be particularly so for CTC"
(they mean it is particularly DIFFICULT); §6 also records that CTC "does not explicitly model
inter-label dependencies" - context comes only through the recurrent state.

### 2.2 CRNN - Shi, Bai, Yao (arXiv v1 text; TPAMI 39(11) 2017)

**Architecture (§2, Table 1).** Input: a **W x 32 gray-scale** image, height normalised, width
arbitrary. Bottom-up:

| stage | config (Table 1) |
|---|---|
| conv1 | 64 maps, k3x3 |
| maxpool | 2x2, s2 |
| conv2 | 128, k3x3 |
| maxpool | 2x2, s2 |
| conv3, conv4 | 256, k3x3 (x2) |
| maxpool | **1x2**, s2 |
| conv5 + BN, conv6 + BN | 512, k3x3 (x2) |
| maxpool | **1x2**, s2 |
| conv7 | 512, **k2x2** - no BN after it: §3.2 inserts exactly "two batch normalization layers ... after the 5th and 6th convolutional layers" |
| Map-to-Sequence | columns -> frames |
| BiLSTM x2 | 256 hidden units each, bidirectional, stacked |
| Transcription | CTC (§2.3) |

The 1x2 pooling orientation: §3.2 says the 3rd and 4th pools use "1x2 sized rectangular pooling
windows instead of the conventional squared ones. This tweak yields feature maps with larger
width, hence longer feature sequence. For example, an image containing 10 characters is typically
of size 100x32, from which a feature sequence 25 frames can be generated." 100 -> 25 frames means
those two pools halve the HEIGHT only (width is halved twice, by the two 2x2 pools), leaving a
final map of height 1 (32 -> 16 -> 8 -> 4 -> 2, then conv7's k2x2 -> 1) and width W/4; each frame
is the concatenation of one column of all maps (§2.1: "the i-th feature vector is the
concatenation of the i-th columns of all the maps. The width of each column ... is fixed to single
pixel"), i.e. 512-dim. Each frame has a rectangular receptive field on the input (§2.1, Fig. 2),
"beneficial for recognizing some characters that have narrow shapes". Batch normalization "is
extremely useful for training network of such depth" (§3.2) - the paper inserts exactly two BN
layers, after the 5th and 6th convolutional layers.

**Sequence modelling (§2.2).** Deep bidirectional LSTM over the frame sequence; the stated
advantages: context makes ambiguous characters separable ("easier to recognize 'il' by contrasting
the character heights"), errors back-propagate into the convolutions (joint training), arbitrary
lengths. BPTT through the stack; a custom "Map-to-Sequence" layer bridges conv -> recurrent.

**Transcription (§2.3).** Lexicon-free: `l* ~= B(argmax_pi p(pi|y))` (§2.3.2 - best path,
citing Graves). Lexicon-based (§2.3.3, eq. 2): restrict the search to the edit-distance
neighbourhood `N_delta(l')` of the lexicon-free result and take `argmax_{l in N_delta(l')} p(l|y)`
via a BK-tree, `O(log|D|)`; they choose **delta = 3** as the accuracy/speed tradeoff (Fig. 4).
Training objective: `O = -sum log p(l_i|y_i)` (eq. 3 of the CRNN paper = CTC eq. 12), SGD with
**AdaDelta (rho = 0.9)** (§2.4).

**What they measured it on (§3).** Trained ONCE on 8M synthetic words (Jaderberg's Synth), no
real fine-tuning; tested on IIIT5k / SVT / IC03 / IC13. Training images resized to **100x32**;
test images scaled to **height 32, width proportional, at least 100 px**. Results (Table 2,
lexicon-free "None" column): IIIT5k 78.2, SVT 80.8, IC03 89.4, IC13 86.7 - competitive with
models trained on millions of real word crops. Model: **8.3M parameters, 33 MB** (Table 3), "can
be easily ported to mobile devices". Test speed 0.16 s/sample on a Tesla K40 (§3.2).

**The small-data precedent (§3.4).** For musical-score recognition with only 2,650 labelled
images (augmented to 265k), they used a SIMPLIFIED CRNN: "the 4th and 6th convolution layers are
removed, and the 2-layer bidirectional LSTM is replaced by a 2-layer single directional LSTM",
and report 74.6-84.0 % fragment accuracy against commercial systems' 20-55 %. This is the
paper's own licence for scaling the configuration down when the data is small - which ours is
(§6.1) - and the spike's config (§4.1) follows it in spirit while keeping the BiLSTM (Baek's
Table 2 measures BiLSTM as worth +2.5/+4.5 %).

### 2.3 Baek et al., ICCV 2019 - which modules, at what cost

**Framework (§3).** Every STR model decomposes into Transformation (None / TPS), Feature
extraction (VGG / RCNN / ResNet), Sequence modeling (None / BiLSTM), Prediction (CTC / Attn);
24 combinations trained and evaluated identically: 14.4M synthetic words (MJ 8.9M + ST 5.5M),
AdaDelta rho = 0.95, batch 192, 300K iters, gradient clipping 5, He init, model selection on a
held validation union every 2k steps (§4.1); evaluated on 8,539 real word images split
**regular** (IIIT, SVT, IC03, IC13) vs **irregular** (IC15, SVT-Perspective, CUTE80 - curved /
perspective) (§2).

**Module contributions (their Table 2, marginalised means, regular % / irregular %):**

| stage | module | accuracy | time | params |
|---|---|---|---|---|
| Trans. | TPS vs None | 86.7 vs 85.6 (**+1.1** / **+3.4**) | +3.6 ms | +1.7M |
| Feat. | ResNet vs VGG | 88.3 vs 84.5 (+3.8 / +7.1) | +4.1 ms | +44.3M vs 5.6M |
| Seq. | BiLSTM vs None | 87.6 vs 85.1 (+2.5 / +4.5) | +3.1 ms | +2.7M |
| Pred. | Attn vs CTC | 87.2 vs 85.5 (+1.7 / +2.6) | **17.1 vs 0.1 ms** | +0.9M |

Their accuracy-time frontier (§4.3, Table 4a): T1 None-VGG-None-CTC **69.5 % at 1.3 ms** -> T3
(+BiLSTM) 81.9 % at 7.8 ms -> T4 (+TPS) 82.9 % at 10.9 ms -> T5 (+Attn) 84.0 % at 27.6 ms, with
the verdict on the last step: "Attn ... only improves the accuracy by 1.1 % at a huge cost in
efficiency". Memory (§4.3, Table 4b): the feature extractor dominates (RCNN family 1.9M -> 7.2M
params across P1-P4 while accuracy climbs 75.4 -> 82.3; ResNet then costs 7.2M -> 49.6M for
+1.7); "transformation, sequential, and prediction modules are not significantly contributing to
the memory consumption".

**Qualitative (§4.4, Fig. 7).** What each module buys: TPS normalises curved/perspective text;
ResNet handles clutter and unseen fonts; BiLSTM "can ignore unrelatedly cropped characters";
**Attn's specific gain is an implicit character-level language model that "finds missing or
occluded character[s]"** - the one published argument FOR attention on glare-occluded rows, weighed
in §4.1 below against the fact that our law already closes the arithmetic exactly.

**Data diversity (§4.2).** Their best model: MJ-only 80.0 %, ST-only 75.6 %, union 84.1 %; and
**20 % of MJ + 20 % of ST (2.9M total) = 81.3 %, better than either full set alone** - "the
diversity of training data can be more important than the number of training examples". Directly
load-bearing for our repetition-rich real pool (§4.5).

**Failure cases and label noise (§4.5).** 644 of 8,539 test images (7.5 %) are missed by ALL 24
combinations; benchmark label noise measured at 1.3 % (24.1 % when case is considered). Our corpus
carries its own analogue - the annotation's own "legibility: partial" flags (8 heldout / 25 train
transaction windows at HEAD, counted §6.1) - and the export already skips them
(`PumpTrainSliceExportTests.swift:163`).

### 2.4 STN - Jaderberg, Simonyan, Zisserman, Kavukcuoglu, NIPS 2015 (considered, deferred)

**Method (§3).** A differentiable module: a **localisation network** `theta = f_loc(U)` (any CNN/
FCN with a regression head, §3.1) predicts transformation parameters from the feature map itself;
a **grid generator** builds the sampling grid - for affine, `(x^s_i, y^s_i)^T = A_theta (x^t_i,
y^t_i, 1)^T` with `A_theta` the 2x3 matrix of the six parameters (§3.2, eq. 10); a **sampler**
(bilinear kernel) produces the output map (§3.3). The whole module is trained by the task loss
alone, "without any extra training supervision or modification to the optimisation process"
(abstract); STs stack and run in parallel (§3.4, §4.2-4.3). Implementation recipes (Appendix
A.4-A.5): the localisation net's final regression layer is **initialised to the identity transform
(zero weights, identity bias)**; on SVHN its learning rate is set to **a tenth** of the base rate.

**What they measured it on (§4).** Distorted MNIST (rotations, RTS, projective, elastic;
40x42/60x60 canvases): error CNN 1.2 / 0.8 / 1.5 / 1.4 vs ST-CNN affine 0.7 / 0.5 / 0.8 / 1.2 and
ST-CNN TPS 0.7 / 0.5 / 0.8 / 1.1 (Table 1) - the gains are on POSED, recoverable distortion.
SVHN multi-digit (1-5 digits, 64x64 crops): ST-CNN Multi sequence error 3.6 % (Table 2),
state-of-the-art single-pass at the time. CUB-200 birds: multiple parallel STNs discover parts
unsupervised (§4.3).

**Why it is deferred here, not adopted (§4.1).** Our strips are rectified BEFORE the reader by a
homography from an annotated or detected quad (`PumpQuadWarp.warpToStrip`, `PumpReader.swift:204`;
the Python mirror `score.py:174-213`), and residual row rotation is PU.69's fast-Hough deskew's
job (median error 0.60 deg against the owner's hand quads, `docs/EXTRACTION.md` PU.69 paragraph).
Baek's Table 2 puts the learned-rectification gain at +1.1 % regular / +3.4 % irregular - the
irregular regime is curved and perspective text, which the quad warp already removes; STN's own
positive results are on synthetic poses. A TPS warp can also bend fixed-pitch seven-segment
geometry, and glyph SHAPE is the segment code the whole reader family lives on (inference,
labelled). STN remains the published add-on if the spike's error analysis shows a residual
tilt/warp class - as its own arm, identity-initialised per their A.4-A.5 recipe, with the owner's
OK (§5-A6).

### 2.5 The automatic-meter-reading family (context and rejection discipline)

- **Salomon, Laroca, Menotti (IJCNN 2020).** UFPR-ADMR: 2,000 unconstrained dial-meter images,
  9,097 dials. Baseline: Faster R-CNN (ResNet-50/101, ResNeXt-101) or YOLO(v2/v3) detect AND
  classify each dial in one pass; best **93.6 % per-dial, 75.25 % per-meter** (all dials of a
  meter right) with Faster R-CNN ResNeXt-101 (abstract). Their metric design is the part worth
  copying (§IV): dial rate via **Levenshtein distance normalised by the longer sequence**, meter
  rate via exact-sequence match, plus integer MAE - "correctly predicting the last digit ... is not
  as important as correctly predicting the first one". Error analysis (§V-C): the dominant error
  is the NEIGHBOUR value (pointer between marks - our analogue: the last-digit misreads PU.78
  traced), then lighting/dirt/glare. No sequence model: each dial is classified independently.
- **Laroca et al. 2019 (J. Electronic Imaging; abstract level).** Fast-YOLO counter detection +
  three CNN recognition approaches on UFPR-AMR (2,000 images); augmentation to balance digit
  classes; per-digit recognition, no sequence model.
- **Laroca et al. 2021 (IEEE Access, full text).** The pipeline closest in spirit to ours:
  detect the counter -> **CDCC-Net** predicts its four corners AND classifies legible/illegible in
  one pass -> **geometric rectification** by the corner homography (their eqs. 1-3 - the same
  device as `PumpQuadWarp`, ours from annotated/detected quads) -> **Fast-OCR**, a lightweight
  YOLO-style DETECTOR of the 10 digit classes with boxes (their Table 3), per-digit confidence.
  Measured: rectification cut reading errors by **34 %** on legible meters; the legibility head
  rejected **98.9 %** of illegible/faulty meters while accepting **99.82 %** of legible ones;
  with confidence-based rejection of low-certainty readings the system reaches **> 99 %**
  recognition (abstract, §I, §III-IV). Copel-AMR: 12,500 field images incl. 2,500 illegible.
- **Yang et al. FCSRN (secondary source only, §1).** The published sequence-model counterpoint:
  fully-convolutional sequence recognition for water-meter digit strings with an Augmented Loss
  for the accumulator's middle state, beating RNN and attention baselines on CONTROLLED, cropped,
  aligned meters (Salomon §II's rendering). Not fetched; not part of the recipe.

Read together (inference, labelled): the applied meter literature converges on
detect -> rectify geometrically -> per-digit classify -> **reject by confidence** - i.e. the shape
this repo already has (detector, quad warp, per-cell classifier, the law's abstentions), and its
measured wins come from rectification quality and rejection discipline, not from sequence models.
The sequence-model evidence for digit strings lives in the scene-text line (CRNN/CTC), which is
what the row proposes to import; nothing published does this for seven-segment pump displays
(§1, null result), so the transfer itself is the experiment the spike runs.

### 2.6 What the papers measured, versus what this corpus is

| | CRNN | Baek | Graves CTC | AMR family | this spike |
|---|---|---|---|---|---|
| train data | 8M synthetic words | 14.4M synthetic | 4,620 utterances (184 -> validation) | 2k-12.5k real images | ~4.8k distinct real strings + synthetic strips (unbounded, calibrated) |
| labels | word strings | word strings | phoneme strings | per-digit boxes/classes | window strings (no per-cell boxes needed - CTC's point) |
| alphabet | Synth word chars + blank (size not stated in the fetched text) | "alphabets and digits" (§4.1; size not stated) | 61 phonemes (+ blank = 62 outputs, §5.2) | 10 digits | **12** (10 digits + sep + blank, §4.3) |
| input | Wx32 gray | 32x100 word crops | 26-dim frames | crops/full images | WxH RGB strips, W96 in 24-458, H 96 (§6.1) |
| test | 4 benchmarks | 8,539 words | 1,680 utterances | 2,000-2,500 images | **195 heldout tx strips / 183 scored cells** (§6.1) |

The corpus is 3-4 orders of magnitude below every training set above except the AMR ones, and the
test tier (68 stills) is below all of them - which is why the bars are comparative (beat the
shipped arm on the same instrument) and interval-reported (PU.68), never absolute claims
(inference, labelled; the PU.68 note §6 makes the same point for the statistics rows).

## 3. The mapping onto this code

Line numbers at HEAD `2050a5d3`. The spike is OFFLINE (row text: "Offline only until it passes
... A Swift integration is its own row"), so nothing below ships in this row; the seam list is
what the spike measures AGAINST and what the integration row would touch.

1. **What the sequence reader replaces (integration row; the spike mirrors it offline).**
   `PumpReader.read` (`PumpReader.swift:201-235`) today: warp quad -> 96 px strip (`:204-206`,
   `stripHeight` `:13`) -> `PumpGlyphSlicer.slice` (`:207`, definition
   `PumpGlyphSlicer.swift:136`) -> plausibility guard on the cell count (`:211`) -> per cell:
   5-crop TTA (`augmentationOffsets` `:568-570`, `cropCell` `:572-578`, `averaged` `:580-587`) ->
   `PumpSegmentsModel.probabilities` (`PumpSegmentsModel.swift:41-52`, input 32x48 `:14-15`) ->
   constrained rank over the ten segment patterns (`rank` `:59-71`) -> slicer-mark override
   (`markProbability` `:244-248`) -> `singleDecimalMark` (`:255-265`). A row-level reader consumes
   the SAME strip at `:206` and emits `[PumpCellReading]` directly: one model call per window
   replaces the slicer, the TTA crops, the per-cell classifier calls, the mark second look and the
   dim-glyph recovery.
2. **What the law consumes - unchanged types.** `PumpCellReading`
   (`PumpReadingTypes.swift:79-110`): the constructor `init(probabilities:ranked:decimalPoint:)`
   (`:84`) already takes an arbitrary ranked `[PumpGlyphCandidate]` (`:70`), and the law test
   suite builds cells exactly this way with `probabilities: []`
   (`PumpReadingLawTests.swift:487,:568`) - the spike's posteriors enter the law through the same
   door, no type change. `PumpReadingLaw.candidates` (`PumpReadingLaw.swift:366-403`) beams
   `beamWidth = 3` per cell (`:26`) into `stringsPerField = 12` strings (`:28`), applies the
   decimal-placement penalty `decimalMarkPenalty = 4.0` (`:44`), and the exact-close tiers
   (`closingTriples` `:405`, `commit` `:451`) judge with `readWindow = 6.0` (`:39`) and
   `ambiguityWindow = 3.0` (`:34`). All of it runs on per-cell ranked log-posteriors - what §4.4
   produces.
3. **The posterior computation is Graves §4.1 verbatim, composed our way.** Decode the strip
   (prefix search, Graves §3.2) to the top string `l*`; for each position `s` and each digit `d`,
   run the forward-backward recursion (Graves eqs. 5-8, log-space with their rescaling) on `l*`
   with position `s` replaced by `d`; normalise the ten probabilities; take logs. Same recursion,
   same equations - the substitution-lattice USE is ours (§5-A4). The sep token's probability at
   each boundary becomes the cell's `decimalPoint` posterior (threshold 0.5 as today,
   `PumpReadingTypes.swift:92-95`).
4. **Calibration and the nat windows.** CTC posteriors are softmax probabilities at a different
   margin scale than round 6's eight sigmoids, so the law's nat windows do not transfer as-is
   (Qwen review §4.2: "the nat windows must be recalibrated from scratch"). The instrument exists:
   `ml/pump-reader/src/pump_reader/temperature.py` (committed at HEAD) fits one shared `T` per
   model by NLL on TRAIN real data (Guo et al. 2017 eq. 9; golden-section `fit_temperature`) and
   reports Guo ECE / per-label ECE / ECE_ML. The spike fits `T` on the TRAIN strips' per-position
   softmax (§4.4), restates the windows in scaled nats, and re-derives them **on train only**
   (PU.72's shipped discipline: "the law's windows restated in calibrated nats and re-derived on
   train, never heldout", `docs/TASKS.md` PU.72 row).
5. **What it retires - only on adoption, by the integration row.** The slicer's whole option
   surface (~30 constants, `PumpGlyphSlicer.swift:35-109`) and its three extension files
   (`+DimGlyphs`, `+Marks`, `+Primitives` - the "class of six named failure shapes" the row
   cites: PU.37's table "12 dim/lost glyphs under one global Otsu, 6 pitch harmonics, 4
   over-merges, 3 mark over-fires, 2 split over-counts, 2 snap/blank", `docs/TASKS.md` PU.37
   row); the 5-crop TTA (`PumpReader.swift:568-578`); `markProbability`/`slicerMarkConfidence`
   (`:239-248`); `singleDecimalMark` (`:255-265`); the dp bit's whole consumer chain
   (`PumpSegmentsModel.swift:78`, `PumpReadingTypes.swift:95`) - the sep token replaces it; and
   `decimalMarkPenalty` (`PumpReadingLaw.swift:44`) changes meaning: placement is then read from
   the string, and the penalty becomes the sep token's own posterior, not a 4-nat constant.
   **The spike retires nothing** (offline-only row).
6. **Two comments/fields become false under adoption - the integration row must rewrite them.**
   "The cell count is a slicer fact, not a hypothesis" (`PumpReadingTypes.swift:113`) - under CTC
   the count is the decoder's length hypothesis; PU.74's `conventions.admits` cell-count check
   (working-tree build; HEAD's law has the permissive `forCurrency` switch,
   `PumpReadingTypes.swift:214-231`) then guards a model output, which is exactly what its
   `.cellCountImpossible` refusal exists for. And the verifier: `PumpRowGeometry.Reason` is
   literally the slicer's measurements (`cellCount/pitch/inkBand/decimalMark/blankLayout`,
   `PumpRowGeometry.swift:22-27`; "the verifier's drops are slicer measurements ..., so a row the
   slicer miscounts is not read badly, it disappears", `docs/EXTRACTION.md:1090-1093` at HEAD) -
   removing the slicer starves the verifier that produces the -17 apportionment drop this row
   targets. The replacement keep-rule (CTC blank-mass, total posterior, decoded length vs box
   width) is the INTEGRATION row's design decision with the owner, named here, not built
   (§7-3).
7. **Training-data seams (spike step 0).** The export already produces exactly the spike's input:
   `PumpTrainSliceExportTests` (`PUMP_TRAIN_EXPORT=1` stills+tracked frames `:16,:31-35`;
   `PUMP_TRAIN_EXPORT_VIDEOS=1` labelled video frames `:40-44`) warps every train window to the
   96 px strip (`warpToStrip` `:64`), writes the strip PNGs (`:68-69`) and the text label per
   window (`:70-85`), skipping `legibility: partial` (`:163`). The current artifacts
   (`ios/.build/pump-reader-out/train/train-slices.json` 8,613 windows / `train-videos.json`
   3,497, both cut **2026-09-21**) PREDATE the 2026-09-24 corpus commit (`22559705`: pump-275
   re-framed, pump-325 framed, video labels and corrections), so **step 0 of the spike is the
   re-export** (PU.73 note §3.3's standing finding). The synthetic renderer already draws strips:
   `render_row_of_labels(..., strip_h=96)` (`row.py:101-134`) with the full augmentation pipeline
   (`augment.py`: glare, blur, perspective, ghosting, reflection, noise, occlusion - `README.md`
   "Augmentations") and the corpus-calibrated palettes (`dataset.py:43-106`: technology priors
   0.80/0.15/0.05, grey-LCD 0.75, real contrast quantiles, dark-on-light 0.94). What does NOT
   exist yet: a corpus-calibrated STRING sampler (§4.3) - `sample_row_text` (`row.py:70-81`)
   draws 1-3 integer + 1-2 fraction digits and adds leading spaces at 25 %, which contradicts
   the corpus convention ("unlit leading cells are never transcribed", `windows.json` `_about`)
   and under-represents the 6-digit zero-padded class (§6.1's distribution).
8. **Scoring seams.** Python-side strips for heldout come from `score.py`'s warp
   (`slice_cells_from_boxes` `:174-213`, `STRIP_HEIGHT = 96` `:49`, `reading_order` mirroring
   `PumpQuadWarp.readingOrder` `:125-136`) over the annotated quads - the SAME 195 transaction
   windows `gateMirror` feeds the law (`PumpReaderPipelineTests.swift:189-283`). The law-over-
   posteriors arm runs Swift-side: the spike writes a JSON of per-window ranked posteriors; a
   test-side loader (precedent: the `PUMP_MODEL=` candidate seam,
   `PumpReaderPipelineTests.swift:80-81`) builds `PumpCellReading`s and replays `gateMirror`'s
   scoring loop (`:235-261`, tolerance `CorpusScorer.tolerance = 0.005`,
   `CorpusABScorer.swift:175`, derived cells 0.1) with `expected.csv`, the window currency and
   `FuelPriceBandStore.bundledPack()`. Every precision prints with PU.68's Wilson interval
   (`PumpPrecisionBounds.swift`, test bundle). No app-path Swift, no Core ML, no device code.

## 4. The recipe the note settles (the row's four questions)

### 4.1 Architecture and loss: scaled CRNN + CTC; attention and rectification rejected, named

**Loss: CTC maximum likelihood** (Graves eq. 12; CRNN eq. 3), hard targets, log-space
forward-backward with rescaling (Graves §4.1). PyTorch `nn.CTCLoss` (which implements exactly
eqs. 5-8/12 in log space) with a hand-rolled eq.-6 recursion as the cross-check (§6.4-F1).
No label smoothing, no focal weighting: neither is in the published CTC recipe, and adding one is
a departure needing the owner's OK (contrast the per-cell model, where LS 0.05 is a load-bearing
REPO decision - `train.py:165-168`; it does not carry over automatically because CTC's loss is a
path sum, not a per-class BCE - inference, labelled).

**Prediction: CTC, not attention.** Baek's controlled measurement: Attn buys +1.7 % regular /
+2.6 % irregular accuracy for 17.1 ms vs 0.1 ms and +0.9M params (their Table 2), and its
specific gain is the implicit character-level language model recovering occluded characters
(§4.4 qualitative). Our "language model" is stronger and already built: the law closes
`volume x price = total` EXACTLY (PU.78, `PumpReadingLaw.swift` header comment `:6-22`,
`docs/EXTRACTION.md:1095-1105`), constrains strings by measured per-currency conventions (PU.74),
and repairs one confusable cell under uniqueness - recovering an occluded digit is the repair
tier's job with arithmetic as the judge, not an n-gram's guess. Attention also decodes
autoregressively: no native per-position posterior of the shape the law consumes (§4.4), and the
worst latency of any module in Baek's study. Decision: **CTC**; attention stays the published
alternative to revisit only if the spike's error analysis shows occlusion-dominated failures the
law cannot repair (a new decision, not an implementer's swap).

**Rectification: none in the model.** §2.4's reasoning: strips arrive homography-rectified
(`PumpReader.swift:204`) and deskewed on refusal (PU.69); Baek measures TPS at +1.1 regular /
+3.4 irregular for 1.7M params and 3.6 ms; Laroca 2021's measured win from rectification (+34 %
fewer errors) comes from GEOMETRIC corner rectification - which we already do - not a learned one.
No STN/TPS module (§5-A6 records the deferred option with its published recipe).

**Architecture: CRNN Table 1's topology, scaled.** The paper's 8.3M-param/512-channel net was
trained on 8M words; §3.4's music-score precedent licenses the smaller build for small data. The
spike's primary config (channel arithmetic this run):

| layer | config | params |
|---|---|---|
| conv1 k3x3 + pool 2x2 | 3 -> 16 | 448 |
| conv2 k3x3 + pool 2x2 | 16 -> 32 | 4,640 |
| conv3 k3x3 | 32 -> 64 | 18,496 |
| conv4 k3x3 + pool **1x2 (height)** | 64 -> 64 | 36,928 |
| conv5 k3x3 + BN | 64 -> 128 | 73,856 |
| conv6 k3x3 + BN + pool **1x2 (height)** | 128 -> 128 | 147,584 |
| conv7 **k2x2** | 128 -> 128 | 65,664 |
| BiLSTM layer 1 (2 dirs, 128 hidden, input 128) | | 263,168 |
| BiLSTM layer 2 (2 dirs, 128 hidden, input 256) | | 394,240 |
| softmax head 256 -> 12 | | 3,084 |
| **total** | | **~1.01M** (~4.0 MB fp32, ~2.0 MB fp16) |

Height path 32 -> 16 -> 8 -> 4 -> 2 -> 1 (conv7's k2x2), width halved only by the two 2x2 pools:
T = W32/4 frames of 128 dims - the paper's Map-to-Sequence (§2.1-2.2) with 128 instead of 512
channels. BN placement follows the paper: exactly two BN layers, after conv5 and conv6 (§3.2).
**RGB input, not the paper's
gray-scale** (§5-A2). Smaller fallback if the budget demands: conv channels [16,32,48,48,96,96,96]
+ BiLSTM 96 -> ~0.45M params (same arithmetic; the integration row's decision, not the spike's).
BiLSTM stays bidirectional 2 layers (Baek Table 2: +2.5/+4.5 %; CRNN §2.2's context argument);
the conv-only `Seq=None` CTC arm (Baek's T1/T2 shape, "Rosetta") is the named fallback if LSTM
ever proves slow on-device - an arm, not a silent swap (§5-A7).

**Optimizer/training protocol.** Baek's published protocol is the default: **AdaDelta rho = 0.95,
gradient clipping 5, He init, batch 192** (their §4.1), scaled down in steps to the corpus
(§4.5). CRNN used AdaDelta rho = 0.9 (§2.4); Graves used online SGD lr 1e-4 momentum 0.9 (§5.2)
- both recorded; AdaDelta-0.95 is the choice because Baek's is the only one measured across
CTC/Attn combos at scale. The repo's AdamW+cosine (`train.py:159-160,:239-243`) is the named
alternative if AdaDelta diverges on the small pool - a swap the implementer logs, not invents
(§5-A8). Input-noise regularisation follows Graves §5.2 (Gaussian noise on the inputs; they
measured CTC needing MORE noise than the hybrid, sigma 0.6 on 26-dim features - our analogue is
the augmentation pipeline the renderer already runs, so no extra noise by default; adding a
pixel-noise knob is inside the renderer's existing overrides).

### 4.2 Input geometry: height 32 (the paper's), width proportional, padded

- **Height 32**, CRNN's exact test-time rule: "scaled to have height 32. Widths are proportionally
  scaled with heights, but at least 100 pixels" (§3.2). Our strips: H96 x W96-in-24..458 -> H32 x
  W8..152 (median 76, p90 118 - counted §6.1 from the Sep-21 export).
- **Padding to the paper's min-width 100 is load-bearing, not cosmetic**: CTC needs
  `T >= |l'| = 2U + 1` (Graves §2: "the target sequence ... is at most as long as the input
  sequence"). At height 32, `T = W32/4`; **594 of 12,110 export strips (4.9 %) have
  W96/12 < 2U+1** for their own label (counted this run, `/tmp/pu77/geom.py`) and would be
  untrainable/undecodable; the min-width-100 pad gives T = 25 >= 17, sufficient for every corpus
  string (max U = 8 tokens: 7 digits + 1 sep, §6.1). Pad on the RIGHT with the strip's own edge
  column (not black: a black margin teaches a blank spike at the end - inference, labelled; the
  exact pad mode is logged in the run's metrics).
- **Training batches**: aspect preserved, padded to the batch max width, capped at 160 (W96 480;
  the export max is 458 -> 152 at h32, inside the cap). CRNN trained on a FIXED 100x32 resize
  (§3.2); that squashes a 6-digit 351 px strip to 3x compression and ~5.6 px per digit - below
  the stroke width the segment code needs (arithmetic this run: median 6-digit pitch 351/6 = 58.5
  px at H96 -> 19.5 px at H32 unsquashed). Deviation named (§5-A3): pad, never squash.
- **Height-48 ablation arm, with the decision rule named in advance**: run it only if the primary
  arm's **sep-token accuracy on the fixture-grouped train validation sits more than 0.03 below
  its digit accuracy**. Rationale: the comma's tail and the LED dot are the smallest ink on the
  strip (PU.73's whole finding is that small marks die in framing), and H96 -> H32 is a 3x
  downsample; H48 halves it at 2.25x the conv MACs (arithmetic). Adopt H48 only on that measured
  gap, not on taste.

### 4.3 Alphabet, labels, and the string sampler

- **Alphabet (12 tokens)**: `0-9`, one separator token `sep`, CTC `blank`.
  - `.` and `,` both map to `sep`: the corpus writes both (465 `.` vs 461 `,` across every split's
    transaction texts at HEAD, counted this run) and treats them identically everywhere
    downstream - `score.parse_cells` sets the dp bit for either (`score.py:90-108`), the law reads
    only PLACEMENT (`PumpReadingLaw.swift:385-396`). Keeping two tokens would split the separator
    mass over a distinction no consumer reads (§5-A5).
  - **No space token**: no corpus transaction text contains one (counted this run - the character
    census over every non-empty tx text at HEAD returned only digits, `.` and `,`, plus the five
    pump-263 strings below); the convention is "unlit leading cells are never transcribed"
    (`windows.json` `_about`). Unlit cells cost CTC nothing - blank frames where there is no ink.
  - **Non-alphabet strings are filtered from training, by name**: pump-263's `closed` (total) and
    four `-00-` boards (5 windows, the only ones in the corpus; listed by `/tmp/pu77/odd.py`).
    The display-decision arm owns "closed", not the reader.
- **Synthetic string sampler (new, corpus-calibrated).** Per draw: a role (total/liters/unitPrice
  at the corpus's field rates - export fields counted §6.1), a digit count from the measured
  distribution (stills: {3: 43, 4: 424, 5: 62, 6: 186, 7: 9}; full export: {3: 1806, 4: 7224,
  5: 393, 6: 2678, 7: 9} - §6.1), a placement from that role's convention rows
  (`PumpDisplayConventions` - PU.74's measured table in the working tree; HEAD's switch
  `PumpReadingTypes.swift:214-231` until PU.74 commits), zero-padding per the corpus (leading
  zeros kept, no leading spaces), and `sep` rendered in BOTH glyph styles the renderer has (dot
  for LED, below-baseline comma for LCD/VFD - `row.py:110,:140-146`'s `comma` flag and the
  profiles). `sample_row_text` (`row.py:70-81`) is NOT reused as-is (§7-3).
- **Real labels**: the export's `text` verbatim, normalised `.`/`,` -> `sep`, spaces dropped
  (none exist), non-alphabet filtered. A strip whose normalised label has U tokens needs
  T >= 2U+1 after padding (§4.2 guarantees it).

### 4.4 Outputs -> the law: per-position posteriors, calibrated

The law needs, per cell: ranked digits with log-posteriors (`PumpGlyphCandidate`,
`PumpReadingTypes.swift:66-77`) and a `decimalPoint` flag. CTC natively gives per-FRAME
distributions, and frames are not cells. The mapping, in four steps, each sourced:

1. **Decode** the strip by prefix search (Graves §3.2, no section-splitting heuristic needed at
   T <= 40) to the top string `l*` = `d_1 sep? d_2 ...`; best-path `B(pi*)` (Graves eq. 4; CRNN
   §2.3.2) runs alongside as the published control - Graves measured prefix search better on
   TIMIT (30.51 vs 31.47), and a harness where best path beats prefix on PEAKED seven-segment
   strips is a finding to report, not to hide. The cells are `l*`'s digit tokens, in order;
   `decimalPoint` on the digit a `sep` follows - exactly `parse_cells`'s rule (`score.py:90-108`).
2. **Per-position posteriors** (the composition is ours; the machinery is Graves §4.1): for each
   digit position `s` and each `d` in 0-9, compute `p(l*^{s->d} | x)` by the forward-backward
   recursion on the substituted string (eqs. 5-8 with their rescaling; `ln p` via `sum ln C_t`);
   also `p(l*^{sep_s inserted/removed} | x)` for the boundary. Normalise the ten (plus the sep
   variant) into a distribution, take logs, sort -> `ranked`; sep posterior -> `decimalPoint`
   probability, thresholded 0.5 for the flag (`PumpReadingTypes.swift:95`'s rule). Cost: ~11
   forward-backward passes per position, each O(T x U) - at T <= 40, U <= 9 that is ~4k
   multiply-adds per position, negligible against the network pass (arithmetic). What this is
   NOT: the marginal over ALL labellings of all lengths (intractable - the same reason Graves
   §3.2 gives for decoding); it is the substitution marginal around the decoded string, which is
   the quantity the law's beam actually consumes (its `candidates` explores exactly one-digit
   substitutions per cell, `PumpReadingLaw.swift:366-379`). Named as adaptation A4; the
   string-level N-best alternative (joint `p(l|x)` per beam string) does not fit the per-cell
   interface and would bypass the law's beam - recorded, not built.
3. **Calibrate before nats.** Fit one shared temperature `T` by NLL on the TRAIN split's real
   strips (Guo eq. 9; `temperature.py`'s `fit_temperature` pattern - golden-section on log T;
   the module today reads `segmentnet.pt`/`cells.npz`, so the spike writes a strip-level twin
   reusing the fit, ~20 lines). Apply `softmax(z/T)` before step 2's logs, report raw-nat and
   T-scaled arms side by side, and re-derive the law's windows (6.0/3.0/4.0 at HEAD
   `PumpReadingLaw.swift:34-44`) on TRAIN scaled nats - PU.72's shipped discipline and PU.73's
   F5 masquerade guard. PU.72's own finding stands as the caution: for the SHIPPED model a shared
   T changed no law decision because every margin scaled alike (its row, "Built 2026-09-24 as the
   note's reporting-only outcome") - for CTC posteriors the windows are NOT scale-free against a
   new model family, which is why the re-derivation is part of the bar, not an option.
4. **Feed the law.** JSON per window: `{fixture, field, windowIdx, positions: [[{digit, logp} x
   <=10] ...], sep: [p ...]}` -> Swift test-side loader builds
   `PumpCellReading(probabilities: [], ranked: ..., decimalPoint: ...)` (`:84`) ->
   `PumpReadingLaw.resolve(windows:currency:priceBand:)` (`:46`) -> `gateMirror`'s scoring loop
   (§3-8). The harness scores the annotated tier exactly as `gateMirror` does - same windows
   (all with text, boards included: the law's no-price branch consumes them,
   `PumpReadingLaw.swift:199-231` at HEAD / `resolveWithoutPrice`), same currency source, same
   bands, same tolerance - so its number is comparable to the 118/123 floor cell for cell.

Length-mismatch honesty: the law's cells-per-window count becomes the decoder's hypothesis. The
spike reports **length accuracy** (decoded token count == `parse_cells(text)` count) as its own
metric - it is the CTC replacement for the slicer's count agreement (236/251 on heldout hand
quads, PU.42 row; 9,481/12,110 = 0.783 on the train export, counted §6.1) - and the integration
row owns what the verifier does with it (§3-6).

### 4.5 Training data and protocol

- **Step 0: re-export** (`PUMP_TRAIN_EXPORT=1` + `PUMP_TRAIN_EXPORT_VIDEOS=1 swift test --filter
  PumpTrainSliceExportTests`, `realglyphs.py:296`'s standing instruction). The Sep-21 artifacts
  (8,613 + 3,497 strips) predate the 2026-09-24 corpus commit; the DB at HEAD holds 726 still tx
  + 321 board windows, 29,793 usable train frame windows (6,498 frames, 161 records) and 19,021
  usable video labels - the re-export is up to ~50k strips (§6.1). Heldout/heldout2 never enter:
  the export's `isTrain` filter (`PumpTrainSliceExportTests.swift:129`) and `realglyphs`'s
  heldout guard (`realglyphs.py:303-306`) already enforce it; heldout RECORDS are excluded by
  their still (`PumpReaderTestSupport.swift:137`).
- **Dedup/cap (Baek §4.2's diversity finding, operationalised).** The frame windows carry only
  **492 distinct (record, field, text) labels** and the videos **3,292 distinct (video, field,
  text)** (counted §6.1) - adjacent frames are near-copies. Cap any one still/record/video at a
  fixed share of the real pool by uniform subsampling - `realglyphs.py`'s `cap_sources`
  water-filling (`:128-158`) is the existing, tested device; start at 2 % per source and record
  the pool composition (`composition()` `:161-172`). Glitch-labelled frames keep their own labels
  (`glitch_frames` `:228-244`).
- **Mix.** Synthetic strips (unbounded, §4.3's sampler + the renderer's augmentation) as the
  bulk - CRNN trained on synthetic ONLY and transferred to four real benchmarks (§3.1) - with
  the real strips mixed at the r6 precedent's **`--real-frac 0.3`** share of every batch
  (`REPORT.md:416-430`: the real mix was worth coverage x2.4 at higher precision on this corpus).
  One knob, no sweep in the spike (budget); the value is logged in the run's metrics.
- **Validation = train-side only** (decision 9): a fixture-GROUPED 10 % of the real train strips
  (no fixture or record on both sides - PU.73's probe protocol) plus a disjoint-seed synthetic
  set (`train.py:30-31`'s `VAL_SEED_OFFSET` pattern). Model selection, the H48 decision rule,
  early stopping: all on this validation. **Heldout is scored ONCE per finalist candidate** and
  the score is logged with the candidate's config (the PU.73 A3 discipline); **heldout2** (4
  stills, 12 tx windows, §6.1) is scored once, at the final go/no-go, never during fitting
  (`docs/EXTRACTION.md`, "Amended 2026-09-23: a second frozen draw").
- **Seeds: 3 per arm.** PU.73's measured seed spread on the tiers was 19-30 live commits - a
  single seed separates nothing (its row, "live swings 43-56 across seeds").
- **Budget**: ~20-40k steps at batch 64-128 (Baek's 300K iters were on 14.4M images; ours is
  ~10^3 real + on-the-fly synthetic - CRNN's §3.4 small-data precedent again). Estimated 2-4 h
  per run on this Mac (inference from r6's measured ~1000 s for 15k steps of a 24k-param cell
  model, `REPORT.md:1345`, scaled by the ~14x per-sample MAC ratio of §7); 3 seeds x (primary +
  H48 + best-path control) ~= 1-2 machine-days.

### 4.6 The dp question the brief asks: does a row reader change PU.73's ceiling? Yes - measurably

PU.73 established, with probes: the shipped CELL crop usually does not contain the mark's ink
(the cell rect ends at the digit run's right edge, `PumpGlyphSlicer.swift:371-381`; the mark sits
in the gap after the glyph, `realglyphs.py:179-182`), so dp's transferable signal is bounded
near 0.63 AUC whatever the loss or head (ceiling ~0.75, PU.73 note §0) - while the SAME linear
probe on gap-framed cells reaches **0.948 / 0.917**. A row-level reader's input is the strip:
the gap is inside every frame's receptive field by construction. The framing bound therefore
does not apply to it, and the gap-probe numbers are a floor (linear, single-crop) for what the
strip carries. The spike makes this a measured claim, not an inference: **sep-token accuracy**
and **placement accuracy** (decoded sep position == `parse_cells` position) are headline metrics,
reported per technology style (LED dot vs LCD/VFD comma - the renderer's two styles, §4.3) so a
style-blind model is visible. Consequences if it passes: PU.78-M4's hard dp-consistency check
(blocked on "dp AUC 0.52-0.55 ... Blocked on PU.73", PU.78 note §3-M4) and PU.84 (inference-time
gap framing, the owner's approved dp-only crop) gain a stronger signal source - both remain the
owner's calls, recorded here as consumers (§7-5), not built.

## 5. Adaptations, named and justified (the fence)

Each is a departure from the published method. **A departure the spike's implementer adds that is
not on this list needs the product owner's OK** - that is the fence that keeps "apply the
research" from drifting back into "invent something that looks like it".

| # | Paper says | We do | Why |
|---|---|---|---|
| A1 | CRNN 7-conv/512-channel net, 8.3M params, trained on 8M words (Table 1, §3.1-3.2) | Same topology, channels [16,32,64,64,128,128,128], BiLSTM 2x128, ~1.01M params (§4.1 table) | The paper's own small-data precedent (§3.4: layers removed, LSTM halved for 2,650 images) plus the repo's bundle reality (classifier budget comment `model.py:9`; a 33 MB second model beside the 31 MB detector is an owner decision the integration row brings, not the spike). Topology, BN placement, pool orientations and the k2x2 final conv are the paper's, unchanged. |
| A2 | Gray-scale Wx32 input (Table 1 "Input") | RGB | The display's technology is a PALETTE (LED red/green/amber vs LCD grey vs VFD, `dataset.py:39-106`); the shipped cell classifier is RGB (32x48x3, `PumpSegmentsModel.swift:14-15,:41-51`) and the renderer emits RGB. Throwing the colour away would discard a cue the corpus's own calibration keeps. Cost: 3x first-conv params (+288), no structural change. |
| A3 | Training images resized to a FIXED 100x32 (§3.2) | Aspect-preserved widths, right-padded to the batch max (cap 160), min width 100 at test per the paper's own rule | Squashing a 351 px 6-digit strip to 100 px leaves ~5.6 px per digit (§4.2 arithmetic) - below the stroke scale the segment code lives at; padding keeps the paper's T = W/4 frame math and its min-100 rule, and repairs the 594 strips that are otherwise shorter than their own label's 2U+1 bound (Graves §2). Pad mode logged. |
| A4 | CTC decoding returns a string (Graves §3.2); no paper publishes per-position substitution marginals | Per-position posteriors for the law = forward-backward on the decoded string with one position substituted, normalised (Graves eqs. 5-8 machinery, §4.4-2) | The law's interface is per-cell ranked candidates (`PumpReadingLaw.candidates` explores exactly single-digit substitutions); the full all-lengths marginal is intractable (Graves §3.2's own statement) and the N-best-strings alternative bypasses the law's beam. The composition is new - flagged as the note's one invented seam, built only from the paper's equations, and F1 below mutation-tests the recursion it stands on. |
| A5 | Scene-text alphabets keep every character distinct (Baek §4.5 even recommends training special characters IN) | `.` and `,` collapse to one `sep` token | No consumer reads the difference: `parse_cells` sets the same dp bit for either (`score.py:90-108`), the law reads placement only. Two tokens would split separator mass across a glyph-style distinction (dot vs comma) that correlates with technology, not with value - and Baek's special-character finding is about characters that MATTER to the output, which this one does not. |
| A6 | STN/TPS rectification is a framework stage (Jaderberg §3; Baek's Trans. stage) | NONE in the spike; if a residual-geometry failure class is measured, STN returns as its own arm with the owner's OK, identity-initialised (Jaderberg A.4-A.5) at 1/10 lr | Strips are homography-rectified before the reader (`PumpReader.swift:204`) and deskewed by PU.69's FHT; Baek measures the gain at +1.1 regular / +3.4 irregular for 1.7M params + 3.6 ms, and a learned warp can bend fixed-pitch segment geometry, where glyph shape IS the label (inference, labelled). Laroca 2021's rectification win is geometric corner warp - which we already do. |
| A7 | BiLSTM is CRNN's sequence stage; Baek also measures Seq=None (Rosetta) as a frontier point | BiLSTM 2x128 primary; conv-only CTC is the named fallback ARM if on-device LSTM latency ever fails the integration row's budget | Baek Table 2: BiLSTM +2.5/+4.5 % for +3.1 ms on a P40; Core ML runs LSTM off-ANE (CPU/GPU) - the device number does not exist yet (PU.75 row: "never timed on an iPhone"), so the fallback is pre-named rather than discovered mid-integration. |
| A8 | AdaDelta rho 0.9 (CRNN §2.4) / rho 0.95 + clip 5 + He (Baek §4.1) / online SGD 1e-4 + momentum 0.9 (Graves §5.2) | Baek's protocol primary (AdaDelta 0.95, clip 5, He, batch 192 -> 64-128 at our pool size); the repo's AdamW+cosine is the logged fallback if AdaDelta diverges | Three published optimizers; one must be picked before the spike so a divergence is a finding, not a silent recipe change. Batch scaled down because a 300K-iteration schedule over 14.4M images has no meaning over ~10^3 real strips + synthetic (steps re-set at 20-40k, §4.5). Any switch is logged in the run's metrics file. |
| A9 | Scene text (CRNN/Baek), speech (Graves), utility meters (AMR family) | Seven-segment pump strips, 12-token alphabet | No published seven-segment sequence reader exists (§1 null result, queries recorded). Nothing in CTC or CRNN is domain-bound (the loss and the topology assume only a left-to-right sequence with per-frame conditional independence - Graves §3.1); the domain risk is measured, not assumed: the spike's whole §6 bar is the transfer test. |
| A10 | Hard targets (Graves eq. 12; CRNN eq. 3); no published CTC + label smoothing | Hard targets; NO label smoothing in the spike | The repo's LS 0.05 is a per-cell-BCE decision (`train.py:165-168`: smoothing keeps the ABSTENTION FRONTIER ranked under a saturating BCE); CTC's path-sum loss has a different saturation geometry and no published LS recipe. If the spike's posteriors prove over-confident, LS (or the temperature of §4.4-3, which is the published post-hoc instrument) is a follow-up arm with the owner's OK - not a keyboard improvisation. |
| A11 | Graves' prefix-search heuristic splits at 99.99 % blank probability (§3.2, §5.2) | Whole-strip prefix search, no splitting | The heuristic exists for utterance-length speech; at T <= 40 and U <= 9 the search is bounded without it. Best-path decoding runs as the published control (§4.4-1). Beam search (a later development, NOT in the fetched 2006 text) is not used; adding it is a departure. |
| A12 | FCSRN's AugLoss for middle states (secondary source only, §1) | NOT used | Primary text never fetched; our displays have no accumulator middle state (LCD/LED digit transitions are not rotary-dial halfway poses) except in video frames mid-roll, which the glitch-frame labelling already handles per-frame (`realglyphs.py:228-244`). Importing an unread loss would be exactly the invented-method failure mode. |

## 6. Populations, bars, expectations, falsifiers

### 6.1 Populations, counted at HEAD `2050a5d3` (files and filters named)

Counted by `/tmp/pu77/count.py`, `db.py`, `db2.py`, `partial.py`, `geom.py`, `exports.py` from
`git show HEAD:Spike/ReceiptSpike/fixtures/pump/{split.csv, windows.json, expected.csv}` and the
COMMITTED `fixtures/corpus.sqlite` (read-only URI; the sqlite is clean at HEAD - `git status`
shows only an untracked `pump-live/corpus.sqlite3`, untouched). The implementer re-counts at the
build commit with the same filters and prints both (the corpus moves: PU.73 §5.1 and PU.78 §5
record the same hazard).

- **Split**: 328 stills - **256 train / 68 heldout / 4 heldout2**; every entry `reviewed: true`
  (counted; matches `PumpReaderTestSupport.isHeldout/isReviewedTrain`, `:83-88`).
- **Annotated tier (the spike's scoring population)**: heldout transaction windows with non-empty
  text = **195** (187 without a `legibility: partial` flag + 8 partial; `gateMirror` feeds all
  195 - it filters nothing on legibility, `PumpReaderPipelineTests.swift:189-283` - while the
  TRAIN export skips partials, `PumpTrainSliceExportTests.swift:163`); plus **57 board** windows
  (consumed by the law's no-price branch, scored only through the fields they help commit).
  **Scored cells: 183** (expected.csv non-blank minus `csvDisagrees`, reviewed heldout - the
  harness's own filter) = `PumpPhotoGate.readerNumericTotal` (`:95`), the cross-check that the
  filter is the harness's.
- **Train strings (training material)**: stills **726 tx** (701 non-partial) + **321 board**;
  tracked frames **29,793 windows** over **6,498 usable frames / 161 records** but only **492
  distinct (record, field, text)** labels; videos **19,021 usable labels**, **3,292 distinct
  (video, field, text)**. Distinct real strings total ~4.8k. The Sep-21 export artifacts hold
  **8,613 + 3,497 = 12,110 strips** (count agreement 6,514 + 2,967 = 9,481, **0.783**); the
  re-export at the build commit will be larger (the 2026-09-24 intake added video labels).
- **Strip geometry** (Sep-21 export, 12,110 usable strips, alphabet-filtered): H96, W96 min 24 /
  p50 236 / max 458; digit counts over the full export (stills+frames+videos) {3: 1806, 4: 7224,
  5: 393, 6: 2678, 7: 9}; the still windows alone at HEAD run {3: 43, 4: 424, 5: 62, 6: 186,
  7: 9}; at h32 W32 p10 59 / p50 76 / p90 118 / max 152;
  **594 strips (4.9 %) violate T >= 2U+1 at h32 without padding** (§4.2).
- **Today's bars at HEAD** (the spike's comparators, all with PU.68's Wilson intervals,
  computed this run): annotated tier **118 committed / 118 correct** (`committedFloor` 118,
  `PumpReaderPipelineTests.swift:30`; Wilson 95 % two-sided **[0.9685, 1.0000]**, one-sided lower
  **0.9776**); with the PU.74 build in the working tree **123 / 123** (two-sided [0.9697,
  1.0000], one-sided 0.9785). Live app path **47 / 47** (`PumpPhotoGate.swift:86,:91`; two-sided
  [0.9244, 1.0000], one-sided 0.9456). Train certify last recorded **126 committed / 120
  correct** in-sample (`docs/EXTRACTION.md:1095-1105`, PU.78 paragraph; two-sided [0.9000,
  0.9780]); the brief's 124/117 is the pre-PU.78 record. Slicer count agreement on heldout hand
  quads **236/251 = 0.940** (PU.42 row; two-sided [0.9038, 0.9635]). Digit-only per glyph on
  heldout count-matched cells: the shipped r6 at **0.9313 single-crop / 0.9370 5-crop TTA**
  (873-cell cut, PU.73 note §0); the PU.73 sweep's retrained arms span 0.927-0.949 on the
  864-cell re-cut (control 0.927-0.941, refused flatten 0.944-0.949; PU.73 row).
- **The brief's context numbers are stale, named so nobody re-derives them**: it says live 45/45
  and annotated 112/112 - those are the pre-PU.78 values (PU.78 moved them to 47/47 and 118/118,
  its row); and PU.74's uncommitted build moves the annotated tier to 123/123.

### 6.2 The bars, restated at today's counts (the row's own falsifier, un-staled)

The row: "string accuracy on the annotated tier's strips must beat the current 0.732 digit-only,
and the law over its posteriors must commit >= 111 at >= 0.99 on the annotated tier - else stop
before any Swift." Restated (orchestrator to carry into the spike brief):

- **B1 (string accuracy).** ONE instrument, both arms, over ALL **195** heldout transaction
  strips (a window the current arm miscounts counts as failed, not skipped - that invisibility is
  the defect the row exists to attack, `docs/EXTRACTION.md:1090-1093`): (a) per-window exact
  string accuracy (digits, count, and sep placement all right - `score.py`'s `per_window`
  shapes, `:428-431,:475-476`); (b) per-window digit accuracy via normalised Levenshtein
  (Salomon's dial-rate metric, §2.5 - it scores a wrong-COUNT read instead of voiding it);
  (c) per-glyph digit-only on the count-matched subset, the ~0.93 lineage above, for continuity.
  **The CTC arm must beat the current arm on (a) and (b) on the same 195 strips**, 3-seed mean,
  each precision printed with its Wilson interval (`PumpPrecisionBounds`). The row's literal
  0.732 is recorded as stale (round-4 model, count-correct-only basis, `REPORT.md:363-368`);
  a spike that "beats 0.732" but loses to the shipped arm on (a)/(b) has NOT passed.
- **B2 (the law over posteriors).** Commits **>= the annotated tier's count at the build commit**
  (118 at HEAD; **123 with PU.74 landed**, which the orchestrator gates first) at precision
  **>= 0.99** over the 183 scored cells, via §4.4's harness, windows restated under the
  train-fitted T, with the oracle ratchet (763 at 0.9987, fragility <= 0.10 - PU.74's gate
  wording) re-run to prove the fed posteriors did not corrupt the law itself.
- **B3 (stop rule).** Fail B1 or B2 after the §4.5 protocol (re-export, 3 seeds, capped pool,
  train-side selection): the row closes as a measured no-go with the report - **no Swift**, per
  the row. PU.32's old estimate for this idea was "annotated ~85-110" (Qwen review §4.2); the
  tier has since risen to 118/123, which is precisely why the bar is the tier and not a number
  written before PU.74/PU.78.
- **heldout2** is scored once at the go/no-go and reported beside the decision, never during
  fitting (its rule, `docs/EXTRACTION.md`).

### 6.3 What we expect (labelled inference over §0/§6.1 measurements unless stated)

| quantity | expectation | basis |
|---|---|---|
| length accuracy (decoded count == label count) | above the slicer's 0.940 hand-quad / 0.783 export agreement, plausibly 0.95-0.99 on annotated strips | CTC needs no pitch grid: the six slicer failure classes (dim glyphs, harmonics, over-merges, mark over-fires, split over-counts, snap/blank - PU.37's table) have no CTC analogue; but glare-washed digits can still drop tokens (Baek §4.5's occlusion class). The spike's first headline number. |
| per-glyph digit accuracy (count-matched) | competitive with 0.927-0.949, not obviously above it | The per-cell model already extracts what transfers linearly from its crop (PU.73 §0); CTC's edge is CONTEXT (BiLSTM, CRNN §2.2) and length robustness, not per-glyph sharpness. A large per-glyph jump would be as suspicious as a collapse (F4). |
| string accuracy (a) on all 195 | CTC above the current arm mainly via the ~6 % miscounted windows it can now read | Apportionment: miscounted rows "disappear" (`docs/EXTRACTION.md:1090-1093`); recovering even half of the 15/251 moves (a) more than any per-glyph gain can. |
| sep/placement accuracy | above the shipped dp bit's whole ceiling (~0.75 AUC); the gap-probe floor 0.92-0.95 AUC is the linear reference | §4.6: the strip contains the mark's ink; the framing bound is gone. Per-style split reported (dot vs comma). |
| law commits on the annotated tier | >= 118/123 plausible; a large jump is NOT expected | The law is exact-close (PU.78): every extra committed cell needs the arithmetic to close to the cent - recovered windows only commit when their digits are RIGHT. The realistic gain is the miscounted-row share of the 60 uncommitted cells (183 - 123), not a wholesale lift. |
| wrong readings | the risk is INSERTED digits (a glare speck read as a token), which change string length - the exact-close law converts most into abstentions, not wrong commits | PU.78's exactness is the guard (a one-digit insertion almost never closes the product); precision floor 0.99 is the hard gate regardless. |

### 6.4 Falsifiers, named in advance

- **F1 (implementation).** Two mutations, red-then-green, verbatim in the report: (i) a
  hand-rolled Graves eq. 5-8 forward-backward must reproduce `nn.CTCLoss` (or the reference CTC
  implementation used) to 1e-5 on random logit sequences; breaking the eq.-6 skip rule (dropping
  the `alpha_{t-1}(s-2)` term when `l'_{s-2} != l'_s`) must go red. (ii) On a synthetic strip with
  a known peaky posterior, the substitution marginal of §4.4-2 for the TRUE digit must exceed
  every wrong digit's - a harness where it does not has a broken recursion, and every law number
  downstream is noise.
- **F2 (no-gain close).** If, across 3 seeds, the CTC arm does not beat the current arm on B1(a)
  and B1(b), or the law arm lands below the tier's count or below 0.99, the row CLOSES as a
  measured no-go with the numbers and the error analysis (which failure class dominated: length,
  digits, sep, or the law's refusals) - a legitimate row result (PU.73's F2 precedent), and the
  sequence-reader family stays closed until new evidence exists.
- **F3 (split leak).** Any selection decision - H48 adoption, early stop, cap share, real-frac,
  window re-derivation - made against a heldout or heldout2 number invalidates the run; the
  spike logs every scored candidate with its config so the audit is mechanical (decision 9,
  `PumpReaderTestSupport.swift:47-88`; PU.73 A3). A train-split number reported as heldout, or a
  heldout string accuracy >= 0.99 (above the shipped arm's digit-only ceiling by more than the
  length effect can explain), is re-checked for leakage BEFORE it is believed (PU.73 F4's shape).
- **F4 (sep too good / too blind).** Sep-placement accuracy >= 0.99 on heldout strips triggers
  the **masking ablation**: repaint the strip's lower-band gap ink (where commas hang,
  `REPORT.md:310-318`) and re-decode - accuracy must FALL toward the placement-prior guess. A
  model that reads placement identically with the mark ink masked is guessing from string shape
  (digit-count conventions), not reading the mark, and its dp claim is void. Conversely, sep
  accuracy far BELOW digit accuracy re-opens the H48 arm by its pre-named rule (§4.2) - once,
  not a sweep.
- **F5 (margin masquerade).** B2 must be reported in BOTH raw nats and T-scaled nats with the
  windows re-derived on train; a commit gain that exists only at one scale is a calibration
  shift, not a reading gain (PU.73 F5; PU.72's whole subject).
- **F6 (length hack).** B1 up while B2 down is not a pass with an asterisk - it means the strings
  the reader gained are strings the law cannot use (wrong lengths, wrong placements). Both bars
  are one gate; reporting only the one that moved is the defect this falsifier names.

## 7. Cost

- **Latency.** The spike is offline: no Release number exists or is owed for this row (PU.68's
  note §7 set that precedent for a row that ships nothing to the device; PU.75 owns device
  timing discipline, and its row records that even TODAY'S reader has "never [been] timed on an
  iPhone"). For the integration row's budget, the arithmetic (labelled - MAC counts from the
  §4.1 config, not profiled): conv stack ~41.5M + BiLSTM ~16.4M = **~58M MACs per median strip**
  (W32 = 100 padded, T = 25) against the current per-window path's ~4.2M MACs/cell x 5 TTA crops
  x ~4.5 cells ~= **95-105M** - the row reader is cheaper per window than the 5-crop per-cell
  path it replaces, before counting the slicer's own per-pixel Swift loops. Paper-measured
  reference points: CRNN 0.16 s/sample on a Tesla K40 (§3.2); Baek's None-ResNet-BiLSTM-CTC (T3)
  7.8 ms and TPS-ResNet-BiLSTM-Attn (T5) 27.6 ms per image on a P40 (Table 4a). Core ML caveat:
  BiLSTM does
  not run on the ANE (CPU/GPU only) - the A7 fallback arm exists for exactly this.
- **Bundle.** ~1.01M params = ~4.0 MB fp32 / ~2.0 MB fp16 (arithmetic from §4.1); against the
  shipped 64 KB classifier and the 31 MB detector. Whether a second multi-MB model ships,
  REPLACES the classifier, or is quantised (PU.75's sources: Jacob et al. 2018) is the
  integration row's owner decision - the spike commits no bytes to the app.
- **Training.** ~2-4 h per run on this Mac (estimate, §4.5), 3 seeds x 2-3 arms ~= 1-2
  machine-days; no GPU dependency (r6's recipe trained CPU-side, `REPORT.md:1345`).
- **New code to maintain.** Spike: ~500-800 lines of Python in `ml/pump-reader` (strip dataset +
  calibrated string sampler, the scaled CRNN module, CTC train loop, prefix decoder + the
  substitution-marginal exporter, the string scorer reusing `score.py`'s warp and
  `parse_cells`), plus ~100-150 lines of Swift IN THE TEST BUNDLE (the posteriors->law harness,
  §3-8) - no C/C++ target, no Accelerate/Metal/Vision, no app code. If adopted, the integration
  row then MAINTAINS a second model family beside `SegmentNet` (export, temperature, corpus
  re-cuts) and deletes the slicer surface (§3-5) - the maintenance trade is part of its decision,
  named here so it is not discovered after.

## 8. Findings recorded, not fixed here

1. **The row's bars are stale** (0.732 is round-4/count-correct; ">= 111" predates PU.78/PU.74):
   §6.2 restates them; the orchestrator carries the restatement into the spike brief and the row
   text when it ticks or rewrites (`docs/TASKS.md` PU.77).
2. **The dispatch brief's context numbers are stale** (45/45, 112/112, 124/117 vs HEAD's 47/47,
   118/118 committed - 123/123 with the PU.74 build - and 126/120 last recorded certify): §6.1
   names both states so the spike report is not judged against the wrong baseline.
3. **`sample_row_text` violates the corpus convention** (leading spaces at 25 %,
   `row.py:79-80`, against "unlit leading cells are never transcribed", `windows.json`
   `_about`) and its 1-3+1-2 digit shape under-represents the 6-digit zero-padded class (2,678
   of 12,110 export strips): the spike's sampler (§4.3) is new code, and any future row reusing
   `sample_row_text` for strips inherits the mismatch. No row owns the old sampler's fix; it
   still serves the CELL renderer, where leading blanks are a class (`dataset.py:77-80`).
4. **The export artifacts predate the corpus** (Sep-21 vs the 2026-09-24 corpus commit): step 0
   re-export (§4.5) - PU.73 §3.3's finding, still standing, now with a second consumer.
5. **Downstream consumers of a passing spike, for the owner's list**: PU.78-M4's hard dp check
   (blocked on dp quality, PU.78 note §3-M4), PU.84's dp-only gap crop (approved as a dp-only
   crop at HEAD's commit `2050a5d3`; a row reader that reads sep from the strip may make it
   unnecessary - measure before building), PU.67's reopen path (pump-275's last-digit misread is
   a read-quality case the context-carrying reader attacks directly), and PU.76's oriented
   detector (a row reader tolerates loose framing better than a pitch grid - the hypothesis B1(b)
   tests, Qwen review §4.2's "robustness to framing"). None is built by this row.
6. **The verifier redesign is the integration row's real work** (§3-6): the -17 apportionment
   drop this row targets is CREATED by the verifier reading slicer measurements; replacing the
   slicer without replacing `PumpRowGeometry`'s inputs would move the drop, not remove it. Seam
   named: `PumpRowGeometry.swift:22-27`, `PumpReader.verdicts` (`:481-551`).
7. **TPAMI page range**: Crossref gives 39(11):2298-2304 for the CRNN journal version; citations
   elsewhere in the repo that say 2224-2236 (a commonly circulated range) should be corrected to
   the Crossref record when next touched. Bibliographic only; no method detail depends on it.
