# PU.69 research note - row angle by a fast Hough transform, with a confidence

*A run of `agents/briefs/RESEARCH-TO-CODE.md` (copy: `agents/briefs/RESEARCH-PU.69.md`). Product
owner, 2026-09-23: **"review the published research to apply it into the code, instead of coming up
with our own solution."** Written read-only; the repo was not modified except this file. Fetch
scratch (downloaded PDFs, extracted text, measurement JSON) lives OUTSIDE the checkout, in the
pre-approved system temp dir `/var/folders/34/b62b3k2s2b9318ztk2c514gr0000gn/T/opencode/pu69/`;
nothing was built (the pre-existing `ios/.build/opt/debug/pump-read` binary was run, not rebuilt).
Evidence rule: every claim cites a paper section/equation, a `file:line`, or a measured number;
inference is labelled.*

- **Row:** `PU.69` - Row angle by a fast Hough transform, with a confidence (`docs/TASKS.md:1070` at
  HEAD `c22d0217`). PU.67's note verified the projection-profile family our current estimator belongs
  to and handed this row two findings, both re-verified here: the sweep is **72 trials per row**
  (1 level + 60 coarse + 11 fine, `PumpRowDeskew.swift:77-86`; `agents/research/PU.67.md` §7-1), and
  the method **returns no confidence** (`deskew` -> `Result{quad, degrees}`, `:46-51`).
- **Papers the row cites:** Bezmaternykh, P., Nikolaev, D. (2019). *A Document Skew Detection Method
  Using Fast Hough Transform.* arXiv:1912.02504 - **VERIFIED, full text fetched** (§1.1); classical
  base Duda & Hart (1972), CACM 15(1) - **VERIFIED bibliographically, and a citation caution**
  (§1.2). Following the FHT paper's own reference [3], the algorithm it runs is **Brady's fast
  discrete approximation of the Radon transform** (SIAM J. Comput. 1998; conference original
  Brady & Yong, SPAA 1992) - the FHT primary (§1.3-1.4). The criterion the paper scores FHT rows
  with (**SSG**) is defined in its closed-access refs [14][15]; the formula used here is the
  **open-access restatement by the same group** (Kunina, Sher, Nikolaev 2023, Computer Optics
  47(4), fetched in full; §1.6, §2.4).
