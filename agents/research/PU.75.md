# PU.75 research note - batched predictions, vectorised warps, and the Vision pass only when it decides

*RESEARCH-TO-CODE run for `PU.75` (`docs/TASKS.md:1078`). Product owner, 2026-09-23: "review the
published research to apply it into the code, instead of coming up with our own solution."
Populations and HEAD facts are at commit `c22d0217` (HEAD when this note was written; a concurrent
build holds uncommitted changes to `PumpReadingLaw.swift`, `PumpPhotoGate.swift` - `readerCommitted`
45 -> 47 in the working tree, not at HEAD - and `PumpReaderPipelineTests.swift`, so the implementer
re-counts and re-baselines at their own build commit, §5). Evidence rule: every claim cites a
fetched paper/doc section, a `file:line`, or a number measured in this run; inference is labelled.
Precisions carry Wilson 95% intervals per PU.68's instrument (`agents/research/PU.68.md` §2.1,
BCD eq. 4). Scratch artifacts of this run live in `/tmp/pu75/` (volatile, named at each use):
`count.py`, `batchprobe.swift`, `vimageprobe.swift`, `vimageprobe2.swift`, `quantize_spike.py`,
fetched paper/doc texts. The only repo write is this file. No repo build was run; the pre-existing
`ios/.build/release/pump-read` was used for timings (provenance in §5.1).*

**Policy note, recorded because HEAD moved mid-run.** Commit `c22d0217` (owner, 2026-09-24,
`docs/DEVELOPMENT-TIMELINE.md` -> "A research note only where a row changes a method") reclassified
PU.75 as an **engineering row** that names its sources in the brief line rather than gating on a
full note. This run was dispatched before that commit and completed anyway; the note is submitted
as the sources record, and its §0 findings (two of which contradict premises of the row text) are
input to the build brief and to `REVIEW-PU-COMPLETENESS.md`, which still runs on every row.

## 0. Headline findings, first because two of them change what the row can promise

1. **Batched predictions work on the shipped classifier as-is, and measured bitwise-identical on
   this Mac.** `MLModel.predictions(fromBatch:)` over an `MLArrayBatchProvider` of 5 succeeded
   against the shipped fixed-shape (1,3,48,32) `PumpSegments.mlpackage` - no re-export needed -
   and its 5x8 outputs equalled the sequential `prediction(from:)` outputs exactly (max |diff|
   0.0), at 0.14 ms vs 0.30 ms per 5 predictions (`/tmp/pu75/batchprobe.swift`, `swiftc -O`, under
   machine load ~4.3). Device (ANE) numerics are NOT covered by this measurement or by any Apple
   doc statement; the corpus-identity check (§5.3) remains the gate.
2. **The cited vImage primitives cannot reproduce our pixel loops exactly, and one cannot express
   our hottest warp at all.** Measured: `vImageScale_ARGB8888` (default and
   `kvImageHighQualityResampling`) differs from both `PumpReader.resample`'s centred bilinear and
   `downscaleRGB`'s nearest sampling on random-noise probes (4478/4608 and 57354/57600 channel
   values differ, §2.2). Verified in the iOS 27 SDK headers: the vImage geometry set is
   Scale/Rotate/AffineWarp(D/CG)/Horizontal+VerticalShear - **affine only**; there is no
   `vImagePiecewiseAffineWarp` and no projective warp, while `warpToStrip` is a homography
   (`PumpQuadWarp.swift:165-195`, h[6]/h[7] generally nonzero). So the row's "vImage warps" half
   is **not a pure speed change**: every adoptable primitive is a resampling change whose pixels
   move, and it stands or falls on the committed-cells identity gate (§5.3, adaptation A4). The
   exact-projective alternatives (Core Image `CIPerspectiveTransform`, Metal, a shear
   decomposition) are departures needing the owner's OK (A5), not licensed here.
3. **Lazy `textLineCount` is the one change that moves no pixel.** `fastVerdict` has ignored its
   `textLines` argument since PU.63 (`PumpDisplayCapture.swift:129-135`), and `decideAt` computes
   the count before it (:196). Measured Release cost of the pass: 6-25 ms on pump stills inside a
   14-48 ms decision, 31-36 ms on receipts (§5.1). Its only observable output is the diagnostic
   field `Detection.textLines`, whose five consumers are named in M1; the fast-path value becomes
   a "not measured" sentinel (A1).
4. **The detector-compression half has no published post-training path that works on the shipped
   model today, and the row's question ("expected to hold decision 10's tight-IoU gate?") has no
   published answer - the honest expectation is a spike verdict, not a prediction.** Measured in
   this run (§2.5, §5.4): the shipped `DigitRows.mlmodel` is a legacy `pipeline`
   [neuralNetwork, nonMaximumSuppression] with every conv weight in `float16Value`
   (31,639,392 fp16 bytes, ~15.8M parameters). `ct.optimize.coreml` (linear quantization,
   palettization) **rejects non-mlprogram models by design** (coremltools 9.0
   `models/utils.py:1316-1329`, message read from source). The legacy tool it points to
   (`neural_network.quantization_utils.quantize_weights`) **crashes** on this model in ct 9.0's
   `_conv_bn_fusion` (`optimization_utils.py:125-166`; TypeError reproduced verbatim, §5.4) - the
   failure is a ct 9.0 conv-BN fusion bug (gamma reshaped to (C,1) then `[:, None]` -> a (C,C)
   bias), **not** the "anchor constants" REPORT.md:508 records; that older diagnosis does not
   reproduce. With the fusion monkeypatched (scratch), the tool completes but the output **fails
   Core ML compilation** ("Convolution layer 'conv0_fwd' has invalid weights/bias fields") and is
   **larger than the original** (47,420,709 B vs 31,751,101 B: the fp16 weights are retained
   beside the added quantization payload). Published accuracy evidence (§2.3-§2.5) exists only
   for QAT 8-bit detection (Jacob Table 4.4: -0.4 COCO mAP **with training-time quantization**),
   post-training classification top-1 (coremltools: -0.04...-0.08), and Jacob §3's explicit
   warning that post-training quantization "leads to significant accuracy drops for small models"
   - nothing measures median IoU on a Create ML row detector. Expectation, labelled: int8
   weight-only is a coin flip against decision 10's "hold or rise" on median IoU and recall@0.7;
   sub-8-bit should be expected to FAIL without QAT (which Create ML does not expose); and the
   spike's first deliverable is a model that loads at all.

