# PU.71 research note - the a-contrario line test (LSD, EDLines) vs. the turned row's band fit

*A run of `agents/briefs/RESEARCH-TO-CODE.md` (copy: `agents/briefs/RESEARCH-PU.71.md`).
Written read-only; the repo was not modified except this file. Populations and corpus numbers
counted from `git show 5b09f520:` blobs; HEAD moved to `c22d0217` (docs-only: the brief and the
timeline) while this note was written, and `git diff 5b09f520 c22d0217` touches no fixture and no
source, so every count here is also today's-commit (`c22d0217`). The working tree holds another
agent's uncommitted pump-law and corpus changes, none of them read for this note except where a
log is named.*

- **Row:** `PU.71` - Fit the turned row's height to its ink with an a-contrario line test
  (`docs/TASKS.md:1074`)
- **Papers the row cites:** Grompone von Gioi, Jakubowicz, Morel, Randall, *LSD: A Fast Line Segment
  Detector with a False Detection Control*, IEEE TPAMI 32(4), 2010 - **VERIFIED, fetched in full as
  the IPOL 2012 version**; Akinlar & Topal, *EDLines: A real-time line segment detector with a false
  detection control*, Pattern Recognition Letters 32(13), 2011 - **VERIFIED bibliographically; the
  article itself is paywalled, its method fetched as the first author's own implementation
  (ED_Lib, MIT)**; the a-contrario framework, Desolneux, Moisan, Morel - **VERIFIED** (§1.3).
