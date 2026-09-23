# PU.67 research note - the published projection-profile family vs. `PumpRowDeskew`

*A run of `agents/briefs/RESEARCH-TO-CODE.md` (copy: `agents/briefs/RESEARCH-PU.67.md`).
Written read-only; the repo was not modified except this file.*

- **Row:** `PU.67` - Turn the rows on a refusal, in the app (`docs/TASKS.md:1058`)
- **Papers the row cites:** none by name. The row says the method is "a projection-profile skew
  estimate (row-brightness profile sharpness)" and asks this note to find and verify the published
  family. Verified members, in the order they matter here: **Baird 1987** (SPSE Symposium on Hybrid
  Imaging Systems), **Bloomberg/Kopec/Dasari 1995** (Proc. SPIE 2422) as published in **Leptonica
  `src/skew.c`** (fetched in full), the comparative studies **Amin 1996** (J. Electronic Imaging
  5(4)) and **Bagdanov & Kanai 1996** (Proc. SPIE 2660), and **Postl 1986** - with a split verdict
  (§1.2: the ICPR paper verifies; the often-cited SPIE title does not). The later, better-evidenced
  estimator for the same job is the Fast Hough Transform (**Bezmaternykh & Nikolaev 2019**,
  arXiv:1912.02504, verified) - **PU.69 owns it; this note does not derive it**.
- **The code seam:** `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowDeskew.swift`
  (`profileSharpness:166`, the search `:77-86`, `rowSize:126`, `inside:139`),
  `PumpReader.DeskewMode` (`PumpRowDeskew.swift:206-220`), `PumpDisplayCapture.classify`'s
  `.onRefusal` retry (`PumpDisplayCapture.swift:326-335`), `PumpDisplayCapture.makeReader`
  (`:106-110`, called by `ios/App/Sources/Capture/CapturePipeline.swift:28-30`).

## 0. State of the row at the time of writing - read this before §5

The brief for this note was written at 17:46 against HEAD `3cead843`. At **HEAD `310e7660`
(2026-09-23 18:08) the orchestrator has already built, measured and HELD PU.67**: with the app's
reader built at `.onRefusal`, `livePath` read **52 committed, 51 correct (0.981)** - `pump-275`
total 103.31 for 103.37 - below the 0.99 floor, so the app stays `.off`, the Swift wiring was
reverted, and only docs were committed (`docs/TASKS.md:1058` "HELD" text, `docs/EXTRACTION.md:1093-1100`).
**The brief's §5 numbers (`.onRefusal` 54/54, tilted-20 0 -> 3, leak 5/116) are the superseded
ad-hoc-script figures**: the correction, committed in `310e7660`, records that the script scored
cells right within 0.1 instead of the corpus scorer's 0.005 and counted the pump-275 misread as
correct, and that the tilted-20 and leak figures "came from the same script and need re-measuring
with the scorer" (`docs/TASKS.md:1058`). This note therefore serves the **reopen** the row defines
("reopen once the pump-275 misread is refused (a law or read change, its own row), then re-run this
row's checks as written").

Also in flight while this note was written (not mine, not touched): PU.68's working-tree changes
(`PUMP_DETECTOR` override in `PumpReaderTestSupport.swift`, untracked
`PumpLeakConsequenceTests.swift`, `PumpPhotoGate.measuredNumericTotal` 865 -> 889) and a corpus run
adding untracked stills `pump-319`..`pump-324` (three named "tilted") and growing
`fixtures/arrival/` from 5 to 10 images mid-session. Every population below is counted at HEAD
`310e7660` per the brief's rule, from `git show HEAD:` blobs where the working tree differs.

## 1. Citations, checked

Fetch log for this section: doi.org content negotiation (CSL JSON), `api.crossref.org` (works,
prefix 10.1117), `api.openalex.org`, `export.arxiv.org/api`, `raw.githubusercontent.com` (Leptonica),
`patents.google.com` (US5245676A full page), DuckDuckGo HTML. Blocked or unavailable: SPIE Digital
Library (Incapsula), Springer (client challenge), ScienceDirect, `ui.adsabs.harvard.edu` (human
verification), `dblp.org` (bot wall), `api.semanticscholar.org` (429, no key), `leptonica.org`
(TLS failure), Google Books API (quota), scholar.archive.org (rate limit). What could not be
fetched is not described from memory anywhere in this note.

### 1.1 Baird 1987 - VERIFIED (bibliographically); original not fetched

**H.S. Baird, "The Skew Angle of Printed Documents", Proceedings of the SPSE Symposium on Hybrid
Imaging Systems, Rochester NY, May 20-21 1987, pp. 21-24.** Confirmed independently by:

1. **US5245676A** (Xerox Corp, inventor A. Lawrence Spitz, filed 1989-12-21, published 1993-09-14,
   "Determination of image skew angle from data including data in compressed form"), fetched in
   full from `patents.google.com/patent/US5245676A/en`: examiner-cited non-patent literature carries
   the exact citation, and the specification devotes its prior-art section to describing Baird's
   method with a page-line quote ("Baird (at page 22, lines 20-22)"). Method in §2.2 below.
2. Reference list of the Springer Handbook chapter "The State of the Art of Document Image
   Degradation Modelling" (`link.springer.com/chapter/10.1007/978-1-84628-726-8_12`, via search
   snippet of the publisher page): "Baird HS (1987) The skew angle of printed documents. Proceedings
   of the SPSE symposium on hybrid imaging systems, Rochester, NY, pp 21-24".
3. Reference list of Spitz, "Analysis of Compressed Document Images for Dominant Skew, Multiple
   Skew..." (`sciencedirect.com/science/article/pii/S1077314298906865`, via snippet): same venue,
   pages, year.
4. Reference list of "Document skew estimation", ACM ICDAR 2011 (`dl.acm.org/doi/10.1145/1947940.1948016`,
   via snippet): "Baird H. S. The skew angle of printed documents. pages 21-24, 1987."
5. OpenAlex `W197527448` (fetched): the 1995 anthology reprint in *Document image analysis*
   (IEEE Computer Society Press eBooks, pp. 204-208; ACM DL `10.5555/201573.201644`).