## 1. The citations, checked

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Apple Core ML batch prediction: `MLModel.predictions(fromBatch:)` / `MLBatchProvider` | Apple docs JSON API fetched for both symbols plus `MLArrayBatchProvider` and `predictions(from:options:)`. Declarations: `func predictions(fromBatch inputBatch: any MLBatchProvider) throws -> any MLBatchProvider`; discussion is one sentence ("Use this method to make more than one prediction at one time."). `MLBatchProvider` = protocol with `features(at:)` + `count`; `MLArrayBatchProvider` = "convenience wrapper ... an array of feature providers or a dictionary of arrays of feature values". Availability: iOS 12.0+ (all four pages) - inside our iOS 18.0 floor. | **Correct as cited.** The docs carry **no performance claim and no numerics guarantee**; both come from our own probe (§2.1). |
| Accelerate vImage: `vImageScale_*`, `vImageAffineWarp_*` | Apple docs JSON fetched: `vImageScale_ARGB8888(_:_:_:_:)` (iOS 5.0+) - discussion covers temp buffers, non-premultiplied advice, flags incl. `kvImageHighQualityResampling`; the default filter is **not named**. `vImageAffineWarp_ARGB8888(_:_:_:_:_:_:)` (iOS 5.0+) - "Applies a single-precision **affine** transformation ... 3 x 3 affine transformation matrix. The coordinate space places the origin at the bottom-left corner." Cross-checked against the iOS 27 SDK headers (`Geometry.h:209` scale, `:283` affine warp; full warp-family enumeration in §2.2). | **Correct as cited, and insufficient for the row's warp half**: affine cannot express `warpToStrip`'s homography (§0.2). |
| Howard et al., *Searching for MobileNetV3*, ICCV 2019, arXiv:1905.02244 | arXiv abs page fetched: title exact; authors Andrew Howard, Mark Sandler, Grace Chu, Liang-Chieh Chen, Bo Chen, Mingxing Tan, Weijun Wang, Yukun Zhu, Ruoming Pang, Vijay Vasudevan, Quoc V. Le, Hartwig Adam; Comments field "ICCV 2019"; v1 6 May 2019, v5 20 Nov 2019. Full text read via ar5iv (`/tmp/pu75/mnv3.txt`): §5.2 h-swish, §5.3 SE, Tables 1-6, §6.3 detection. | **Correct as cited.** Full text read; method in §2.3. |
| Jacob et al., *Quantization and Training of Neural Networks for Efficient Integer-Arithmetic-Only Inference*, CVPR 2018, arXiv:1712.05877 | arXiv abs page fetched: title exact; authors Benoit Jacob, Skirmantas Kligys, Bo Chen, Menglong Zhu, Matthew Tang, Andrew Howard, Hartwig Adam, Dmitry Kalenichenko; submitted 15 Dec 2017; **the abs page carries no venue comment**, so the venue was verified separately: CVF Open Access page fetched (`openaccess.thecvf.com/content_cvpr_2018/.../Jacob_Quantization_and_Training_CVPR_2018_paper.html`) - title and author list match, CVPR 2018 proceedings. Full text read via ar5iv (`/tmp/pu75/jacob.txt`): §2.1-§2.4 eqs. (1)-(11), §3 eq. (12)-Algorithm 1, §4 Tables 4.1-4.6. | **Correct as cited** (venue confirmed via CVF, not arXiv). Full text read; method in §2.4. |
| Core ML Tools' weight quantization/palettization docs | `apple.github.io/coremltools/docs-guides` fetched: Quantization Overview (linear/affine equations, 8- and 4-bit weights, 8-bit activations, symmetric default, per_tensor/per_channel/per_block, NE int8-int8 note), Quantization Performance (post-training W8 tables), Palettization Overview (N in {1,2,3,4,6,8}, per_grouped_channel, **mlprogram-only, iOS16+**), Palettization Performance (K-Means post-training at 6/8 bit; Differentiable K-Means - a training-time method - at 2/4 bit; CenterNet detection table), Flexible Input Shapes (EnumeratedShapes / RangeDim recipes). coremltools **source** in `ml/pump-reader/.venv` (9.0) read where the docs are silent (§2.5). | **Correct as cited**, with the finding that the maintained toolchain excludes our detector's model type (§0.4). |

No misattribution found in the row's citation list. The row text itself contains one code-fact
drift: it cites `PumpDisplayCapture.swift:195` for the `textLineCount` call; at HEAD the call is
`:196` (`:195` is the `trace?.begin` line). Immaterial; corrected line numbers are used below.

## 2. The methods as published

### 2.1 Core ML batch prediction (Apple docs) + what this run measured

Published surface (§1): one call takes an `MLBatchProvider` (count + `features(at:)`) and returns
an `MLBatchProvider` of outputs, one per input. Apple publishes no latency claim, no requirement
that the model declare a flexible batch dimension, and no statement about output numerics under
batching. `MLArrayBatchProvider` wraps an array of providers.

Measured in this run (`/tmp/pu75/batchprobe.swift`, `swiftc -O`, macOS, shipped
`ios/App/Resources/PumpSegments.mlpackage` compiled at probe start, machine load ~4.3; 200 timed
rounds after warm-up):

| workload | result |
|---|---|
| 5 sequential `prediction(from:)` (one per TTA crop) | 0.30 ms per 5 |
| 5 batched `predictions(fromBatch:)` | **0.14 ms per 5** (2.1x) |
| 40 batched (a full 8-cell window x 5 crops) | 1.05 ms (0.026 ms/pred vs 0.06 sequential) |
| output equality, 5x8 segment probabilities | **max abs diff 0.0** vs sequential |
| model input shape | fixed `(1,3,48,32)` (`export.py:60-66`) - batching succeeded **without** re-export |