- **The code seam:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift` - `deskew`
  (`:57-117`), the per-trial `score` closure (`:66-76`), the coarse/fine search (`:79-86`),
  `profileSharpness` (`:166-177`), `minimumGain` (`:39,87-89`), `largeTurn`/`rowSize` (`:29,126-133`);
  the confidence consumer is PU.70's size rule (`PumpDisplayCapture.minimumWidestRowFraction`
  `:88`, `passesSize` `:152-155`). All `file:line` refs are HEAD `c22d0217`; the working tree's
  in-flight PU.78 changes (`PumpReadingLaw.swift`, `PumpPhotoGate.swift`, pipeline tests,
  `windows.json`) touch none of the deskew seams, and where a working-tree-modified file is cited
  the line is from `git show HEAD:` (§0).

## 0. State of the row at the time of writing - read this before §5

HEAD moved twice while this note was measured. **Everything is pinned to `c22d0217`** (2026-09-24
00:59); the pump fixtures at `c22d0217` are byte-identical to `b42f38da` (`git diff b42f38da..HEAD --
Spike/ReceiptSpike/fixtures/pump/` is empty), which is the commit the measurements ran against.

In flight in the working tree while this note was written (not mine, not touched):

1. **PU.78 is landing** (uncommitted at this writing): `PumpReadingLaw.swift` exact-close change,
   `PumpPhotoGate.readerCommitted` 45 -> 47, `PumpReaderPipelineTests.committedFloor` 112 -> 118
   ("PU.78 made the close exact ... 112 -> 118 committed, all correct, 35 -> 41 photos" - the
   working tree's test comment), `docs/TASKS.md` ticking PU.78 and filing PU.81. The brief's context
   numbers (live 45/45, annotated 112/112, train 124/117) are **HEAD's**, and they match HEAD
   exactly; if PU.78 commits before PU.69 builds, the row's "app path live >= PU.67's count"
   re-counts to 47 at the build commit (§5.2, F5).
2. **The owner is re-annotating pump-275 right now**: the working tree's `windows.json` has its
   `reviewed` flag cleared and its windows changed, so heldout momentarily reads 67 in the working
   tree. All populations below are HEAD's (`reviewed: true` for pump-275 at HEAD -> heldout 68).
   The owner's annotator servers (`pump-read --slice-serve`, `--read-serve`, PIDs 74312/74412) were
   running during the measurements - left alone; latency numbers carry the contention label (§5.4).

The measurement instrument for §5.3-5.4 was the pre-existing optimised `pump-read`
(`ios/.build/opt/debug/pump-read`, mtime Sep 23 19:51:13). Verified current for this purpose:
`find ios/Sources -newer ios/.build/opt/debug/pump-read` returns only
`ExpenseCategoryInference.swift` (RV.304, not on the pump path) - every pump-path source, including
`PumpRowDeskew.swift` (mtime Sep 23 01:41), predates the binary. The binary holds the **pre-PU.78
law**; angle estimates do not depend on the law (they come from `candidates(for:deskewRows:)`
before any reading), so §5.3 is unaffected; §5.4's refusal set was decided under the old law and is
labelled.

## 1. Citations, checked

Fetch log: arxiv.org abs page (webfetch), ar5iv.labs.arxiv.org (full HTML of 1912.02504),
arxiv.org PDFs via curl (1912.02504, 2411.07351, 1811.06378, 1712.05615, 2002.01176, 2311.10064,
1909.03812; text extracted with pypdf installed into the temp dir), computeroptics.ru OA PDFs
(KO45-5/450509, KO46-3/460311, KO47-4/470417, KO40-3/400312), `api.crossref.org`,
`api.openalex.org` (incl. `fulltext.search` and a `cites:W2801491629` walk),
`api.semanticscholar.org/graph`, `api.github.com` (SmartEngines org), doi.org header redirects.
Blocked or unavailable: SPIE Digital Library (refs [14][15] full text - Incapsula, as in PU.67's
run), SIAM (Brady 1998 full text), IEEE (DISEC'13 contest paper, Duda & Hart full text), dblp (bot
wall), DuckDuckGo/Bing/Mojeek HTML (empty or walled), webfetch >5 MB limit (KO PDFs - fetched via
curl instead). **What could not be fetched is not described from memory anywhere in this note.**

### 1.1 Bezmaternykh & Nikolaev, arXiv:1912.02504 - VERIFIED, full text fetched

**"A Document Skew Detection Method Using Fast Hough Transform", Pavel Bezmaternykh (FRC CSC RAS;
Smart Engines Service LLC), Dmitry Nikolaev (IITP RAS; Smart Engines Service LLC).** arXiv abs page
fetched: title and both authors exact, submitted 5 Dec 2019, cs.CV. Full text fetched twice (ar5iv
HTML and the arXiv PDF; they agree). **Published version** (the row cites only the preprint):
Proc. SPIE **11433**, **114330J** (2020), *Twelfth International Conference on Machine Vision
(ICMV 2019)*, DOI 10.1117/12.2559069 - confirmed by the fetched Crossref record (container title,
event name, publisher, published-print 2020-01-31) and independently by the fetched reference [20]
of Kunina et al. 2023 (§1.6), which spells out "Proc SPIE 2020; 11433: 114330J". The row's
"2019, arXiv:1912.02504" is correct as a preprint citation; cite the venue year as 2020 when the
published version is meant. Method: §2.1. Measured results: §2.1, §5.1.

### 1.2 Duda & Hart 1972 - VERIFIED bibliographically; caution: the FHT paper does not cite it

**R.O. Duda, P.E. Hart, "Use of the Hough transformation to detect lines and curves in pictures",
Communications of the ACM 15(1):11-15, Jan 1972, DOI 10.1145/361237.361242** - fetched Crossref
record confirms title, both authors (Stanford Research Institute), venue, volume 15, issue 1, pages
11-15, 1972. The row's "classical base Duda & Hart 1972 (CACM 15(1))" is a correct citation of the
classical Hough-for-lines paper. **Caution:** it appears **nowhere** in arXiv:1912.02504's text or
reference list (0 hits in the fetched full text). The FHT paper's own lineage runs Hough 1959 ->
Brady [3] / Nikolaev et al. [4] (its §1-2; also 2411.07351 §1-2, fetched). Nothing in this note's
method comes from Duda & Hart; the (rho, theta) normal parameterization they popularised is not the
parameterization the FHT uses (§2.3). Full text not fetched; no content claims made.

### 1.3 Brady 1998 (SIAM) - VERIFIED bibliographically; the FHT the skew paper cites

**M.L. Brady, "A Fast Discrete Approximation Algorithm for the Radon Transform", SIAM Journal on
Computing 27(1):107-119, Feb 1998, DOI 10.1137/S0097539793256673** - fetched Crossref record
confirms title, single author, venue, volume, pages, year. This is reference **[3]** of the skew
paper - the citation it gives for "Fast Hough Transform (FHT)" itself (§1, §2: "its fast
approximation, known as Fast Hough Transform [3]"). SIAM full text paywalled, not fetched; **the
algorithm is described here from the fetched open restatement** in Kazimirov, Nikolaev, Rybakova,
Terekhin, arXiv:2411.07351 (§1.4), which states the Brady-Yong algorithm as executed pseudocode
(its Algorithms 1-2) and its exact complexity (its Theorem 1).

### 1.4 Brady & Yong 1992 (SPAA) and the FHT lineage - VERIFIED; "the one the algorithm comes from"

**M.L. Brady, W. Yong, "Fast parallel discrete approximation algorithms for the radon transform",
Proc. 4th Annual ACM Symposium on Parallel Algorithms and Architectures (SPAA '92), pp. 91-99, June
1992, DOI 10.1145/140901.140911** - fetched Crossref record (venue, authors, year; pages from
2411.07351's fetched reference [7]). The brief asked to cite the FHT source the algorithm actually
comes from: the school's own fetched papers call it **the Brady-Yong algorithm** - "the pioneering
Brady-Yong algorithm ... the de facto standard for practical applications of the Hough transform"
(2411.07351 §1); "the Fast Hough Transform (FHT) algorithm proposed by M.L. Brady" (1811.06378
abstract); "In 1992 explicit scheme for FHT calculating was for the first time proposed by Brady and
others [11] (though more known is his publication in 1998)" (1811.06378 §2). The skew paper cites
the 1998 single-author journal version; both denote the same algorithm. Priority history, from the
fetched Russian text of Ershov & Karpenko arXiv:1712.05615 §1 (labelled: their account): first
proposed by Gots (1993 dissertation, English publication 1995), independently by Voulemin (1994);
1811.06378 §2 adds DEC's "Fast Linear Hough Transform" (1994) and Innsbruck (1993) as independent
inventions. **Cite for this row: Bezmaternykh & Nikolaev 2019/2020 (the skew method) over Brady
1998 = Brady & Yong 1992 (the FHT).**

Supporting fetched papers used below: **arXiv:2411.07351** (Kazimirov, Nikolaev, Rybakova,
Terekhin 2024, *Generalization of Brady-Yong Algorithm for Fast Hough Transform to Arbitrary Image
Size* - full text; the algorithm, complexity theorems, accuracy bound, arbitrary-size variants);
**arXiv:1811.06378** (Aliev, Ershov, Nikolaev 2018, *On the use of FHT, its modification for
practical applications and the structure of Hough image*, ICMV 2018, related DOI 10.1117/12.2522803
from the arXiv page - full text; parameterization, padding, quadrants, arbitrary-angle-range
modification); **arXiv:1712.05615** (Ershov, Karpenko 2017, Russian - abstract+intro; FHT O(n^2
log n), dyadic-pattern peak error O(log n / 6), history). Cited second-hand from 2411.07351's
fetched text (labelled where used): Khanipov's Omega(n^2 log n) lower bound (its ref [13] =
arXiv:1801.01054, downloaded, not read), Karpenko & Ershov 2021 *Problems of Information
Transmission* 57(3):292-300 (its ref [11]), Anikeev, Raiko, Limonova, Aliev, Nikolaev 2021
*Programming and Computer Software* 47:335-343, "Efficient implementation of fast Hough transform
using CPCA coprocessor" (its ref [10] - the existing arbitrary-size implementation).

### 1.5 Nikolaev, Karpenko, Nikolaev, Nikolayev, ECMS 2008 - PARTIALLY VERIFIED; not fetched

The skew paper's ref **[4]** - "Hough transform: Underestimated tool in the computer vision field",
Proc. ECMS '08, 238-246 - is where, per its §1, "the applicability of such approximation usage for
the angle detection problem along with some useful insights were firstly proposed ... but the
algorithm itself was not presented". OpenAlex confirms title and year (2008); its record carries
**three** authors (Dmitry Nikolaev, Simon M. Karpenko, I. P. Nikolayev) against the skew paper's
**four** (D. Nikolaev, S. Karpenko, I. Nikolaev, P. Nikolayev) - discrepancy flagged; cite as the
skew paper's reference list spells it, with this flag. ECMS proceedings not in Crossref; full text
not fetched; **no method content is taken from it** (the derivative-operator convention it defines
is the gap §2.7-6 names).

### 1.6 The SSG criterion: refs [14][15] CLOSED; the open restatement used instead

The skew paper's per-row criterion `SSG_FHT` (its Alg. 1 lines 6, 11) is defined in its refs
[14]/[15]: **Limonova, Bezmaternykh, Nikolaev, Arlazarov, "Slant rectification in Russian passport
OCR system using fast Hough transform", ICMV 2016, Proc. SPIE 10341, DOI 10.1117/12.2268725** and
**Bezmaternykh, Nikolaev, Arlazarov, "Textual blocks rectification method based on fast Hough
transform analysis in identity documents recognition", ICMV 2017, Proc. SPIE 10696, DOI
10.1117/12.2310162**. Both verified bibliographically (Semantic Scholar graph records: titles,
authors, venues; DBLP key `conf/icmv/BezmaternykhNA17`), both **CLOSED** (S2 `openAccessPdf`
status CLOSED, abstract elided by publisher; SPIE DL Incapsula-blocked as in PU.67's run). The
formula below is instead from a **fetched open-access paper by the same institute and company**:
**I.A. Kunina, A.V. Sher, D.P. Nikolaev, "Screen recapture detection based on color-texture
analysis of document boundary regions", Computer Optics 47(4):650-657, 2023, DOI
10.18287/2412-6179-CO-1237** (Crossref-verified; PDF fetched in full from computeroptics.ru), whose
§3.5 eq. (4) defines SSG and whose reference [20] for it is **the skew paper itself** - i.e. an OA
restatement one citation step from the closed original, by overlapping authors (Nikolaev is on both;
Smart Engines Service LLC / IITP RAS on both). Found via an OpenAlex `fulltext.search` for "SSG" +
"fast Hough transform" (2 hits: the skew paper and this one) after the `cites:W2801491629` walk
surfaced it. §2.4 quotes it. **If the implementer ever obtains [15] itself and it disagrees with
the restatement, changing the criterion is a departure needing the product owner's OK (§4 fence).**

### 1.7 DISEC'13 - VERIFIED bibliographically; methodology as summarised in the fetched paper

**A. Papandreou, B. Gatos, G. Louloudis, N. Stamatopoulos, "ICDAR 2013 Document Image Skew
Estimation Contest (DISEC 2013)", 12th ICDAR, Aug 2013, DOI 10.1109/ICDAR.2013.291** - fetched
Crossref record confirms title, authors, venue, year. Full text not fetched (IEEE); the dataset and
metric definitions used below are the fetched skew paper's §4.1 summary of it (§2.5).

## 2. The method as published

### 2.1 The skew detection algorithm - arXiv:1912.02504 §3, Algorithm 1 (fetched)

Input: a **grayscale image I**; "the algorithm does not require initial binarization step, but can
deal with binary images as well" (§3). Steps, as listed in its Alg. 1:

1. `Dh <- HorizontalDerivative(I)`; `Fh <- FastHoughTransform(Dh)` - the accumulator for **"mostly
   horizontal"** lines.
2. `H <- height(Fh)`; for every row `i` of `Fh`:
   `Kh[i] <- sqrt(1 + i^2/(H-1)^2)` and `Ch[i] <- (Kh[i])^3 * SSG_FHT(Fh[i])`.
3. `Dv <- VerticalDerivative(I)`; `Fv <- FastHoughTransform(Dv)` - **"mostly vertical"** lines;
   `W <- width(Fv)`; for every row `i` of `Fv`: `Kv[i] <- sqrt(1 + i^2/(W-1)^2)`,
   `Cv[i] <- (Kv[i])^3 * SSG_FHT(Fv[i])`.
4. `Cv <- Recalculate(Cv)` - interpolated to the length of `Ch` ("These vectors have different
   lengths because of the FHT calculation peculiarities. So, they represent criterion values for
   different sets of angles", §3).
5. `C <- Combine(Ch, Cv)` - "combined into one vector C by summing the appropriate values" (§3);
   `I_res <- argmax(C)`; `alpha <- arctan(skew(I_res))`.

Both directions are computed "to take into account both text lines and small vertical strokes of
symbols" (§3). The paper publishes **no tunable thresholds** for the estimate itself - no acceptance
gate, no confidence test, no interpolation of the peak; Alg. 1 returns the angle alone. What it
measured, and on what: §5.1.

`Kh[i] = sqrt(1 + tan^2) = sec(phi_i)` where row `i` carries slope `i/(H-1)` - so the weight is
`sec^3(phi)`, a geometric correction for oblique lines being longer and denser in the accumulator
(interpretation labelled: the paper states the formula, not its reading; the same weight appears
inside Kunina's SSG with the explicit note "the weight function k(t) guarantees the criterion
covariance in terms of the input image rotation", §2.4).

### 2.2 The FHT itself (Brady-Yong) - as restated in fetched arXiv:2411.07351 §1-4

- **What it computes:** sums of image values over **dyadic patterns** - staircase polylines that
  approximate the straight lines `y = x*t/(n-1)`, `t = 0..n-1`, for an `n x n` image (its §2-3,
  Alg. 2). Every vertical shift of every pattern is computed, so the accumulator row `t` is the
  projection profile at slope `t/(n-1)` over all offsets.
- **How:** dynamic programming over a recursive bisection of the image width (its Alg. 1):
  split `w` into two parts, recurse, then merge - for each row `t`,
  `J(t,:) <- JP(0)(t*kP,:) + Rotate(JP(1)(...), (t - floor(t*kP(1))) mod h)`, i.e. **a vector
  addition of one cyclically shifted row-pair per accumulator row per level** - which "is used to
  skip the repeated calculation of the sums of already processed segments" (its §1).
- **Cost:** `Theta(n^2 log2 n)` summations for `n = 2^q` (Brady-Yong, its §1-2); exact count
  `fS(n) = (floor(log2 n)+2)*n^2 - 2^(floor(log2 n)+1)*n <= 1.052*n^2*log2 n` (its Theorem 1,
  eq. 1); arbitrary-size generalisations FHT2DS (Anikeev 2021) and FHT2DT (this paper) keep the
  same `Theta` (Theorem 1, eq. 2). Khanipov proved the matching `Omega(n^2 log2 n)` lower bound for
  dyadic-pattern HT computation, so "the Brady-Yong algorithm is non-improvable in terms of speed"
  (its §2, citing ref [13]).
- **Accuracy of the approximation:** a dyadic pattern deviates from its ideal line by at most
  `log2(n)/6` px (`n = 2^q`, even q; `-1/18` for odd q) - Karpenko & Ershov 2021, cited second-hand
  from its §2; its own Theorem 2 generalises: `E_T(n) <= floor(log2 n)/6 + 1 - 2^(-floor(log2 n))`.
  At our scales: `w = 135` -> bound ~2.16 px; `w = 374` -> ~2.33 px (arithmetic on Theorem 2).
- **Speed measured by the skew paper** (§4.2, fetched): for a `1095 x 894` DISEC image and "number
  of projections equal to 3975 (for this image it is an exact number of projections required for
  the FHT calculation for both vertical and horizontal directions)": **FHT 45 us vs. discrete Radon
  transform ~21000 us** - the per-angle-transform scheme (our sweep's shape) costs ~467x more.
  Machine: AMD Ryzen 7 1700, Ubuntu 18.04, 16 GiB. (3975 = 2*(1095+894-1) - 1: projections per
  direction = w+h-1 - arithmetic reproducing their count from the padded-transform geometry of
  §2.3; derivation labelled.)

### 2.3 Parameterization, padding, angle ranges - fetched arXiv:1811.06378 §3-4

- **Brady parameterization:** lines are "mostly vertical" when `|tan(phi)| <= 1` and "mostly
  horizontal" when `|cot(phi)| <= 1` (phi = the normal's angle); a mostly-vertical line is stored
  as `(x0, shift)` with `shift = h*tan(phi)`; the mostly-horizontal case is the transpose (§3.1).
  A point maps to a straight "linear pattern" in the accumulator (their §3 title result: "using
  Brady parameterization transforms any line into a figure of type 'angle'").
- **Padding and the "black zone":** the image is extended by `h x h` (mostly vertical; result
  `(w+h) x h`) or `w x w` (mostly horizontal) so cyclic shifts wrap into zeros instead of real
  data; the accumulator contains a triangular **zero region whose rows correspond to no line
  crossing the image** ("black zone", §3.1-3.2) - those rows carry no evidence and must not win
  the argmax on a correction term alone.
- **Full angular coverage:** the four quadrants `[315,0] + [0,45] + [45,90] + [90,135]` concatenate
  edge-to-edge (some flipped) into one Hough image of size `2*(w+h)-3` with points staying collinear
  across seams (§3.3, eqs. 1-2) - the published mechanism for **signed** angles around horizontal.
- **Arbitrary angle range [gamma1, gamma2]:** scale x by alpha (compresses the tan-range) and shear
  by gamma (recentres it); both fold into the FHT's first iteration with **no extra operations or
  memory** ("FHTShift", §4-5) - the published mechanism for restricting the search to a band like
  our +-30 deg instead of the full +-45 deg.

### 2.4 The SSG criterion - fetched Kunina/Sher/Nikolaev 2023 §3.5, eqs. (4)-(6) (OA restatement, §1.6)

For a Hough image `H` of size `w x h` (row = angle bin `t`, column = offset `s`):

```
SSG_def(H, t) = sum_{s=0}^{w-1} k(t)^(3/2) * (H(s+1, t) - H(s, t))^2            (their eq. 4)
k(t) = 1 + ((t - floor(h/2)) / floor(h/2))^2                                     (their eq. 4, "where")
t_m = argmax_t SSG(H_h, t)  (over the analysed range, per band h/v)              (their eq. 5)
c_m = 1 - SSG(t_perp)/SSG(t_m)  (perpendicular band ratio; ~1 pronounced
       orientation, ~0 isotropic)                                                (their eq. 6)