The 1987 conference original has no open host I could reach (SPSE proceedings; ACM DL only carries
the 1995 reprint). **Citation caution:** cite the 1987 original (pp. 21-24), not the 1995 reprint
(pp. 204-208) - the two are routinely conflated. The method description in §2.2 is the fetched
patent's, which quotes the paper directly; no page numbers or accuracy figures beyond what the
patent states are claimed for Baird.

### 1.2 Postl 1986 - SPLIT VERDICT: the ICPR paper verifies; the often-cited SPIE title does not

Two distinct Postl 1986 papers circulate under "Postl 1986" in the skew literature:

- **VERIFIED (bibliographically): W. Postl, "Detection of Linear Oblique Structures and Skew Scan
  in Digitized Documents", Proceedings of the Eighth International Conference on Pattern
  Recognition (ICPR-8), Paris, Oct. 1986, pp. 687-689, ISBN 0-8186-0742-4.** Source: the fetched
  US5245676A non-patent citations (examiner-cited). The paper itself, and any abstract of it, could
  not be fetched (ICPR 1986 is not in Crossref; IEEE Xplore blocked), so **its method is not
  described in this note.**
- **NOT VERIFIED - treat as suspect: "Determination of the document skew angle and its probability
  distribution", Proc. SPIE 697 (Applications of Digital Image Processing IX, 1986).** This is the
  title secondary sources attach to "Postl 1986" and to the variance-of-projection-profile
  criterion. I could not confirm it exists in that form from any reachable source:
  - Crossref HAS SPIE vol. 697 registered: its DOI block `10.1117/12.976199`-`10.1117/12.976239`
    enumerates 41 papers (fetched, all titles listed) and **no skew paper is among them**;
    neighbouring DOIs resolve to vols 608 and 698, so the block is complete.
  - OpenAlex: absent under every title/fulltext/author query tried.
  - DuckDuckGo exact-phrase search: zero results for the title (while returning results for
    neighbouring queries in the same session).
  - SPIE Digital Library: Incapsula-blocked; ADS: human-verification wall; Semantic Scholar: 429.
  - Notably, the Xerox patent - written by the group that built this literature and that compares
    itself against "Postl" - cites the **ICPR** paper, not the SPIE one.

  **Verdict:** I cannot verify this citation and will not describe its method from memory.
  INFERENCE (labelled): either SPIE never registered it with Crossref and search engines have not
  indexed the DL page, or it is a mutated reference propagated through secondary citation lists.
  Either way, **when our docs cite "Postl 1986" they must cite the ICPR paper above, or not at
  all.** `docs/EXTRACTION.md:1093-1095` currently says "a projection-profile skew estimate" with no
  citation - that is the safe state.

### 1.3 Bloomberg, Kopec, Dasari 1995 - VERIFIED (bibliographically); the method fetched as code

**D. Bloomberg, G. Kopec, L. Dasari, "Measuring document image skew and orientation", Proc. SPIE
2422, pp. 302-316 (1995), DOI 10.1117/12.205832** - confirmed by fetched doi.org CSL JSON
(container "SPIE Proceedings", volume 2422, pages 302-316, issued 1995-03-30). The SPIE PDF is
Incapsula-blocked, so no corpus numbers are quoted from the paper. Its method, however, is public
as the first author's implementation: **Leptonica `src/skew.c`, fetched in full from
`raw.githubusercontent.com/DanBloomberg/leptonica/master/src/skew.c` on 2026-09-23** (master
branch; cited below by function and constant name, which are stable, rather than by line number).
§2.3 describes the method strictly from that fetched source.

### 1.4 Amin 1996 (comparative study) - VERIFIED (bibliographically); full text not fetched

**Adnan Amin, "Comparative study of skew detection algorithms", Journal of Electronic Imaging 5(4),
p. 443, Oct. 1996, DOI 10.1117/12.245770** - confirmed by fetched doi.org CSL JSON (single author;
container "Journal of Electronic Imaging", vol 5, issue 4, page 443). Abstract, as surfaced from
the SPIE page via search snippet: compares "O'Gorman, Hinds, Le, Baird, Postl, and Akiyama" against
a new algorithm. Full text not fetched; **no accuracy numbers are cited from it.** This is the
nearest thing to a survey of exactly this family that I could verify; it is also the evidence that
"Postl" is a recognised member of the family, without saying which Postl paper.

### 1.5 Bagdanov & Kanai 1996 (evaluation) - VERIFIED (bibliographically); full text not fetched

**A.D. Bagdanov, J. Kanai, "Evaluation of document image skew estimation techniques", Proc. SPIE
2660 (Document Recognition III), pp. 343-353, DOI 10.1117/12.234715** - confirmed by fetched
doi.org CSL JSON. Not fetched; no findings cited from it.

### 1.6 Bezmaternykh & Nikolaev 2019 (FHT) - VERIFIED; PU.69's, not re-derived here

**"A Document Skew Detection Method Using Fast Hough Transform", arXiv:1912.02504** - fetched via
the arXiv API (id_list query): title, authors (Pavel Bezmaternykh, Dmitry Nikolaev) and year match
the PU.69 row's citation exactly. It is the later, better-evidenced estimator for the same job
(O(n^2 log n), yields accumulator mass as a confidence - the thing our sweep does not return).
**PU.69 owns it**; this note's only use of it is the boundary statement in §4-A6/§6.

### 1.7 van Beusekom, Shafait, Breuel 2009 - VERIFIED (bibliographically); scope note

**"Resolution independent skew and orientation detection for document images", Proc. SPIE 7247,
72470K, DOI 10.1117/12.807735** - confirmed by the fetched Crossref record. Projection-profile
family at low effective resolution, which is the regime our fixed 48-px search strip deliberately
lives in (§4-A4). Full text not fetched; no claims made about its contents.

### 1.8 Search log (auditability of "no better-evidenced estimator found")

Queries run: arXiv API `all:"skew detection"` (4 hits: the FHT paper, a 2018 OCR-alphabet paper,
two 2024 non-skew papers); Crossref `works` title/bibliographic/author queries and prefix 10.1117
queries; OpenAlex `title.search`/`search`/`referenced_works` walks (33 references of Okun et al.
1999 enumerated); DDG HTML searches. **No deep-learning or other post-2009 skew estimator with
fetchable evidence and an on-device fit surfaced beyond the FHT** (labelled: absence of results in
these indexes is not proof of absence in the literature; the reachable indexes were listed above).