Inference, labelled: the 2.1x is per-call-overhead amortisation on a tiny model (~24k parameters;
`PumpSegments.mlpackage`'s weight.bin is 48,768 B of fp16); the compute itself is negligible, so
the win should be similar or larger on A14 where per-call overhead is relatively bigger -
unmeasured.

### 2.2 vImage geometry primitives, as published and as measured

Published set, enumerated from the iOS 27 SDK headers (`vImage.framework/Headers/`, fetched this
run): `vImageScale_<fmt>` (`Geometry.h:209`; discussion: multiple-pass, temp buffer, acceptable
flags `kvImageEdgeExtend` (default edging), `kvImageDoNotTile`, `kvImageHighQualityResampling`,
`kvImageNoFlags`; "higher quality but a slower resampling filter" for the HQ flag; the default
filter is not named), `vImageAffineWarp_<fmt>` (`:283`; 3x3 **affine** matrix, bottom-left
origin), `vImageAffineWarpD_/CG_` variants, `vImageRotate_`, `vImageHorizontalShear_/
vImageVerticalShear_` (bilinear displacement between two edge profiles), `vImagePiecewiseGamma_*`
and `vImagePiecewisePolynomial_*` (pixel-value mappings, not geometric warps). A grep for
`PiecewiseAffineWarp`/`GridMesh` over the iOS 27 SDK vImage headers returns **nothing** - the
grid-mesh piecewise affine warp is not in this SDK. `Geometry.h`'s own scale comment names
`vImageWarp_<fmt>` and the shears as the lower-level alternatives; `vImageWarp` is not declared
in this SDK either.

Conversion/colour primitives for `grayscale()` (`PumpQuadWarp.swift:23-32`, luma
(0.299, 0.587, 0.114)/255 into Float): `vImageMatrixMultiply_ARGB8888ToPlanar8` exists (8-bit
output - wrong type), `vImageConvert_ARGB8888toPlanarF` exists (per-channel Float planes, no
mixing); a Float luma needs convert + weighted plane sum (vDSP), whose float addition order is
not published to match our scalar loop's.

Measured exactness (`/tmp/pu75/vimageprobe{,2}.swift`, `swiftc -O`, deterministic random-noise
sources - the worst case for any filter difference, stated so the numbers are not overread):

| comparison | differing channel values | max abs diff |
|---|---|---|
| `PumpReader.resample` math (centred bilinear, clamp) vs crop + `vImageScale_ARGB8888` default flags, integer rect 37x53 -> 32x48 | 4478 / 4608 | 68 |
| same vs `kvImageHighQualityResampling` | 4511 / 4608 | 79 |
| `downscaleRGB` nearest math vs `vImageScale_ARGB8888` default, 400x300 -> 160x120 | 57354 / 57600 | 197 |

Conclusion (measured, then inference labelled): **no published vImage primitive reproduces any of
our four sampling loops bit-exactly**; `vImageScale` is an interpolating filter (not nearest) with
an unnamed default kernel whose grid alignment differs from our centred bilinear. On natural
images the deltas will be far smaller than on noise (inference), but "smaller" is not "zero", and
our consumers are threshold rules (the slicer's 0.15 contrast mask, band edges; the classifier's
margins; the law's nat windows) - so each replacement is a resampling change that must pass the
corpus identity gate (§5.3) or be refused. The projective `warpToStrip` has **no** vImage
candidate at all (§0.2); `vImageAffineWarp_ARGB8888` - already used exactly once in the tree, for
the affine levelling turn (`PumpRowDeskew.swift:317`) - stays the correct primitive for what it
does.

### 2.3 MobileNetV3 - Howard et al. 2019, as fetched

Design components relevant to a small detector: h-swish, §5.2: `h-swish[x] = x * ReLU6(x+3)/6`
(hard sigmoid analogue; the paper's stated motivations include being "quantization-friendly" -
"eliminates potential numerical precision loss caused by different implementations of the
approximate sigmoid"), used only in the second half of the network; squeeze-and-excite, §5.3:
bottleneck fixed at 1/4 of the expansion layer's channels. Sizes and speeds, Table 3 (single big
core, batch 1, Pixel phones): V3-Large 1.0 = 75.2% top-1, 219M MAdds, **5.4M params**, 51/61/44
ms on P-1/P-2/P-3; V3-Small 1.0 = 67.4%, 56M MAdds, **2.5M params**, 15.8/19.4/14.4 ms.
Quantized performance, Table 4 (the paper gives **no method detail** for these numbers - no
quantization section text was found in the fetched body; labelled: the recipe behind Table 4 is
not stated in the paper): V3-Large 73.8% top-1 (-1.4 vs float), V3-Small 64.9% (-2.5), V2 70.9%
(-1.1), with equal-or-better latencies (P-1: 44 vs 51 ms Large). Detection, §6.3 Table 6
(SSDLite, COCO test): V3 = 22.0 mAP @ 137 ms, 4.97M params; V3 with the C4-C5 channel halving
(dagger) = 22.0 @ 119 ms, **3.22M params**; V3-Small-dagger = 16.1 @ 43 ms, 1.77M; V2 = 22.1 @
162 ms, 4.3M.

Relevance to this row, bounded: our detector is ~15.8M params (fp16 bytes / 2, §5.4) against
MobileNetV3-class SSDLite detectors of 1.8-5.0M - so the paper says a **replacement** detector
could be 3-8x smaller at COCO-grade quality. But replacement means training, which is PU.76's row
(an oriented detector, its own papers); PU.75's detector half is **compression of the frozen
Create ML export**, to which MobileNetV3 contributes only the expectation that small mobile
detectors tolerate 8-bit quantization at a ~1-2.5 point classification cost (Table 4) and that
detection mAP tolerates it at ~0.1-0.4 absolute **when trained with it** (§2.4).

### 2.4 Quantization - Jacob et al. 2018, as fetched

Scheme, §2.1 eq. (1): `r = S(q - Z)`, one (S, Z) per array; 8-bit `q` (uint8 in their
implementation), biases int32 with `S_bias = S1*S2, Z_bias = 0` (§2.4 eq. 11). Integer-only
inference, §2.2 eqs. (4)-(7): `q3 = Z3 + M * sum (q1 - Z1)(q2 - Z2)` with `M = S1*S2/S3`
normalised as `M = 2^-n * M0`, `M0 in [0.5, 1)` held in fixed point; §2.3 eq. (7)-(8) factors the
zero-points into O(N^2) row/column sums so the core stays an int8->int32 GEMM (eq. 9-10).
Simulated-quantization training, §3 eq. (12): `q(r;a,b,n) = round((clamp(r;a,b) - a)/s)*s + a`,
`s(a,b,n) = (b-a)/(n-1)`, `n = 256` for 8-bit; weight range `[min w, max w]` nudged so 0 is
exact, activation ranges by EMA over training with quantization **delayed** 50k-2M steps (§3.1;
COCO detection used a 500k-step delay, §4.2.2); batch-norm folded before weight quantization
(§3.2 eq. 14). **The post-training warning, §3 preamble, quoted:** training in float and then
quantizing weights "works sufficiently well for large models ... but leads to significant accuracy
drops for small models", with two named failure modes: >100x weight-range differences across
output channels of one layer, and outlier weights.

Measured by them: ResNet 50/100/150 8-bit QAT within 2% of float (Table 4.1: 74.9/76.6/76.7 vs
76.4/78.0/78.8); InceptionV3 8-bit 75.4 vs 78.4 float (Table 4.3); **COCO detection** (SSD
MobileNetV1, QAT 8-bit, Table 4.4): mAP 22.1 -> 21.7 ("-1.8% relative"), latency big core 370 ->
272 ms, LITTLE 778 -> 687 ms; face detection (§4.2.3): ~2x latency cut at ~2% AP cost. Note what
every one of these numbers required: **quantization present during training**. None of their
tables is a post-training result on a frozen small model - that is precisely the regime they warn
about and precisely our situation with a Create ML export.

### 2.5 Core ML Tools compression, as published and as its source states

Docs (fetched, §1): linear quantization is the same affine family as Jacob eq. (1)
(`w_q = clip(round(w/scale) + zero_point)`), symmetric by default, weights at 8 or 4 bits,
granularities per_tensor/per_channel/per_block, activations 8-bit with calibration data;
palettization is k-means LUT clustering at N in {1,2,3,4,6,8} bits, per_grouped_channel on
iOS18+, and is **available only for mlprogram models** (Palettization Overview, "Feature
Availability"). Published post-training results (iPhone 14 Pro, iOS 17, Xcode 15): W8 linear
post-training gives compression 1.92-1.99x vs fp16 at -0.04...-0.08 top-1 (MobileNetV2, ResNet50)
and near-zero latency change (0.48 -> 0.45 ms); palettization post-training (K-Means) is published
at 6 and 8 bit only (compression 1.93-2.65x); 2/4-bit palettization used **Differentiable
K-Means, a training-time method**; the one detection model in their tables (CenterNet/ResNet34)
shows the same shape: 4-bit 3.94x compression, 6.85 -> 6.67 ms, method = training-time.
Activation+weight int8 buys Neural Engine compute only on A17 Pro/M4 and newer (Quantization
Performance) - **not on iPhone 12's A14**, where weight-only int8 is a size/memory-bandwidth win,
not a compute win.

Source facts read this run (coremltools 9.0 in `ml/pump-reader/.venv`): `ct.optimize.coreml.*`
raises `TypeError` for model types `neuralNetwork*`/`pipeline*`, directing the user to
`coremltools.models.neural_network.quantization_utils.quantize_weights` (`models/utils.py:1316-
1329`); that legacy tool exists in 9.0 (`quantize_weights(model, nbits, quantization_mode=
'linear'|'kmeans_lut'|...)`); `ct.utils.quantize_weights` (the older public alias) is **gone**.
Our detector is a `pipeline` (verified: `[neuralNetwork(raw_confidence, raw_coordinates),
nonMaximumSuppression]`), so the maintained toolchain refuses it and the legacy one is the only
published candidate - and it fails (§0.4, §5.4).

## 3. The mapping onto this code

All line numbers are HEAD `c22d0217`; the concurrent working-tree build touches none of the six
seam files named by the row (verified: `git diff HEAD --stat` empty for all of them).

**M1. Lazy text-line pass.** `PumpDisplayCapture.decideAt` (`PumpDisplayCapture.swift:192-229`):
move `let textLines = textLineCount(upright)` (:196) into the slow branch, after `fastVerdict`
(:200) returns false; the fast path's `detectorDetection(rows:textLines:)` (:201, :237-249) takes
the sentinel (A1: `-1`, "not measured" - `0` is a real count on this corpus, PU.63 measured pumps
at 0-58 lines, so `0` would lie). `fastVerdict`'s `textLines` parameter (:135) stays in the
signature (its doc comment already says it "no longer decides"; `PreviewGuidance.swift:30` already
passes 0). The slow path is untouched: `textLines` computed before `makeDetection` (:218) exactly
as today, `maximumTextLines` (:83) still guards it (PU.63). Consumers of the changed field, all
diagnostic, none gating (verified by search): `CapturePipeline.swift:67` -> `CaptureClassify`
log's `textLines` field (`LogEvents.swift:575-581`; a count - loggable, hard rule 12);
`CaptureLabRunner.swift:153` (run.json column); `PumpReadTool/main.swift:342` and
`TraceServe.swift:187` (annotator replies); `PumpDisplayCaptureTests.swift:72,:88` (prints only -
no test asserts the field's value on a fast-path detection). Saves, per fast-decided frame: the
1600-px nearest downscale (`textLineCount` :269-273 -> `downscaleRGB`) plus a full
`VNRecognizeTextRequest(.fast)` (`PumpVisionProposer.swift:64-73`). Retires: nothing.

**M2. Batched predictions.** Seam: `PumpSegmentsModel.probabilities(cell:)`
(`PumpSegmentsModel.swift:41-52`; the single `model.prediction(from:)` is :47) and its caller
`PumpReader.averaged(model:crops:)` (`PumpReader.swift:580-587`, the 5-crop loop). Add a batched
sibling: build the 5 (or per-window 40) `MLDictionaryFeatureProvider`s exactly as :44-46 does
today - the per-crop `CVPixelBuffer` copy (:83-108) is unchanged - wrap in `MLArrayBatchProvider`,
one `predictions(fromBatch:)`, read the 8 probabilities per output row in input order, average as
:581-586 does. Two call sites: the read's TTA (`PumpReader.swift:223`, 5 crops/cell;
`augmentationOffsets` :568-570 unchanged) and the verifier's margin pass (:521-524, one crop per
cell - batch the cells of a candidate into one call; the margin feeds `Verdict.meanMargin` and,
for Vision-sourced rows on the slow path, `displayRows`' `classificationMinimumMargin` check at
`PumpDisplayCapture.swift:281-290`, so identity of probabilities matters there too). Inputs and
outputs in our types are unchanged: `[PumpRGBImage]` in, `[Double]`x8 per crop out. The measured
Mac probe (§2.1) says the shipped fixed-shape mlpackage accepts the batch and returns bitwise-equal
probabilities; if a device refuses or diverges, adaptation A2 (re-export with a flexible batch via
`export.py:57-70`, `ct.EnumeratedShapes` or `ct.RangeDim` per the Flexible Input Shapes doc) is
the published remedy - same checkpoint weights, identity-gated like everything else. Retires:
nothing (the 5-crop TTA stays; only the call count changes).

**M3. vImage replacements - each a measured resampling change, not a pure speed change (§0.2).**
Loops in scope, hottest first (Release stage evidence in §5.1):
- `warpToStrip` (`PumpQuadWarp.swift:165-195` + `sampleBilinear` :254-277): projective; **no
  published vImage primitive** (§2.2). Stays as-is under this row unless the owner OKs an A5
  alternative (CI/Metal/other). This is the dominant cost of the receipts' slow-path `verify`
  (48 candidates x 1-2 warps each, `PumpReader.swift:142-155`; measured verify 303-507 ms on two
  receipts, §5.1) and of every pump read (one warp per window, `PumpReader.swift:204`).
- `resample` (`PumpReader.swift:590-618`): crop + scale to 32x48; candidate = sub-buffer copy +
  `vImageScale_ARGB8888`. Measured NOT pixel-identical (§2.2). Per-call size is tiny (1536 px),
  so the Release win is small even before the identity risk; inference, labelled: deprioritise.
- `downscaleRGB` (`PumpPanelLocator.swift:161-176`, nearest): candidate = `vImageScale_ARGB8888`;
  measured NOT identical, and its output feeds Vision counts (`textLineCount`, `locate`'s 1600-px
  frame :31) - so a pixel change here can move `textLines`, slow-path verdicts and candidate quads
  on receipts. Release cost today is ~4 ms (REPORT.md:1125-1126) - the Debug-only 337 ms win was
  PU.38's; inference: low value on device, non-zero identity risk.
- `downscaleGray` (`:178-194`) and `grayscale` (`PumpQuadWarp.swift:23-32`): same story via
  `vImageConvert_ARGB8888toPlanarF` + vDSP; float-op order not published to match; feeds the
  classical locator and the slicer's contrast mask - identity-gated or refused.
- `rotatedRGB` (`PumpPanelLocator.swift:48-66`): exact permutation, no interpolation involved;
  vImage offers only interpolating rotate. A CGContext draw under a 90-degree CTM is exact in
  practice (inference, labelled - CG publishes no pixel-exactness guarantee); runs up to 3x per
  photo only in the orientation search (`PumpReader.swift:356-362`), i.e. on refusals.
Precedent already in the tree: `PumpRowDeskew.levelled` uses `vImageAffineWarp_ARGB8888` for the
affine levelling turn (`PumpRowDeskew.swift:307-319`) - the one place the cited primitive is the
right one. Retires: nothing.

**M4. Detector-size spike (report only; ships under its own row if it lands).** Object:
`ios/App/Resources/DigitRows.mlmodel` (31,751,101 B; identical byte-for-byte to
`ml/pump-reader/.out/det/DigitRows.mlmodel`, verified with `cmp`). Structure verified this run
(coremltools 9.0): `pipeline` = [`neuralNetwork` with 9 conv layers, all weights in
`float16Value` totalling 31,639,392 B (~15.8M params), `nonMaximumSuppression`]. Published
compression routes and their status for this object:
1. `ct.optimize.coreml.linear_quantize_weights` / `palettize_weights` - **refuses the model type**
   (`models/utils.py:1316-1329`, source-read).
2. Legacy `neural_network.quantization_utils.quantize_weights` - the tool ct itself points to:
   **crashes** unpatched (ct 9.0 `_conv_bn_fusion` bug, traceback captured verbatim in §5.4), and
   **produces an unloadable, larger model** when the crash is patched around (Core ML validator
   rejects `conv0_fwd`; 47,420,709 B). Not shippable as-is; fixing it is toolchain work (options
   in A6), and REPORT.md:508's "trips on its anchor constants" needs correcting to the reproduced
   failure (docs drift; the spike row owns the fix).
3. mlprogram conversion then route 1 - no public ct 9.0 converter accepts a legacy pipeline
   (`ct.convert` demands a source framework; the internal `_convert_model_spec_to_pymil_prog`
   raises the same mlprogram-only TypeError). A Create ML re-export does not produce mlprogram
   (inference from the shipped artifact's spec).
4. A MobileNetV3-class replacement (§2.3) - a **training** row (PU.76's territory), out of scope
   here; recorded so the spike report can cite the 3-8x size headroom as the reason a replacement
   row may be worth more than a compression row.
The gate for any candidate that does load: decision 10's PU.57 amendment
(`docs/EXTRACTION.md:985-988`): median IoU and recall@IoU 0.7 hold or rise, false rows/photo rises
by at most 0.05; measured by `ml/pump-reader/detector/measure.swift <model>
ml/pump-reader/.out/det/heldout 0.3` (usage at `measure.swift:8`), against a **same-day control**
(A7). Retires: nothing in code; on a PASS the spike report may recommend the owner retire the
"owner's call before ship" flag on the 30.3 MiB bundle (Qwen review §2.6 item 4).

## 4. Adaptations, named and justified (the fence)

Each is a departure from what the sources publish, or a decision the sources leave open.
**Anything the implementer adds beyond this list needs the product owner's OK.**

- **A1. `Detection.textLines = -1` sentinel on the fast path.** Apple/Vision publish nothing
  here; today the field carries a real count the decision ignores (PU.63). We: keep the field,
  `-1` = "not measured on the fast path". Why not `0`: PU.63 measured pump faces at 0-58 real
  lines, so `0` would misreport. Consequence: `capture.classify` log lines, Capture Lab's
  `textLines` column and the annotator's decision payload show `-1` on fast frames - a
  diagnostics-contract change the docs (`docs/EXTRACTION.md` decision 10 PU.63 text,
  `docs/LOGGING.md` field list if it names the field) must record in the same change.
- **A2. Batching a fixed-shape model without re-export; re-export only if the device needs it.**
  Apple docs neither promise nor forbid this; the Mac probe shows it works and is bitwise equal
  (§2.1). coremltools' published best practice for flexible shapes is to declare them at
  conversion (Flexible Input Shapes: "the best practice is to specify a flexible input shape when
  converting"; `flexible_shape_utils` is neuralnetwork-only). We: try zero-change batching first
  (no model churn = no re-export risk); if any device arm refuses or diverges, re-export from the
  **same checkpoint** with `EnumeratedShapes` {(1,3,48,32), (5,3,48,32)} (the doc's
  performance-preferred form, and 5 is the TTA count) via `export.py`, identity-gated. A retrain
  is never part of this row.
- **A3. Assuming batch numerics from a Mac probe, gated by corpus identity.** No published
  guarantee exists (§2.1); ANE execution on A14 may reorder arithmetic. The gate is §5.3's
  identity check on every arm; a single differing committed cell refuses the batch half.
- **A4. vImage adoption per-primitive, identity-gated, default-refuse.** The published primitives
  are not pixel-exact against our loops (§2.2, measured). We: adopt a replacement only when the
  full §5.3 identity battery is byte-equal with it; otherwise keep the Swift loop and say so in
  the row's report. This departs from the row's framing ("a speed change moves no reading") by
  making the vImage half conditional rather than assumed.
- **A5. No projective-warp substitute under this row.** `CIPerspectiveTransform` (Core Image),
  a Metal kernel, or a self-built piecewise-affine grid are all *inventions relative to the cited
  sources* (vImage has no such primitive, §2.2) and each carries its own colour-management /
  edge-extrapolation conventions. Building any of them needs the owner's OK; this note does not
  license them.
- **A6. The detector spike may write scratch toolchain workarounds but ships none.** This run's
  monkeypatch of `_conv_bn_fusion` (recorded in full in `/tmp/pu75/quantize_spike.py`) exists to
  measure how far the published path gets; it is not a shippable fix. A spike row that wants a
  loadable quantized detector must either patch coremltools properly (upstreamable), or
  dequantize fp16 -> fp32, quantize with a maintained tool and reassemble a valid spec - each a
  named step in the spike report, each measured against the same-day control.
- **A7. Same-day control for the decision-10 gate.** PU.57 recorded shipped-detector primaries
  0.734 / 0.797 / 0.632 (2026-09-22); this run's control on the same directory measured
  0.723 / 0.796 / 0.656 (§5.4) - recall@0.7 172/238, Wilson 95% [0.663, 0.776], overlapping
  PU.57's 175/238 [0.676, 0.787], i.e. the drift is inside interval noise but outside a
  point-value "hold or rise" reading. The spike therefore re-measures the shipped model minutes
  before each candidate, in the same session, and gates against that control; remembered numbers
  never decide (PU.57's own candidate-mixup lesson).
- **A8. Latency facts are Release-only, from two named instruments.** Mac: `swift build -c
  release --product pump-read` + `timingsMs` (§5.1; the pre-existing Sep-21 release binary was
  used for this note's numbers, provenance stated there). Device: Capture Lab (`#if DEBUG`,
  PU.39) before/after in the **same build configuration** - its absolute ms are Debug numbers and
  are reported as ratios - plus, for true Release-device numbers, the shipped app's own
  `capture.classify.durationMs` / `capture.pipeline.durationMs` fields (`LogEvents.swift:575-586`,
  `CapturePipeline.swift:65-95`), which exist in Release and reach the diagnostics export. Debug
  absolutes are never latency facts (REPORT.md:1123-1126: Debug runs 7-25x).
- **A9. Domain transfer, stated rather than assumed.** The papers measure ImageNet top-1 and COCO
  mAP on Snapdragon/Pixel hardware; decision 10 gates median IoU of ~15.8M-parameter Create ML
  boxes over 238 seven-segment rows on A14/ANE. No published number transfers directly; the
  papers bound expectations (classification deltas ~0.1-2.5 points; QAT detection -0.4 mAP;
  post-training-on-small-models warned), the corpus decides.
- **A10. `heldout2` and the frozen `heldout` discipline carry over unchanged.** The identity
  battery runs on `heldout` (68) + annotated windows + the non-pump 116 + optionally reviewed
  `train`; `heldout2` (4 stills) stays unmeasured by model-scored ratchets
  (`docs/EXTRACTION.md:900-910`). A speed change may not retune any constant: `slowPathBudget`,
  `maximumTextLines`, the slicer fractions and the law's windows all keep their values; only code
  paths change.

## 5. Population, measurements of this run, expectations, falsifiers

### 5.1 Release timings on the Mac, measured in this run

Instrument: the pre-existing `ios/.build/release/pump-read` (mtime Sep 21 20:54 - built at PU.38's
commit `0cbc9b2d`, so it predates PU.63/PU.65; the seams it times - `textLineCount`, detector,
verify, read - are structurally unchanged at HEAD, and PU.63 only changed whether the fast verdict
*reads* the count, not what the count costs). Request `{}` (live path), `PUMP_REPEAT` warm-up,
`timingsMs` keys from `main.swift:260-362`. Machine load average 4.3-4.4 during the runs
(concurrent agents) - numbers are upper bounds, labelled. How to reproduce (the row's instrument):

```
cd ios && swift build -c release --product pump-read      # or use the existing binary
echo '{}' > /tmp/req.json
PUMP_REPEAT=2 .build/release/pump-read <still.jpg> --request /tmp/req.json
# reply carries timingsMs: readPhoto, detectorOnly, candidates, verify, textLines,
# appDecide, appClassifyAndRead, read, law  (main.swift:260-362)
```

| frame | appDecide | textLines | detectorOnly | verify | read | appClassifyAndRead |
|---|---|---|---|---|---|---|
| pump-032 (fast) | 48 | **25** | 3 | 38 | 24 | 105 |
| pump-092 (fast) | 14 | **6** | 5 | 55 | 23 | 90 |
| receipt-015 (slow) | 585 | 31 | 0 | 507 | 63 | 580 |
| receipt-017 (slow) | 431 | 36 | 0 | 303 | 35 | 436 |

Readings: the Vision text-line pass is **43-52% of the fast-path decision** on these two stills
(25/48, 6/14) - M1's win; on receipts the decision is verify-dominated (M3's warp loops, which
this row cannot reach exactly, §0.2) with textLines a 5-8% slice the slow path genuinely needs.
The `read` stage (23-24 ms) contains ~80 single predictions for a 16-cell photo; at the probe's
0.06 -> 0.026 ms/prediction (§2.1) batching should remove ~2-3 ms of it on Mac, more of the
`verify` stage's per-candidate margin passes. These are consistent with the row's quoted Release
ranges (decision 13-73 ms, read 112-164 ms; REPORT.md:1123-1135) and with Qwen §2.6's item list;
one Qwen §2.5 number needs correcting: it quotes "~4 ms in Release" for the whole `textLineCount`
- the 4 ms in REPORT.md:1125-1126 is the **downscale alone**; the pass measured 6-36 ms here.

On a device: nothing exists ("never timed on an iPhone", row text). Capture Lab (Settings -> About
-> Capture lab, DEBUG build; PU.39, `CaptureLabRunner.swift:100-121`) writes per-preset
`pipelineMs`, `classifyPath`, `textLines`, `committed` to `Documents/CaptureLab/<session>/run.json`
- the before/after instrument the row names, with A8's Debug caveat; Release-device numbers come
from `capture.classify.durationMs` / `capture.commit` `durationMs` in the diagnostics export. The
preview guidance's detector pass (~80 ms/frame on the simulator, PU.40; device number is RV.295's,
still open) is untouched by M1-M3 (preview never runs `textLineCount` - it passes 0).

### 5.2 Populations, counted at HEAD `c22d0217`

Counted by `/tmp/pu75/count.py` over `git show HEAD:` versions of
`Spike/ReceiptSpike/fixtures/pump/{split.csv, windows.json, expected.csv}` with the harness's own
filter (`PumpReaderTestSupport.swift:57-88`: split + `reviewed: true`; scored cells = expected.csv
liters/unitPrice/total non-blank minus each still's `csvDisagrees` keys,
`PumpReaderPipelineTests.swift:574-583`):

- **heldout: 68 stills, 183 scored cells** - cross-check: `PumpPhotoGate.readerNumericTotal = 183`
  at HEAD (`PumpPhotoGate.swift:95`); the app path commits 45/45
  (`readerCommitted = readerCommittedCorrect = 45`, :86,:91; Wilson two-sided 95% on 45/45:
  [0.9213, 1.0000]). **The working tree's in-flight build moves these to 47/47 - the implementer
  re-counts and re-baselines at their build commit.**
- **reviewed train: 255 stills, 680 scored cells** (the certify arm's population; the test comment
  says "244 stills at the 2026-09-23 corpus", `PumpReaderPipelineTests.swift:124` - the corpus
  moved; the run brief quotes the arm's latest result as "124/117" in-sample - re-measure it).
- **heldout2: 4 stills, 9 cells** - not measured by ratchets (A10).
- **non-pump fixtures: 116** (receipts 97, screenshots 9, expenses 9, fiscal 1 - `git ls-tree`
  count at HEAD with `PumpLeakConsequenceTests`' extension filter, :16, :41-43).
- **detector gate population:** `ml/pump-reader/.out/det/heldout` - 64 photos, 238 rows
  (`annotations.json`, mtime Sep 21 14:14, i.e. before the Sep-23 re-frames; the spike report
  should say whether it re-runs `detdata`).
- **timing population (Mac and device):** the 6 heldout pump stills + first 8 sorted receipt
  `.jpg`s of `PumpDisplayCaptureTests.classifies` (`PumpDisplayCaptureTests.swift:21-26, :50`) -
  the same frames PU.38's Release table used - plus, on device, one Capture Lab session per build
  (pump + receipt source, every preset the phone supports).

### 5.3 The identity battery - what "committed cells identical" means, concretely

Run before/after **each** of the three changes separately (the row's own requirement), all at the
build commit:

1. `livePath` (`PumpReaderPipelineTests.swift:81-115`): committed **== 45** (equality, :97),
   every committed cell correct (:99), and equal to the `PumpPhotoGate` constants (:105-114).
2. `gateMirror` (:186-280): committed >= 112 and precision >= 0.96 (:279-280) - floors, so ALSO
   compare the printed report's committed count, precision (with its Wilson interval, PU.68) and
   wrong-cell list before/after; identical means the same 112 cells, not merely >= 112.
3. Per-cell value dump: for all 68 heldout stills, the app path's committed (still, field, value)
   triples - from `measureLive`'s report or `pump-read`'s `appCommitted` per still - byte-equal
   before/after. This is the strongest form and the one the row's "(a speed change moves no
   reading)" names; the suites' floors alone would pass a change that moved one still up and
   another down.
4. `PumpDisplayCaptureTests.classifies` (:45-101): >= 4/6 pumps (today 5/6), **0/8 receipts
   leaked** (equality, :100).
5. `PUMP_LEAK=1 PumpLeakConsequenceTests` (:27-70): routed <= 6, committing == 0 over the 116
   (:23-24) - the resampling-sensitive arm, because receipt routing reads Vision proposals that
   any downscale change perturbs.
6. Optional but recommended for M2/M3: `PUMP_CERTIFY=1 trainSplitRiskBound` (:125-157) - same
   committed count and same wrong-photo list before/after on the 255 reviewed train stills.

Detector spike (M4) does NOT run this battery; it runs decision 10's gate (§5.4) - a detector
change is a model change, not a speed change, and ships under its own row.

### 5.4 The detector spike, measured this run

Control (shipped `DigitRows.mlmodel`, same session, `measure.swift` line 1):
**median IoU 0.796 | recall@0.7 172/238 = 0.723 (Wilson 95% [0.6626, 0.7757]) | false rows/photo
0.656 (42/64) | recall@0.5 205/238 = 0.861 ([0.8117, 0.8995]) | photos any row 59, all rows
49/64**. PU.57's recorded shipped numbers were 0.734 / 0.797 / 0.632 - see A7.

Candidate attempt (int8 linear, legacy tool): unpatched crash, verbatim:

```
File ".../coremltools/models/neural_network/optimization_utils.py", line 159, in _conv_bn_fusion
    conv.bias.floatValue.extend(bp)
TypeError: [-5.54199219 -0.43457031  2.265625 ... 6.8828125 ] has type ndarray,
but expected one of: float
```

(the 16-vector is conv0's fused bias, not an anchor constant; `bp` came out (16,16) because ct 9.0
reshapes gamma to (C,1) at `optimization_utils.py:146-147` and then indexes `[:, None]`).
With `_conv_bn_fusion` monkeypatched to the 1-D math (`/tmp/pu75/quantize_spike.py`): the tool
completed ("Quantizing layer __tc_internal__c_anchors of type loadConstant" - the anchors layer IS
touched by the quantizer), saved 47,420,709 B, and Core ML rejected it: `compiler error: ...
Convolution layer 'conv0_fwd' has invalid weights/bias fields` (ct itself warns "You will not be
able to run predict()"). Post-mortem of the spec: all 9 convs still carry their fp16 weights
(31,639,392 B) beside added quantization payload - negative compression. `measure.swift` on the
candidate: **did not load; verdict N/A**. kmeans_lut (palettization-equivalent) fails identically
unpatched (same TypeError, reproduced).

Expected outcome of a properly-fixed spike, labelled inference from §2.3-§2.5: a *loadable* int8
weight-only model should land ~16 MB (coremltools' published 1.92-2.0x vs fp16) with recall/mAP
deltas of a few tenths of a point IF the quantizer's symmetric per-tensor default suits the
weights - but decision 10 demands median IoU **hold or rise**, a point-value bar no published
post-training result clears by construction (they all report small losses). Verdict vocabulary
from PU.57: PASSED (both primaries hold or rise, false rows +<= 0.05, size falls) / REFUSED
(anything else), with the same-day control printed beside the candidate. A REFUSED verdict is a
complete spike result - it closes the compression route and strengthens the case for a
MobileNetV3-class replacement row (§2.3's 3-8x headroom) or leaving the 30.3 MiB as the owner's
accepted ship cost.

### 5.5 Falsifiers, named in advance

- **F1 (identity).** Any committed cell, routing verdict, leak count or classify verdict differing
  before/after one of M1-M3 on the §5.3 battery falsifies that change as a *speed* change; it is
  refused (A4) or sent to the owner - never absorbed by loosening a floor.
- **F2 (batch on device).** A device arm where batched outputs differ from sequential (any
  committed cell moves) or Core ML refuses the fixed-shape batch falsifies the zero-change route;
  A2's re-export is the published remedy, itself identity-gated.
- **F3 (lazy textLines moves a verdict).** M1 changes no pixel and no decision input; if any
  verdict in suites 1/4/5 moves, something unknown consumes `textLines` on the fast path - a
  defect to name, not a tuning opportunity.
- **F4 (spike).** A quantized/palettized detector that does not load, or loads and fails decision
  10's gate against the same-day control, or grows the file: verdict REFUSED in the spike report
  (§5.4's vocabulary); the size half of PU.75 then ships nothing, as the row allows.
- **F5 (no win).** A stage whose Release `timingsMs` (Mac) and Capture Lab `pipelineMs` ratio
  (device, same config) do not measurably improve falsifies the overhead premise for that stage;
  report the null with the numbers.

## 6. Cost

- **Latency (Release; Mac numbers from §5.1, under load 4.3; device numbers DO NOT EXIST yet and
  are the row's deliverable).** M1: removes 6-25 ms from a 14-48 ms fast-path decision on Mac
  (~40-50%); nothing on receipts (their slow path needs the count). M2: removes ~50% of
  classifier call time - 2-5 ms/photo on Mac in `read`, plus the verifier's per-candidate margin
  passes; device share unknown (A14 per-call overhead is likely relatively larger - inference).
  M3: bounded by A4/A5 - the exact-identity subset may end up empty, in which case the honest
  result is "warps stay Swift; only the downscale/gray loops change if identity holds", worth ~4
  ms Release on Mac per downscale (REPORT.md:1125-1126) and unmeasured on A14. M4 spike: no
  runtime promise; published W8 weight-only latency deltas are ~0-6% (coremltools tables), the
  int8 NE compute win needs A17 Pro/M4 (not iPhone 12), so the spike's prize is **bundle size**,
  not speed.
- **Bundle.** M1-M3: +0 resources; classifier re-export only under A2 fallback (same ~58 KB
  package). M4: int8 done right ~16 MB vs today's 30.3 MiB (-~15 MB) IF it loads and passes; the
  measured naive output was 45.2 MiB (worse than today - §5.4). Palettization 6-bit would promise
  ~12 MB but is mlprogram-only (unreachable for this export, §2.5).
- **New code to maintain.** M1: ~10 lines moved + sentinel doc comments + the A1 doc updates. M2:
  ~40-60 lines (a batched sibling of `probabilities(cell:)`, one `MLArrayBatchProvider` wrapper,
  the two call sites switched) + the A2 export-script variant if invoked. M3: ~30-80 lines per
  adopted primitive (buffer plumbing around `vImageScale`/convert), each with its identity note;
  zero if A4 refuses all. M4: spike script(s) ~80-150 lines of Python under
  `ml/pump-reader/detector/` + a REPORT.md section + the REPORT.md:508 correction; no app code.
  No C/C++ target is needed for anything in this row (vImage is C-callable from Swift directly,
  as `PumpRowDeskew.swift:317` already proves); iOS 18.0 / iPhone 12 constraints are met by every
  cited API (all iOS 12 or earlier, §1).