```

with an absolute refusal threshold on the peak (`max S_m < T_swroi` -> structure not found, their
§3.6-4). `k = sec^2`, so `k^(3/2) = sec^3` - identical total weight to the skew paper's external
`(Kh[i])^3` with `Kh[i] = sqrt(1 + i^2/(H-1)^2)` (consistency arithmetic; the 3/2 superscript was
read from PDF text extraction - if it were 3 the two sources would disagree by sec^3, and the skew
paper's own Alg. 1, which is unambiguous, is the one this note implements). **SSG is the sum of
squared successive differences of a projection profile - the same criterion family our
`profileSharpness` computes on a warped strip** (Leptonica's `pixFindDifferentialSquareSum`,
PU.67 §2.3): the FHT's contribution is evaluating it at every angle from one transform, since
accumulator row `t` IS the projection profile at slope `t` over all offsets (§2.2). Equivalence
labelled as inference from the fetched algorithms, not quoted from either paper.

### 2.5 What the papers measured

- **Skew paper (§4, fetched):** DISEC'13 benchmark - 155 unique document images x 10 rotated
  samples, rotation angles random in (-15 deg, +15 deg), ground truth set manually once per unique
  image (§4.1, summarising the contest paper §1.7). Metrics at threshold 0.1 deg: **AED 0.086 deg,
  TOP80 0.056 deg, CE 68.80 %**; **maximum error 0.547 deg**; ranked third among the table's
  methods (behind LRDE-EPITA-a 0.072/0.046/77.48 and Ajou-SNU 0.085/0.051/71.23; ahead of
  LRDE-EPITA-b, Gamera, CVL-TUWIEN - its Table 1). Error is **independent of the ground-truth
  angle** across 1-deg buckets (its Fig. 3); worst 10 image groups AED 0.228-0.307 deg (its
  Table 2). Speed: §2.2 above. "The proposed method is straightforward and doesn't require any
  preprocessing step" (§4.2).
- **DISEC'13 metric definitions** (as summarised in the fetched §4.1): AED = average absolute error;
  TOP80 = average absolute error over the best 80 % of results; CE = percentage of estimates within
  0.1 deg of truth.
- No published measurement exists for FHT skew on strips, seven-segment displays, images under
  ~500 px, or angles beyond +-15 deg - every such number in §5.4-5.5 of this note is ours or
  labelled inference.

### 2.6 Duda & Hart's role

None in the executed method (§1.2). The row's "classical base" phrasing is kept as lineage only.

### 2.7 What the published method does NOT contain (the fence for §4)

From the fetched texts: (1) **no confidence output** - Alg. 1 returns the angle; nothing in the
skew paper ranks or gates its estimate (the row's "yields the accumulator mass as a confidence" is
not in the paper - §7-3); (2) **no per-row / local use** - one global skew per image; (3) **no
retry or policy wrapper** - the estimate is unconditional; (4) **no acceptance gate at all** (no
Leptonica-style conf >= 3, no minimum gain); (5) **no sub-bin peak refinement** - bare argmax;
(6) **the derivative operators are undefined in the fetched text** - "HorizontalDerivative" /
"VerticalDerivative" get no formula; the convention lives in closed ref [4]; (7) **no treatment of
italic/slanted glyph stroke** as a confounder - the method deliberately USES vertical strokes
(§2.1 step 3 rationale), which is exactly what our domain forbids (`PumpRowDeskew.swift:16-17`,
PU.67 A9); (8) the accumulator's signed-angle layout is **ambiguous across the fetched sources**
(the skew paper's `Kh[i]` indexing has no centring term, while 1811.06378 §3.1-3.3 describes
signed coverage via padding/quadrant concatenation) - §4-A5 names the test that pins it. Anything
of ours in those eight slots is an adaptation, named below.

## 3. Mapping onto this code

The method replaces the **search inside** `PumpRowDeskew.deskew` and nothing else in the pipeline.
Published element -> our seam:

| Published element (source) | Our implementation today | Becomes |
|---|---|---|
| Grayscale input I, no binarization (Alg. 1 preamble) | the 48-px warped strip's grayscale (`score` `:66-76`, `grayscale()` `PumpQuadWarp.swift:23-32`) | ONE axis-aligned crop of the row's upright box (`box`/`centre` `:58-60`, `searchPadding` `:34`, `inside` clamp `:139-150` kept), downscaled to `searchStripHeight` 48 (`:36`) - no per-angle warp at all (A1) |
| Dh/Dv derivative step (§3; operator undefined, §2.7-6) | none - raw row-mean luminance (`profileSharpness` `:168-173`) | across-row first difference of luminance, horizontal band only (A4) |
| `FastHoughTransform` (Brady-Yong, §2.2) | the 72-trial warp sweep `:77-86` (60 coarse `:79-82`, 11 fine `:83-86`, 1 level `:77`) | one recursive dyadic transform per row (new pure-Swift file; merge = vector add + cyclic shift, Theorem-1 shape); arbitrary-size variant (FHT2DS/2DT) since strips are not powers of two |
| Accumulator row = projection profile at slope t (§2.2, §2.4) | one warped strip per trial angle, its row means | row `t` of `Fh` - all angles at once |
| `SSG_FHT` per row (Alg. 1 lines 6, 11; eq. 4 §2.4) | `profileSharpness` `:166-177` (squared successive row-mean differences, / height) | sum of squared successive differences along each accumulator row - **same criterion quantity** (§2.4 equivalence, labelled inference) |
| `(Kh[i])^3 = sec^3` weight (Alg. 1 lines 5-6) | height normalisation `:176` (ours, PU.67 A1) | the paper's weight; height normalisation retired |
| `Recalculate`/`Combine` of the vertical band (Alg. 1 lines 12-13) | (absent - we never score vertical structure, `:16-17`) | **DROPPED** - horizontal band only (A3, italic guard) |
| `argmax -> arctan` (Alg. 1 lines 15-16) | best-of-grid at 0.2 deg quantisation (`fineStep` `:31`) | argmax over the +-30 deg rows (A5) + quadratic sub-row interpolation (A2) |
| +-15 deg DISEC range, full band computed (§4.1) | `maximumAngle` 30, `coarseStep` 1, `fineStep` 0.2 (`:24,30-31`) | `maximumAngle` survives as the row-selection bound (or FHTShift scale/shear); `coarseStep`/`fineStep` **retired** |
| (no gate published, §2.7-4) | `minimumGain` 5 % over level (`:39,87-89`) | kept as a ratio gate on the SSG curve: accept iff `C(that^) >= (1+minimumGain)*C(0)` (A6) |
| (no confidence published, §2.7-1) | none - `Result{quad, degrees}` `:46-51` | `Result` gains `confidence`; formula = named published statistics on the same C curve (A6); consumed by PU.70 (`passesSize` `PumpDisplayCapture.swift:152-155` vs `minimumWidestRowFraction` `:88` - wiring is PU.70's row) |
| (page-scale input, §2.5) | `largeTurn` 6 deg + `rowSize` inversion (`:29,67-70,126-133`) | **retired** - no per-angle crop reshaping exists any more (A7); the >6 deg guard intent moves to the row's >6 deg accuracy bucket (§5.2: 5 boxes) |
| Padding, black zone (§2.3) | (absent - warps sample black outside and the clamp forbids it, `:136-138`) | pad per 1811.06378 §3.1; zero-coverage rows excluded from argmax (A8); `inside` clamp kept |
| Output geometry | `rotatedRect` `:154-161`, `Result.quad` | unchanged |
| Photo levelling | `levelAngle` median `:287-292`, `levelled` vImage warp `:298-322`, `unlevelled` `:325-331`, `minimumLevelAngle` `:282` | unchanged - consumes per-row angles whatever produces them (A9) |
| Policy wrapper | `DeskewMode` `:206-220`, `readPhotoDetailed` `:251-275`, `classify` retry `PumpDisplayCapture.swift:346-359` | unchanged (PU.67's subject; still HELD at 52/51 = 0.981) |

**Types.** In: unchanged - a detector quad as `[CGPoint]` pixels + `PumpRGBImage` (`deskew:57`).
Out: `Result{quad, degrees, confidence: Double}` (`:46-51` extended). The normalised bridge
`PumpReader.deskewed` (`PumpRowDeskew.swift:230-234`, called from `candidates(for:deskewRows:)`
`PumpReader.swift:54-63`) gains a variant that carries `degrees`+`confidence` out for PU.70; the
existing quad-only call sites (`levelAngle` `:288`, `candidates`) keep their signatures.

**Constants retired:** `coarseStep` (`:30`), `fineStep` (`:31`), `largeTurn` (`:29`) and the
`rowSize` function (`:126-133`); `profileSharpness` (`:166-177`) retires as the production scorer
(kept only if a test needs the old oracle - the implementer decides, and says so). **Repurposed:**
`maximumAngle` (`:24`) from sweep range to accumulator-row selection bound. **Kept:**
`searchStripHeight` (`:36`), `searchPadding` (`:34`), `inside` (`:139-150`), `minimumGain` (`:39`,
mechanism; value see A6), `bandFraction`/`bandMargin`/`inkBand` (`:42-44,182-203`, the `fitsBand`
path - PU.71's territory, untouched), `minimumLevelAngle` (`:282`).

**C/Accelerate verdict (the row's conditional clause):** **no C or C++ target is needed; the note
says the Swift loop CAN meet it.** Arithmetic (labelled inference; the row's Release gate
confirms): per median strip (135 x 48, §5.2) the transform is ~135*48*(ceil(log2 135)+2) ~= 65 K
additions (Theorem-1 shape, §2.2) plus SSG ~182*47 ~= 9 K - tens of microseconds of flat-array work
even scalar; at native crop size (median 374 x 133) ~0.5 M additions, still sub-millisecond. The
paper's own C implementation does 3975 projections over ~1 Mpx in 45 us (§2.2) - our input is ~150x
smaller in pixels and ~8x in projections. The merge step (vector add with a cyclic offset) maps to
two `vDSP_vadd` calls per row if wanted; Accelerate is already imported (`PumpRowDeskew.swift:1`).
No Core ML, no Metal, no `Package.swift` target change; iOS 18.0 floor untouched (no new API).

## 4. Every adaptation, named and justified

Fence restated: **a departure the row's implementer adds later that is not listed here needs the
product owner's OK.**

- **A1. Input scale: one axis-aligned crop at `searchStripHeight` 48, not a ~1 Mpx document scan.**
  *Paper:* whole document images (155 DISEC scans, ~1095 x 894 typ., §4.1-4.2); nothing smaller
  measured. *Ours:* the row's upright box (`:58-60`), clamped in-frame (`:139-150`), downscaled to
  48 px height (existing `searchStripHeight` `:36`); measured strip widths 105-181 px, median 135
  (§5.2). *Why:* uniform cost bound across a corpus whose row crops vary ~10x (PU.67 A4's
  reasoning, unchanged); the read path still warps at 96 px (`PumpReader.swift:13`), so the search
  scale never degrades the read. *Consequence, owned:* the native angle grid is 0.25-0.38 deg at
  those widths (§5.5) - hence A2. *Named fallback inside this note:* if the row's agreement gate
  (F1) shows the error distribution clustering at the grid step (quantisation-dominated), raise the
  FHT input height toward the native crop (the paper's own accuracy scales with image size, §2.5
  Fig. 3 logic); that is a parameter move inside the published method, not a new departure.
- **A2. Sub-row quadratic peak interpolation - the paper takes a bare argmax.**
  *Paper:* `I_res <- argmax(C)` (Alg. 1 line 15); no refinement published; at DISEC scale the grid
  is ~0.03 deg (1/1987 rad, arithmetic on §2.2's projection count) so none was needed. *Ours:*
  Lagrange/quadratic fit through the SSG maximum and its two neighbours before `arctan`. *Why:* our
  grid is ~10x coarser (A1); the refinement is itself published in this family - Leptonica's
  `numaFitMax` on the sweep peak (PU.67 §2.3, fetched source) - so this is importing a published
  refinement of the sibling method, not inventing one. Without it the estimator's endpoint is
  provably no better than 0.25-0.38 deg.
- **A3. Horizontal band only - the Ch+Cv fusion is DROPPED.**
  *Paper:* computes both bands and sums them, explicitly "to take into account both text lines and
  small vertical strokes of symbols" (§3, Alg. 1 lines 7-13). *Ours:* only the mostly-horizontal
  accumulator; no `Fv`, no `Recalculate`, no `Combine`. *Why:* the corpus's pump fonts are often
  italic, and vertical strokes are slanted by design - voting them would read the italic as a turn.
  This is the existing hard guard (`PumpRowDeskew.swift:16-17`: "Vertical strokes are deliberately
  not used"; PU.67 A9), mutation-tested by `italicIsNotATurn`
  (`PumpRowDeskewTests.swift:96`), which must stay green (F3). Cost side-effect: half the
  transform work disappears.
- **A4. Derivative input: across-row luminance difference; the paper's operator is undefined in
  fetched text.**
  *Paper:* `Dh <- HorizontalDerivative(I)` with no formula anywhere in the fetched text; the
  convention lives in closed ref [4] (§2.7-6) - this note will not guess it from memory. *Ours:*
  feed the mostly-horizontal FHT the across-row first difference of luminance (dI/dy - the operator
  that responds to the flat segment tops/bottoms the current scorer uses, `:12-17`), polarity-free
  after the SSG squaring (PU.67 A1's reasons (i)-(iii) carry over unchanged: glare/night boards
  break fixed thresholds; both LCD and LED polarities exist). *OA precedent for raw luminance:*
  Kunina §3.5 applies SSG to the Hough image of a (contrast-enhanced) grayscale window with no
  derivative at all. *Decision:* the difference operator ships first; switching to raw luminance is
  within this note IF the TRAIN-split measurement prefers it and the switch is reported; anything
  else (binarization, gradient magnitude, Sobel) is a departure.
- **A5. Range +-30 deg and SIGNED angles: row selection over the padded/concatenated accumulator,
  or FHTShift - and a test that pins the layout.**
  *Paper:* the full mostly-horizontal band (+-45 deg via padding/quadrants, §2.3); DISEC's range is
  +-15 deg with no statement of how negative skews index into `Kh[i]` (the fetched Alg. 1's `i/(H-1)`
  has no centring term - §2.7-8 ambiguity). *Ours:* keep `maximumAngle` 30 as the bound on which
  accumulator rows are read; obtain signed coverage by one of the TWO published mechanisms -
  quadrant concatenation (1811.06378 §3.3) or shear+scale range mapping (§4-5, "FHTShift") - choice
  recorded in the build; the `Recalculate` interpolation of Alg. 1 line 12 is not needed since only
  one band survives (A3). *Why 30 stays:* hand-drawn truth at HEAD tops out at 10.35 deg (§5.2) but
  the runtime reader has met larger turns on detector rows (PU.65's tilted arm), and shrinking the
  range is a separate decision. *Mandatory pin:* a synthetic strip with a line drawn at signed theta
  must peak at signed theta within one grid step pre-interpolation (F2) - this, not prose, resolves
  the layout ambiguity.
- **A6. Acceptance gate and the confidence formula - both named choices, neither in the paper.**
  *Paper:* no gate, no confidence (§2.7-1,4). *Ours:* (i) the existing relative-gain acceptance
  survives verbatim in spirit - turn kept iff `C(theta^) >= (1 + minimumGain) * C(0)`,
  `minimumGain` 0.05 (`:39,87-89`), our unpublished gate (PU.67 A6) re-based onto the SSG curve;
  its value is NOT re-fitted by this row - if the SSG scale makes 5 % misfire, re-fitting on the
  TRAIN split is a reported change, not a silent one. (ii) `Result.confidence` exposes THREE
  published-shape statistics of the same C curve, so PU.70 fits its threshold on TRAIN against
  whichever separates (its row already says "a threshold fitted on the TRAIN split"): the
  Leptonica-style ratio `C(theta^)/min(C over the searched rows)` (PU.67 §2.3, fetched; their
  working range 3.0-6.0 is the reference point), Kunina's normalised dominance `c_m` (eq. 6, §2.4 -
  with the perpendicular band unavailable per A3, computed as peak-vs-range-median and labelled),
  and the raw peak mass `C(theta^)` (the row text's "accumulator mass"). *Why:* the row promises
  "a confidence"; the paper offers a criterion curve and nothing else; every formula above is a
  fetched published statistic over that curve, and the choice among them is measurement, not
  invention.
- **A7. `rowSize`/`largeTurn` retire.**
  *Paper:* nothing comparable - the page is the input, no per-angle object reshaping exists.
  *Ours today:* past 6 deg each trial crop is re-sized by inverting the upright-bound trigonometry
  (`:29,62-71,126-133`), because a fixed crop of a nearly-square upright bound warps to a strip a
  few dozen px wide where "the digits alias and a wrong angle can outscore the right one" (`:62-65`);
  mutation-tested by `largeTurnRecoversTheRowSize` (`PumpRowDeskewTests.swift:62`). *With FHT:* the
  failure mode is structural to per-angle warping - there is no warp. The upright box already
  contains the turned row; lines at its angle vote in the accumulator (padding per A8 covers lines
  exiting the crop). *Guard transfer:* the >6 deg population (5 hand boxes, §5.2) becomes a named
  accuracy bucket of the F1 distribution; `largeTurnRecoversTheRowSize` retires with `rowSize`, and
  its INTENT (>6 deg rows keep their length/height in the output quad) is already carried by
  `rotatedRect` + the unchanged output path - the build must show the >6 deg bucket does not
  regress against §5.3's (median err 1.43 deg, n=5).
- **A8. Padding and the black zone.**
  *Paper:* pad by h x h / w x w so cyclic shift wraps into zeros; the accumulator's zero-coverage
  triangle carries no evidence (§2.3). *Ours:* same padding on the crop before the transform; rows
  whose patterns never cross real pixels are excluded from the argmax (they cannot win on SSG alone
  once the sec^3 weight is applied to nothing - but the exclusion is explicit, because the weight
  GROWS with |i| and a partly-covered row could otherwise outscore a fully-covered one). The
  `inside` clamp (`:139-150`) stays: it guards a different artefact (black outside-frame samples
  scoring as edges, `:136-138`) at the crop level.
- **A9. Per-row angles and median levelling are inherited, not re-decided.**
  The paper estimates one global skew (§2.7-2); our per-row use with median aggregation
  (`:19-20,284-292`) is PU.65's adaptation, already fenced as PU.67 A8; FHT changes the producer of
  each row's angle and nothing about the aggregation. Likewise `DeskewMode` and the retry policy are
  PU.67's wrapper (its A10), untouched here.
- **A10. Domain.** Seven-segment pump-display rows (two strong horizontal edges per glyph, segments
  a/d; glare, reflections, night boards, both display polarities) instead of scanned document pages;
  a 66-still heldout measurement tier instead of a 1550-sample contest set. Statistically the FHT
  method is distribution-free (it is a transform plus an argmax); the accuracy transfer is the
  open question F1 answers, and §5.5 states the expectation.

**On-device constraints, all satisfied:** iOS 18.0 target - pure Swift, `Accelerate` already
imported, no API newer than the floor; iPhone 12 - the cost arithmetic of §3 (tens of microseconds
per row) is two orders of magnitude under the current per-row deskew cost (§5.4); no Core ML/Vision
change; no Metal; no new package target; bundle impact §6.

## 5. What the paper measured; what we measured; the populations; falsification

### 5.1 Published measurements (fetched only)

§2.5 and §2.2 carry them: DISEC'13 AED 0.086 deg / TOP80 0.056 deg / CE 68.80 % / max 0.547 deg,
flat error-vs-angle, third of six in its Table 1; FHT 45 us vs DRT 21 ms at 1095 x 894 / 3975
projections. **No published number exists for inputs at our scale** (105-181 px strips), our domain
(seven-segment), or our range (+-30 deg) - the expectations below are arithmetic on the fetched
method, labelled.

### 5.2 Our populations, counted at HEAD `c22d0217` (fixtures == `b42f38da`; file + filter for each)

Counted with python over `git show HEAD:` blobs of
`Spike/ReceiptSpike/fixtures/pump/{windows.json, split.csv, expected.csv}` (the working tree's
copies are mid-annotation and differ - §0); filters are the harness's own so the counts are
reproducible:

| Population | Count | File and filter |
|---|---|---|
| Still image files in fixtures/pump | **328** | jpg/jpeg/png/heic under the folder |
| Heldout stills (live-path universe) | **68** | `split.csv` == heldout AND `windows.json` `reviewed: true` - `PumpReaderTestSupport.isHeldout` (`:83`, split `:57`, reviewed `:74`) |
| Scored heldout numeric cells | **183** | `expected.csv` non-blank liters/unitPrice/total minus `csvDisagrees` keys - `measureLive`'s filter; cross-check: equals `PumpPhotoGate.readerNumericTotal` at HEAD (`PumpPhotoGate.swift:95`, from `git show HEAD:`) |
| Upright heldout stills (rotationCW == 0, expected row present) | **66** | the apportionment loop's filter (`PumpApportionmentTests.swift:75-80`); 2 rotated stills skipped |
| Hand windows on those 66 (field + non-empty text + quad) | **243** | the apportionment `truth` filter (`:214-223`) |
| **Hand transaction boxes (non-board) - THE ROW'S POPULATION** | **190** | the presence loop's filter (`:100-105`); matches the brief's "190 heldout hand quads" exactly; `placedBy`: 179 hand / 11 auto |
| Drawn angle of the 190, PIXEL space (top edge, EXIF-oriented) | median **0.93 deg**, p90 **3.39**, max **10.35** (pump-166 total); >0.5 deg: **128**; >2 deg: 48; >6 deg: **5**; >12 deg: **0** | this note's computation, `atan2(dy*H, dx*W)` over `windows.json` quads - **NOT** the normalised-space numbers PU.65/PU.67 quoted (§7-1) |
| Hand-quad geometry | aspect median **2.81** (p10 2.20, p90 3.78); pixel width median **374** (p10 131, p90 1271); 48-px-strip width **105-181, median 135** | `PumpQuadWarp.aspect` formula (`:81-86`) over the same quads |
| App path at HEAD | **45 committed / 45 correct of 183**; Wilson 2s 95 % [0.921, 1.000], 1s lower 0.9433 | `PumpPhotoGate.readerCommitted`/`readerCommittedCorrect` (`:86,91`, HEAD blob); floors bound through `liveCommittedFloor`/`livePrecisionFloor` (`PumpReaderPipelineTests.swift:56-58`, `livePath` `:82`); intervals per PU.68 §4 |
| Annotated tier at HEAD | **112 / 112** (`committedFloor` `:28` HEAD; `gateMirror` `:187`); Wilson 2s [0.967, 1.000] | PU.79's close commit `2f7fd5dd` ("annotated tier reads 112/112 and the live path 45/45") |
| PU.67's held `.onRefusal` measurement | 52 / 51 = 0.981, Wilson 2s [0.899, 0.997] | `docs/EXTRACTION.md:1093-1100` (HEAD), PU.68 §4 table |
| Train split (PU.70's fitting tier) | **256 stills, 255 reviewed** | `isTrain` (`:85`) over the same blobs; PU.68 counted 250 at `310e7660` - the corpus grows |
| Leak population | **116** non-pump fixtures (receipts 97, screenshots 9, expenses 9, fiscal 1); shipped instrument read 6/116 routed, none commits | PU.68 §6 + its close text (`docs/TASKS.md`, PU.68 row) |

Corpus drift warning (the brief's rule): PU.78's commit will move the app-path constants (47/47,
floor 118 per its working-tree state) and the owner's pump-275 re-annotation will move heldout to 67
and the 190 with it; **the implementer re-counts every population above at the build commit with
these filters** (the row's "live >= PU.67's count" reads against the constants at THAT commit).

### 5.3 The sweep's angle error against the hand quads today (this note's measurement)

**Instrument (read-only):** `./ios/.build/opt/debug/pump-read <still>` with request
`{"rotationCW": 0, "currency": <expected.csv>, "deskew": "always"}`; estimate = pixel-space top-edge
angle of each returned `candidates` quad with `detected: true` (these are the deskewed detector
rows - `candidates(for:deskewRows: true)`, `PumpReader.swift:54-63`; widening preserves the top-edge
direction, `:157-171`); truth = drawn top-edge angle of the hand box it matches at upright-bounds
IoU >= 0.3, the apportionment matching rule (`PumpApportionmentTests.swift:227-236`). Binary
provenance and currency: §0. Raw per-box records: temp-dir `angle_pairs.jsonl` (path in the header).

**Proxy caveat, stated up front:** the row's gate feeds the HAND QUADS themselves to the estimator;
this instrument measures the sweep on DETECTOR BOXES matched to hand quads, because `pump-read`
exposes no deskew-a-given-quad mode and this note may not write code. `deskew` reads only the input
quad's upright bounds and centre (`:58-60`), so the two instruments coincide up to the
detector-vs-hand framing difference. Coverage: **174 of 190** hand boxes matched a detected
candidate (0.916, Wilson 2s [0.868, 0.948]); the 16 unmatched sit on 8 stills (pump-008, -134,
-166, -186, -187, -190, -194, -198). The implementer's gate run closes this gap by feeding hand
quads directly.

**Result (n = 174, |est - drawn truth| in degrees):**

| statistic | value |
|---|---|
| median | **0.68** |
| mean (= our AED analogue) | **0.96** |
| p90 | **1.99** |
| max | **5.60** (pump-179 unitPrice: est 6.00 vs truth 0.40, IoU 0.44, kept=False - framing mismatch) |
| within 0.5 deg | 64 = 0.368 [0.300, 0.442] |
| within 1 deg (= CE@1 deg) | **120 = 0.690 [0.617, 0.754]** |
| within 2 deg | 158 = 0.908 [0.856, 0.943] |
| beyond 2 deg | 16 = 0.092 [0.057, 0.144] |
| signed error | median +0.16, mean +0.22 (mild over-turn) |
| est == 0 (refusal or level find) | 20 boxes: 8 with truth <= 0.5 deg (legitimate level holds), **12 refusals of genuinely turned rows** (the `minimumGain` gate or a 0-scoring search) |
| DISEC-analogue metrics | AED 0.958 deg, TOP80 0.577 deg, CE@0.1 deg **7.5 %** (the 0.2 deg grid cannot resolve 0.1 deg - the paper's CE is not transferable to our quantisation) |
| robustness slices | IoU >= 0.7 (n=129): median 0.60, mean 0.88 - framing quality is NOT the dominant error term; truth <= 0.5 deg: median err 0.80 (n=59); 0.5-2 deg: 0.60 (n=71); 2-6 deg: 0.68 (n=39); >6 deg: 1.43 (n=5) |

Worst matched boxes (est vs truth): pump-179 unitPrice 6.00/0.40 (IoU 0.44); pump-166 total
-6.00/-10.35; pump-055 liters -5.20/-0.85; pump-161 unitPrice 10.80/6.62; pump-161 liters
1.40/-2.67; pump-125 liters -4.60/-0.90; pump-277 total 3.40/0.00; pump-080 unitPrice -3.80/-0.88.

**Reading (labelled inference):** the error mass sits in (a) content failures - glare/reflection
rows where the profile criterion locks onto the wrong structure (pump-055, -125, -277 are named
glare/reflection fixtures) - and (b) near-level rows where the sweep "finds" 2-6 deg of turn that
is not drawn; not in the 0.2 deg quantisation (69 % already within 1 deg; the IoU>=0.7 slice barely
improves). FHT is a different voting scheme over the same pixels: it removes the warp-interpolation
smearing and adds dyadic-pattern deviation (~2 px bound, §2.2) - a large distribution shift in
either direction is not expected, and the row's agreement gate (F1) decides.

### 5.4 Latency - and why this note does NOT report a baseline number

**The latency measurement is unreliable on this machine right now, and reporting a median would be
false precision.** Same binary, same still (pump-030, 12-Mpx), same request, minutes apart:

| when | readPhoto, deskew off |
|---|---|
| run 1 batch, ~01:40 (still #4 of 66) | **104 ms** |
| this note's confirmation, ~02:45, three fresh processes | **2523 / 2516 / 2551 ms** |
| ~02:47, `PUMP_REPEAT=3` (measured call is the 4th, so warm) | **2553 ms** |

The 24x swing is NOT warm/cold (the warm 4th call is as slow as the cold 1st), NOT photo size (same
still), and NOT CPU load (load average stayed 1.2-1.6 throughout). It is **Neural Engine / GPU
contention with the owner's live annotation session**: `pgrep -x pump-read` shows the annotator's
resident `--slice-serve` and `--read-serve` processes (§0), each holding a loaded CoreML detector +
classifier; while the owner re-annotates pump-275 (§0), those processes issue ANE inferences that
serialise against this note's `pump-read` ANE calls. The clean numbers agree with each other and
with the tree: run 1's first stills (pump-028 90 ms off / 128 always, pump-030 104 / 154) and the
idle smoke test (pump-028 142 ms) all sit at **~90-150 ms**, matching PU.75's committed "read
112-164 ms Release-on-Mac" (`docs/TASKS.md`, PU.75 row). The contended batch medians (off 2719-2858
ms, onRefusal on refusals 9108-9131 ms) are the SAME pipeline inflated ~25x by ANE contention.

**Consequence for this row:** the row's gate - "a Release latency number for the refusal path,
before and after" - **must be measured on a quiet machine (annotator closed, no other CoreML client)
or on-device (Capture Lab, PU.39), never while the owner is annotating.** This note therefore hands
the implementer a clean-order-of-magnitude, not a median: a 12-Mpx still reads in **~90-150 ms**
when the ANE is free; deskew-always added ~40-50 ms over off on the two clean stills (pump-028
+38 ms, pump-030 +50 ms, for 3 rows each -> **~13-17 ms per row for the 72-trial sweep**).

The structural cost the FHT replaces is PU.67 §6's count, accurate at HEAD: per row, **72 score
evaluations**, each a `warpToStrip` scalar homography over a 48 x 105-181 strip (§5.2 widths) plus a
CGImage creation, a decode back to RGBA (`PumpQuadWarp.swift:72-75`), a grayscale pass and a profile
pass - ~72 CoreGraphics round-trips per row, measured here at ~13-17 ms/row. The FHT replaces that
with one derivative pass + one transform + one SSG pass on flat arrays (~65 K additions at the
median strip, §3). Expectation (labelled inference): the per-row angle step falls from ~13-17 ms to
sub-millisecond; the refusal path's remaining cost is its SECOND verify+read (classifier over up to
48 candidates), which this row does not touch - so the refusal total will NOT fall proportionally to
the deskew step, and the before/after Release number must be read with that in mind (F4).

### 5.5 What we expect on our corpus - and the brief's two questions

- **Angle resolution (arithmetic on §2.2-2.3, labelled derivation):** per direction the padded FHT
  yields ~w+h-1 projections (reproduces the paper's 3975 for 1095 x 894); row slope grid =
  `arctan(i/(rows-1))`, so near horizontal the step is ~atan(1/(rows-1)): **0.25-0.38 deg at our
  48-px strip widths (105-181 px)**; 0.04-0.15 deg at native crop widths (131-1271 px). This is the
  same inverse-width information limit the sweep lives under (Leptonica's accuracy rule via PU.67
  §5.4; at the measured median width 135 the limit is ~0.42 deg, and the sweep's measured median
  error 0.68 deg sits just above it - consistent).
- **Question 1 - is FHT expected to BEAT the sweep's accuracy on a single row strip?** **No -
  expect parity, not gain, at equal input scale** (labelled inference): both are bounded by ~1/w
  rad; the paper's own sub-degree accuracy was measured at 23x our linear scale; the dyadic-pattern
  deviation bound (~2 px at our widths, Theorem 2) is noise the exact-warp sweep does not have,
  while the warp's bilinear smearing is noise the FHT does not have. With A2's interpolation both
  land near the grid limit. The wins the paper DOES publish at our scale are cost (45 us vs 21 ms
  for the per-angle scheme, §2.2 - the row's "the retry's main cost" premise) and the free
  criterion curve the confidence is read from (A6). If FHT nonetheless shows a materially worse
  agreement distribution than §5.3's baseline, F1 falsifies the row. The "~240-px row strip" in the
  brief and PU.67 §5.4 overstates the real widths (105-181 px measured - §7-2), which makes the
  resolution case slightly WORSE than previously assumed, not better.
- **Question 2 - is a C/Accelerate kernel needed?** **No** (§3 verdict; arithmetic labelled
  inference, confirmed only by the row's Release gate): ~65 K flat additions at the median strip
  (0.5 M at native crop) is tens-to-hundreds of microseconds in Swift; the paper's C reference does
  1 Mpx in 45 us. `vDSP_vadd` for the merge is permitted, not required; no C/C++ target, no Metal.
- **Confidence expectation (labelled):** the SSG curve's peak dominance should separate the §5.3
  failure shapes - the 12 refusals and the 2-6 deg-on-near-level rows are exactly low-evidence peaks
  (Leptonica's conf < 3 regime, PU.67 §2.3) - but no published threshold transfers (domain, scale);
  PU.70 fits on TRAIN (256 stills) per its row, and F6 falsifies if nothing separates.

### 5.6 The results that would falsify the row

1. **F1 (agreement):** the FHT-vs-drawn-truth distribution over the 190 hand quads (deskew fed the
   HAND quads - the gate's own instrument, closing §5.3's proxy gap), with the sweep re-run through
   the same instrument for a like-for-like baseline, materially worse than §5.3 (median 0.68 deg,
   CE@1 deg 0.690 [0.617, 0.754]) - the row's premise is speed+confidence at parity; lost parity
   falsifies it. The >6 deg bucket (5 boxes) must not regress against median 1.43 deg (A7's guard
   transfer).
2. **F2 (layout pin):** a synthetic strip with a line drawn at signed theta fails to peak at signed
   theta within one grid step pre-interpolation -> the accumulator convention (A5, §2.7-8) was
   implemented wrong; no corpus number counts until it passes. Named mutation: transpose the
   angle/offset axes of the accumulator - the test must go red.
3. **F3 (italic guard):** `italicIsNotATurn` (`PumpRowDeskewTests.swift:96`) red after the change,
   OR its mutation - enabling the mostly-vertical fusion (undoing A3) - fails to turn it red.
 4. **F4 (latency):** the Release refusal-path number (the row's gate; same population, warmth, and a
    QUIET machine per §5.4 - never while the owner annotates) does not FALL against its before number
    -> the sweep was not the retry's main cost (§5.4 already shows the second verify+read dominates),
    or the FHT implementation is pathological. The deskew STEP falling (~13-17 ms -> sub-ms, §5.4)
    is the real target; the refusal TOTAL falling is a weaker, secondary expectation.
5. **F5 (app path):** live commits < `readerCommitted` at the build commit (45 at HEAD; 47 if PU.78
   has landed - §5.2 drift rule), or ANY new wrong committed cell at `CorpusScorer.tolerance` 0.005
   (`CorpusABScorer.swift:175`) -> hold exactly as PU.67 was held.
6. **F6 (confidence):** on the TRAIN split, no statistic of A6's three separates high-error from
   low-error angles (e.g. AUROC ~0.5 for |err| > 2 deg vs <= 1 deg against drawn truth) - the
   "with a confidence" deliverable fails even if the angles pass, and PU.70 has no input.

## 6. Cost

- **Latency.** Paper's anchor: 45 us for 3975 projections over ~1 Mpx in C (§2.2). Ours per row:
  ~65 K additions + ~9 K SSG ops at the median strip (§3, §5.5 arithmetic; labelled inference) -
  tens of microseconds scalar Swift, against the sweep's 72 warps + 72 CGImage round-trips
  (~0.5-1.3 M bilinear samples per row, PU.67 §6), measured CLEAN at ~13-17 ms per row (§5.4). A
  12-Mpx still reads in ~90-150 ms when the ANE is free; the sweep adds ~40-50 ms for its 3 rows.
  After FHT the per-row angle step should fall to sub-millisecond, but the refusal path's dominant
  remaining cost is its SECOND verify+read, which this row does not touch - so the refusal total
  will not fall proportionally (§5.4, F4). The row's gate: a Release refusal-path number, before and
  after, **on a quiet machine or on-device** (§5.4 shows the ANE-contention trap), population and
  warmth pinned; never Debug.
- **Bundle size.** No model, no resource, no framework, no new target: ~+250-400 lines of Swift in
  TankbookCore (transform + SSG + weights + interpolation + confidence), minus ~70 retired
  (`score` loop, `rowSize`, coarse/fine strides) - estimate (labelled): single-digit KB of binary.
- **New code to maintain.** One pure-functional file beside `PumpRowDeskew.swift` (dyadic split,
  merge-with-cyclic-shift, padding, black-zone mask - the merge's index arithmetic is the part that
  silently corrupts angles if wrong, which is why F2 exists); `Result` gains one field; three test
  seams (F2 layout pin, F3 mutation, the F1 agreement harness over `windows.json`); docs: the
  EXTRACTION deskew paragraph (`:1093-1100`) re-described, and the `PumpRowDeskew.swift:22-23`
  comment corrected per §7-1 in the same change that rewrites the file.

## 7. Findings handed off (found, not fixed - this note is read-only)

1. **The corpus's drawn-angle statistics in committed docs and code comments are normalised-space
   artefacts, inflated by each photo's aspect ratio.** PU.65's row text ("140 of 190 heldout hand
   boxes are turned (median 1 deg, p90 4, max 18)") and PU.67 §5.2's table ("175 turned > 0.5 deg";
   ">12 deg: pump-140 12.3, pump-161 14.1, pump-166 18.0, pump-275 13.2") were computed as atan2 on
   NORMALISED quad deltas. Pixel-space truth at HEAD (§5.2): turned >0.5 deg **128** of 190, median
   0.93, p90 3.39, **max 10.35, none past 12 deg**. Demonstration: pump-166 is 780 x 438 (W/H
   1.781); its drawn 10.35 deg is exactly the "18.0" quoted (atan(tan(10.35 deg) * 1.781) = 17.99).
   Consequence: `PumpRowDeskew.swift:22-23`'s comment ("The corpus has rows turned past 15 degrees
   (a display shot from the side)") overstates the drawn evidence - the +-30 deg range may still
   stand (runtime reader-side turns are a different quantity, and PU.65's tilted-20 list was
   reader-side, "not reproducible statically" per PU.67 §5.2), but its stated justification is
   wrong. Owner: the PU.69 build (comment fix rides the file rewrite); the orchestrator for a
   correction note on the PU.65/PU.67 row texts (committed history - append, don't edit).
2. **The "~240-px row strip" is an overestimate.** Measured hand-quad aspects are 2.20-3.78 (median
   2.81), so the 48-px search strips are **105-181 px wide (median 135)**, not PU.67 §5.4's
   130-380 / this brief's ~240. The inverse-width accuracy limit is correspondingly ~0.32-0.54 deg,
   and the FHT grid at A1's scale is 0.25-0.38 deg (§5.5) - the numbers PU.69's brief and PU.70's
   width reasoning should use. Owner: the PU.69/PU.70 briefs.
3. **The row text's "yields the accumulator mass as a confidence" is not in the cited paper.**
   Alg. 1 returns the angle alone; no confidence or gate is published there (§2.7-1,4). The
   confidence formulas are this note's named choices from fetched published statistics (A6). Owner:
   the orchestrator (row-text correction when briefing), so the completeness review does not hold
   the build to a paper promise that does not exist.
 4. **Pump latency measured on the dev Mac while the owner annotates is inflated ~25x by Neural
    Engine contention - a trap every pump latency gate must avoid.** This note's own measurement
    (§5.4) swung pump-030's `readPhoto` from 104 ms to 2500 ms across an hour, same binary/still/
    request, warm and cold alike, with CPU load flat at ~1.3. The cause is the annotator's resident
    `pump-read --slice-serve` / `--read-serve` processes (and any other CoreML client) contending
    for the ANE, not photo size or warmth. The CLEAN numbers agree with the tree: ~90-150 ms per
    12-Mpx still, matching PU.75's committed "read 112-164 ms Release-on-Mac" - so PU.75's figure
    was right, and this note's contended batch medians (2.7-9.1 s) are the artefact. **PU.69's
    "Release latency number for the refusal path, before and after", PU.75's device numbers, and any
    future pump timing must run with the annotator closed and no other CoreML client live (or
    on-device via the Capture Lab, PU.39), and must state that they did.** This is a measurement-
    hygiene rule, not a code defect; it belongs in the pump latency gate procedure. Owner: the PU.69
    build brief and PU.75's row; consider a line in `docs/TESTING.md` or the capture-screenshots
    procedure so the next agent does not report a contended median as a baseline.
5. **The SSG originals are closed-access; the implementable source is the OA restatement chain.**
   [15]/[14] (SPIE) could not be fetched or abstracted (§1.6); the formula this note specifies is
   Kunina/Sher/Nikolaev 2023 eq. (4) (OA, same group, one citation step from the original, Crossref-
   verified) cross-checked against the skew paper's own unambiguous `(Kh)^3` weighting. If [15] ever
   surfaces and disagrees, changing the criterion needs the owner's OK (§4 fence). Owner: recorded
   here; nobody acts unless the source appears.
6. **ECMS 2008 author-list discrepancy** (§1.5): the skew paper's ref [4] lists four authors,
   OpenAlex's record three. Cite as the skew paper spells it, with the flag. Owner: none (cosmetic);
   recorded so a future verification does not "fix" one into the other silently.
7. **The corpus is moving under this row** (§0, §5.2): PU.78's uncommitted law change moves the app
   path to 47/47 and the annotated floor to 118 and files PU.81; the owner re-annotated pump-275
   mid-run (heldout 68 -> 67 until commit); the annotator's resident `pump-read` servers were live
   during measurement. Every number here is HEAD `c22d0217`'s; the row's gates re-count at the
   build commit with §5.2's filters. Owner: the PU.69 build brief (re-count rule is in the row
   already - "live >= PU.67's count" - this finding says which count that will be).