## 2. The methods as published

### 2.1 The family

Projection-profile skew estimation: for each candidate angle θ, transform the image (rotate or
shear), compute the horizontal projection P_θ(y) (per-row sums or means of ink/intensity), score
S(θ) by a sharpness criterion on P_θ, and take θ̂ = argmax S. The family members differ in
(a) the score - Σ of squared point-bins (Baird), Σ of squared successive projection differences
(Leptonica/Bloomberg), variance of the projection (attributed to Postl in secondary sources -
UNVERIFIED per §1.2, not described here); (b) the search - linear sweep, sweep + quadratic fit +
binary search (Leptonica); (c) the acceptance rule - a confidence gate (Leptonica) or none
published (Baird, per the patent).

### 2.2 Baird 1987, as documented in the fetched US5245676A prior-art section

The patent (Xerox, Spitz) describes Baird's published method in detail, quoting it:

- **Input filtering:** binarised document; text connected components separated from non-text by a
  size rule - "the maximum dimension of a text mark is less than or equal to the 'em' in a
  predetermined maximum font size, e.g., 24 point". "Baird's technique will only yield meaningful
  results for text images."
- **Feature point:** the **fiducial point** = bottom centre of each component's bounding box (a
  baseline proxy; dotted i/j and punctuation add off-baseline points).
- **Scoring:** for each candidate rotation, project all fiducial points onto a family of parallel
  lines ("bins", one per text line) and count per line. The score is the **sum of squares of the
  bin counts**: S(θ) = Σᵢ Cᵢ(θ)², where Cᵢ(θ) is the count in bin i at angle θ - which the patent
  quotes from **Baird p. 22, ll. 20-22** as "a real-valued energy alignment measure function".
  Efficient implementation by trigonometric translation of the points and projection into bins.
- **Estimate:** θ̂ = the angle of greatest power; the patent notes "in the event of weak alignment
  or multiple alignments... this assumption may need to be otherwise verified" (no published
  numeric gate found in the fetched material).
