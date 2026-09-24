# PU.76 research note - an oriented row detector: quads, not upright boxes

*A run of `agents/briefs/RESEARCH-TO-CODE.md`. Product owner, 2026-09-23: **"review the published
research to apply it into the code, instead of coming up with our own solution."** Written
read-only; the repo was not modified except this file. Fetch and measurement scratch lives OUTSIDE
the checkout, in `/var/folders/34/b62b3k2s2b9318ztk2c514gr0000gn/T/opencode/pu76/` (paper HTML/txt,
`measure.py`, `out.txt`, and a Release `pump-read` built with `--scratch-path` there - no build
output inside the checkout; the pre-existing `ios/.build/opt/debug/pump-read` was NOT used for
timing because it is a Debug-configuration binary, §7.1). Evidence rule: every claim cites a paper
section/equation, a `file:line`, or a measured number; inference is labelled.*

- **Row:** `PU.76` - An oriented row detector: quads, not upright boxes (`docs/TASKS.md:1082` at
  HEAD `2050a5d3`; `:1084` in the working tree, which carries uncommitted PU.74 - §0). The
  evidence the row rests on, re-verified here: the apportionment's framing arm (hand windows kept
  by the verifier read **78** cells from their hand quads, **45** from the detector's own boxes:
  **-33**, `docs/EXTRACTION.md:1083-1093` at HEAD); the same hand windows as UPRIGHT rectangles
  **89 at 0.944** against quads at the annotated tier's **112 committed / 111 correct = 0.991**
  (`docs/EXTRACTION.md:1088`, `ml/pump-reader/REPORT.md:2029` - the row's "111 at 0.991" is the
  annotated tier, a different instrument than the apportionment's oracle arm, which read 108 in
  the same run; both pre-date PU.78/PU.74's law changes, §0); PU.66's three refused rotated-data
  retrains (`docs/TASKS.md:1068` at HEAD, round tables quoted in §5.6); PU.70's cut - the detector
  frames a turned row as a small upright box (pump-302: detector 0.10 of frame width against the
  hand row's 0.30; and an in-plane turn makes a row's UPRIGHT bound WIDER, w = L cos t + H sin t,
  so the size rule cannot be fixed by measuring along the axis - `docs/TASKS.md:1076` at HEAD);
  PU.69's fast Hough angle and its three confidence statistics, shipped and available to any
  detector that outputs an angle (`PumpRowDeskew.swift:62-70,168-203`; `docs/EXTRACTION.md:1111`).
- **Papers the row cites (each fetched and checked, §1):** TextBoxes++ (Liao, Shi, Bai) -
  **VERIFIED, correct arXiv id is 1801.02765**, IEEE TIP 27 (2018) 3676-3690; the row's flagged
  misattribution (the 2017 TextBoxes id 1611.06779 paired with a 2018 date) is **CONFIRMED**.
  Ma et al., *Arbitrary-Oriented Scene Text Detection via Rotation Proposals*, arXiv:1703.01086 -
  id/title/authors/year verified; **the row's venue is wrong: it is IEEE Transactions on MULTIMEDIA
  20(11):3111-3122, 2018, not TPAMI** (an error the row did not flag). Deng et al., *PixelLink*,
  AAAI 2018, arXiv:1801.01315 - **VERIFIED**. Xie et al., *Oriented R-CNN*, ICCV 2021,
  arXiv:2108.05699 - **VERIFIED**. The survey of what runs on iOS 18 today (§2.6, §4) fetched the
  ultralytics OBB docs and LICENSE (AGPL-3.0) and Apple's Create ML / Vision docs.
- **The code seam:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDetector.swift` - the
  whole class is the Create ML/Vision wrapper, and the ONLY upright-forcing line in the pipeline is
  `:67-71` (a `CGRect` `boundingBox` rebuilt as a four-corner quad); `Row.quad` is already a quad
  (`:14-27`). Consumers: `PumpReader.candidates` (`PumpReader.swift:49-63`, deskew hook `:56`),
  `PumpReader.detectedRows` (`:68-73`), the verifier's slice (`PumpQuadWarp.warpToStrip`, a full
  homography over ANY quad, `PumpQuadWarp.swift:165-195`), `PumpRowGeometry.verdict`
  (`PumpRowGeometry.swift:76-103`), the fast display decision (`PumpDisplayCapture.swift:135-155`),
  the preview guidance (`PreviewGuidance.swift:150,159`, throttled to 10/s at `:119`). Training:
  `ml/pump-reader/detector/{train,measure}.swift`, `ml/pump-reader/src/pump_reader/detdata.py` -
  the upright-ing line is `detdata.py:65-69` (`bbox()` takes the quad's axis-aligned bounds);
  decision 10's gate (tight IoU) is `docs/EXTRACTION.md:985-997` at HEAD, asserted in
  `ml/pump-reader/tests/test_detector_gate.py`. All `file:line` refs are HEAD `2050a5d3` unless
  the file is working-tree-modified (§0 names those; for them the ref is `git show HEAD:`).

## 0. State of the row at the time of writing - read this before §5

HEAD moved while this note was written (`cefbce35` -> `2050a5d3`, the PU.72 close). Everything is
pinned to **`2050a5d3`** (2026-09-24). The corpus database is byte-identical at both commits and
to the working tree (`shasum Spike/ReceiptSpike/fixtures/corpus.sqlite` =
`d6127cd6555cf2d32fffd40bfa67171212cc45ff`, SHA-1, equal to `git show HEAD:` of the same file), so
**every corpus count in §5 is at that pinned blob** and does not move with the in-flight work.

In flight in the working tree while this note was written (not mine, not touched):

1. **PU.74 is landing uncommitted** (`PumpReadingLaw.swift`, `PumpReadingTypes.swift`,
   `PumpReaderPipelineTests.swift`, `PumpReadingLawExactTests.swift` modified): the per-currency
   conventions table. Its working-tree test comment reads "PU.74 ... with the owner's pump-275
   re-frame: **123** committed, all correct, 43 of 68 photos" (`committedFloor = 123` in the
   working tree; **118 at HEAD**, `git show HEAD:ios/Tests/TankbookCoreTests/PumpReaderPipelineTests.swift:30`).
2. **The dispatch brief's context numbers are one law-change stale**: it quotes heldout app path
   45/45, annotated 112/112, train 124/117. At HEAD those are **live 47/47** (PU.78, commit
   `8253bca0`; `PumpPhotoGate.readerCommitted = 47`, `readerCommittedCorrect = 47`,
   `readerNumericTotal = 183`, `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift:86,91,95` -
   file clean at HEAD) and **annotated 118/118** (PU.78's commit text), moving to 123 when PU.74
   commits. Wilson two-sided 95 % (PU.68 §2.1, BCD eq. 4): 47/47 -> [0.925, 1.000]; 118/118 ->
   [0.968, 1.000]. **The spike re-counts every population and floor at its own build commit** with
   §5's filters (the standing rule from `docs/DEVELOPMENT-TIMELINE.md`, 2026-09-22).
3. The owner's annotator servers were RUNNING during this note's timing batch
   (`pump-read --slice-serve` PID 74312, `--read-serve` PID 74412): PU.69 §7-4 measured that this
   contention inflates pump latency up to ~25x. §7.1's numbers carry the contention label; the
   spike's decisive timings must run with the annotator closed (PU.69 §7-4's hygiene rule).
4. Untracked, not mine, not touched: `Spike/ReceiptSpike/fixtures/arrival/` (intake staging) and
   `Spike/ReceiptSpike/fixtures/pump-live/corpus.sqlite3` (an annotator scratch copy - the
   `PUMP_ANNOTATE_DB` redirect pattern, `scripts/corpus_db.py:56-58`).

## 1. Citations, checked

Fetch log: arXiv API (`export.arxiv.org/api/query`) title search for "TextBoxes++" and `id_list`
fetch for 1801.01315/2108.05699; `arxiv.org/abs/` pages for 1611.06779 and 1703.01086; full texts
via `ar5iv.labs.arxiv.org/html/{1801.02765, 1801.01315, 2108.05699, 1703.01086}` (curl, text
extracted in the scratch dir); `raw.githubusercontent.com/ultralytics/ultralytics/main/LICENSE`;
`docs.ultralytics.com/tasks/obb/`; Apple `developer.apple.com/documentation/createml/mlobjectdetector.md`
and `.../vision/vnrecognizedobjectobservation.md`. **Not fetched:** the IEEE publisher pages
(paywalled - the arXiv `journal_ref` fields are the venue evidence); Apple's
`VNDetectedObjectObservation` page (one 403 through the fetch proxy; the `boundingBox: CGRect`
semantics are cited instead from our compiling code, `PumpRowDetector.swift:67-71`). Nothing below
describes a method whose text was not fetched.

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Liao, Shi, Bai, *TextBoxes++*, 2018 (row flags: the review paired the 2017 TextBoxes id with a 2018 date) | arXiv title search returns **arXiv:1801.02765**, "TextBoxes++: A Single-Shot Oriented Scene Text Detector", Minghui Liao, Baoguang Shi, Xiang Bai, v1 9 Jan 2018, `journal_ref` "IEEE Transactions on Image Processing 27 (2018) 3676-3690", DOI 10.1109/TIP.2018.2825107. **arXiv:1611.06779 is a DIFFERENT paper**: "TextBoxes: A Fast Text Detector with a Single Deep Neural Network", Liao, Shi, Bai, Wang, Liu, v1 21 Nov 2016, "Accepted by AAAI2017" - full text fetched: it detects horizontal text with "long" default boxes at aspect ratios {1, 2, 3, 5, 7, 10} (§III), and its own conclusion names "extend TextBoxes for multi-oriented texts" as FUTURE work - that extension is TextBoxes++ itself. | **Row's citation correct** (authors, title, year). The flagged misattribution is **confirmed**: any id pairing "TextBoxes++" with 1611.06779 is wrong twice (wrong paper, wrong year). The correct id is **1801.02765**; venue **IEEE TIP 27(10), 2018**. Full text fetched. |
| Ma et al., *Arbitrary-Oriented Scene Text Detection via Rotation Proposals*, **TPAMI** 2018, arXiv:1703.01086 | arXiv abs page: title exact; authors Jianqi Ma, Weiyuan Shao, Hao Ye, Li Wang, Hong Wang, Yingbin Zheng, Xiangyang Xue; v1 3 Mar 2017, v3 15 Mar 2018; `journal_ref` **"IEEE Transactions on Multimedia, vol. 20, no. 11, pp. 3111-3122, 2018"**, DOI 10.1109/TMM.2018.2818020. | Id, title, authors, year **verified**; **venue WRONG in the row: TMM, not TPAMI** - an error the row did not flag (it flagged only the TextBoxes pairing). Full text fetched. Cite as *IEEE TMM 20(11), 2018*. |
| Deng et al., *PixelLink*, AAAI 2018, arXiv:1801.01315 | arXiv record: "PixelLink: Detecting Scene Text via Instance Segmentation", Dan Deng, Haifeng Liu, Xuelong Li, Deng Cai, v1 4 Jan 2018, comment "AAAI-2018". | **Correct as cited.** Full text fetched. |
| Xie et al., *Oriented R-CNN*, ICCV 2021, arXiv:2108.05699 | arXiv record: "Oriented R-CNN for Object Detection", Xingxing Xie, Gong Cheng, Jiabao Wang, Xiwen Yao, Junwei Han, v1 12 Aug 2021, comment "ICCV 2021". | **Correct as cited.** Full text fetched. |
| Survey: YOLO-family OBB + Core ML export | `docs.ultralytics.com/tasks/obb/` fetched 2026-09-24: current line is **YOLO26n-obb** (2.4 M params, 14.8 GFLOPs at 1024 px, DOTAv1 mAP50-95 52.4 / mAP50 78.9, 2.8 ms T4 TensorRT), pretrained on DOTAv1; label format `class_index x1 y1 x2 y2 x3 y3 x4 y4` (four normalised corners - our quad format verbatim); CoreML is in the export table (`format='coreml'` -> `.mlpackage`, args `imgsz, dynamic, quantize, nms, batch, device`); "`nms=None` defaults to raw outputs for external NMS". `raw.githubusercontent.com/ultralytics/ultralytics/main/LICENSE`: **GNU AGPL v3.0**. | Verified as fetched. The AGPL finding is a ship-gate for this option (§4-C2, §6). |
| Survey: Apple on-device | `MLObjectDetector` docs fetched: annotation-driven training, `ObjectAnnotation` = "label, location, confidence"; the annotation types our own training call names are `.boundingBox` with centre-based `{x, y, width, height}` (`ml/pump-reader/detector/train.swift:24`, `detdata.py:65-69`) - **no quadrilateral or rotated annotation type exists**, which is why PU.66's rotated copies could only be labelled with the upright bound of a turned row ("a detector that returns turned boxes is the real fix and is outside Create ML", `docs/TASKS.md:1068` round 1). `VNRecognizedObjectObservation` docs fetched: inherits `VNDetectedObjectObservation`, whose `boundingBox` our code reads as an axis-aligned `CGRect` (`PumpRowDetector.swift:67-71`). | Verified: **no Apple API emits oriented boxes**; a custom Core ML model with Swift post-processing is the only on-device path (precedent in-repo: `PumpSegmentsModel.swift:36-47` runs a custom-output model via `MLModel.prediction`, exported by `ml/pump-reader/src/pump_reader/export.py` through `coremltools`). |

## 2. The methods as published

### 2.1 PixelLink (Deng et al., AAAI 2018, arXiv:1801.01315) - segmentation, then minAreaRect

The shape (§3, Fig. 2): a CNN makes **two pixel-wise predictions** - text/non-text (2-channel
softmax) and **links** between each pixel and its 8 neighbours (8 x 2 = 16-channel softmax)
(§3.1). Positive pixels are joined through positive links into connected components with a
**disjoint-set** structure; a link fires when **either** endpoint predicts it positive (§3.2).
Each CC's box is then extracted **without any regression** by `minAreaRect` (OpenCV), whose output
is an oriented rectangle, convertible to a quadrangle (§3.3). Post-filtering drops CCs by simple
geometry: the paper's IC15 thresholds (shorter side < 10 px, area < 300) are the **99th percentile
of the TRAINING set** - a rule, not magic numbers (§3.4).

Training (§4): ground-truth pixels are those inside text boxes (overlaps: only un-overlapped
pixels positive); a link is positive when both pixels are in the same instance (§4.1). Loss

```
L = lambda * L_pixel + L_link,   lambda = 2.0 in all experiments            (eq. 1)
B_i = S/N,  S = sum_i S_i,  w_i = B_i / S_i   (instance-balanced weights)  (eq. 2)
L_pixel = (1/((1+r)S)) * W * L_pixel_CE,  r = 3 (OHEM negative:positive)    (eq. 3)
L_link  = L_link_pos/rsum(W_pos_link) + L_link_neg/rsum(W_neg_link)          (eq. 4)
```

i.e. every instance contributes equally regardless of area (eq. 2), negatives are the r*S
highest-loss pixels (OHEM, r = 3), and the link loss is a class-balanced CE over positive pixels
only (§4.2). Augmentation: random 0/90/180/270 rotation with p = 0.2, random crop area 0.1-1,
aspect 0.5-2, resize to 512 x 512; instances with shorter side < 10 px or < 20 % remaining are
ignored (§4.3).

Implementation and results: SGD momentum 0.9, weight decay 5e-4, **xavier random init - NOT
ImageNet-pretrained**, lr 1e-3 for 100 iters then 1e-2; batch 24 on 3x GTX Titan X, ~0.65 s/iter,
7-8 h total (§5.2). IC15 (1 000 train images): **from scratch**, 4s ~40k iters / 2s ~60k; pixel
and link thresholds (0.8, 0.8); test at 1280 x 768; **F 83.7 (2s) / 82.3 (4s)** at 3.0 / 7.3 FPS
(Tab. 1). TD500 (**line-level**, arbitrarily oriented annotations, 300 train + 400 HUST-TR400):
pretrained on IC15 15k iters, fine-tuned 25k, thresholds (0.8, 0.7), post-filter 15 px / 600,
**F 77.8 (2s)** (Tab. 2, §5.4). IC13 (229 train): fine-tuned 10k, **F 84.5** single-scale (Tab. 3,
§5.5). Ablations (Tab. 5, §6.2): **removing the link mechanism drops F 82.3 -> 64.0**; removing
post-filtering keeps R 82.3 but precision collapses 82.9 -> 52.7; removing instance-balancing
costs ~1 F point. The data-efficiency table (Tab. 4, §6.1): PixelLink from scratch at 25k iters on
IC15 alone reaches F 79.7, while SegLink **with** ImageNet pretraining **plus** SynthText reaches
75.0 and EAST 76.4; from scratch SegLink manages only 67.8. The paper's own explanation (§6.1):
regression heads must "learn to predict ... precise numerical values, i.e. coordinates of four
vertices" - "far from intuitive and simple" - while segmentation neurons "only have to observe the
status of itself and its neighboring pixels": **the least receptive-field demand and the easiest
task among the compared methods**, which is why it trains "from scratch with a very limited amount
of data". Multi-scale fusion for a model with no per-box confidence: resize prediction maps to the
largest size, average, then threshold (§5.5) - the paper is explicit that PixelLink "has no direct
output as confidence on each detected bounding box".

### 2.2 TextBoxes++ (Liao, Shi, Bai, IEEE TIP 2018, arXiv:1801.02765) - quadrilateral single-shot

SSD-derived, fully convolutional (VGG-16 conv1_1..conv5_3 + conv6/conv7 + four appended stages,
six output scales) (§III-B1). Each location regresses, per default box, a horizontal rect AND a
quadrilateral. With default box `b0 = (x0, y0, w0, h0)` written as quad corners `q0` (eq. 1):

```
x = x0 + w0*dx,  y = y0 + h0*dy,  w = w0*exp(dw),  h = h0*exp(dh)
x^q_n = x^q_0n + w0*dx^q_n,   y^q_n = y^q_0n + h0*dy^q_n,  n = 1..4        (eq. 2)
```

(a rotated-rectangle variant regresses two top corners + height, eq. 3). Ground-truth quads are
matched to default boxes by their **minimum horizontal bounding rect** (efficiency), and their
corner ORDER is canonicalised clockwise to minimise the summed corner distance to that horizontal
rect (eq. 4) - a labelling rule we need in some form whatever we train (§5.4). Default-box aspect
ratios **{1, 2, 3, 5, 1/2, 1/3, 1/5}**, each duplicated with a **vertical offset** to cover dense
text (§III-B2); text-box layers use **3x5** "inception-style" kernels (§III-B3). Loss is SSD's

```
L = (1/N)(L_conf + alpha * L_loc),  alpha = 0.2,  smooth-L1 loc, 2-class softmax conf   (eq. 5)
```

with two-stage hard-negative mining 3:1 then 6:1 (§III-C3). Augmentation: random crops constrained
by Jaccard overlap **or object coverage** C = |B n G|/|G| (eq. 6 - the coverage form exists because
Jaccard fails on small objects), thresholds drawn from {0, 0.1, 0.3, 0.5, 0.7, 0.9} (§III-C4).
Test: six scales merged into one confidence map, then **cascaded NMS** - first on the minimum
horizontal rects at IoU 0.5 (cheap), then on the quadrilaterals at IoU 0.2 (§III-D). Training
schedule (Tab. I): Adam; **SynthText pretrain 60k iters at 384 px**; then per-dataset stage 1
(lr 1e-4, 384, neg 3:1; IC15 8k iters) and stage 2 (lr 1e-5, **768**, neg 6:1; IC15 4k). Results:
IC15 (1 000 train images) **F 0.817 at 11.6 FPS for 1024 x 1024**; COCO-Text F 0.5591 at 19.8 FPS
for 768 x 768 (abstract, §IV). §III-E's recognition-refinement (eqs. 7-8) is out of scope - our
verifier and law already play that role, on geometry only (decision 10).

### 2.3 Oriented R-CNN (Xie et al., ICCV 2021, arXiv:2108.05699) - two-stage, midpoint offsets

Stage 1, **oriented RPN**: FPN levels P2..P6, three HORIZONTAL anchors per location (ratios 1:2,
1:1, 2:1; areas 32^2..512^2), and a regression branch emitting **6** parameters per anchor -
the **midpoint offset representation** `O = (x, y, w, h, da, db)`:

```
decode:  da' = da_delta * w,  db' = db_delta * h,  w = aw*exp(dw), h = ah*exp(dh),
         x = dx*aw + ax, y = dy*ah + ay                                     (eq. 1)
vertices: v1 = (x, y-h/2)+(da',0);  v2 = (x+w/2, y)+(0,db');
          v3 = (x, y+h/2)+(-da',0); v4 = (x-w/2, y)+(0,-db')                (eq. 2)
```

- (x, y, w, h) is the EXTERNAL horizontal rectangle, and the two offsets place v1 on its top side
and v2 on its right side; v3/v4 follow by symmetry (§3.1.1). Assignment: anchors positive at IoU
> 0.7 with any ground truth (the GT's **external rectangle**) or as the highest-IoU anchor above
0.3; negative below 0.3 (§3.1.2). Loss: CE + smooth-L1 over N = 256 samples (eq. 3) with the
affine parameterisation of eq. (4). Stage 2: **rotated RoIAlign** - rectify the proposal
parallelogram by extending its shorter diagonal, project `(x_r, y_r, w_r, h_r, theta)` with
`w_r = w/s, x_r = floor(x/s)` (eq. 5), sample an m x m grid (m = 7) through a rotation transform
(eq. 6), then FC layers classify and refine (§3.2). Inference: keep 2 000 proposals per FPN level,
**horizontal NMS at IoU 0.8**, top-1 000 to stage 2, polygon NMS at IoU 0.1 above probability 0.05
(§3.3). Training: ResNet-50-FPN **ImageNet-pretrained**, SGD momentum 0.9 wd 1e-4, batch 2 on one
RTX 2080Ti, 12 epochs on DOTA 1024 x 1024 crops (stride 824), lr 0.005 /10 at epochs 8, 11 (§4.2).
Results: DOTA **75.87 % mAP**, HRSC2016 **96.50 %**, **15.1 FPS at 1024 x 1024 on the 2080Ti**
(abstract). The representation, not the pipeline, is this paper's portable part (see §4-D).

### 2.4 RRPN (Ma et al., IEEE TMM 2018, arXiv:1703.01086) - rotated anchors + RRoI pooling

Ground truth as a rotated 5-tuple `(x, y, h, w, theta)`, h the short side, theta canonicalised
into **[-pi/4, 3pi/4)**; image rotation for augmentation carries the label by eqs. (1)-(3) (§IV-A).
**R-anchors**: 6 orientations {-pi/6, 0, pi/6, pi/3, pi/2, 2pi/3} x 3 aspect ratios {1:2, 1:5,
1:8} x 3 scales {8, 16, 32} = **54 anchors per location** (270 regression + 108 score outputs per
position) (§IV-B). Assignment is ANGLE-AWARE: positive = (highest IoU or IoU > 0.7) AND skew-angle
difference < pi/12; negative = IoU < 0.3, or IoU > 0.7 with angle difference > pi/12 (§IV-C).
Multitask loss (eq. 4) with softmax CE (eq. 5) and smooth-L1 over the scale-invariant targets
(eqs. 6-9, with the wrapped angle difference `a (-) b = a - b + k*pi` inside [-pi/4, 3pi/4)).
Skew IoU by convex-polygon intersection + triangulation (Algorithm 1); **Skew-NMS** in two phases:
keep max-score above IoU 0.7, and among IoU in [0.3, 0.7] keep the minimum angle difference when
it is < pi/12 (§IV-D). RRoI pooling projects each rotated proposal into axis-aligned bins for the
classifier (Algorithm 2, §IV-E) - a custom layer. Training: ImageNet-pretrained, lr 1e-3 for 200k
iters then 1e-4 for 100k, wd 5e-4, momentum 0.9 (§V). Rotation augmentation is worth **+21.8 F
points** on their small-dataset setting (Tab. I: F 41.5 -> 63.3). TD500 baseline trained on its
**300 images**: P 57.4 / R 54.5 / **F 55.9** vs Faster R-CNN's 34.0 (§V-A); runtime 0.214 s/image
on a Titan X, 2x Faster R-CNN (Tab. II). Their named failure modes (§V-A): blur/uneven lighting,
extremely small instances, and **1:10 lines split into several proposals** - the last one is our
row shape's specific risk under any anchor-based method (our hand-quad aspect is 2.20-3.78,
median 2.81, PU.69 note §7-2, so inside their fitted range, but a detector box must not split a
row).

### 2.5 What none of the four publishes

No seven-segment-display measurements; no iPhone/Core ML/ANE numbers (all report desktop GPUs);
no label-NOISE tolerance study (our hand quads disagree at median polygon IoU 0.745 across
sessions, §5.4 - none of the papers measures how their method behaves when the training boxes
carry that much noise); no sub-10-instance-count-per-image regime except TD500/IC13 (2-6 rows a
photo is sparse even by those). Every on-device expectation below is therefore labelled inference
or must be measured by the spike.

### 2.6 The survey the brief asks for: what runs on-device on iOS 18 today

1. **Apple's own APIs emit no oriented boxes** (§1, Apple rows): `MLObjectDetector` annotations are
   centre-based `{x, y, width, height}`; `VNRecognizedObjectObservation.boundingBox` is an
   axis-aligned `CGRect`. `VNDetectContoursRequest` exists (arbitrary contours, classical) but has
   no published accuracy on LED/LCD displays and no instance semantics; not ranked.
2. **YOLO-family OBB with Core ML export exists off-the-shelf** (ultralytics docs, §1): YOLO26n-obb
   is 2.4 M params / 14.8 GFLOPs at 1024, exports to `.mlpackage`, takes four-corner normalised
   labels - our `windows.quad` verbatim. Two catches, both verified: **AGPL-3.0** (LICENSE fetched;
   an App Store binary without source disclosure needs Ultralytics' commercial licence - an owner
   decision, not an engineering one), and raw-output export ("`nms=None` defaults to raw outputs
   for external NMS"): the Swift side must decode `[1, 4+1+nc, anchors]` and run its own rotated
   NMS. Pretrained on DOTAv1 (aerial ships/vehicles) - domain distance to pump displays is
   unmeasured.
3. **Segmentation-then-min-area-rectangle** needs nothing Apple does not already run in this app:
   a conv net with sigmoid/softmax heads converts through `coremltools` (this repo's own
   `export.py` path for `PumpSegments.mlpackage`, `ct.convert(convert_to="mlprogram")`), runs via
   `MLModel.prediction` (the `PumpSegmentsModel.swift:36-47` precedent), and the post-processing
   (threshold, disjoint-set, min-area rect) is plain Swift/Accelerate - no custom Core ML op.
4. **The cheapest option of all is already built**: keep the Create ML detector and turn each row
   with PU.69's FHT angle before the verifier - that is `PumpRowDeskew` + `DeskewMode`
   (`PumpRowDeskew.swift:253-265`), measured on the app path (§4-A). It is the baseline every
   other option must beat, not a candidate that needs a spike.

## 3. Mapping onto this code

**What changes is ONE function; what must be re-fitted is a constants table.**

The locator's contract is already oriented: `PumpRowDetector.Row.quad` is `[TL, TR, BR, BL]`
normalised, top-left origin (`PumpRowDetector.swift:14-27`); `bounds` derives the axis-aligned
rect from it (`:26`); every consumer reads the quad through `bounds` (size rules,
`sharesSpan`/`stacks` - `PumpReader.swift:92-111`; `passesSize` - `PumpDisplayCapture.swift:152-155`)
or through the homography warp (`warpToStrip` - any quad in, horizontal strip out,
`PumpQuadWarp.swift:165-195`; `widened` already has a turned-quad branch whose comment says "A
turned box widens along its own axes; rebuilding it from its upright bounds would undo the turn",
`PumpReader.swift:157-171`). **Proof the read stage is quad-native: the annotated tier reads the
owner's oriented hand quads at 118/118 (HEAD), and the apportionment's hand-quad arms beat every
live arm by 30+ cells** (`docs/EXTRACTION.md:1083-1093`). The only place uprightness enters is
`PumpRowDetector.detect(handler:)` rebuilding a CGRect into a degenerate quad
(`PumpRowDetector.swift:67-71`).

So an oriented detector **replaces `PumpRowDetector.detect`'s model call and observation parsing**
and nothing else structurally: inputs stay `CGImage`/`CVPixelBuffer`, outputs stay `[Row]`
(quad + confidence), sorted by confidence. For options B/C the class grows a second initialiser
(a custom `MLModel` like `PumpSegmentsModel`'s, not a `VNCoreMLModel`) plus a Swift post-processor;
`PumpReader.detectedRows` (`PumpReader.swift:68-73`), the rescue (`:79-88`), the fast verdict and
the preview guidance consume it unchanged.

**Training and gating seams.** `detdata.py` is the label exporter: `bbox()` (`:65-69`) is the
upright-ing line; option B replaces it with mask rasterisation, option C writes the quads
themselves (the YOLO-OBB text format is `class x1 y1 x2 y2 x3 y3 x4 y4` - a `--format yolo-obb`
flag away). Its decision-9 assertions (`:240-250`), `--hand-only` filter (`:126-127, 205-209`) and
rotation augmentation (`:72-105`, exact for quads/masks - the labels turn WITH the pixels, unlike
PU.66's upright bounds) are reused as-is. `detector/train.swift` (Create ML) is retired by B/C but
stays on disk for the shipped model's provenance. `detector/measure.swift` computes axis-aligned
IoU (`:13-19`) - the gate needs a **rotated-IoU twin** (convex polygon intersection; the reference
math exists in this note's scratch `measure.py` `poly_iou`, Sutherland-Hodgman + shoelace) and
`tests/test_detector_gate.py` (ordering rule, `FALSE_ROWS_SLACK = 0.05`) a rotated twin asserting
the same ordering. The apportionment already scores a candidate detector without overwriting the
shipped one (`PUMP_DETECTOR=` env, `PumpApportionmentTests.swift:51-59`).

**Constants the options retire or re-fit** (all currently fitted to the Create ML detector's
scores and boxes):

| Constant | Where | Option A | Option B/C |
|---|---|---|---|
| `minimumConfidence` 0.3, `rescueConfidence` 0.15 | `PumpRowDetector.swift:33,38` | unchanged | **re-fit on the train split** - the new score's scale is different (decision 10 allows this: geometry decides, never the classifier's margin; the locator's own score thresholds have always been detector-specific, `docs/EXTRACTION.md:921-947`) |
| `fastConfidenceHigh` 0.5 | `PumpDisplayCapture.swift:93` | unchanged | re-fit with the above |
| `searchMinimumConfidence` 0.5 | `PumpReader.swift:339` | unchanged | re-fit with the above |
| `detectedMarginHorizontal` 0.1 | `PumpReader.swift:122` | unchanged | keep for the spike; a tight oriented box may shrink it later, under PU.35's rule (a margin may never cost a cell, `docs/EXTRACTION.md:934-947`) |
| `DeskewMode` ladder | `PumpRowDeskew.swift:253-265, 296-320` | IS the option | `.always` becomes redundant; `.onRefusal` survives as an FHT REFINEMENT of the detector's own angle (the detector's quad angle vs FHT's is a spike measurement; PU.69's `Confidence` triplet `:62-70` gates it). PU.67's held decision is orthogonal and unchanged |
| `minimumWidestRowFraction` 0.18, `minimumRowHeightFraction` 0.025 | `PumpDisplayCapture.swift:88`, `PumpReader.swift:407` | unchanged | **do not re-fit**: PU.70 measured that a turned row's upright bound is WIDER than the hand box's, so oriented quads can only help the size rule; the tilted-still refusals (pump-302 class) fall without touching the constants |
| `DigitRows.mlmodel` (31 751 101 bytes, `ls -l ios/App/Resources/DigitRows.mlmodel`) | bundle | stays | **replaced**: net bundle change = new model bytes - 31.75 MB (§7.2) |
| `detector/measure.swift` gate, `test_detector_gate.py` | `ml/pump-reader/` | unchanged | rotated-IoU restatement of decision 10 (the row's gate: "decision 10 restated in those terms BEFORE the first candidate") |

## 4. The options, each with its adaptations named

An adaptation is a departure from the published method; **a departure the implementer adds later
that is not listed here needs the product owner's OK** (the brief's fence).

### A. Keep the Create ML upright detector; turn each row with PU.69's FHT angle ("the cheapest option of all")

**Already built and measured - no spike needed; this is the baseline arm.** `PumpRowDeskew.deskew`
(`PumpRowDeskew.swift:76-115`) turns a detector box to its digits' angle (FHT + SSG + sec^3,
`:168-203`); `readPhotoDetailed`'s `.onRefusal` ladder (`:296-320`). Measured on the app path
(heldout 68, corpus scorer 0.005): `.off` **47/47** at HEAD (45/45 before PU.78); `.onRefusal`
**52 committed / 51 correct (0.981, Wilson 2s [0.899, 0.997])** - held below the 0.99 floor on
pump-275's 103.31-for-103.37 (`docs/EXTRACTION.md:1137-1153`, PU.67 row `docs/TASKS.md:1069`;
that measurement pre-dates PU.78's exact close, and PU.67's own row orders a re-run of its checks
at the reopen's commit); `.always` (turn every row before the verifier) **46/46** under the
2026-09-23 law - it churns: "turning a box moves where its ends fall" (PU.65 row). FHT
cost 2.9-3.1 ms/row Release-on-Mac, angle median error 0.60 deg vs hand quads (`docs/EXTRACTION.md:1111-1125`).
**Why it cannot close the row alone**: (i) the -33 framing arm persists - a turned UPRIGHT box has
the wrong extent (its length/height come from `rowSize`'s bound inversion, `:124-131`, not from the
row's ends); (ii) rows the detector never frames stay unfound - PU.70's pump-302 (detector 0.10 of
frame vs hand 0.30) is refused by the SIZE rule before any angle exists; (iii) `.onRefusal` is
held at 0.981 by a misread, and PU.81 closed with no repair. Its role after B/C: the refusal-path
refinement and the angle cross-check (the table above).

### B. Segmentation-then-minAreaRect: PixelLink's method with a small backbone - **RANK 1, spike first**

**Mapping.** New `PumpRowSegmenter` beside `PumpRowDetector` (same `Row` output contract, §3):
Core ML model -> two probability maps (pixel, 8 links) at prediction scale -> thresholds ->
disjoint-set join -> CCs -> post-filter -> min-area rect per CC -> oriented quad in reading order
-> confidence. `detdata.py` grows a mask/quad export; `measure.swift` grows the polygon-IoU gate.

**Published method applied as-is:** the two-head architecture and link semantics (§3.1-3.2),
GT rule (§4.1), losses eqs. (1)-(4) with lambda = 2.0, OHEM r = 3, instance-balanced weights,
augmentation (§4.3), SGD/xavier-from-scratch schedule (§5.2), thresholds and the **train-split
99th-percentile post-filter rule** (§3.4, §5.3), minAreaRect extraction (§3.3), link head
non-optional (Tab. 5: F 82.3 -> 64.0 without it).

**Adaptations (each a departure, each justified):**

- **B1 - backbone.** Paper: VGG16 (+fc6/fc7 as convs), ~134 M params, 2s/4s fusion from
  {conv2_2..fc7}. Ours: a small conv encoder-decoder in the repo's own idiom (SegmentNet's 3x3 +
  BN + ReLU blocks, `model.py:19-26`, scaled up; target <= 1 M params / <= 4 MB). Why: VGG16 at
  fp32 is ~500 MB against a 31.75 MB budget; the paper's contribution is the pixel+link
  formulation, not the backbone ("Following SSD and SegLink, VGG16 is used" - inherited, §3.1),
  and its own §6.1 argues the task needs SMALL receptive fields, not depth. Cost: no published
  accuracy number for a shrunk backbone - the spike measures it (falsifier F4/F5, §5.7).
- **B2 - input scale.** Paper: train 512 x 512, test 1280 x 768. Ours: train and test at one size
  in {512, 640, 736}, chosen from the measured row heights: at 512 input the median train row is
  **29.9 px** tall (p10 16.6) - §5.5 - so the **2s-style head (predict at 1/2)** is the floor;
  4s would put the median row at ~7 px of mask. The paper's 2s beat 4s on IC15 anyway (Tab. 1).
- **B3 - confidence.** Paper publishes NO per-box confidence (§5.5 says so explicitly). Our
  consumers need one (`minimumConfidence`, `rescueConfidence`, `fastConfidenceHigh`,
  `searchMinimumConfidence`). Ours: the CC's mean pixel probability (the maps are probabilities;
  the paper's own multi-scale fusion averages them). Thresholds re-fit on the TRAIN split at the
  shipped detector's operating shape (0.3 keeps ~86 % of rows - `PumpRowDetector.swift:30-33`'s
  measured curve is the fitting target). This is an invention of ours where the paper is silent -
  flagged as the option's weakest link; the alternative (a constant confidence, thresholds decided
  by geometry alone) is a smaller departure and the spike should report both arms.
- **B4 - augmentation rotations.** Paper: 0/90/180/270 only. Ours: add small in-plane rotations
  (+-3, +-6, and a +-12..25 arm) carrying masks/quads exactly (`detdata.py:72-105` already does
  this for quads). Why: our turned population is in-plane (train max 43.6 deg, 13 stills > 12 deg
  - §5.3), and RRPN's Tab. I (+21.8 F from rotation augmentation) and PU.66's failure analysis
  both point the same way - with quad/mask labels the "upright bound of a turned row" defect that
  sank PU.66's rounds does not exist.
- **B5 - labels are the hand quads, rasterised.** Paper: GT pixels inside text boxes, links inside
  instances (§4.1). Ours: fill each hand quad (all window fields, boards included - the detector
  learns boards today, `detdata.py:146-183`); link = same window. Re-pin under ONE rule first
  (§5.4): the row's gate says "labels re-pinned under one rule", and TextBoxes++'s eq. (4)
  corner-order canonicalisation is the published precedent for the corner part of that rule.
- **B6 - post-processing in Swift, not OpenCV.** No OpenCV on device (the repo's opencv dependency
  is Python-toolchain-only, `pyproject.toml` `frames` extra). Disjoint-set (~40 lines), CC
  extraction, rotating-calipers min-area rect (~80), corner order to TL/TR/BR/BL reading order
  (~30, matching `PumpQuadWarp.readingOrder`'s convention, `:124-132`). Pure Swift/Accelerate; no
  C target needed.
- **B7 - post-filter thresholds from OUR train split** by the paper's own rule (§3.4): 99th
  percentile of train row shorter-side and area, replacing the paper's literal 10 px / 300 (IC15
  statistics). Plus the repo's existing geometry rules stay downstream (`isKeypadRow`,
  `PumpReader.swift:191-197`).
- **B8 - negatives** are the 116 non-pump fixtures with all-zero masks (the detector's implicit
  background becomes explicit; same files `detdata.py:227-238` exports today).

**Training data needed:** the hand pool counted in §5.2 - 255 train stills / 1 051 windows + 275
owner-verified train frames / 1 003 windows (88 frames under the export's frame-step 5; PyTorch
training may use all 275 - a spike arm) + 116 negatives. That is **~530 images against the paper's
1 000 (IC15, from scratch, F 82.3-83.7) and 700 (TD500 line-level, F 77.8)** - the only one of the
four papers with a published from-scratch result at our data scale, and its §6.1 is an explicit
argument that segmentation is the least data-hungry formulation of this task.

**Conversion risk to Core ML: LOW.** Conv/BN/ReLU/upsample/sigmoid only - the exact op set this
repo already converts (`export.py`, `ct.convert(convert_to="mlprogram")`; the venv runs torch
2.14.0 + coremltools with a version warning that PU.73's runs shipped through). No custom op, no
NMS in-graph.

**The cheap falsifying spike (report only):** export masks for the train pool (detdata flag);
train the small pixel+link net (paper's schedule, xavier from scratch, ~40-60k iters is the
paper's number at batch 24 on 3 Titans; ours is smaller - hours on this Mac; note `train.py:204`
selects cuda-or-cpu only - adding MPS is tooling, not method); decode in PYTHON first (no Swift
needed for the report); score against the heldout 68 with the rotated-IoU restatement of decision
10 (§5.6) and the apportionment's `PUMP_DETECTOR=`-style arm. **Falsified when**: the rotated gate
fails against the shipped detector re-scored in the SAME metric (F1), or framing loss stays >= ~15
cells (F2), or masks merge stacked rows on more than a named fraction of heldout stills despite
the link head (F4 - the measured overlap rate says ~8 % of stacked pairs touch, §5.5), or the
model misses the size/latency budget (F5).

### C1. A small quadrilateral single-shot detector - TextBoxes++'s method, our backbone - **RANK 2**

**Mapping.** Same seam as B (`PumpRowDetector.detect` replacement); output decode: per default box
read `(dx, dy, dw, dh, dx^q_1..dy^q_4, c)` and apply eq. (2); cascaded NMS (§III-D) in Swift
(horizontal pass at 0.5, quad pass at 0.2 - polygon IoU, same primitive as the gate).

**Published method applied as-is:** quad regression eqs. (1)-(2); GT corner canonicalisation
eq. (4) (also the re-pinning rule's corner half); SSD loss eq. (5) with alpha = 0.2; hard-negative
mining 3:1 -> 6:1; coverage-based random crops eq. (6); cascaded NMS; vertical-offset default
boxes (our rows stack at p10 gap 0.5 px, §5.5 - the paper's dense-text motivation applies
literally).

**Adaptations:**

- **C1-1 - backbone**: VGG-16 -> the same small backbone as B1 (same size argument).
- **C1-2 - default-box aspects**: paper {1, 2, 3, 5, 1/2, 1/3, 1/5}; ours from the measured hand
  aspects 2.20-3.78 (median 2.81, PU.69 §7-2): {2, 3, 4, 6} plus their reciprocals ONLY if the
  orientation search's 90/270 arms feed it sideways rows (they do not - rows are upright in the
  searched frame; drop the reciprocals, a stated departure).
- **C1-3 - NO SynthText pretrain.** The paper's schedule assumes 60k iters on 800k synthetic
  images (Tab. I). We have no such corpus and building one is a different row. This is the
  option's central risk and it is exactly what PixelLink's Tab. 4 measures AGAINST: regression
  heads from scratch on ~1k images underperformed segmentation from scratch by ~12-15 F points in
  their comparison (SegLink-scratch 67.8 vs PixelLink-scratch 82.3). Mitigation the spike can
  measure: the repo's synthetic renderer (`ml/pump-reader`'s `render.py`/`dataset.py` pipeline
  trains the classifier on synthetic glyphs today) can render synthetic ROWS with known quads -
  unbounded free labels; that is a data change of the PU.82 class and needs the owner's call
  before it is more than an idea.
- **C1-4 - single scale, one output stage** (paper: six): our rows occupy a narrow size band
  (16.6-60.7 px at 512, §5.5) and the image is downsampled once; six stages is wasted bundle.
- **C1-5 - score = the paper's `c`** (no B3 invention needed - this is C1's structural advantage
  over B: a published per-box confidence exists).

**Data needed:** the same pool as B, in quad form. **Conversion risk: LOW-MEDIUM** (conv-only
graph; decode/NMS in Swift ~200 lines; anchor generation must match between Python training and
Swift inference - the classic silent-mismatch trap; a pinned vectors test is mandatory).
**Falsifier:** the same F1/F2/F3/F5, plus F-convergence: if the quad regression does not reach the
shipped detector's presence (171/188 learned, `docs/EXTRACTION.md:1090-1092`) within the paper's
iteration budget at our data scale, C1's data-hunger is confirmed and the family moves to B or
closes.

### C2. YOLO26n-obb (ultralytics) - the off-the-shelf rotated-box engineering probe - **RANK 3, licence-gated**

Not one of the row's papers - the brief's survey item. What is verified (§1): a maintained 2.4 M-param
OBB detector whose label format IS our quad format, DOTAv1-pretrained weights, one-command Core ML
export. **The spike is report-only and internal, which AGPL permits (running the program is
unrestricted, LICENSE §2); SHIPPING is blocked on the owner's licence decision** (AGPL-3.0 vs an
App Store binary; Ultralytics sells an enterprise licence - not this note's call). Adaptations if
it ever ships: C2-1 raw-output decode + rotated NMS in Swift (the exporter's `nms` embedding is
not available for OBB - "unsupported formats fall back to their native output path", docs);
C2-2 fine-tune from DOTAv1 weights on our ~530 images (domain gap unmeasured - aerial objects vs
LED rows); C2-3 our confidence thresholds re-fit onto its score scale (same as B3's re-fit, but
the score is published, not invented). Value even unshipped: it is the **cheapest possible answer
to "can ANY oriented box beat the framing loss on this corpus"** - a day of config, no new
Swift - and a positive result de-risks C1 (the same formulation, licence-clean); a negative result
on a DOTA-pretrained nano model is weak evidence against B (different failure modes: domain gap vs
data scale). Run it as a REFERENCE arm beside B's spike, labelled as such.

### D. Oriented R-CNN - **RANK 4, not recommended**

Two-stage with a custom **rotated RoIAlign** (eqs. 5-6): no MIL/Core ML op implements it;
converting means re-expressing it as affine-grid + bilinear sampling through `coremltools`
composite ops - high-risk, unproven in this repo, and the only option needing a second-stage head
at all. Its capacity is aimed at DOTA's ~100 objects per 1024^2 crop; our photos hold 2-6 rows.
The 2 000-proposals-per-level -> top-1 000 -> poly-NMS pipeline (§3.3) is ~500 lines of Swift
decoding for a problem with five answers. **What to borrow, if ever (a listed adaptation, not
silent):** its **midpoint-offset representation** (eqs. 1-2) is a bounded, angle-free
parameterisation of a quad - strictly better-conditioned than TextBoxes++'s raw 8 offsets for
nearly-horizontal rows (da, db are small numbers). If C1's spike shows unstable quad regression,
swapping the head parameterisation to midpoint-offset IS the fix, and it is pre-approved here as
C1-3b rather than being invented at build time. Requires the owner's OK only in the sense that it
changes C1's cited equations (this note lists it, so the fence is satisfied).

### E. RRPN - **RANK 5, not recommended**

Everything D's conversion problem is, plus 54 rotated anchors per location over the FULL
[-pi/4, 3pi/4) angle space when our measured distribution is a narrow cone (heldout transactions:
median 0.81 deg, p90 3.25, none past 12 - §5.3; train's tail reaches 43.6 deg but 13 stills of
255). RRoI pooling is a second custom layer. Its published small-data point (TD500 from 300
images, F 55.9) still leans on ImageNet pretraining and lands well below PixelLink's from-scratch
TD500 F 77.8. **What to borrow, if ever (listed):** its **angle-aware Skew-NMS second phase**
(among IoU in [0.3, 0.7], keep the smaller angle difference, §IV-D) and its **angle-aware positive
assignment** (IoU > 0.7 AND dtheta < pi/12, §IV-C) - both are one-paragraph additions to C1's
matching/NMS and both exist because box IoU alone under-detects long thin rows, which is exactly
our shape. Also its Tab. I is the published evidence behind adaptation B4.

## 5. Populations, measurements, expectations, falsification

All counts from the pinned corpus blob (§0) with `ml/pump-reader/.venv/bin/python` over
`Spike/ReceiptSpike/fixtures/corpus.sqlite` (read-only URI) + PIL size/EXIF reads; script and raw
JSON in the scratch dir (`measure.py`, `out.txt`). Angles are in PIXEL space of the upright
(EXIF-transposed, then `rotationCW`) image, mean of the quad's top and bottom edge angles - the
space PU.69 §7-1 established as the honest one (normalised-space angles are aspect artefacts).
Polygon IoU is Sutherland-Hodgman + shoelace on the quads as drawn. Fractions carry Wilson
two-sided 95 % intervals (PU.68 note §2.1, BCD eq. 4).

### 5.1 What the papers measured (recap, fetched only)

PixelLink: IC15 F 83.7 from scratch / 1 000 images; TD500 lines F 77.8 / 700 images fine-tuned;
IC13 F 84.5 / 229 fine-tuned (Tabs. 1-3). TextBoxes++: IC15 F 0.817 at 11.6 FPS 1024^2 WITH 800k-image
SynthText pretraining (Tab. I, §IV). Oriented R-CNN: DOTA (aerial imagery, 1024 x 1024 crops at
stride 824, §4.2) 75.87 mAP, 15.1 FPS 1024^2 on a 2080Ti; HRSC2016 96.50 mAP. RRPN: TD500 F 55.9
from 300 images with ImageNet pretraining; 0.214 s/image Titan X. None measured our domain, device
or label noise (§2.5).

### 5.2 The training pool (what an oriented detector would learn from), counted at HEAD

| Population | Count | File and filter |
|---|---|---|
| Train stills (split = train) | **256** (255 with windows) | `fixtures.split='train'` + `entries`, kind='pump'; the detdata stills query requires >= 1 window (`detdata.py:146-149`) |
| Train still windows (hand quads) | **1 051** (1 047 with text; 726 transaction-with-text; 322 board) | `windows` joined on those stills |
| Heldout stills / windows | **68** (all reviewed) / **252** (195 transaction-with-text, 57 board) | `fixtures.split='heldout'`, `entries.reviewed=1`; matches `PumpReaderTestSupport.isHeldout` (`:83`). The apportionment's own filter (66 UPRIGHT stills, `PumpApportionmentTests.swift:75-78`) counts **190** transaction-with-text rows at HEAD: this note's 195 minus the 5 on the two `rotationCW=90` stills (pump-019: 3, pump-023: 2 - `windows` query). PU.69's note counted **188** at `c22d0217` with the same upright filter; the +2 is the owner's pump-275 re-frame (5 windows) in corpus commit `22559705`. Each number here names its own filter |
| heldout2 (frozen tilted draw) | **4** stills / 20 windows | `fixtures.split='heldout2'`; excluded from BOTH export dirs (`detdata.py:152-156`) - **never used to pick a detector** |
| Owner-verified frames (`frames.verified=1`) | **281**: 275 train-split (58 live + 217 video), 6 heldout-split (excluded by decision 9's assertion, `detdata.py:240-250`) | `frames` + record meta split |
| Windows on verified train frames | **1 003** | `frame_windows` joined to those frames |
| Verified frames surviving detdata's filters | **88 of 275** (frame-step 5) | this note's re-run of `detdata.py:186-224`'s filter chain via `corpus_db.tracked/tracked_records/labels` |
| Tracker-boxed labelled frames (NOT hand; PU.66 round 3 says they degrade the detector) | 26 116 distinct record/frame with windows; 6 124 video frames with a non-skip label | `frame_windows`, `labels` |
| Negatives | **116** (receipts 97, screenshots 9, fiscal 1, expenses 9) | `detdata.py:42`'s folders, image files counted |
| Hand-quad pool for a hand-only oriented train (PU.66 round 3's recipe, today) | **255 stills + 88..275 verified frames** (~1 051 + 330..1 003 boxes) vs round 3's "249 stills + 60 verified frames" on 2026-09-23 | rows above; the pool grew 4.6x in frames at the owner's 2026-09-24 session (`22559705`) |

### 5.3 The turned population (why upright boxes lose), at HEAD

| Statistic | Value (pixel space, upright image) |
|---|---|
| Heldout transaction windows (195): \|angle\| | median **0.81 deg**, p90 **3.25**, max **8.73**; > 0.5 deg **130/195 = 0.667 [0.598, 0.729]**; > 6 deg 5/195; **> 12 deg 0/195** |
| Heldout all windows (252) | median 0.99, p90 5.44, max 10.22 |
| Train all windows (1 051) | median 1.16, p90 6.34, max **43.6** (pump-320, the tilted rain batch); > 6 deg **117/1 051 = 0.111 [0.094, 0.132]**; > 12 deg 37/1 051 = 0.035 [0.026, 0.048] |
| Stills with any window > 12 deg | train **13/255 = 0.051 [0.030, 0.085]**; heldout **0/68**; heldout2 2/4 (median window angle there **22.7 deg**) |
| Stills with any window > 6 deg | train 49, heldout **9**, heldout2 2 |

Consistency with the docs: PU.69 §5.2 measured heldout transaction quads at median 0.93 / p90 3.39 /
max 10.35 over 188 windows at `c22d0217`; the deltas here (195 windows, transaction median 0.81,
max 8.73) are the owner's 2026-09-24 re-frames (pump-275 - whose drawn angle PU.67 had at 13.2 deg
normalised - plus pump-014, pump-325) and this note's wider filter (all 68 heldout stills including
the 2 `rotationCW=90` ones; §5.2 reconciles 188 -> 190 -> 195 exactly). PU.65's row text
"140 of 190 turned, max 18" is the normalised-space artefact PU.69 §7-1 corrected; do not reuse it.
**Consequence for the spike's tilted arm:** heldout contains NO hand row past 12 deg, so the row's
"live pass ~65" gate is decided on mild turns (<= 8.7 deg), and the > 12 deg population lives in
train (13 stills - in-sample, report-only) and heldout2 (frozen, may be MEASURED for reporting but
may not pick the detector, `detdata.py:152-156`). PU.65's "tilted-20" arm was reader-side runtime
angles with **no committed list** (PU.67 note §5.2/finding at `agents/research/PU.67.md:447`); the
spike must rebuild it from PU.69's FHT angle over detector rows and name it, or drop it and say so.

### 5.4 Label consistency - the row's precondition, measured

The row's "hand quads agree at IoU 0.75-0.79" is the TRACKER-vs-hand number (`ml/pump-reader/REPORT.md`
live-6333 section: 0.75 / 0.77 / 0.79 against still / nearest pin / chained; PU.66: "median IoU
0.77, 42 % below 0.7"). The brief asks for the hand-vs-hand number - **where two quads cover one
row and both were drawn by the owner**. Three sources exist in the corpus; the fourth (anchors) is
not independent:

| Two quads, one row | n | Polygon IoU (recomputed) | Angle difference |
|---|---|---|---|
| **Still re-frames across sessions** (`corrections.kind='quad'`, `proposedBy='operator'`, still scope - the owner's earlier hand quad vs his new one; pump-300s batch 2026-09-22/23, pump-014, pump-055, pump-275, pump-325) | **75** | median **0.745**, p25 0.530, p75 0.849, mean 0.704; **< 0.7: 34/75 = 0.453 [0.346, 0.566]**; < 0.75: 0.507 [0.396, 0.617] | median 0.92 deg, p90 4.95, max 34.7 (pump-322's reframe); > 2 deg: 22/75 = 0.293 [0.202, 0.404] |
| Still corrections of AUTO prefill (`proposedBy='auto'`) | 18 | median 0.774 | - |
| **Frame re-adjustments** (`kind='quad'`, `proposedBy='operator'`, record scope - in-session nudges of his own/anchor quads) | **620** | median **0.901**, mean 0.785; < 0.7: 122/620 = **0.197 [0.167, 0.230]** | median 0.30 deg, p90 2.27 |
| Tracker-proposed frame quads vs the owner's correction | 444 | median **0.766**; < 0.7: 181/444 = 0.408 [0.363, 0.454] (the documented "0.77 / 42 %" reproduces) | median 0.28 deg, p90 2.82 |
| Tracking anchors vs verified-frame windows (same record/frame/field, best IoU match) | 854 pairs | **1.000 for all 854** | 0.00 |

Findings: (i) anchors are NOT a second independent drawing - they are copied verbatim into the
verified frames' windows, so the only genuine hand-vs-hand evidence is the corrections ledger;
(ii) **the owner's own cross-session still quads agree at median 0.745 with 45 % below 0.7** -
consistent with REPORT.md's live-6333 residuals ("between ADJACENT frames the hand quads differ by
up to a quarter of the row height at the top edge ... the noise is in the pins") and with its
verdict "the detector's median IoU (0.80) is that noise, learned"; (iii) my polygon IoU differs
from the ledger's stored `iou` column by > 0.02 on 42 of 1 157 rows (the annotator's own metric is
not documented; the recomputed polygon value is the one this note stands behind); (iv) the
tracker's angle error is SMALL (median 0.28 deg) while its IoU is loose (0.766) - tracker boxes
know the row's direction and lose its edges, which is why PU.66 round 3's hand-only recipe was the
largest single gain. **Consequence for the row's gate**: a rotated-IoU gate scores agreement with
labels that carry ~0.25-row-height edge noise; the shipped detector's 0.797 median (upright metric)
already sits at that noise floor. The spike must re-score the SHIPPED detector in the rotated
metric as its baseline (F1), and the "labels re-pinned under one rule" step targets exactly the
75-row still population above (proposed rule in B5; the owner picks).

### 5.5 Row geometry at model scale (train stills, upright bounds, 512-px input) - measured

Row height at 512 input: **p10 16.6 / median 29.9 / p90 60.7 px** (n = 1 051). Vertical gap between
x-overlapping window pairs (n = 1 099): median 50.2 px, **p10 0.5 px**, and **89/1099 = 0.081
[0.066, 0.099] of pairs OVERLAP** in upright bounds. This is the quantitative case for the link
head (B's published ablation: without it F 82.3 -> 64.0) and for TextBoxes++'s vertical-offset
default boxes; it also sets B2 (2s head: the median row is ~15 px of mask at 2s, ~7 at 4s).

### 5.6 The gate, restated in rotated terms before any candidate (the row's order)

Decision 10's PU.57 amendment (`docs/EXTRACTION.md:985-997`): a candidate ships only when **median
IoU and recall @ IoU 0.7 both hold or rise** and **false rows per photo rises by <= 0.05**;
recall@0.5 never decides. Restated for oriented boxes (this restatement is what `measure.swift`'s
twin and `test_detector_gate.py`'s twin must implement before the first candidate trains):

- **IoU = convex-polygon IoU** between the candidate's quad and the HAND QUAD (not its upright
  bound) on the 68 heldout stills' 252 windows;
- **baseline = the shipped DigitRows detector re-scored in the same rotated metric** (its upright
  boxes are polygons too). The published 0.797 / 0.734 / 0.632 triple (`docs/TASKS.md:1068` round 3
  table) is the UPRIGHT metric against upright truth bounds - comparable in spirit, not in number;
- matching rule unchanged (best unmatched IoU, greedy, as `measure.swift:50-62`);
- false rows per photo, presence counts (the apportionment's 188-row ladder: 182 proposed by any
  source, 171 by the learned detector, 155 kept - `docs/EXTRACTION.md:1090-1092`), and the
  `test_detector_gate.py` ordering assertion (tight beats loose-but-more-overlapping) all carry over.

### 5.7 What we expect on our corpus, and what falsifies the row

Population for the row's gate: the apportionment's **66 upright heldout stills / 177 asserted
cells** (its own filter, `PumpApportionmentTests.swift:75-88`, re-counted at the spike's commit -
the ASSERTED count is annotation-driven, but every arm's COMMITTED count moves with the law: the
oracle arm read 108 at the 2026-09-23 run, and the annotated tier has since moved 112 -> 118 ->
(working tree) 123 through PU.78/PU.74) and the live path's **68 heldout stills / 183 numeric
cells** (`PumpPhotoGate.readerNumericTotal`).
Expectations (inference, labelled - the papers give no display-domain numbers):

- The **-33 framing arm** is mostly orientation, per the row's own evidence (hand windows as
  upright rects 89/0.944 vs quads ~111/0.991; 140-of-190-turned at PU.65's counting). An oriented
  locator that frames like the hand quads should bring the detector-box arm from 45 toward the
  kept-windows arm (78). **Gate: framing loss < ~15 cells** (row) - a delta between two arms of
  the SAME run, so it survives the law moving under it.
- **Live pass ~65 at zero wrong readings** (row): 47 today + most of the framing recovery. The
  binding clause is zero wrong readings (the precision floor `livePrecisionFloor = 0.99` is a
  point estimate; at zero wrong it is 1.000, Wilson 2s 95 % at 65/65 = [0.944, 1.000], PU.68 §2.1).
  The spike reports every precision with its interval per PU.68 §4.
- **Presence** should not fall (171 learned / 155 kept): B4's rotation augmentation targets the
  turned stills PU.66 round 1 found but framed worse ("67 of 68 photos with a row", recall@0.5
  0.909 - the finding that a quad-labelled retrain keeps without the framing penalty).
- Tilted tier (report-only): the 13 train stills > 12 deg in-sample, the rebuilt reader-side
  tilted arm (§5.3), and heldout2 measured-but-not-selecting.

**Falsifiers (the row closes the family on these):**

- **F1 (gate)**: rotated median IoU or recall@rotIoU 0.7 falls below the shipped detector's
  re-scored baseline, or false rows/photo rises > 0.05 -> candidate refused before apportionment.
- **F2 (framing)**: apportionment framing loss stays >= ~15 cells -> "the family closes" (row).
- **F3 (live)**: live pass < ~65 or ANY wrong reading on heldout -> family closes (row); PU.66's
  signature warning applies - every retrain so far "makes wrong readings on heldout where the
  shipped one makes none".
- **F4 (B-specific)**: stacked rows merge into single CCs on > 5 % of heldout stills despite the
  link head (the base rate of touching pairs is 8.1 % of pairs, §5.5 - the link head's whole job)
  -> B's instance model fails on this corpus; fall back to C1 before closing the family.
- **F5 (cost)**: bundle > 31.75 MB or Mac-Release classify-path latency > 2x the shipped median
  (~52 ms appDecide, §7.1) with the annotator closed -> shrink or close. iPhone 12 numbers are
  PU.75's instrument (Capture Lab), required before any ship, not before the spike report.
- **F6 (labels)**: if after re-pinning under one rule the hand-vs-hand still agreement does not
  move materially from median 0.745 / 45 %-below-0.7 (§5.4), the labels - not the method - are the
  binding constraint (PU.66 round 3's "signature of label quality"), and the family decision goes
  back to the owner with that measurement instead of a third retrain.

## 6. Ranking for THIS corpus and device, and the spike to run first

| Rank | Option | Expected effect on the -33 framing arm | Training data | Core ML conversion risk | Spike cost | Bundle |
|---|---|---|---|---|---|---|
| **1** | **B - PixelLink-shaped segmentation -> minAreaRect, small backbone** | Directly attacks it: quads come from the row's own pixels, no coordinate regression to underfit at 530 images; published from-scratch small-data evidence (Tab. 4, §6.1) at our scale | 255 stills + 88..275 verified frames + 116 negatives, labels = rasterised hand quads (exist; re-pin the 75-row population first) | **LOW** - conv/sigmoid only; repo-precedented toolchain (`export.py`) | Days: mask export + small net + Python decode; no Swift needed for the report | ~1-4 MB (B1), **-28 MB net** vs today |
| 2 | C1 - TextBoxes++-shaped small quad detector | Same target, regression route; the published per-box confidence is a real advantage over B3 | same pool, quads verbatim | LOW-MEDIUM (anchor parity between Python/Swift must be pinned) | ~1 week (head + anchors + NMS + parity tests) | ~2-8 MB |
| 3 | C2 - YOLO26n-obb reference probe | Unknown (DOTA domain gap); answers "can any oriented box beat framing loss here" in a day | same pool in YOLO-OBB text format | export exists; raw-output decode in Swift | Hours (config), but **ship-gated on AGPL - owner decision** | ~5-10 MB (est. from 2.4 M params) |
| 4 | A - upright + FHT turn | **Measured**: churns (46/46 always; 52/51 on refusal, held); cannot fix extent or the unfound turned rows | none | none | none - baseline arm only | 0 |
| 5 | D - Oriented R-CNN | capacity for DOTA, not for 2-6 rows | would want ImageNet-pretrained R50 | **HIGH** - rotated RoIAlign has no MIL op | weeks | ~100 MB+ (R50-FPN) - fails F5 alone |
| 6 | E - RRPN | full angle space wasted on a <= 12 deg cone | same | HIGH (RRoI + 54-anchor decode) | weeks | high |

**Spike first: B, with C2 run beside it as a labelled reference arm if the owner wants the cheap
cross-check (internal-only; no ship without the licence call).** Why B:

1. **It is the only option whose paper publishes from-scratch training at our data scale** (IC15:
   1 000 images, no ImageNet pretrain, F 82.3-83.7; TD500 line-level: 700 images, F 77.8), and its
   §6.1 gives the reason as a mechanism (segmentation neurons learn local texture; regression
   neurons must learn exact coordinates - PixelLink's own Tab. 4 numbers quantify the gap at ~1k
   images). Our pool is ~530 hand images and growing; C1's published schedule needs 800k synthetic
   images we do not have (C1-3).
2. **Task-shape match**: our ground truth IS a straight rigid strip; minAreaRect over a segmented
   row reproduces the hand quad's geometry by construction, including the perspective tilt the hand
   quads carry (a rotated rectangle approximates a trapezoid row better than an 8-offset regression
   trained on 500 images - inference, and the spike measures it).
3. **Lowest conversion risk in the repo's own toolchain** (B: conv+sigmoid through `export.py`'s
   proven path; the decode is Swift loops like `PumpGlyphSlicer`'s, no C target needed).
4. **Its failure modes are visible and bounded**: a bad mask is inspectable; F4 names the one
   corpus-specific risk (touching rows, base rate measured at 8.1 % of stacked pairs) and the
   published ablation says the link head is the mitigation, not an invention.
5. **It retires the most weight**: DigitRows.mlmodel's 31.75 MB against a 1-4 MB model - the only
   option that turns the bundle gate from a constraint into a win.

The spike's deliverable is a REPORT (the row: "A spike first, report only"): the rotated-gate
triple against the re-scored shipped baseline (F1), the apportionment re-run with the candidate as
locator (F2, `PUMP_DETECTOR=`-style env so nothing shipped is touched), the live pass with the
corpus scorer at 0.005 and Wilson intervals (F3, PU.68 §4), the merge rate (F4), size and
Mac-Release latency with the annotator closed (F5, PU.69 §7-4's hygiene rule), and the label
agreement re-measured after any re-pinning (F6). **The completeness review of the spike is Qwen
3.8 max and the method-choice second opinion is Codex `gpt-6-sol`** (the row's routing); this note
is the input to both.

## 7. Cost

### 7.1 Latency (Release, measured THIS NOTE, Mac - contention-labelled)

Built `pump-read` with `swift build -c release --product pump-read -Xswiftc -enable-testing
--scratch-path <scratch>` (a plain `-c release` build FAILS: `PumpReadTool/main.swift:17` uses
`@testable import TankbookCore`; the release configuration needs `-enable-testing` - handed off,
§8-9). Ran the live-path request over 12 heldout stills; **the owner's annotator servers were
running** (PU.69 §7-4: contention inflates up to ~25x; treat these as upper bounds):

| Stage (median over 12 stills) | Mac Release, contended |
|---|---|
| `detectorOnly` (the Create ML detector, 416 x 416 input, Vision) | **~5 ms** (range 1-9) |
| `appDecide` (detector + fast verdict, or slow path) | **~52 ms** (range 13-453; the 453 is pump-008's slow path) |
| `readPhoto` | ~378 ms (range 159-456; pump-008's slow-path fallback 29 048 ms - the known 28 s-class verifier fallback, `docs/EXTRACTION.md:949-966`) |

Committed baselines for comparison: classify decision 13-73 ms and classify+read 112-164 ms
Release-on-Mac (`ml/pump-reader/REPORT.md:1125-1128`; PU.75 row). **Nothing has ever been timed on
an iPhone** (PU.75: "never timed on a device"; the row's iPhone 12 floor and the preview
guidance's 100 ms throttle - `PreviewGuidance.swift:119` - are the budgets any replacement must be
measured against, with PU.75's Capture Lab instrument). Estimates for the options (INFERENCE, not
measurement): B's small net at 512-640 input is ~2-5 GFLOPs-class -> ~5-15 ms Mac Release,
~15-50 ms A14 (the ANE runs conv/sigmoid natively; the Swift decode adds disjoint-set + calipers
over a ~256 x 320 mask, single-digit ms); C1 similar minus the decode, plus NMS over ~10^3 anchors;
C2's yolo26n is 14.8 GFLOPs at 1024 (2.8 ms T4 TensorRT published) - larger than B/C1 by design;
A adds 2.9-3.1 ms/row (PU.69, shipped measurement).

### 7.2 Bundle

Shipped today: `DigitRows.mlmodel` **31 751 101 bytes** (`ls -l ios/App/Resources/DigitRows.mlmodel`;
Create ML pipeline, 416 x 416 RGB input, Vision-style `confidence`/`coordinates` outputs - read
from the model spec with coremltools) + `PumpSegments.mlpackage` 64 KB. B: ~1-4 MB fp32 (B1's <= 1 M
param target; fp16 via `ct.convert`'s precision option halves it again - PU.75's quantization
references cover that path if ever needed). C1: ~2-8 MB. C2: ~5-10 MB (estimate from 2.4 M
params). D: fails the budget outright (R50-FPN ~100 MB+). Every option except D/E comes in under
the 31.75 MB it replaces.

### 7.3 New code to maintain (estimates, lines, labelled as estimates)

- **B**: ~250-350 Swift (model wrapper + threshold/decode/disjoint-set/calipers/quad-order +
  rotated polygon IoU shared with the gate) + ~150 Python (mask export in `detdata.py`, training
  loop beside `train.py`'s idiom, MPS device line) + ~60 Swift/Python gate twin. No C target.
- **C1**: B's Swift minus the mask decode plus ~200 (anchor generation, eq. 2 decode, cascaded
  NMS) + the Python/Swift anchor-parity test suite (the silent-mismatch trap, C1's own fence).
- **C2**: ~150 Swift (raw-output decode + rotated NMS) + training config; plus the licence file
  question, which is not code.
- **A**: 0 (shipped).
- **D/E**: > 1 000 Swift + MIL rewrites of custom ops - not recommended partly for this reason.

## 8. Findings handed off (found, not fixed - this note is read-only)

1. **The row's TextBoxes++ citation needs its id fixed when briefed**: the quadrilateral paper is
   arXiv:1801.02765 (TIP 27, 2018); arXiv:1611.06779 is the 2017 horizontal-box TextBoxes (AAAI
   2017). The row flagged this itself; this note confirms it by fetch (§1). Owner: the PU.76 row
   text / spike brief.
2. **A citation error the row did NOT flag: RRPN's venue is IEEE Transactions on Multimedia
   20(11):3111-3122, 2018 - not TPAMI** (arXiv `journal_ref` + DOI 10.1109/TMM.2018.2818020, §1).
   Same class of defect as the flagged one (a method wearing the wrong paper's authority). Owner:
   the row text / spike brief.
3. **The row's precondition number ("hand quads agree at IoU 0.75-0.79") is the tracker-vs-hand
   agreement**, not hand-vs-hand. The hand-vs-hand numbers this note measured (§5.4): still
   re-frames median polygon IoU **0.745, 45 % [34.6, 56.6] below 0.7** (n = 75); in-session frame
   nudges median 0.901 (n = 620); anchors are verbatim copies of verified-frame windows (854/854 at
   IoU 1.000) and are not independent evidence. The "labels re-pinned under one rule" gate step
   should name the 75-row still population as its target and F6 as its check. Owner: the spike brief.
4. **Tracking anchors being verbatim frame-window copies** also means `detdata.py`'s verified-frame
   pool and the anchor pool are the same boxes; any claim of "two label sources agreeing" over
   those frames is vacuous. Owner: PU.66's follow-ups / PU.82's pool reasoning (the classifier's
   hand-box pool has the same shape).
5. **heldout has no hand row past 12 deg (0/252 windows; max 8.7 deg)** - the tilted population is
   train (13 stills) and heldout2 (frozen; may be reported, may not select - `detdata.py:152-156`).
   PU.65's "20 stills past 12 deg" arm was reader-side runtime angles with no committed list
   (PU.67 note `:447`). Any PU.76/PU.67 gate citing a tilted arm must rebuild and name it (FHT
   angle over detector rows is now the instrument). Owner: the spike brief and PU.67's reopen.
6. **The brief's context floors are stale** (45/45, 112/112, 124/117): at HEAD `2050a5d3` the live
   floor is **47/47** (`PumpPhotoGate.swift:86,91`) and the annotated floor **118** (HEAD test
   `:30`), with PU.74's uncommitted working tree at 123. Quoting 45/45 in the spike brief would
   repeat the PU.67 "54/54" mistake the HANDOVER already lists as a memory
   ("score-with-the-corpus-scorer"). Owner: the orchestrator (spike brief).
7. **The apportionment's absolute numbers move with the law**: the row's "89 at 0.944 / 111 at
   0.991" and EXTRACTION's "oracle 108, detector boxes 45" are 2026-09-23-law numbers; PU.78
   (exact close) and PU.74 (currency conventions) already moved the annotated tier 112 -> 118 ->
   (working tree) 123. The spike must RE-RUN `PumpApportionmentTests` at its own commit rather
   than compare against the remembered -33; the delta (framing loss) is the invariant, the absolute
   arms are not. Owner: the spike brief.
8. **`test_detector_gate.py`'s ordering rule and `measure.swift`'s summary line are upright-IoU
   only**; the row's "gated in rotated-box IoU (decision 10 restated in those terms before the
   first candidate)" needs the twins named in §5.6 built BEFORE any candidate trains - including
   re-scoring the shipped detector in the rotated metric as the baseline (F1). Owner: the spike's
   first work item.
9. **`swift build -c release --product pump-read` fails as written in PU.75's brief**
   (`agents/briefs/PU.75.md:29`): `PumpReadTool/main.swift:17`'s `@testable import` needs
   `-Xswiftc -enable-testing` in the release configuration (measured: plain `-c release` exits 1;
   with the flag it builds, §7.1). Also `ios/.build/opt/debug/pump-read` is a DEBUG-configuration
   binary despite the "opt" scratch name - timings taken with it are not Release numbers. Owner:
   PU.75's brief / whoever times next.
10. **`train.py:204` selects `cuda`-or-`cpu` only** - no MPS. Any PyTorch training spike on this
    Mac (B or C1) runs CPU-speed unless the device line grows MPS; that is tooling, not method,
    but it multiplies the spike's wall-clock (PixelLink-class schedule at batch 24 was 7-8 h on
    3x Titan X). Owner: the spike build.
11. **The verified-frame pool grew 60 -> 275** (owner's 2026-09-24 session, commit `22559705`) -
    PU.66 round 3's "more owner-verified frames are the lever" is now partly banked, and PU.82
    (classifier on the hand-box pool) cites "273 train frames owner-verified" - the same pool at
    the same date. Whatever PU.76 trains on, PU.82's pending decision should be read against the
    same counts so the two rows do not diverge. Owner: PU.82's call (already with the owner per
    HANDOVER) and the spike brief.
12. **Untracked scratch in the fixtures dir**: `Spike/ReceiptSpike/fixtures/pump-live/corpus.sqlite3`
    (an annotator redirect copy, `corpus_db.py:56-58`'s `PUMP_ANNOTATE_DB` pattern) and a growing
    `fixtures/arrival/` (PU.67 note §7-2 already flagged arrival's growth). Neither touched; both
    are corpus-intake business, not this row's. Owner: the corpus run.

*The second opinion (Codex `gpt-6-sol`, per the row's routing) should be asked specifically: does
the ranking survive if PixelLink's Tab. 4 data-efficiency argument does NOT transfer from scene
text to high-contrast seven-segment rows (where "texture" is nearly binary and a simpler
segmentation may suffice), and is C2's one-day DOTA-pretrained probe worth running BEFORE B's
multi-day from-scratch spike as a pure existence check for "oriented boxes beat framing loss
here"? This note's answer to the second question is yes-if-free (it is hours, internal-only, and
its negative result is uninformative while its positive one de-risks C1) - recorded here so the
second opinion has something to disagree with.*