- **The code seam:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift` - the
  `fitsBand` path (`:57` signature, `:90-116` the fit, `:182-203` `inkBand`, constants `:42,44`);
  its only feed is `PumpReader.deskewed` (`PumpReader.swift:230-234`) via
  `candidates(for:deskewRows:)` (`:54-60`), reached on the app path only by `classify`'s
  `.onRefusal` retry (`PumpDisplayCapture.swift:346-359`); the strip the fit feeds is
  `PumpGlyphSlicer.prepare`/`context` (`PumpGlyphSlicer.swift:145-180,183-234`, band at `:192-196`).
  History: PU.58's upright-box trim lost cells because it read bezel as ink
  (`docs/TASKS.md:1056`, patch kept at `diagnostics/PU.58-bandtrim.patch`); PU.55 measured the
  detector box 21 % taller than the hand window with the ink band at rows 6..95 of a 96-px strip
  (`ml/pump-reader/REPORT.md` §PU.55).

## 0. State of the row at the time of writing - read this before §5

Three facts bound what this note can promise.

1. **The `fitsBand` path is dead code, not merely unmeasured.** The row says the path "exists and
   is unmeasured on the app path"; the tree says stronger: `grep -rn fitsBand` over `ios/Sources`,
   `ios/Tests` and `Spike/` finds the parameter only at its definition
   (`PumpRowDeskew.swift:57,90`) - no production caller passes `true`, and no test in
   `PumpRowDeskewTests` (5 tests, `:55-99`) exercises it. `PumpReader.deskewed`
   (`PumpReader.swift:230-233`) calls `deskew` with the default. So `inkBand` (`:182-203`),
   `bandFraction` (`:42`) and `bandMargin` (`:44`) have never run on a corpus pixel in any arm.
   The row's first build step is therefore a wiring, and the wiring is where the mode decision
   lives (`CapturePipeline.pumpReader`, `ios/App/Sources/Capture/CapturePipeline.swift:28-30`,
   builds the reader today at `.off`).
2. **PU.71 turns rows only where PU.67's retry runs, and PU.67 is held.** `classify` reaches the
   row-turn retry only when the frame passed the display decision and both the seed and the
   orientation-searched read committed nothing (`PumpDisplayCapture.swift:324,328,346`). PU.67 was
   built, measured and HELD: with the app reader at `.onRefusal`, `livePath` read 52 committed,
   51 correct (0.981), under the 0.99 floor (`docs/TASKS.md:1066`), and it reopens only after
   PU.81's pair-repair guard is the owner's call (`docs/TASKS.md:1069`). **Per the brief, the band
   fit is measured on the 190 hand quads regardless** - that measurement needs no retry to run,
   because a hand quad is its own turned box.
3. **The row's premise - "a statistical false-alarm bound that a low-contrast bezel edge fails" -
   is not what the papers' own parameters do on this corpus.** Measured here (§5.3): on the 380
   drawn row edges of the heldout hand quads, a horizontal gradient ridge exists in the padding
   zone the fit crop includes (0.15-0.6 row-heights outside the drawn ink edge) on 379 of 380
   scans, with a median contrast 0.87 of the ink edge's own (p90 1.00); LSD's published gradient
   threshold rho leaves 181 of 379 of those bezel ridges in play, and the NFA test at the papers'
   epsilon = 1 validates 0.99 of the ink ridges **and 0.99 of the bezel ridges**. The a-contrario
   test is a noise guard, not an ink/bezel separator, at our strip sizes. What the row can take
   from the papers is the validation machinery plus a **named, measured contrast-ranking
   departure** for choosing which validated line bounds the ink (§4-A4); if that departure cannot
   separate on the train split, the honest outcome is PU.58's - cut with the measurement attached.

## 1. Citations, checked

Fetch log: `api.crossref.org` (works by DOI and by bibliographic query), `api.semanticscholar.org`
(graph API, one paper), `api.unpaywall.org`, the IPOL article page and its `article.pdf` (fetched
in full, 21 pages), `raw.githubusercontent.com` (ED_Lib master: `README.md`, `EDLines.h`,
`EDLines.cpp`, `NFA.h`, `NFA.cpp`), DuckDuckGo HTML. Blocked or unavailable: ScienceDirect
(paywall, both PRL papers), IEEE Xplore (not attempted past Crossref), ResearchGate direct PDF
(HTML challenge), `pdftotext`/`pypdf` absent locally (the IPOL PDF was read as a document, not
parsed). What could not be fetched is not described from memory anywhere in this note.

### 1.1 LSD - VERIFIED, both versions; the IPOL one fetched in full

- **TPAMI original:** *LSD: A Fast Line Segment Detector with a False Detection Control*, IEEE
  Transactions on Pattern Analysis and Machine Intelligence, vol. 32, no. 4, pp. 722-732, April
  2010, DOI **10.1109/TPAMI.2008.300** - confirmed by fetched Crossref record (container, volume
  32, issue 4, pages 722-732, issued 2010-04) and by the IPOL paper's own reference [1]. The row's
  citation ("IEEE TPAMI 32(4), 2010") is correct. Caution for anyone copying the DOI from secondary
  sources: `10.1109/TPAMI.2009.127` is a different object (an inside-cover page, vol. 31, 2009);
  I hit it before the right one.
- **IPOL implementable reference:** *LSD: a Line Segment Detector*, Image Processing On Line 2
  (2012), pp. 35-55, DOI 10.5201/ipol.2012.gjmr-lsd, published 2012-03-24, same four authors -
  fetched as the full manuscript PDF plus the page metadata (code `lsd_1.6.zip`, **license
  AGPL-3.0-or-later**; manuscript CC-BY-NC-SA). The IPOL text states it "includes some further
  improvement over the one described in the original article", so where the two differ this note
  cites IPOL and says so. All section, equation, algorithm and figure numbers below are the IPOL
  manuscript's.

### 1.2 EDLines - VERIFIED bibliographically; article not fetched; method fetched as the authors' code

**C. Akinlar, C. Topal, "EDLines: A real-time line segment detector with a false detection
control", Pattern Recognition Letters, vol. 32, iss. 13, pp. 1633-1642, October 2011, DOI
10.1016/j.patrec.2011.06.001** - confirmed by fetched Crossref (container PRL, volume 32, issue 13,
pages 1633-1642, issued 2011-10), by Semantic Scholar (DBLP `journals/prl/AkinlarT11`, authors
Cuneyt Akinlar and C. Topal), and by the first author's own library header, which cites the same
pages (`ED_Lib/EDLines.h:8-9`). The row's citation ("Pattern Recognition Letters 32(13), 2011") is
correct. The conference twin - *EDLines: Real-time line segment detection by Edge Drawing (ED)*,
18th IEEE ICIP, Sep. 2011, pp. 2837-2840, DOI 10.1109/ICIP.2011.6116138 - is verified
bibliographically by Crossref and not fetched.

The article PDF is closed (Semantic Scholar `openAccessPdf: CLOSED`, Unpaywall no OA location,
ResearchGate serves an HTML challenge). **Its method is therefore described here from the first
author's own implementation**, `github.com/CihanTopal/ED_Lib` (master, fetched 2026-09-24;
repository license MIT; `EDLines.cpp` header names both authors and both papers), cited by file
and line - the same instrument PU.67's note used for Bloomberg's method via Leptonica
(`agents/research/PU.67.md` §1.3). No accuracy or runtime number is quoted for EDLines anywhere in
this note: the paper's experiments were not fetched, and the library's benchmarks are not the
paper's.

### 1.3 The a-contrario framework - VERIFIED

- **Desolneux, Moisan, Morel, *Meaningful Alignments*, International Journal of Computer Vision
  40(1):7-23, 2000**, DOI 10.1023/A:1026593302236 - confirmed by fetched Crossref. This is the
  alignment NFA's origin (LSD's reference [3]).
- **Desolneux, Moisan, Morel, *From Gestalt Theory to Image Analysis, a Probabilistic Approach*,
  Springer 2008, ISBN 0387726357 / 9780387726359** - confirmed by fetched Crossref book record
  (DOI 10.1007/978-0-387-74378-3, ISBNs match) and by LSD's reference [4]. The brief's citation is
  correct. The epsilon = 1 convention this note uses is quoted from the LSD manuscript, which
  attributes it to these two works (IPOL §1, p. 39: "Following Desolneux, Moisan, and Morel [3, 4],
  we set epsilon = 1 once for all").

## 2. The methods as published

### 2.1 LSD (IPOL 2012 manuscript; quotes are its sections and equations)

Pipeline (Algorithm 1, p. 40): scale the image; compute the level-line field; reject pixels whose
gradient magnitude is under rho; region-grow line-support regions from the strongest gradients;
approximate each region by a rectangle; cut regions whose aligned-point density is under D;
improve the rectangle; compute its NFA; keep it iff NFA <= epsilon.

- **Level-line field and gradient (§2.2).** 2x2 mask: gx = (i(x+1,y)+i(x+1,y+1)-i(x,y)-i(x,y+1))/2,
  gy likewise; level-line angle LLA = arctan(gx / -gy); magnitude G = sqrt(gx^2+gy^2). Segments are
  oriented: the sign encodes which side is darker.
- **The a-contrario model and the NFA (§1, eq. (1); §2.7).** H0: the LLA field is independent and
  uniform on [0, 2pi]. A pixel of a rectangle r whose LLA equals the rectangle's orientation within
  a tolerance p·pi is a *p-aligned point*; with n(r) pixels and k(r,i) aligned points on image i,
  the number of false alarms is **NFA(r,i) = (NM)^{5/2} · gamma · B(n(r), k(r,i), p)** where
  B(n,k,p) = sum_{j=k..n} C(n,j) p^j (1-p)^{n-j} is the binomial tail, N x M is the (scaled) image
  size, and gamma is the number of precision values tried. A rectangle with NFA <= epsilon is
  *epsilon-meaningful* and is a detection. **Theorem 1** (p. 39): under H0 the expected number of
  epsilon-meaningful rectangles is <= epsilon - the Helmholtz principle, proved in the IPOL text.
- **The threshold the papers set: epsilon = 1**, "once for all" (p. 39), i.e. one false detection
  per image on average under H0; and the result is insensitive to it because the detection limit
  varies like sqrt(-log epsilon) (p. 39; figure 10 shows epsilon = 1, 1e-1, 1e-2 differing by a few
  small segments).
- **The six internal parameters and the authors' values (§2 preamble, §2.1-2.9):** S = 0.8
  (Gaussian sub-sampling to 80 %, sigma = Sigma/S with Sigma = 0.6, §2.1); rho = q / sin(tau) with
  q = 2 for [0,255] quantisation (§2.4), i.e. **rho = 5.226 at tau = 22.5 deg** - pixels below it
  are never used, "flat zones or slow gradients" plus quantisation error; **tau = 22.5 deg = pi/8**,
  hence **p = tau/pi = 1/8 = 0.125** (§2.5); **D = 0.7** aligned-point density, d = k /
  (length·width) (§2.8); **gamma = 11** precision values (§2.9); **epsilon = 1**. The authors are
  explicit that these are design constants, not user parameters: "Changing their values would
  amount to define a new variant of the algorithm" (§2).
- **Region growing (§2.5, Algorithm 2):** 8-connected growth while |LLA - region angle| < tau,
  region angle updated as the mean unit vector; seeds taken in decreasing gradient magnitude
  (1024-bin pseudo-ordering, §2.3).
- **Rectangle fit (§2.6):** centre = gradient-magnitude-weighted centroid; orientation = the
  eigenvector of the smallest eigenvalue of the inertia matrix; width and length the smallest that
  cover the region.
- **Rectangle improvement (§2.9):** five steps - finer precisions p/2..p/32, width reduced in 0.5-px
  steps (up to 5), one side, the other side, finer precisions again; each kept iff it lowers the
  NFA. This is the paper's own mechanism for shrinking a rectangle onto its evidence.
- **Complexity (§2.10):** linear in the pixel count.
- **What the IPOL paper measures:** no accuracy tables. Its evidence is the Helmholtz theorem, the
  epsilon-stability experiment (figure 10), a white-noise image with zero detections (figure 16),
  and the **image-size dependence of the threshold** (figures 19-20: a square undetectable in a
  417x417 image is detected in a 28x28 crop of it, "the detail level depends on the size of the
  whole data being analyzed"). The TPAMI original's experiments were not fetched; no number from
  them is quoted.

### 2.2 EDLines (method from the fetched ED_Lib; bibliography from §1.2)

EDLines = Edge Drawing (ED) edge-segment extraction, line fitting on each segment, then the same
a-contrario validation as LSD with EDLines' own number of tests. From `EDLines.cpp` / `NFA.cpp`:

- **Validation rectangle and aligned points** (`EDLines.cpp:455-505`): a fitted line is validated
  over a line-support rectangle of width 1 for long segments (len > 25), width 2 for short ones and
  as a retry (`EnumerateRectPoints`, `EDLines.cpp:1003-1033`, `width = 2`); a pixel is aligned when
  its gradient angle (3x3 mask, `EDLines.cpp:478-486`, pixelAngle = atan2(gx, -gy)) differs from
  the line angle by <= prec or >= pi - prec, with **prec = 22.5 deg** (`#define PRECISON_ANGLE
  22.5`, `EDLines.cpp:50`) - the polarity-free form, so a light-on-dark and a dark-on-light edge
  validate alike.
- **The NFA** (`NFA.cpp:106-196` returns **-log10 NFA**; `checkValidationByNFA`, `NFA.cpp:38-44`,
  accepts when it is >= 0, i.e. **NFA <= 1**): log10 NFA = log10 B(n,k,p) + logNT with **p = 0.125**
  (`EDLines.cpp:52`) and **logNT = 2·(log10 W + log10 H)**, i.e. **N_test = (W·H)^2**
  (`EDLines.cpp:55`) - EDLines' number of tests is the squared pixel count, not LSD's
  (NM)^{5/2}·gamma. The binomial tail is the same truncated series LSD describes (IPOL §2.7),
  10 % relative error tolerated (`NFA.cpp:109`).
- **The minimum line length is derived, not tuned** (`ComputeMinLineLength`,
  `EDLines.cpp:267-276`): round((-logNT / log10 0.125) · 0.5) - the shortest segment whose fully
  aligned rectangle can reach NFA <= 1 at that image size.
- **Parameter-free claim:** the library README states EDLines "is alos a parameter-free algorithm
  which validates all detected lines via Helmholtz Principle" and cites the PRL paper with the
  pages of §1.2. The constructor's defaults (`EDLines.h:68`: line_error 1.0, max_distance 6.0,
  max_error 1.3) are the line-fitting and joining stage, not the validation.

### 2.3 What the two papers agree on, and where they differ (the fence for §4)

Agreed: p = 1/8 from tau = 22.5 deg; validation is NFA <= epsilon with epsilon = 1; aligned-point
counting over a thin rectangle; the binomial tail under a uniform-orientation H0. Differed: the
number of tests ((NM)^{5/2}·gamma vs (NM)^2); the front end (level-line region growing with a
gradient threshold rho vs Edge Drawing's additive anchors); the rectangle refinement (LSD's five
improvement steps vs EDLines' width-1-then-2 retry). **Neither paper publishes a rule for choosing
between several validated parallel lines** - LSD reports every meaningful rectangle it finds.
Anything of ours in that slot is an adaptation (§4-A4).

## 3. Mapping onto this code

The job: after `deskew` has chosen an angle, replace the height/centre of the turned box with the
ink band's, so the warped 96-px strip carries ink and not bezel (PU.55's 21 % overhang, PU.58's
lost cells). Mapping, published element to ours:

| Published element (source) | Our implementation | Relation |
|---|---|---|
| Gradient + LLA, 2x2 mask (LSD §2.2) | none today in the deskew path; `inkBand` uses a row activity sum of abs horizontal differences (`PumpRowDeskew.swift:184-189`) | the line test adds the gradient field; the activity sum is its polarity-free cousin without orientation |
| rho = q/sin tau, pixels below rejected (LSD §2.4) | none - `inkBand` thresholds activity at `bandFraction` 0.3 of the peak row (`:42,191`) | **retires `bandFraction`**: the contrast gate becomes the published rho, rescaled (§4-A2) |
| Region grow + rectangle fit (LSD §2.5-2.6) | not needed: the line's orientation is already known (the turned row's axis), so the candidate rectangles are horizontal bands of the strip | adaptation A3 - the search family shrinks to what the turn already fixed |
| NFA(r) = (NM)^{5/2} gamma B(n,k,p), epsilon = 1 (LSD §1, §2.7) / NFA with N_test = (NM)^2, epsilon = 1 (EDLines `EDLines.cpp:55`, `NFA.cpp:38-44`) | none today | the validation the row names; N_test must be **our** family's count (§4-A3) |
| Aligned-point density d >= D = 0.7 (LSD §2.8) | none | available as a cut criterion on candidate band rectangles; at our strip sizes epsilon = 1 alone implies densities far below D (§5.4), so D is the stricter published guard |
| Rectangle improvement, 0.5-px width steps (LSD §2.9) | `bandMargin` 0.12 of the band height added above and below (`:44,106-108`) | **retires `bandMargin`** in favour of the published half-pixel shrinking, or keeps it as a named adaptation (A5) |
| EDLines minimum line length from logNT (`EDLines.cpp:267-276`) | none | the sanity floor for a band edge: at our strip sizes it is ~5 px (§5.4) |
| (nothing published: choosing among parallel validated lines) | `inkBand`'s longest run at 0.3 of peak (`:192-201`) | the slot our contrast-ranking departure fills (A4) |
| (nothing published: band fit after a skew retry) | `fitsBand` block (`:97-116`): band centre offset along the turned axis, height floored at 0.5 of the box | geometry stays; its band source changes |

**Types and seams.** In: the turned strip as `PumpGrayscale` (the one `fitsBand` already warps at
`searchStripHeight` 48, `:100-101`) or, if the fit moves to the read strip, the 96-px one
(`PumpReader.stripHeight`, `PumpReader.swift:13`). Out: `ClosedRange<Int>` band rows in strip
coordinates, exactly what `inkBand` returns today, so `:105-116` is untouched. Wiring: a
`fitsBand`-carrying parameter through `PumpReader.deskewed` (`PumpReader.swift:230-234`) and
`candidates(for:deskewRows:)` (`:54-60`), set where the reader is built
(`CapturePipeline.swift:28-30`) - the same delta shape PU.67's held attempt used for the mode.
Downstream consumers of a tighter quad, all already in the tree: the slicer's own band
(`PumpGlyphSlicer.swift:192-196`, threshold `bandRowThresholdFraction` 0.15 at `:47`) and the
verifier's band-fraction rule (`PumpRowGeometry.swift:58,91-94`) - a tighter box raises the band's
fraction of the strip, which can flip verifier verdicts either way; §5.5 names it as a measured
risk, not an assumption.

**Constants PU.71 retires:** `bandFraction` (`PumpRowDeskew.swift:42`) and, if A5 takes the
published route, `bandMargin` (`:44`). Nothing else: `searchPadding`, `searchStripHeight`,
`minimumGain` belong to the angle search (PU.67/PU.69's surface).

## 4. Every adaptation, named and justified

Fence restated: **a departure the row's implementer adds later that is not listed here needs the
product owner's OK.**

- **A1. Implement from the papers, not from either codebase.**
  *Paper/code:* IPOL LSD code is AGPL-3.0-or-later (`lsd_1.6.zip` metadata, §1.1); ED_Lib is MIT
  but is C++ against OpenCV (`EDLines.h:18-20`).
  *Ours:* Swift in `TankbookCore`, written against the IPOL manuscript's equations and ED_Lib's
  formulas as specification. *Why:* an AGPL dependency cannot ship in a closed iOS app bundle, and
  hard rule 14's gate has no C++ target in `ios/Sources/TankbookCore` today; the method needs none -
  gradient, binomial tail (log-gamma series, IPOL §2.7 / `NFA.cpp:106-196`) and the ridge scan are
  a few hundred lines of plain Swift or Accelerate. No Core ML, Metal or Vision addition; iOS 18.0
  deployment target unexercised (no API newer than 18 is needed).
- **A2. rho rescaled to the strip's own quantisation, not q = 2 on [0,255].**
  *Paper:* rho = q/sin tau with q = 2 because pixel values are integers in [0,255] and the maximal
  gradient error is 1, conservatively doubled (IPOL §2.4).
  *Ours:* the strip the test runs on is a bilinear warp of a photo, values in [0,1] floats
  (`PumpQuadWarp.warpToStrip`, `PumpQuadWarp.swift:165-195`), so q = 2/255 in strip units - or the
  test runs on the 0-255 photo and keeps q = 2. *Why:* rho's derivation is a quantisation bound;
  copying the literal 5.226 onto [0,1] data would reject every pixel, and copying 0.008 onto [0,255]
  data would reject nothing. The choice of domain (photo pixels vs warped strip) is itself part of
  this adaptation: **the note fixes the test on the warped strip in 0-255 scale** (multiply the
  warp's [0,1] by 255), because the band is defined in strip rows and because JPEG/HEIC decode
  noise, not source quantisation, is the error the bound must survive; if the implementer measures
  that decode noise exceeds q = 2 on the train split, raising q is a further departure and needs
  the owner.
- **A3. The number of tests is our hypothesis family, not (NM)^{5/2} gamma nor (NM)^2.**
  *Paper:* LSD counts every oriented rectangle at every width in the image; EDLines counts
  (W·H)^2.
  *Ours:* the family is the band-edge hypotheses the fit actually tries: top row x bottom row x a
  small width set on the 48-px search strip, i.e. (48·47/2)·3 = 3384 tests, log10 N_test = 3.53;
  multiplied by the number of turned rows tested in one photo if the implementer counts per photo
  instead of per strip - the note fixes **per strip**, matching LSD's practice of taking the
  analysed data as the universe (IPOL §2.1: the NFA "automatically adapt[s] to the image size").
  *Why:* the a-contrario guarantee is only as true as the test count: using LSD's whole-image
  family for a 34-hypothesis question would overstate the bound by nine orders of magnitude and
  admit bands that our own search would never have tried. The consequence is measured, not
  assumed: at 3384 tests the epsilon = 1 density floor is 0.175-0.238 (§5.4), far below the ink
  ridges' 0.45 median and also far below the bezel ridges' - which is exactly why A4 exists.
- **A4. Choosing the band edges among validated parallel lines: outermost validated line whose
  ridge contrast reaches a fraction f of the strip's strongest, with f fitted on the TRAIN split.**
  *Paper:* nothing. LSD returns all meaningful rectangles (IPOL Algorithm 1 line 15); EDLines
  returns all validated lines; neither has an object-boundary rule.
  *Ours:* candidate horizontal ridges are scanned outward from the strip centre (the ridge search
  of §5.3 is the reference implementation of the scan); each is validated by NFA <= 1 (A3); the
  band top/bottom are the outermost validated ridges whose median gradient magnitude is >= f times
  the strongest validated ridge in the strip; f fitted on train only (decision 9,
  `PumpRowGeometry.swift:14-18` states the house rule for this verifier family).
  *Why:* the measurement in §5.3 says the published gates cannot make this choice alone - at
  epsilon = 1 the bezel ridges validate at the same rate as ink (0.99 vs 0.99), and rho leaves 181
  of 379 bezel ridges above threshold - while the contrast ratio still carries signal (bezel/ink
  p10 0.09). The ranking is ED's own principle ("join them by maximizing the total gradient
  response", ED_Lib README) applied as a selection, not as extraction. **This is the row's central
  departure; its fitted f and its train-split separation curve are the row's main evidence.** If
  no f separates on train (the p90 = 1.00 bezel/ink ratio in the padding zone says half the bezels
  are as strong as their ink), the row cuts with the measurement, PU.58-style.
- **A5. Margin: LSD's 0.5-px width shrinking, or `bandMargin` kept - decided by measurement, named
  either way.**
  *Paper:* rectangle improvement reduces width in 0.5-px steps while the NFA improves (IPOL §2.9).
  *Ours:* today `bandMargin` = 0.12 of the band height above and below (`:44,106-108`), an
  unpublished cushion that keeps anti-aliased glyph crowns inside the warp. The row tries the
  published half-pixel shrinking first (the NFA-improves criterion becomes "the band's committed
  cells on train do not fall"); if it loses cells on train, `bandMargin` stays and is re-fitted on
  train, recorded here as the kept adaptation. *Why:* a warp that clips a glyph's top row changes
  the classifier's input distribution, which was trained on the current framing - the same reason
  PU.65 kept the detector's box below 6 deg ("the verifier's rules were tuned on the detector's
  own framing", `PumpRowDeskew.swift:26-28`).
- **A6. The test runs on the turned strip only, after the angle is chosen - never on the upright
  read.**
  *Paper:* LSD/EDLines run on whatever image they are given, unconditionally.
  *Ours:* `fitsBand` is inside `deskew` past the `minimumGain` gate (`:87-96`), and PU.71's gate
  text says "applied after the turn only". *Why:* PU.58 measured the upright trim and it lost cells
  (47 to 44, two wrong); PU.65 measured unconditional turning and it churned (46/46 vs 47/47). The
  band fit inherits both lessons: it may only touch a box the turn already moved, so a photo the
  upright read commits on is untouched by construction (hard rule 15's "a second attempt must not
  disturb a first that worked", `agents/research/PU.67.md` A10).
- **A7. Polarity: the aligned test's mod-pi form is kept, not adapted.**
  *Paper:* EDLines accepts diff <= prec or >= pi - prec (`EDLines.cpp:499`); LSD's oriented
  rectangles would need both orientations tested.
  *Ours:* the mod-pi form as published, because both display polarities exist (LCD dark-on-light,
  LED light-on-dark) and the existing profile score is polarity-free by the same trick
  (`PumpRowDeskew.swift:163-165`). Listed so the implementer does not "fix" the doubled condition
  away.
- **A8. No region growing, no ED: ridges are scanned, not grown.**
  *Paper:* LSD grows 8-connected line-support regions from seeds (Algorithm 2); EDLines inherits
  ED's anchor-grown segments.
  *Ours:* the candidate lines' orientation and extent are already fixed by the turned box (the
  line runs along the row axis across the strip width), so a ridge scan over row offsets with the
  aligned-density and NFA evaluated per candidate rectangle replaces growth. *Why:* region growing
  exists to discover orientation and extent; both are known here, and growing on a 48-px strip
  whose rows are one glyph crown tall would merge glyph edges into blobs (the "angle problem" of
  IPOL §2.8 is the generic warning). The cost of the scan is §6's.

**On-device constraints, all satisfied:** pure Swift plus optionally Accelerate for the gradient
and the row sums; no C/C++ target, no Core ML, no Metal, no new dependency; iOS 18.0 deployment
target needs no `@available` guard for anything here. iPhone 12: the added work is one gradient
pass and one ridge scan per turned row on a 48-px strip (§6).

## 5. What the papers measured; what we expect on our corpus; falsification

### 5.1 What the papers measured (only what was fetched)

LSD IPOL: the Helmholtz bound (Theorem 1), epsilon-insensitivity (figure 10), zero detections on
white noise (figure 16), and threshold dependence on analysed size (figures 19-20). No accuracy
tables; the TPAMI experiments were not fetched. EDLines: nothing quantitative fetched - the PRL
article is closed (§1.2); its validation formulas and derived minimum length are quoted from the
authors' code, not its results.

### 5.2 Our populations, counted at HEAD `5b09f520` (file and filter for each)

Counted with python over `git show 5b09f520:` blobs of `Spike/ReceiptSpike/fixtures/pump/{split.csv,
windows.json, expected.csv}` (byte-identical at HEAD `c22d0217`; the working tree's fixtures are
mid-corpus-run elsewhere and were not read):

| Population | Count | File and filter |
|---|---|---|
| Heldout stills (the live-path universe) | **68** | `split.csv` column `split` == `heldout` intersect `windows.json` entries with `reviewed: true` - exactly `PumpReaderTestSupport.isHeldout` (`PumpReaderTestSupport.swift:66-83`) |
| Asserted numeric cells on those stills | **183** | `expected.csv` non-blank liters/unitPrice/total minus each still's `csvDisagrees` keys - `measureLive`'s cell filter (`PumpReaderPipelineTests.swift:580-585`); equals `PumpPhotoGate.readerNumericTotal` (`PumpPhotoGate.swift:95`) |
| Heldout stills the app path commits on (`.off`) | **17** photos, 45 cells | `livePath` at `b42f38da` (`/tmp/agentlogs/pu79-on-b42f38da.log`: "photos: 17 committing"); HEAD adds only RV.304, which touches no pump code - labelled inference that the count holds at HEAD; the gate re-runs `livePath` anyway |
| **App-path refusal photos - where PU.71's fit can run** | **41** | the 51 stills that commit nothing minus the 10 whose reading carries no abstention reason: the histogram at `b42f38da` lists law reasons for 41 (nothingClosed 22, priceOutOfBand 10, priceUnvalidated 5, cellUnknown 3, noTotalWindow 1) and `classify` returns a reason-less `.abstained` (`PumpReadingTypes.swift:170-171`) only when the display decision refused (`PumpDisplayCapture.swift:324`) - the retry at `:346` runs exactly on the 41 |
| **Heldout hand quads - the band-fit truth** | **190** | `windows.json` windows with a quad, non-empty `text` and `field` not `board`, on the 66 heldout reviewed stills with `rotationCW == 0` - PU.65's instrument (`docs/TASKS.md:1064` "140 of 190 heldout hand boxes are turned"); reproduced here: 190 windows, **140 turned past 0.3 deg**, median 0.93 deg, p90 3.9, max 18.0. (All-window denominators are different and must not be conflated: 252 windows incl. boards, 195 incl. the 2 rotated stills' rows - `agents/research/PU.67.md` §5.2 warns the same) |
| Edge scans in the ridge measurement below | **380** | 190 quads x top/bottom edge |

### 5.3 Our measurement: can the published test separate ink from bezel? (new, this note)

Method (script kept at `/tmp/pu71/measure2.py`, run over the HEAD blobs' stills): per hand quad,
LSD's 2x2 gradient and LLA on the photo; along each drawn edge, scan parallel lines at offsets
t = -0.5h..+1.5h in 0.05h (h = the quad's row height); per line record median gradient magnitude,
the fraction of pixels above rho = 5.226, the aligned density at tau = 22.5 deg mod pi, and log10
NFA at p = 0.125 under three test families (ours 3384; LSD's (NM)^{5/2}·11 on the 48-px strip;
EDLines' (NM)^2). Ink ridge = the strongest gradient·density line within +-0.5h of the drawn edge;
padding-zone ridge = the strongest in 0.15h..0.6h outside it - the zone `fitsBand`'s 1.6x crop
includes beyond the ink (`searchPadding` 0.3, `PumpRowDeskew.swift:34`, over a detector box PU.55
measured up to 21 % tall). Results over 380 scans (379 with both ridges):

| quantity | ink ridge | padding-zone ridge |
|---|---|---|
| median gradient magnitude (0-255) | 9.1 (p10 3.3, p90 48.1) | 4.9 |
| median aligned density (tau 22.5 deg) | 0.45 | 0.35 |
| ridge offset from the drawn edge | t* median +0.10h | 0.15-0.6h by construction |
| pixels above rho = 5.226, median fraction | 0.70 | 0.63 |
| NFA <= 1, our family / LSD family / EDLines family | 0.99 / 0.95 / 0.97 | 0.99 / 0.85 / 0.91 |

Bezel-to-ink gradient ratio: p10 0.09, **median 0.87, p90 1.00**; both ridges above rho in 181 of
379 scans. Read plainly: **the a-contrario validation at epsilon = 1 and the published rho pass
the bezel as readily as the ink on this corpus** - the row's premise holds only through A4's
contrast ranking, whose headroom the ratio distribution quantifies (a global f sits between p10
0.09 and median 0.87, i.e. it can reject the weak half of bezels and cannot touch the strong
half). Two secondary facts the implementer needs: the drawn edge sits a median 0.10h outside the
gradient ridge (annotator slack), so any band-fit truth metric must compare against the ridge or
tolerate +-0.15h, not against the drawn line pixel-exactly; and aligned densities of 0.45 (ink)
mean night and glare photos wobble in orientation, so D = 0.7 as a hard cut would reject real ink
edges - D is usable only as a region-cut criterion, as LSD uses it, not as a band-edge gate.

### 5.4 What epsilon = 1 means on a ~96-px strip

Computed from the fetched formulas (binomial tail in log space, p = 0.125): the minimum aligned
density a rectangle must show to reach NFA <= 1, by strip and family:

| strip | family (log10 N_test) | 300x1 rect | 300x2 rect |
|---|---|---|---|
| 96 x 300 (read strip, aspect 6.25) | LSD (12.19) | 0.280 | 0.232 |
| 96 x 300 | EDLines (8.92) | 0.253 | 0.213 |
| 96 x 300 | ours (3.53) | 0.197 | 0.175 |
| 96 x 130 (narrow row) | LSD (11.28) | 0.362 | 0.288 |
| 48 x 300 (search strip) | ours (3.53) | 0.197 | 0.175 |

EDLines' derived minimum line length on these strips is **5 px** (`EDLines.cpp:267-276` formula).
So on a 96-px strip, epsilon = 1 buys a noise guard at densities 0.17-0.36 - an order of magnitude
below what a real glyph crown delivers (0.45 median, and the bright stills near 1.0) and below
what the bezel delivers too. That is LSD's own size-dependence (figures 19-20) working as
designed: a small analysed universe makes every test cheaper to pass. **The band fit's selectivity
cannot come from epsilon; it comes from A4.**

### 5.5 What we expect, and the results that would falsify the row

Expectations, labelled: on the 41 refusal photos the fit can only help where the turned box's
overhang is what loses the cell - PU.55's shape (box 21 % tall, band 6..95 of 96) - and PU.65's
apportionment put 33 of the heldout lost cells on framing of rows the verifier kept
(`docs/EXTRACTION.md:1085-1090`); on the 190 hand quads the fit should shrink the warped strip's
bezel share toward zero where the padding ridge is weak (p10 0.09 of ink) and change nothing where
it is strong. Falsifiers:

1. **The row's own gate:** arms off / onRefusal / onRefusal+fit on the app path over the 41-photo
   refusal population, corpus scorer 0.005 - the fit ships only if it adds committed cells at zero
   wrong readings (`docs/TASKS.md:1074`); a single wrong cell or a lost cell kills it, which is
   exactly how PU.58 died (47 to 44, two wrong).
2. **Hand-quad band agreement:** for each of the 190, the fitted band's top/bottom rows (mapped
   back through the warp) against the quad's ridge edges; if the fitted band is not tighter than
   the detector box's measured overhang on the same quads, the fit adds nothing and the row cuts.
3. **A4's separation on TRAIN:** the fitted f must separate ink from padding-zone ridges on the
   reviewed train split (`PumpReaderTestSupport.isReviewedTrain`, `:88`); if the train bezel/ink
   ratio distribution matches the heldout one measured here (median 0.87), no f exists and the row
   cuts with this note's numbers as the record.
4. **Verifier side-effects:** the `PumpRowGeometry` reason histogram (`inkBand`, `pitch`,
   `cellCount`, `PumpRowGeometry.swift:76-103`) before/after on both arms - a tighter strip moves
   the band-fraction ratio (`:91-94`) and can refuse rows that used to pass; a rise in any reason
   count without a committed-cell gain is a falsifier.
5. **Leak unchanged:** the named instrument `PumpLeakConsequenceTests` (folders pinned in the test,
   `agents/research/PU.67.md` §5.2) - the fit must not make a non-pump fixture readable as a pump.
6. **The mutation:** build the reader with the fit off while `PumpPhotoGate`'s constants carry the
   fit-on number - `livePath` must go red (`PumpReaderPipelineTests.swift:56-58,106-114`).

## 6. Cost

- **Latency.** The fit runs only on rows the turn moved, inside the refusal retry - photos that
  commit upright pay zero (`PumpDisplayCapture.swift:328` returns before `:346`). Per turned row it
  adds: one gradient + LLA pass over the already-warped 48 x W search strip (W = 48·aspect,
  ~130-384 px, so 6-18 K pixels, ~4 ops each) and the ridge scan, 41 offsets x 2 edges x W bilinear
  samples ≈ 12-31 K samples, plus one binomial-tail evaluation per candidate (the log-gamma series,
  truncated at 10 % relative error as published). Order of magnitude: **one to two extra
  warp-trial equivalents per turned row**, against the retry's existing 72 warp trials per row
  (`agents/research/PU.67.md` §6) - i.e. a few percent on the refusal path, not a new term in it.
  Labelled inference from operation counts read off the code and the script; **the row's gate
  requires the Release number on a refusal photo, before and after, and no Debug figure counts.**
  Context: the pipeline today is 13-73 ms decision and 112-164 ms read, Release on Mac, never yet
  timed on an iPhone (PU.75 row, `docs/TASKS.md:1078`).
- **Bundle size:** +0 bytes of resource; a few KB of compiled Swift, no model, no dependency.
- **New code to maintain:** one file-sized addition - the gradient/LLA pass, the NFA (log-gamma
  binomial tail, ~60 lines ported from the published series), the ridge scan and the A4 selection,
  estimated 150-250 lines plus tests - against retiring `inkBand`, `bandFraction` and possibly
  `bandMargin` (~35 lines). The maintained surface gains one fitted constant (f, stored with the
  train-split evidence like `PumpRowGeometry`'s bounds) and loses two unpublished ones.

## 7. Findings handed off (found, not fixed - this note is read-only)

1. **The row text understates the seam's state:** "`PumpRowDeskew`'s `fitsBand` path exists and is
   unmeasured on the app path" (`docs/TASKS.md:1074`) - it is uncalled everywhere, tests included
   (§0-1). The build brief should say "wire and then measure", or the implementer will assume a
   caller exists and hunt for one.
2. **The row's premise sentence is false as published and true only through A4:** "the segment
   tops/bottoms of a turned row are line evidence with a statistical false-alarm bound that a
   low-contrast bezel edge fails" - on this corpus the bezel edge is not low-contrast relative to
   rho (181 of 379 above it) and the false-alarm bound passes it (0.99). The measurement is in
   §5.3 with its script; whoever briefs the row should carry the corrected sentence, exactly as
   PU.67's correction carried its own (`docs/TASKS.md:1064` last sentence).
3. **PU.69's sweep count and PU.71's cost interact:** the ridge scan reuses the strip the sweep
   already warps at its best angle; if PU.69 lands first and retires the sweep (FHT), the fit's
   strip source moves to the FHT's own crop and this note's A3 test count (per strip) still holds,
   but the "one to two warp-trial equivalents" framing of §6 does not. Owner: whichever row builds
   first; the second re-reads §6.
4. **The drawn-edge slack (+0.10h median) is a corpus fact, not a code fact:** any future row that
   scores a geometry against hand quads at pixel precision (PU.76's rotated-IoU gate is the next
   candidate) inherits it. Filed here because PU.71's truth metric is the first to need the
   tolerance written down.
5. **EDLines' PRL article remains unfetched in this repo's research record:** PU.71's note describes
   it from ED_Lib. If a later row needs EDLines' own experiments (runtime vs LSD, detection
   accuracy tables), someone must obtain the article - the numbers do not exist in the library.