- **Documented weakness (the patent's critique):** as skew grows, "the distance between the bottom
  of the mark and the bottom of the bounding box may increase... as a function of the sine of the
  angle of skew", smearing bin counts, and the error affects the score "as a square of that error":
  at larger angles "skew angle determination performance disintegrates".

No search range, step, or dataset numbers were extractable from the fetched material; the paper's
own pp. 21-24 were not obtained (§1.1).

### 2.3 Leptonica `src/skew.c` (fetched master, 2026-09-23) - the published differential criterion, with parameters

All constants and quotes below are from the fetched file; they are the archived parameter set of
the Bloomberg/Kopec/Dasari line of work (§1.3):

- **Score** (`pixFindDifferentialSquareSum`): over a 1-bpp image sheared vertically by θ, let P(y)
  be the ON-pixel row sums. S(θ) = Σ_y (P(y) − P(y−1))², summed over rows **excluding the top and
  bottom nskip rows**, nskip = max(min(h/10, 0.05·w)/2, 1) - "to avoid getting a spurious signal
  from the top and bottom of a (nearly) all black image" (function notes).
- **Why the differential score** (file header, "Page skew detection"): it "rejects the background
  noise due to total number of black pixels, and has maximum contributions from the baselines and
  x-height lines of text when the textlines are aligned with the raster lines. It also works well
  in multicolumn pages where the textlines do not line up across columns."
- **Search** (`pixFindSkewSweepAndSearchScorePivot`): linear sweep over ±`DefaultSweepRange` = 7.0°
  at `DefaultSweepDelta` = 1.0° on a `DefaultSweepReduction` = 4× reduced binary image; the sweep
  peak is refined by a **quadratic (Lagrange) fit through the maximum and its two neighbours**
  (`numaFitMax` in `pixFindSkewSweep`); then an **interval-halving binary search** on a
  `DefaultBsReduction` = 2× image down to `DefaultMinbsDelta` = 0.01°. A maximum at the sweep edge
  invalidates the result ("max found at sweep edge" warning). Shear pivots about the UL corner;
  "for large angles (say, greater than 20 degrees), it is better to shear about the center"
  (pivot function, note 2).
- **Stated accuracy** (`DefaultMinbsDelta` comment): "The expected accuracy is not better than the
  inverse image width in pixels, say, 1/2000 radians, or about 0.03 degrees"; file header: "accurate
  to within an angle (in radians) of approximately the inverse width in pixels of the image".
- **Stated data sufficiency** (file header): "will work on a surprisingly small amount of text data
  (just a couple of text lines). Consequently, it can also be used to find local skew if the skew
  were to vary significantly over the page."
- **Acceptance gate** (`pixDeskewGeneral`, `pixFindSkewSweepAndSearchScorePivot`): confidence
  conf = maxscore/minscore over the searched angles, forced to 0 unless minscore >
  `MinscoreThreshFactor` (2·10⁻⁶) · w² · h **and** maxscore ≥ `MinValidMaxscore` (10000) **and**
  the peak is interior to the sweep; the deskew itself is refused when |θ̂| < `MinDeskewAngle`
  (0.1°) or conf < `MinAllowedConfidence` (3.0); notes: "Values between 3.0 and 6.0 are common."
- **Binarisation:** threshold `DefaultBinaryThreshold` = 160, "set deliberately above 130 to
  capture light foreground with poor printing or images that are out of focus"; adaptive variant
  via `pixFindSkewAdaptAndDeskew` for dark backgrounds.
- **The vertical-structure trap** (`pixFindSkewOrthogonalRange` notes 1-3): the 0°-vs-90°
  orientation ambiguity is resolved by searching both ranges and comparing confidences with an
  optional prior (`confprior`); and "if there are vertical lines in the margins, do not work below
  150 ppi. The signal from the text lines must exceed that from the margin lines" - i.e. vertical
  ink can outscore horizontal ink if the projection is not the only one used.
- **Application step** (`pixDeskewGeneral`): rotate by θ̂ with `pixRotate(..., L_ROTATE_AREA_MAP,
  L_BRING_IN_WHITE, ...)`.

### 2.4 What the published methods do NOT contain (the fence for §4)

From the fetched material: (1) no per-row angle over perspective-varying rows - one global θ per
page (local skew only "can be used", no aggregator published); (2) no policy of retrying deskew
only after recognition refused - the papers deskew unconditionally before OCR; (3) no re-estimation
of a rotated object's bounding rectangle - they own the whole page; (4) no confidence on a
resulting READING - Leptonica's confidence gates the ANGLE, not downstream recognition. Anything
of ours in those four slots is an adaptation, named below.

## 3. Mapping onto this code

The method is already built (PU.65, commit `bf02cbfb`); PU.67's own delta is the mode the app's
reader is built with. Mapping, published element -> ours:

| Published element (source) | Our implementation | Relation |
|---|---|---|
| Row projection P(y) | row means of the grayscale strip, `profileSharpness` (`PumpRowDeskew.swift:166-177`) | same quantity, grayscale means instead of 1-bpp ON-pixel counts (§4-A1) |
| Σ(P(y)−P(y−1))² score (`pixFindDifferentialSquareSum`) | `:174-176`, squared successive row-mean differences, summed then **divided by strip height** | **direct instance of the Leptonica differential criterion**, not of Baird's Σ Cᵢ² (no component extraction exists in our pipeline); height normalisation is ours (§4-A1) |
| Per-angle transform (vertical shear `pixVShearCorner`/`Center`) | `score(_:)` `:66-76` warps a trial-oriented rectangle crop to an axis-aligned strip, `PumpQuadWarp.warpToStrip` (`PumpQuadWarp.swift:165-195`, scalar homography + bilinear) | same job, different geometry: the unit is one detector row, not a page (§4-A2) |
| Sweep ±7° @1° + quadratic fit + binary search to 0.01° | coarse ±30° @1° (`:24,30,79-82`), fine ±1° @0.2° (`:31,83-86`); **72 score evaluations per row** (1 level + 60 coarse + 11 fine); no quadratic fit, no bisection | same two-stage shape (coarse grid, then refine), coarser endpoint, wider range (§4-A3). Note: the PU.69 row text "sweeping +-30 deg in 0.2 deg steps" misstates this - see §7-1 |
| 4×/2× image reduction for speed | fixed 48-px strip height `searchStripHeight` (`:36`) | our reduction analogue (§4-A4) |
| nskip top/bottom edge rows (`pixFindDifferentialSquareSum` notes) | `inside(...)` clamps the trial crop into the frame, ≤12 × 0.85 height shrinks (`:139-150`) | different guard, same artefact class (§4-A5) |
| Acceptance: conf = max/min ≥ 3.0, absolute floors, `MinDeskewAngle` 0.1° | keep the turn only if best ≥ level × 1.05 (`minimumGain`, `:39,87-89`); a level row keeps its box exactly | both refuse noise-level turns; ours is a **relative gain over level**, not a max/min ratio, and **emits no confidence** (§4-A6; PU.69 owns confidence) |
| Vertical-rules warning (`pixFindSkewOrthogonalRange` note 3) | rows profile only, columns never scored (`:12-17`); mutation-tested by `italicIsNotATurn` (`PumpRowDeskewTests.swift:95-99`) | we structurally exclude the trap they warn about (§4-A9) |
| 0°/90° orientation search (`pixFindSkewOrthogonalRange`) | none in deskew; orientation is a separate upstream stage (`bestOrientation`, `readPhotoDetailed` `:253-258`; `classify`'s rotation retry `PumpDisplayCapture.swift:314-323` at HEAD) | division of labour differs (§4-A11) |
| `pixRotate` application | per-row: `rotatedRect` (`:154-161`); whole-photo: `levelled` via `vImageAffineWarp_ARGB8888` (`:298-322`), inverse map `unlevelled` (`:325-331`) for crop rects | ours adds the inverse map (no published counterpart; needed because `classify` returns crop rects in the original frame) |
| "local skew if it varies over the page" (header note) | per-row angle by design (`:19-20`); photo levelling by the **median** of rows' angles, `levelAngle` (`:287-292`), gated at `minimumLevelAngle` 3.0° (`:282`) | the local-skew usage they anticipate; the median aggregator is ours (§4-A8) |
| (nothing published) | `rowSize` inversion past `largeTurn` 6° (`:29,62-71,126-133`): solves w = L·cosθ + H·sinθ, h = L·sinθ + H·cosθ for the row inside its upright bound, floored at 0.5w/0.3h, guarded at det > 0.1 | §4-A7 |
| (nothing published) | `DeskewMode` `.off/.onRefusal/.always/.level` (`:206-220`); app retry in `classify` (`PumpDisplayCapture.swift:326-335`), read ladder in `readPhotoDetailed` (`:251-275`) | §4-A10, the row's own subject |

**Types.** In: a detector quad as `[CGPoint]` pixels + `PumpRGBImage`; out: `Result{quad, degrees}`
(`:46-51`). Normalised-quad bridge: `PumpReader.deskewed` (`:230-234`); candidate feed:
`PumpReader.candidates(for:deskewRows:)` (`PumpReader.swift:54-57`); the read strip is warped at
`PumpReader.stripHeight` = 96 (`PumpReader.swift:13`) - twice the search strip. App seam at HEAD:
`makeReader` (`PumpDisplayCapture.swift:106-110`) builds `PumpReader(model:detector:)`, whose
`deskew` parameter defaults to `.off` (`PumpReader.swift:33-38`); `CapturePipeline.pumpReader`
(`CapturePipeline.swift:28-30`) is the only app caller. The held build's delta was
`appDeskew: DeskewMode = .onRefusal` passed here (reverted; visible in this session's worktree diff
before the hold).

**Constants PU.67 retires:** none - the method is prebuilt. Constants **other rows** retire or
re-read: PU.69 may retire `maximumAngle/coarseStep/fineStep` (FHT; its row: "the sweep is retired
or kept only as the note justifies"); PU.75 retires the scalar warp loops (`PumpQuadWarp.swift:179-193`);
PU.70 re-reads `minimumWidestRowFraction` (`PumpDisplayCapture.swift:88`) along the row's axis.

## 4. Every adaptation, named and justified

Fence restated: **a departure the row's implementer adds later that is not listed here needs the
product owner's OK.**

- **A1. Grayscale row means, height-normalised - not 1-bpp ON-pixel sums.**
  *Paper:* Leptonica binarises (threshold 160, or adaptive) and sums ON pixels
  (`pixFindDifferentialSquareSum`); Baird counts binarised component points.
  *Ours:* `profileSharpness` averages 0..1 luminance per row over the warped strip
  (`PumpRowDeskew.swift:168-173`) and divides the squared-difference sum by the strip height (`:176`).
  *Why:* (i) pump photos are not bimodal scans - reflections, glare and night boards break a fixed
  threshold (the corpus's named failure modes include glare; `docs/EXTRACTION.md` records Vision
  misreads at confidence 1.00 on pump-004); (ii) both display polarities exist - LCD dark-on-light
  and LED light-on-dark - and squared differences are polarity-free either way, which the code
  documents (`:163-165`) while a binarised ON-pixel sum is polarity-sensitive without inversion;
  (iii) binarising per trial angle would multiply the search's cost. The height normalisation keeps
  scores comparable across trials whose crops differ in size (they do, past 6° - see A7).
  *Evidence:* the polarity-free design note; INFERENCE (labelled): thresholding on our corpus was
  never measured - if anyone proposes it, it needs its own measurement.
- **A2. Homography warp of an oriented-rectangle crop - not a vertical shear of the page.**
  *Paper:* Leptonica shears the whole binarised page (`pixVShearCorner/Center`), which is cheap and
  keeps raster rows; Baird translates points trigonometrically.
  *Ours:* each trial builds a rotated rectangle (`rotatedRect:154`) and warps it to an
  axis-aligned strip (`PumpQuadWarp.warpToStrip:165-195`, scalar per-pixel loop).
  *Why:* the input is one display ROW inside a photo, whose box is (a) a sub-rectangle and (b) only
  known as an upright bound - a shear of the whole photo would have to be followed by a crop anyway,
  and the warp un-rotates the trial quad exactly, feeding the same strip geometry the read path
  uses (`PumpReader.readUpright:305` warps through the same function at strip height 96).
  *Cost consequence:* the scalar loop is the retry's main cost; PU.75 owns vectorising it, PU.69
  owns removing the sweep (§6).
- **A3. Range ±30°, coarse 1° + fine 0.2° - not ±7° sweep + bisection to 0.01° + quadratic fit.**
  *Paper:* Leptonica defaults `DefaultSweepRange` 7.0°, `DefaultSweepDelta` 1.0°, `DefaultMinbsDelta`
  0.01°, quadratic peak fit.
  *Ours:* `maximumAngle` 30, `coarseStep` 1.0, `fineStep` 0.2 (`:24,30-31`); grid quantisation at
  0.2°, no fit, no bisection.
  *Why:* scanned pages skew a few degrees; corpus rows do not - hand quads run to 18.0° (counted at
  HEAD from `windows.json`, §5) and the code documents displays shot from the side past 15°
  (`:22-23`). The 0.2° endpoint: Leptonica's own accuracy rule (angle accuracy ≈ inverse strip
  width in radians) puts the information limit of a ~240-px strip at ≈ 0.24° (§5, inference) -
  bisecting to 0.01° would be claiming precision the strip does not carry. The quadratic fit is
  Leptonica's sub-step refinement on a smooth score; our score at 48-px strip height is coarse
  enough that the fit's benefit is unmeasured here (INFERENCE, labelled; if PU.69's angle-agreement
  distribution shows 0.2° quantisation losses, the fit is the published fix).
- **A4. Fixed 48-px search strip - not 4×/2× image reduction.**
  *Paper:* reduction factors 4 and 2 (`DefaultSweepReduction`, `DefaultBsReduction`).
  *Ours:* `searchStripHeight` 48 regardless of row size (`:35-36`), width = 48 × crop aspect
  (`PumpQuadWarp.warpToStrip:166`).
  *Why:* row crops vary ~10× in pixel height across the corpus (arm's-length vs. side shots); a
  fixed small strip bounds every trial's cost uniformly and is "coarse enough for a profile"
  (`:35` comment). The read path still warps at 96 px (`PumpReader.swift:13`), so the search never
  degrades the read itself.
- **A5. In-frame crop clamp - not top/bottom scanline skipping.**
  *Paper:* Leptonica skips nskip edge rows of the sheared image so border artefacts do not score.
  *Ours:* `inside(...)` shrinks the crop height (≤12 × 0.85) until all four corners lie in the
  photo (`:139-150`).
  *Why:* our artefact is different and stronger - samples outside the photo come back black, and
  "the jump from a display to black scores as a sharp edge, so a crop leaving the frame would win
  for the wrong reason" (`:136-138`). The clamp removes the artefact at the source instead of
  trimming it after. Both guard the same failure class the literature knows (shear/black borders
  producing spurious profile edges). No trial scores content that is not in the photo.
- **A6. Acceptance = 5% relative gain over level, no confidence output.**
  *Paper:* Leptonica gates on conf = max/min ≥ 3.0 with absolute floors (`MinAllowedConfidence`,
  `MinValidMaxscore`, `MinscoreThreshFactor`) and refuses deskew under 0.1°; Baird has no published
  numeric gate (the patent notes weak/multiple peaks "may need to be otherwise verified").
  *Ours:* keep the turn only when best ≥ level × 1.05 (`minimumGain`, `:39,87-89`); otherwise the
  detector's box stands untouched. `deskew()` returns no confidence.
  *Why:* the level score is always computed first (`:77`), so a relative gain is a scale-free
  comparison across heads, lighting and polarities - Leptonica's max/min ratio is the closest
  published analogue, and a fixed absolute floor like `MinValidMaxscore` is meaningless across our
  strip sizes (INFERENCE, labelled). The missing confidence is a known gap with a named owner:
  **PU.69** ("it returns no confidence"; FHT accumulator mass), consumed by **PU.70** (size rule on
  the row's axis, gated by that confidence). The held measurement (§5) shows why the gap matters:
  our gate polices the ANGLE, and pump-275's failure is a bad READING after a legitimate turn - the
  published family has no gate for that either (§2.4-4); in our pipeline it belongs to the law,
  calibration (PU.72) or the reopen row the gate names.
- **A7. `rowSize` inversion past 6° - no published counterpart.**
  *Paper:* the page is the input; the object's rectangle never needs inferring.
  *Ours:* past `largeTurn` 6° (`:29`), each trial crop is sized to the row its upright bound
  implies, by inverting w = L·cosθ + H·sinθ, h = L·sinθ + H·cosθ (`:119-133`), floored
  (0.5w/0.3h) and guarded (det > 0.1).
  *Why:* the detector returns UPRIGHT boxes only (Create ML limitation, recorded in PU.66); at
  large θ the upright bound is nearly square around a long thin row, and a fixed-size trial crop
  warps to a strip a few dozen pixels wide where "the digits alias and a wrong angle can outscore
  the right one" (`:62-65`). Verified by `largeTurnRecoversTheRowSize` (a 20° row gets ±8% length,
  ±20% height back; `PumpRowDeskewTests.swift:61-69`). The 6° threshold itself is a measured
  operating point from PU.65 (below it, keeping the detector's box "measured safer than any refit
  because the verifier's rules were tuned on the detector's own framing", `:26-28`).
- **A8. Per-row angles; photo levelling by their median, gated at 3°.**
  *Paper:* one global θ; Leptonica's header anticipates local skew but publishes no aggregator.
  *Ours:* "Each row gets its own angle: rows at different heights of one display photographed at an
  angle do not share one (perspective)" (`:19-20`); `levelAngle` = median of the rows' angles
  (`:284-292`), applied by vImage warp only at ≥ `minimumLevelAngle` 3° (`:282,255-258`).
  *Why:* the median "levels every row closely rather than one row exactly" (`:285-286`); the 3°
  gate avoids warping near-level photos - measured: "level-only a wash on the heldout" and app-path
  levelling "adds nothing and is NOT merged" (PU.65 row, `docs/TASKS.md:1056`). The median choice
  (over mean) is ours, unpublished, and rests on that measurement plus perspective-robustness
  reasoning (INFERENCE, labelled).
- **A9. Italic guard: horizontal profile only, vertical structure never scored.**
  *Paper:* Leptonica warns that vertical rules can outscore text lines and confines scoring to the
  horizontal projection with resolution advice (`pixFindSkewOrthogonalRange` note 3); Baird avoids
  the issue by scoring component base points instead of pixels.
  *Ours:* the same confinement, made explicit for a domain where the vertical ink is PART of the
  text: "Vertical strokes are deliberately not used: many pump fonts are italic, and levelling the
  strokes would shear every digit" (`:16-17`). Enforced by `italicIsNotATurn` (a 10° italic row is
  found level within 0.6°) and its named mutation (score the column profile - the test goes red;
  PU.65 L1 record, `docs/TASKS.md:1056`).
- **A10. Retry only on refusal - nothing published has this policy.**
  *Paper:* deskew runs unconditionally before recognition.
  *Ours:* `.onRefusal` reads upright first; only when that commits nothing does it retry with rows
  turned, then (on `readPhoto` only) with the photo levelled (`:210-214,251-275`; app path
  `PumpDisplayCapture.swift:326-335` - row-turn retry only, levelling not merged per PU.65).
  *Why:* turning a box "moves where its ends fall" - the always-turn arm measured 46/46 vs. 47/47
  off (PU.65 row): unconditional deskew LOSES cells the upright read had. "A photo the upright read
  commits on never changes" (`:212-213`) is both the measurement and the product rule (hard rule 15:
  a capture is a head start; a second attempt must not disturb a first that worked). This is the
  adaptation PU.67 is about; it is a policy wrapper around a published estimator, not a change to it.
- **A11. No 0°/90° ambiguity stage inside deskew.**
  *Paper:* Leptonica searches about 0° and about 90° and compares confidences
  (`pixFindSkewOrthogonalRange`).
  *Ours:* orientation is a separate upstream stage (PU.53: `bestOrientation` search in
  `readPhotoDetailed:253`, rotation retry in `classify`); deskew assumes an upright photo and
  searches ±30° only.
  *Why:* the display decision and the orientation search already ran before any deskew
  (`classify:314-326` order); re-deciding orientation per row would double the sweep for a question
  answered upstream. The ±30° range covers the residual (hand quads max 18°, §5).

**On-device constraints, all satisfied by the existing build:** iOS 18.0 target - pure Swift plus
`Accelerate` (`vImageAffineWarp_ARGB8888` only, in `levelled:298-322`; no API newer than iOS 18 is
used, so the compiler guard of the deployment target is not exercised); no Core ML or Metal
additions; no C/C++ target needed for PU.67 (PU.69's note may need one for the FHT kernel, per its
row). iPhone 12: the retry's cost model is §6.

## 5. What the papers measured; what we measured; the populations; falsification

### 5.1 Published measurement claims (only what was fetched)

- Leptonica/skew.c: accuracy target ≈ inverse image width in radians (≈0.03° at 2000 px); works on
  "a couple of text lines"; confidence ratios 3.0-6.0 typical in practice. The SPIE 2422 paper's own
  datasets and error tables were NOT fetched - no numbers from it are quoted.
- Baird 1987: no dataset numbers extractable from the fetched patent; the patent's sin-θ degradation
  critique (§2.2) is the published performance statement used here.
- Amin 1996 and Bagdanov & Kanai 1996 exist and are comparative/evaluative by title and abstract;
  full texts not fetched, nothing cited from them.

### 5.2 Our populations, counted at HEAD `310e7660` (file + filter for each)

Counted with python over `git show HEAD:` blobs (the working tree's copies are mid-corpus-run and
differ); filter identities given so the counts are reproducible:

| Population | Count | File and filter |
|---|---|---|
| Heldout stills (the live-path universe) | **68** | `Spike/ReceiptSpike/fixtures/pump/split.csv` rows == `heldout` ∩ `windows.json` entries with `reviewed: true` - the `PumpReaderTestSupport.isHeldout` filter (`PumpReaderTestSupport.swift:66-75`) |
| Asserted numeric cells on those stills | **183** | `expected.csv` non-blank liters/unitPrice/total minus each still's `csvDisagrees` keys - exactly `measureLive`'s cell filter (`PumpReaderPipelineTests.swift:524-553`); matches `PumpPhotoGate.readerNumericTotal` (`PumpPhotoGate.swift:95`) |
| Non-pump fixtures (the leak population) | **116** | image files (jpg/jpeg/png/heic) under `fixtures/{receipts 97, screenshots 9, expenses 9, fiscal 1}` - the folder list of the in-flight `PumpLeakConsequenceTests.folders` (untracked file, `:15`). Caution: `service 3 + arrival 5 + receipt-synth 1` also sums to 116 (arrival is untracked and has since grown to 10); the folders above are the instrument's, and the reopened gate must NAME the instrument, not the bare number (§7-2) |
| Hand windows on heldout stills | 252 (175 turned > 0.5°) | `windows.json` window quads, top-edge angle |atan2| - this counts ALL annotated windows; the apportionment's "188 hand transaction rows / 190 hand boxes" (PU.65 row; `PumpApportionmentTests` presence loop, `:96-101` counts truth rows excluding `.board`, upright stills only) is the narrower transaction-row instrument. Do not conflate the two denominators |
| Heldout stills with a HAND window past 12° | **4** (pump-140 12.3°, pump-161 14.1°, pump-166 18.0°, **pump-275 13.2°**) | `windows.json` quads, same angle filter |
| "tilted-20" (a row past 12°) | **not reproducible statically** | PU.65's 20-still list was a runtime measurement of the READER's found angles over detector rows, by the ad-hoc script; no committed file lists it. The hand-quad count above is 4, so the 20 is a different (reader-side) quantity. The reopen must rebuild and name the list with the corpus scorer - the row already orders this ("the tilted-20 and leak figures above came from the same script and need re-measuring with the scorer") |

Corpus drift warning: the in-flight corpus run is adding tilted stills (`pump-320/321/322` are named
"tilted" in their filenames) - the tilted arm will get more members at the reopen's commit.

### 5.3 Our measurements

- **Synthetic L1** (`PumpRowDeskewTests.swift`): turns of −20..+20° found within 0.6° (`:55-59`); a
  level row keeps its box exactly (`:87-93`); a 10° italic is not read as a turn (`:95-99`); a 20°
  row recovers its length/height past the large-turn bound (`:61-69`); levelling round-trips a point
  (`:71-85`).
- **App path, `.off` (HEAD, shipped):** 45 committed / 45 correct of 183 (`PumpPhotoGate.swift:86-95`;
  floor bound through `liveCommittedFloor = PumpPhotoGate.readerCommitted`,
  `PumpReaderPipelineTests.swift:56-58`, expectations `:96-114`). At HEAD `livePath` builds
  `PumpReader(model:detector:)` directly, whose default is `.off` (`:82-83`,
  `PumpReader.swift:33-38`); the build-through-`makeReader` binding was part of the reverted
  attempt and returns with the reopen - the row's gate is explicit that the floor "measures the
  app's mode, not a test-only one".
- **App path, `.onRefusal`, corpus scorer (0.005):** **52 committed / 51 correct = 0.981 -> HELD**
  (`310e7660`; `docs/TASKS.md:1058`; `docs/EXTRACTION.md:1093-1100`). The one wrong cell: pump-275
  total 103.31 for 103.37.
- **Superseded ad-hoc figures (0.1 tolerance, quoted by this note's brief):** `.off` 45/45,
  `.onRefusal` 54/54, tilted-20 0 -> 3, leak 5/116 either way (PU.65 row + its correction sentence,
  `docs/TASKS.md:1056`; parity commit `d1ea3f44`). The five routed non-pump fixtures were named in
  PU.63: receipt-002, receipt-076, receipt-090, receipt-095 and one expense invoice - "the five the
  display rule already let through", unchanged by deskew.
- **readPhoto ladder (PU.65, ad-hoc):** off 47/47, on refusal 59/59, always 46/46 (churn), level-only
  a wash - the always-arm loss is the measured basis of A10.

### 5.4 What the literature predicts, and whether ours is consistent

- **Accuracy bound:** Leptonica's own stated rule - angle accuracy ≈ inverse image width in radians
  (fetched header/constant comments) - applied to our ~240-px search strip gives ≈ 1/240 rad ≈
  **0.24°** (INFERENCE: arithmetic on their documented rule). Our 0.2° fine grid sits exactly at
  that bound and the synthetic tolerance (0.6°) does not claim better. Consistent. PU.69's gate
  (angle agreement with the sweep on the heldout hand quads, truth = their drawn angle) is the
  direct test of this.
- **Small-data sufficiency:** "works on... just a couple of text lines" - a single seven-segment row
  carries two strong horizontal edges per glyph (segments a and d), the display analogue of the
  baselines/x-heights Leptonica's header names as the differential score's main contributors.
  Consistent: one row is enough for our per-row estimate by construction.
- **Large-skew degradation:** Baird's documented sin-θ smearing predicts the method weakens as the
  turn grows. Ours: the tilted arm moved 0 -> 3 of 20 (ad-hoc) - a gain, but 17 of 20 still failed;
  and the held row's single misread (pump-275) is a 13.2° still. PU.65 attributes the residual to
  the detector's framing on turned displays (PU.66, three retrainings refused) and the classifier
  under reflections - i.e. the failures sit in the stages the angle estimate feeds, which is the
  same scope the published family claims for itself (angle only, §2.4). Consistent, with the caveat
  that our angle estimates themselves were never scored against ground truth on the corpus - that
  is PU.69's gate, not yet run.
- **The confidence gap is real and already bit:** Leptonica refuses to act when its score evidence
  is weak (conf < 3 -> clone the image, `pixDeskewGeneral`); we gate the angle choice
  (`minimumGain`) but nothing gates the READING that a turned crop produces, and pump-275 is exactly
  a low-evidence reading committing (0.06 off, law closed on it). The published family offers no
  reading-side gate (§2.4-4) - so the fix is ours to place: the reopen row the gate names
  ("a law or read change, its own row"), with confidence from PU.69/PU.70 and calibration from
  PU.72 as the published-adjacent instruments. Consistent with the literature's own fence: an
  angle estimator does not vouch for a recogniser.

### 5.5 The result that would falsify the reopened row

1. `livePath` through `makeReader` in the app's mode commits **< 45** (worse than `.off`) - the
   retry destroys value it was meant to add.
2. **Any wrong committed cell** at corpus tolerance (precision < 0.99): hold again - this is what
   happened at 18:08 today (52/51), and it is the row's own reopen condition.
3. Leak instrument on its named population: routed > 5 **or** any routed non-pump photo COMMITS a
   field (`PumpLeakConsequenceTests` ceilings 5/0, in flight) - deskew must not make a receipt
   readable as a pump.
4. The tilted arm, rebuilt with the corpus scorer on a named list, gains **nothing** over `.off`
   (a 0 -> 0 shape): the case for turning rows at all was the tilted gain (0 -> 3 ad-hoc). Expect
   ≤ 3 under the stricter scorer (INFERENCE, labelled); a rise above 3 needs explaining as much as
   a fall to 0 does.
5. The row's named mutation: build the app reader at `.off` while the gate constants carry the
   `.onRefusal` number - `livePath` must go red. If it stays green, the floor is not measuring the
   app's mode (the exact defect PU.61/PU.63 existed to kill).
6. No Release (never Debug) latency number for a refusal photo - the row's gate says produce it;
   the held attempt never did.

## 6. Cost

- **Latency.** The retry runs only on refusal photos (`classify` returns on commit at `:311`; the
  retry is gated on mode at `:326`) - photos that read upright pay zero, which is why `.off`'s 45/45
  photos are untouched by construction. On a refusal photo, per candidate row, `deskew()` runs **72
  score evaluations** (1 level + 60 coarse + 11 fine, `:77-86`), each doing: `rowSize` trig past 6°,
  `inside` clamp (≤12 iterations), one `warpToStrip` scalar homography+bilinear pass over
  48 × round(48·aspect) pixels (heldout rows span 0.20-0.39 of frame width per
  `PumpDisplayCapture.swift:84-88`; at 4032-px photos and row aspects ~2.7-8 that is ~130-380-px
  strips, ~6-18 K pixels), one CGImage creation, one CGImage decode back to RGBA
  (`rgbImage(from:)`, `PumpQuadWarp.swift:72-75`), one grayscale pass and one profile pass. Order
  of magnitude per row: ~0.5-1.3 M bilinear samples plus 72 CoreGraphics round-trips; a refusal
  photo carries 2-4 detector rows -> a few million scalar ops before the second verify+read even
  starts (**INFERENCE, labelled - there is no committed measurement of the deskew arm's latency;
  this is a count of executed operations read off the code**). Context: the existing pipeline costs
  Release-on-Mac 13-73 ms decision and 112-164 ms read (PU.75 row, `docs/TASKS.md:1066`), never yet
  timed on an iPhone. The reopened row's gate requires the Release number on a refusal photo; the
  structural fixes are owned elsewhere - PU.75 (vImage warps, batched predictions) and PU.69 (FHT
  retires the sweep; its row calls the sweep "the retry's main cost").
- **Bundle size:** +0 bytes. `PumpRowDeskew.swift` (332 lines) has been compiled into TankbookCore
  since `bf02cbfb`; no model, no resource. The reopen delta is a mode constant, one `makeReader`
  argument, gate constants and doc text.
- **New code to maintain:** the reopen re-lands ~10-15 lines (the exact delta is visible in this
  session's reverted worktree diff: `appDeskew` constant + `deskew: appDeskew` in `makeReader` +
  `livePath` building through `makeReader` + `PumpPhotoGate` reader constants 45/45 -> the
  re-measured number) plus the EXTRACTION decision-text flip from "held" to "ships". The method
  surface itself (6 tunables at `PumpRowDeskew.swift:24-44`, one enum, mutation-tested guards) is
  already maintained and tested.

## 7. Findings handed off (found, not fixed - this note is read-only)

1. **PU.69's row text misstates the sweep it will replace:** "sweeping +-30 deg in 0.2 deg steps"
   (`docs/TASKS.md:1060`) - the implementation is coarse 1° + fine 0.2° = 72 trials per row
   (`PumpRowDeskew.swift:30-31,79-86`), not 301. PU.69's cost baseline and its "retire the sweep"
   argument should start from the real count. Owner: the PU.69 row when briefed.
2. **Two folder sets sum to 116** (§5.2): the committed-in-flight instrument uses
   receipts+screenshots+expenses+fiscal; service/arrival/receipt-synth is a different 116. A gate
   written as "leak <= 5/116" is ambiguous across them, and `arrival/` is growing untracked
   (5 -> 10 images during this session). Owner: PU.68 (its test pins the folders) and the reopened
   PU.67 gate text (name the instrument).
3. **pump-275 is the reopen's whole ballgame:** it is a tilted-arm member (13.2° hand quad), the
   single corpus-scorer misread (103.31/103.37), and the reason the app stays `.off`. Whatever row
   refuses or fixes that reading inherits both roles; §5.4 places it in the published confidence-gap
   shape. Already named by `docs/TASKS.md:1058` - restated here so the reopen does not treat it as
   a rounding accident.
4. **"Postl 1986" needs care wherever it is cited** (§1.2): the SPIE title is unverifiable from any
   source I could reach; the ICPR paper is the verified Postl 1986. `docs/EXTRACTION.md:1095`'s
   uncited "projection-profile skew estimate" is currently correct as written; if the reopen adds a
   citation, use Baird 1987 + Bloomberg/Kopec/Dasari 1995 (via Leptonica skew.c), and Postl-ICPR
   only if someone actually obtains and reads it.
5. **The corpus is moving:** pump-319..324 (three "tilted"-named), arrival growth, and
   `measuredNumericTotal` 865 -> 889 in the working tree mean every population here changes at the
   next corpus commit. Per the brief's rule, the reopened row re-counts its population at its own
   commit; the counts in §5.2 are HEAD `310e7660`'s.
6. **The brief itself is stale in one place:** RESEARCH-PU.67's §5 instruction quotes 54/54 as "the
   measured result"; HEAD corrects it to 52/51 (0.981). Noted for the orchestrator so the next
   run's brief carries the corrected numbers.
