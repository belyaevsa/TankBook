# PU.68 research note - interval estimates, a detector override, and the leak's consequences

*RESEARCH-TO-CODE run for `PU.68` (`docs/TASKS.md`). Product owner, 2026-09-23: "review the
published research to apply it into the code, instead of coming up with our own solution."
Counted population is at commit `310e7660` (today's HEAD when this note was written); the
working tree holds an uncommitted corpus intake (`split.csv`, `expected.csv`, `windows.json`,
three new stills), so the implementer re-counts at their own build commit with the same filter
(§6). Evidence rule: every claim cites a paper section/equation, a `file:line`, or a measured
number; inference is labelled.*

## 1. The citations, checked

| Citation as the row gives it | Fetch result | Verdict |
|---|---|---|
| Wilson, E. B. (1927). *Probable Inference, the Law of Succession, and Statistical Inference.* JASA 22(158): 209-212 | CrossRef `10.1080/01621459.1927.10502953`: title, single author Edwin B. Wilson, *Journal of the American Statistical Association*, vol 22, issue 158, pages 209-212, published-print 1927-06. The publisher page (tandfonline) returned HTTP 403 to the fetcher, so the 1927 full text was **not** read in this run; the method below is taken from Brown-Cai-DasGupta §3.1.1 eq. (4), which derives the score interval and attributes it to "Wilson (1927)", and from BCD's reference list entry (same title, venue, volume, pages). | **Correct as cited.** Method sourced second-hand from BCD, stated as such. |
| Angelopoulos, A. N., Bates, S. (2021). *A Gentle Introduction to Conformal Prediction and Distribution-Free Uncertainty Quantification.* arXiv:2107.07511 | arXiv abs page fetched: title and both authors exact; v1 15 Jul 2021, v6 7 Dec 2022; cs.LG. | **Correct as cited.** It is a tutorial, not the primary risk-control paper; its §4.3 (eqs. (27)-(31), Theorem 2, citing its ref. [17]) and Appendix A (citing its ref. [18]) point at the primaries, followed below. |
| Primary for risk-controlling prediction sets (row: "follow its references") | arXiv API title search: **arXiv:2101.02703**, *Distribution-Free, Risk-Controlling Prediction Sets*, Bates, Angelopoulos, Lei, Malik, Jordan (v1 Jan 2021, v3 Aug 2021). Venue "JACM" is taken from a citing paper's abstract (arXiv:2406.10490: "Bates et. al. (JACM '24)"), not from JACM itself; labelled secondary. | Cite as **Bates et al. 2021, arXiv:2101.02703 (RCPS)**. |
| Primary for conformal risk control | arXiv API title search: **arXiv:2208.02814**, *Conformal Risk Control*, Angelopoulos, Bates, Fisch, Lei, Schuster (v1 Aug 2022, v4 Jun 2025). The venue (commonly given as ICLR 2024) did **not** appear in the fetched record; unverified here. | Cite as **Angelopoulos et al. 2022, arXiv:2208.02814 (CRC)**. |
| Primary for Learn-then-Test | arXiv API title search: **arXiv:2110.01052**, *Learn then Test: Calibrating Predictive Algorithms to Achieve Risk Control*, Angelopoulos, Bates, Candès, Jordan, Lei (v1 Oct 2021, v5). Author list checked: Candès is on it; Fannjiang and Zrnic are not (an earlier draft of this note guessed otherwise from memory and was wrong). Venue unverified here. | Cite as **Angelopoulos et al. 2021, arXiv:2110.01052 (LTT)**. |
| Brown, Cai & DasGupta (2001). *Interval Estimation for a Binomial Proportion.* Statistical Science 16(2) | CrossRef `10.1214/ss/1009213286`: title, authors Lawrence D. Brown, T. Tony Cai, Anirban DasGupta, *Statistical Science* vol 16 issue 2, May 2001. Full 33-page article (with discussion) fetched as PDF from Project Euclid: pages 101-133. | **Correct as cited**, full text read. |
| Clopper-Pearson exact interval (row asks for the comparison) | Not an independent fetch: the method is read from BCD §4.2.1 (definition, coverage property, verdict), which is the row's own comparison source. Clopper & Pearson 1934 itself appears in BCD's reference list (*Biometrika* 26: 404-413). | Method as published **in BCD's rendering**; the 1934 original not fetched. |

Caution for the implementer, recorded because it cost this run two fetches: the arXiv ids
`1905.03430` and `2308.02814`, guessed from memory as RCPS and CRC, resolve to an atomic-physics
paper and a control-theory paper. Verify ids by title search, never by recall; the same applies
to any id quoted in review prose.

## 2. The methods as published

### 2.1 The score (Wilson) interval - BCD §3.1.1, eq. (4)

With `κ = z_{α/2} = Φ^{-1}(1 - α/2)`, `p̂ = X/n`, the interval obtained by inverting the score
test (null standard error, not estimated) is

```
CI_W = (X + κ²/2)/(n + κ²)  ±  (κ·n^{1/2})/(n + κ²) · (p̂(1-p̂) + κ²/(4n))^{1/2}      (BCD eq. 4)
```

BCD §3.1.1: "This interval was apparently introduced by Wilson (1927) and we will call this
interval the Wilson interval." At the boundary `X = n` the formula collapses in closed form to
`[n/(n + κ²), 1]`; the one-sided version substitutes `κ = z_α` (BCD treats two-sided intervals;
the one-sided inversion of the same test is the standard reading of eq. (2), and BCD §2.2 notes,
citing Hall (1982), that for one-sided intervals the skewness error can exceed the discreteness
error). BCD §3.2 measures Wilson's coverage at 1-α = 0.95: `lim inf` over `p = γ/n` is 0.92
(γ ≥ 1), 0.936 (γ ≥ 5), 0.938 (γ ≥ 10), against 0.860/0.870/0.905 for the Wald interval.
BCD §4.1.1 gives the boundary fix (modified Wilson): for `x = 1..x*` replace the lower bound by
`λ_x/n` where `λ_x` solves `e^{-λ}(λ⁰/0! + ... + λ^{x-1}/(x-1)!) = 1 - α` (eq. 10), with
`x* = 2` for `n < 50`, `x* = 3` for `51 ≤ n ≤ 100+`; Table 4 tabulates `λ_x` (at 1-α = 0.95:
0.051, 0.355, 0.818 for x = 1, 2, 3; at 0.99: 0.010, 0.149, 0.436). Our counts sit at the *other*
boundary (`x` near `n`), where the symmetric prescription applies (BCD §4.1.1, "a symmetric
prescription needs to be followed to modify the upper bound for x very near n"; at `x = n` the
unmodified Wilson lower bound is already the closed form above).

### 2.2 Clopper-Pearson - BCD §4.2.1

`CI_CP = [B(α/2; X, n-X+1), B(1-α/2; X+1, n-X)]`, the beta quantiles, i.e. the inversion of the
equal-tail binomial test. Coverage is **always ≥ nominal** for every `p` (BCD §4.2.1), and BCD's
verdict is explicit: "The Clopper-Pearson interval is wastefully conservative and is not a good
choice for practical use, unless strict adherence to the prescription C(p,n) ≥ 1-α is demanded."
At `X = n` the two-sided lower endpoint is `(α/2)^{1/n}` and the one-sided (level α) lower
endpoint is `α^{1/n}`.

### 2.3 What BCD recommends - §5

"For small n (n ≤ 40)" the Wilson or the equal-tailed Jeffreys interval; "for larger n" Wilson,
Jeffreys and Agresti-Coull are comparable and Agresti-Coull (eq. 5) is recommended "for practical
use when n ≥ 40" on simplicity. Our committed-cell counts (45-183, §6) sit in the "larger n"
band where all three agree; Wilson is the one with a closed form and the one the row names.

### 2.4 Risk-controlling prediction sets - RCPS §2.2, Theorem 1; §3; Appendix B

Setting: a set-valued predictor `T_λ` monotone in `λ`, risk `R(λ) = E[L(Y, T_λ(X))]`, calibration
set of size `n`. UCB calibration: `λ̂ = inf{λ : R̂⁺(λ') < α for all λ' ≥ λ}` where `R̂⁺` is a
pointwise `(1-δ)` upper confidence bound on `R`. Theorem 1 (eq. 5): `P(R(T_λ̂) ≤ α) ≥ 1 - δ`.
Remark 2: the guarantee holds "even if the data used to fit the initial predictive model comes
from a different distribution. The only requirement is that the calibration data and the test data
come from the same distribution." Concentration choices (§3.1): simple Hoeffding (eq. 6-7),
Hoeffding-Bentkus (§3.1.2, Prop. 3-4), Waudby-Smith-Ramdas (§3.1.3, their recommendation for
general bounded loss); and for **binary** loss, Appendix B eq. (41)-(42):

```
R̂⁺_bin(λ) = sup{ R : P(Binom(n, R) ≤ ⌈n·R̂(λ)⌉) ≥ δ }        (RCPS eq. 42, App. B)
```

with the instruction (§3.1.2, p. around eq. 270 of the fetched text): "In the special [case] where
the loss takes values only in {0,1}, this exact binomial result gives the most precise upper
confidence bound and **should always be used**." Theorem B.1: with this bound, `T_λ̂bin` is an
(α, δ)-RCPS. Calibration-size guidance (§3.4, Fig. 4(b)): at α = 0.1 about 1,000 calibration
points suffice; at α = 0.01 "a few thousand"; at α = 0.001 about 10,000. Dependent losses:
§6.1-6.2 handle pairwise (ranking, metric-learning) losses as U-statistics of order two, with
tail bounds at effective sample size `⌊n/2⌋` (Prop. 7, Hoeffding-Bentkus-Maurer); that is the
family's published device for losses that are functions of tuples rather than points. Measured
on: five tasks (cost-sensitive, multi-label and hierarchical classification, image segmentation,
protein structure prediction; abstract and §5).

### 2.5 Conformal risk control - CRC eq. (3)-(5), Theorem 1-2

For monotone losses bounded by `B`, `λ̂ = inf{λ : (n/(n+1))·R̂_n(λ) + B/(n+1) ≤ α}` (eq. 4);
Theorem 1 gives the guarantee `E[L_{n+1}(λ̂)] ≤ α` (eq. 3) under i.i.d. calibration-plus-test and
monotonicity; Theorem 2 and Prop. 1 show tightness up to `2B/(n+1)` (eq. 5). The guarantee is **in
expectation only**; §2.4 shows the algorithm fails for non-monotone risk. (The gentle intro's
rendering, §4.3 eq. (29), is the same algorithm written `α - (B-α)/n`.) Measured on: false
negative rate, graph distance, token-level F1 (abstract).

### 2.6 Learn then Test - LTT §1.1, §2.1-2.3, Theorem 1

Calibration set i.i.d. (§1.1); a discrete family `{T_λ}_{λ∈Λ}`; risk `R(λ) = E[L(T_λ(X), Y)]`.
Procedure (§2.1): (1) per `λ_j` the null `H_j : R(λ_j) > α`; (2) a finite-sample valid p-value
per null; (3) `Λ̂ = A({p_j})` for any family-wise-error-rate controlling `A`, e.g. Bonferroni
`p_j ≤ δ/|Λ|`. Theorem 1 (eq. 1): `P(sup_{λ∈Λ̂} R(λ) ≤ α) ≥ 1 - δ`, so **any** `λ ∈ Λ̂`, chosen
even data-drivenly after the fact, is an (α, δ)-risk-controlling prediction. The p-value they
recommend for bounded loss (Prop. 1, eq. 2) is the hybrid Hoeffding-Bentkus:

```
p_j^HB = min( exp{-n·h_1(R̂_j ∧ α, α)},  e·P(Bin(n, α) ≤ ⌈n·R̂_j⌉) ),
h_1(a,b) = a·log(a/b) + (1-a)·log((1-a)/(1-b))                     (LTT eq. 2)
```

Representative δ: "The reader can think of 10% as a representative value of δ" (§1.1).
**With |Λ| = 1 this is exactly a test of a FIXED threshold on a calibration set**: reject
`H_0 : R(λ_0) > α` at level δ; no multiplicity correction is needed because there is one
hypothesis. Measured on: FDR-controlled multi-label classification, selective classification and
regression, OOD detection, instance segmentation with three simultaneous risks (§3-4).

### 2.7 What the gentle intro adds - §3.2 Table 1, §4.1, §4.3, §4.5-4.6, App. A

Calibration-set size for split conformal (§3.2, Table 1, δ = 0.1, α = 0.1): slack ε = 0.01 needs
n = 2491, ε = 0.005 needs n = 9812. Group structure (§4.1, eqs. (19)-(22), Prop. 1): to get
per-group guarantees, stratify the calibration scores by group and calibrate a quantile **within
each group**; valid under i.i.d. sampling of the grouped points. Non-exchangeability: §4.5
weighted conformal under covariate shift, §4.6 under drift; its reference list carries Barber et
al., *Conformal prediction beyond exchangeability*, as the pointer for dependent/non-exchangeable
sequences (read here only as cited by the gentle intro, not fetched). Appendix A restates LTT
with the high-probability goal (eq. 58) against CRC's in-expectation one.

## 3. Mapping onto this code

All line numbers are HEAD (`310e7660`); the working tree's only change to a named seam is
`PumpPhotoGate.measuredNumericTotal` 865 → 889 (in-flight corpus intake), which moves no line.

1. **Printing the interval.** `PumpReaderPipelineTests.report` (`ios/Tests/TankbookCoreTests/
   PumpReaderPipelineTests.swift:559-573`) extends its precision line with the Wilson two-sided
   95% interval and the one-sided 95% lower bound, computed from `LiveMeasurement.committedCorrect`
   / `.committed` (struct at :473-487). Same addition in `gateMirror`'s print (:225-228). Inputs
   are our `Int` counts; output is two `Double`s formatted like the existing `%.3f` fields. The
   per-head table (:565-567) keeps raw counts; per-head intervals are optional stratification
   (adaptation A4 below).
2. **The floors stay drift alarms, not gates.** `liveCommittedFloor` / `livePrecisionFloor`
   (:56-58) and `committedFloor` / `precisionFloor` (:28-29) keep their equality/floor assertions
   (:97-101, :236-237); the interval is printed beside them. Nothing retires them.
3. **The gate's comparison.** `PumpPhotoGate.precisionThreshold` (`ios/Sources/TankbookCore/
   Config/PumpPhotoGate.swift:112`) is compared against point estimates today:
   `allowsPumpPhoto` (:137-139) and `violation(flagEnabled:precision:coverage:)` (:146-156) read
   `measuredPrecision` (:125-127) / `readerPrecision` (:98-100), i.e. `committedCorrect /
   committed` from the constants at :39-48 and :86-95. Those constants are exactly the `(x, n)`
   the interval formulas take. **No constant is retired by this row.** If the product owner
   decides "the 0.99 floor holds" means the interval's lower bound (§5.3), the change is one
   expression at :138 and the parameter meaning at :146-156 (pass the lower bound), plus the same
   reading in `livePath`'s `#expect(measurement.precision >= Self.livePrecisionFloor)`
   (PumpReaderPipelineTests.swift:101). That decision is the owner's; this note supplies the
   arithmetic only, per the row.
4. **The risk-control bound.** A new test-support function computes, over the TRAIN split, the
   per-photo binary loss `1{any committed cell wrong}` and the per-photo fractional loss
   `wrong/committed`, then the exact binomial UCB (RCPS App. B eq. 42) on the binary loss and the
   HB p-value (LTT eq. 2) on the fractional loss, at α = 0.01, δ = 0.05 and δ = 0.10. It reuses
   `PumpReaderTestSupport.isTrain` (`PumpReaderTestSupport.swift:77`) and the scoring loop shape of
   `measureLive` (PumpReaderPipelineTests.swift:493-557) with the split filter flipped; the result
   is printed beside the heldout point estimate in `report`. It runs in the L5 harness only.
5. **Detector override.** `PumpReaderTestSupport.detectorURL` (`PumpReaderTestSupport.swift:26-29`)
   hardcodes `ml/pump-reader/.out/det/DigitRows.mlmodel`; the override mirrors the existing
   classifier pattern `modelURL` (PumpReaderPipelineTests.swift:78-79): `PUMP_DETECTOR=<path>`
   read from `ProcessInfo.processInfo.environment`, falling back to the dev path, with
   `makeDetector` (:31-33) unchanged in shape. No paper involved; the Qwen review §2.1 names the
   defect (candidate exports conflated by overwriting the dev copy).
6. **The leak's consequences.** `PumpLeakConsequenceTests.swift` (untracked at this commit, being
   built concurrently; ceilings at :21-22, per-currency commit scan at :44-54) is the seam. The
   row scopes it to fields and presence of values only (hard rule 12), so **no interval is
   computed over leak values**: the consequence measurement is which (photo, currency) reads
   commit which fields, named. The 116-photo denominator is §6's count.

## 4. Decision 1 - which interval to print, at what confidence, which side

**Print the Wilson score interval, two-sided 95%, beside every precision the pipeline prints;
print the one-sided 95% Wilson lower bound as the gate-facing number; keep Clopper-Pearson as the
named conservative cross-check, not the headline.** Reasons, all from the fetched texts: the row
names Wilson; BCD §5 recommends Wilson (or Jeffreys) below n = 40 and treats Wilson as comparable
to the alternatives above it, with the closed form; BCD §4.2.1 rules Clopper-Pearson out as an
estimation interval ("wastefully conservative") while its guaranteed coverage is exactly what a
*certification* reading wants (§5.3); Jeffreys needs a beta quantile (no closed form, BCD §3.1.3)
for no decision-relevant gain at our n; Agresti-Coull is Wilson widened (BCD §3.1.2: "never
shorter than the Wilson intervals"), so it would only flatter the floor.

Formulas to implement, `x` correct of `n` committed:
- two-sided 95%: BCD eq. (4) with `κ = 1.959963984540054`;
- one-sided 95% lower: BCD eq. (4)'s lower endpoint with `κ = 1.6448536269514722`, which at
  `x = n` is exactly `n/(n + κ²)`;
- CP one-sided 95% lower: `α^{1/n}`-form at `x = n`, else the beta quantile
  `B(0.05; x, n-x+1)` (BCD §4.2.1), computed by bisection on `P(Bin(n,p) ≥ x) = 0.05`.

Values at today's measurements (computed for this note, `x/n` = correct/committed):

| measurement | x/n | Wilson 2s 95% | Wilson 1s 95% lower | CP 1s 95% lower |
|---|---|---|---|---|
| app path `.off`, gate constants @HEAD | 45/45 | [0.9213, 1.0000] | 0.9433 | 0.9356 |
| PU.67 livePath `.onRefusal` (held 2026-09-23) | 51/52 | [0.8988, 0.9966] | 0.9183 | 0.9120 |
| PU.65 readPhoto on-refusal | 54/54 | [0.9336, 1.0000] | 0.9523 | 0.9460 |
| annotated windows, gateMirror | 111/112 | [0.9512, 0.9984] | 0.9610 | 0.9583 |

The 45/45 two-sided lower bound 0.9213 reproduces the Qwen review §2.1 arithmetic ("≈0.92"),
which is the number that motivated the row.

## 5. Decisions 2-4

### 5.1 Decision 2 - risk control on a FIXED threshold, and which split calibrates

Certifying a fixed pipeline is **not** conformal risk control or RCPS as published: CRC eq. (4)
and RCPS §2.2 *choose* λ from the calibration set and guarantee the risk of the chosen λ̂
(CRC eq. 3 in expectation; RCPS eq. 5 with probability 1-δ). Certifying a λ fixed in advance is
the singleton case of **Learn then Test** (LTT §2.1 with |Λ| = 1, Theorem 1): a one-sided test of
`H_0 : R(λ_0) > α` on the calibration set, p-value LTT eq. (2), reject at level δ; for our binary
per-photo loss the sharper published instrument is the exact binomial UCB, RCPS Appendix B
eq. (41)-(42) and Theorem B.1, which the paper says "should always be used" for {0,1} loss.
Certify = "UCB ≤ α", equivalently "p^HB ≤ δ".

What the test assumes (LTT §1.1: calibration set i.i.d.; RCPS Remark 2: calibration and test from
the same distribution, the fit allowed to come from anywhere else; CRC Theorem 1: i.i.d.
calibration-plus-test) and what our corpus violates, in three ways:

1. **In-sample fit.** The shipped classifier's round 6 trained on the train split's real glyphs
   (`PumpReaderTestSupport.swift:39-48`, decision 9: "a number measured on it is memorisation"),
   and the law's nat windows (`PumpReadingLaw.swift:33,38,43`) are tuned to that round's margin
   scale. Losses on train stills are therefore in-sample losses of the shipped pipeline, not
   exchangeable draws of its deployment loss. RCPS Remark 2 permits the *fit* to use other data
   but not the *calibration* data; here calibration is the fit data.
2. **Same-fill duplicates inside train.** `pump-088-...-reflection-b`, `pump-243/246/265/293-...-
   second-angle` (split.csv @HEAD) are second photos of fills already in train; their losses are
   near-copies, not independent draws.
3. **Station clusters.** 32 of the 68 heldout stills are Circle K forecourts, 7 of them the same
   two Peetri/Sikupilli stations; train is heavier still. A station is a random effect over
   display families, so "photos" are not identically distributed across stations.

What the literature says to do about each, and what this row takes:
- For (1), two published routes. (a) **Label the certificate for what it is**: a train-computed
  bound certifies the pipeline *as it would behave blind to these stills*; reported beside the
  heldout point estimate it is an honest in-sample number, which is what the row prescribes
  ("computed on the TRAIN split and reported beside the heldout point estimate"). (b) **Let LTT
  absorb the selection**: take Λ = the grid of candidate law windows (and deskew modes), compute
  one HB p-value per setting on train, apply Bonferroni δ/|Λ| (LTT §2.1 step 3); then "the shipped
  setting is in Λ̂" is a valid (α, δ) claim *despite* being tuned on the same split, because the
  family-wise correction prices the search. This is LTT's stated purpose and needs no new data.
  The clean fix remains a second frozen draw, which the row keeps as the owner's call.
- For (2) and (3), the published devices are: make the **group the calibration unit** (a loss per
  fill, or per photo, is i.i.d. across groups even when cells inside it are not); **per-group
  calibration** for per-group claims (gentle §4.1 eqs. (20)-(22), Prop. 1); **U-statistic
  concentration at reduced effective sample size** when the loss is a function of tuples (RCPS
  §6.1, Prop. 7, effective n = ⌊n/2⌋ for order two); and **weighted conformal** under a stated
  shift (gentle §4.5). This row takes the first: the photo is the unit (§5.4), and per-make
  stratification is available later through the existing per-head table
  (PumpReaderPipelineTests.swift:62-67) via gentle §4.1's stratification, unexercised now.

So: **the train split calibrates, as the row directs, with the certificate labelled in-sample;
the photo is the exchangeable unit; the exact binomial UCB (RCPS App. B) on the per-photo binary
wrong-commit loss is the bound; δ reported at 0.05 and 0.10; α = 0.01.** Reachability at today's
train size (250 photos, 668 scored cells, §6), computed for this note:

| calibration unit, k wrong | exact binomial UCB, δ=0.05 | certifies ≤ 0.01? | δ=0.10 | certifies? |
|---|---|---|---|---|
| 668 cells, k=0 | 0.0045 | yes | 0.0034 | yes |
| 668 cells, k=1 | 0.0071 | yes | 0.0058 | yes |
| 668 cells, k=2 | 0.0094 | yes | 0.0079 | yes |
| 668 cells, k=3 | 0.0116 | no | 0.0100 | yes (edge) |
| 250 photos, k=0 | 0.0119 | **no** | 0.0092 | yes |
| 250 photos, k=1 | 0.0188 | no | 0.0155 | no |

The photo-unit row is the one to print as the headline: at 250 photos even a perfect in-sample
run cannot certify 0.01 at δ = 0.05 (0.0119), and certifies at δ = 0.10 only with zero wrong
photos. The cell-unit line certifies more easily precisely because it pretends the 2.67 cells per
photo are independent; print it as the secondary, labelled.

### 5.2 Decision 3 - what "the 0.99 floor holds" can mean, and what each reading needs

Three readings, with the committed-cell count `n` (zero or one wrong commit) at which each becomes
*reachable at all*, computed for this note by solving the bound ≥ 0.99:

| reading | 0 wrong | 1 wrong |
|---|---|---|
| point estimate `x/n ≥ 0.99` | n ≥ 100 | n ≥ 100 (99/100 = 0.99) |
| Wilson one-sided 95% lower ≥ 0.99 | **n ≥ 268** | n ≥ 446 |
| Wilson two-sided 95% lower ≥ 0.99 | n ≥ 381 | n ≥ 563 |
| CP one-sided 95% lower ≥ 0.99 | **n ≥ 299** | n ≥ 473 |
| CP two-sided 95% lower ≥ 0.99 | n ≥ 368 | n ≥ 555 |

At the photo unit (binary loss, "no photo commits a wrong cell") the same table applies with
photos as n: 268 (Wilson 1s) / 299 (CP 1s) error-free photos. Today's populations (§6): heldout
offers 183 scored cells in 68 photos and 45-52 commits per arm; train offers 668 cells in 250
photos. Therefore:

- The **point-estimate reading** is reachable today and is what `allowsPumpPhoto`
  (PumpPhotoGate.swift:138) and `livePrecisionFloor` (PumpReaderPipelineTests.swift:58) implement;
  it is also what no measurement in the tree establishes as a floor, which is the row's premise
  (Qwen §2.1).
- The **cell-unit interval reading** is unreachable on heldout at any precision (183 < 268) and
  reachable on train only in-sample (668 ≥ 268), i.e. it would certify the memorising pipeline,
  not the shipped one.
- The **photo-unit interval reading** is unreachable on both splits today (68 and 250 photos
  against 268/299), in-sample or not. A second frozen draw of ~60 stills (Qwen §4.5) does not
  close it either; reaching 268 error-free *photos* is a corpus-growth programme, not a row.

What the papers imply: BCD's whole argument (§2, §5) is that a point estimate with no coverage
statement is not an interval claim, and that the conservative interval (CP) is the instrument when
"at least 1-α" is the contract; RCPS/LTT make the same point in risk language (a bound with a
δ, not a mean). So the literature's answer to "point or lower bound" is: **the lower bound, at
the confidence the decision's error budget names, with the sample size the bound needs stated
next to it** - and where the needed n exceeds the corpus, the honest output is "not yet
decidable", which is exactly PU.67's held outcome. The gate's rule (which reading ships the mode)
is the product owner's; the arithmetic above is the row's deliverable.

### 5.3 Decision 4 - the counting unit under clustering

Cells are not independent within a photo: the law commits a pair or a triple together ("a triple
commits only when EXACTLY one combination closes the arithmetic; fields the surviving triples
agree on commit alone", `PumpReadingLaw.swift:8-14`; the price-less pair path, PU.54), so one
misread cell drags its partners' fate and one good photo yields up to three correlated losses.
The conformal family's assumption is exchangeability **of the calibration points** (LTT §1.1,
CRC Theorem 1, RCPS Remark 2); it says nothing about independence inside a point. Hence:

- **Primary unit: the photo.** Per-photo binary loss `1{any committed cell wrong}`; losses are
  then one per capture event, exchangeable across captures to the extent captures are; the exact
  binomial UCB (RCPS App. B) applies as-is. This is the unit the product promise lives in ("never
  a wrong fill-up" is per fill-up, PumpPhotoGate.swift:23-27).
- **Secondary unit: the photo with fractional loss** `wrong/committed ∈ [0,1]`, which targets the
  cell-level wrong-commit rate the gate names; bounded loss, so the HB bound (RCPS §3.1.2, Prop.
  3-4; LTT eq. 2) applies. It weights photos equally, not cells, so it estimates the per-photo
  mean of the within-photo error fraction, not the pooled cell rate; label it.
- **Tertiary, labelled approximation: cell-level Wilson with a design-effect-adjusted n**,
  `n_eff = n / (1 + (m̄-1)ρ)` with m̄ = 2.69 scored cells per heldout photo (183/68) and 2.67 on
  train, ρ the within-photo correlation of correctness measured from the per-fixture table the
  report already prints. The design effect is the standard survey-sampling device for clustered
  binomial data (Kish 1965; Rao-Scott style adjustments for interval widths); **it is named here,
  not fetched in this run**, and the implementable recipe above does not depend on it. RCPS's own
  device for dependent losses is the U-statistic route (§6.1, Prop. 7), which fits pairwise
  losses, not our within-photo clusters; say so rather than stretching it.
- **Per-group claims** (per make, per station brand) use gentle §4.1's stratified calibration
  (eqs. 20-22) when anyone asks for them; at 5 makes and 68 heldout photos the strata are too
  thin today (32 Circle K, 25 other/unknown, §6).

## 6. Population, counted at today's commit, and what would falsify the row

Counted at `310e7660` from `Spike/ReceiptSpike/fixtures/pump/{split.csv, windows.json,
expected.csv}` with the harness's own filter (`PumpReaderTestSupport.swift:49-77` and the scoring
loop `PumpReaderPipelineTests.swift:498-552`): split == heldout AND `reviewed: true` AND field
non-blank in expected.csv AND not `csvDisagrees`:

- **heldout: 68 stills, 183 scored numeric cells** (all 68 reviewed; 3 heldout cells excluded by
  `csvDisagrees`: pump-031 total, pump-140 unitPrice, pump-208 unitPrice - 186 asserted minus 3).
  183 equals `PumpPhotoGate.readerNumericTotal` @HEAD (PumpPhotoGate.swift:95), which is the
  cross-check that the filter is the harness's.
- **train: 250 stills, 668 scored cells** (same filter; 679 asserted minus 11 `csvDisagrees`).
- **non-pump (leak denominator): 116 images** - receipts 97, screenshots 9, expenses 9, fiscal 1 -
  matching the row's "5 of 116".
- Clustering facts used in §5: 2.69 scored cells per heldout photo; same-fill duplicates present
  in train (`-second-angle`, `-reflection-b` names above); 32/68 heldout stills Circle K, 7 of
  them two Peetri/Sikupilli stations.
- The working tree's uncommitted intake (three new stills, moved split/expected/windows) is **not**
  in these counts; the implementer re-runs the same filter at their build commit and prints both.

What the papers measured versus what we expect here: BCD measured exact coverage and length over
(n, p) grids in S-PLUS (n to ~2000, 2000-point p grids, §2-3) and recommends by those curves;
RCPS measured five vision/biology tasks and calibration sizes (§3.4, Fig. 4b: α = 0.01 needs "a
few thousand" points); CRC measured FNR, graph distance and token-F1 (abstract); LTT measured
FDR, selective prediction and OOD tasks (§3-4); the gentle intro's size table (§3.2 Table 1) puts
±0.01 slack at n = 2491. **Our 668 train cells / 250 photos sit an order of magnitude below the
calibration sizes those papers recommend for α = 0.01**, which is why §5.1's table, not a
certificate, is the expected output: expect "cell-unit certifies in-sample iff k ≤ 2; photo-unit
does not certify at δ = 0.05 at any k", printed beside a heldout point estimate whose own interval
(§4 table) excludes 0.99 on every arm measured since PU.63.

Falsifiers, named in advance:
- **F1 (implementation).** Mutate one scored heldout cell from correct to wrong (or inject k into
  the interval function's inputs): the printed Wilson and CP bounds must equal the hand-computed
  values of §4's table to four decimals, red before the fix and green after. A printed bound that
  does not move with k is the defect this row exists to prevent.
- **F2 (transfer).** If the train run certifies ≤ 0.01 while the heldout arm shows k ≥ 3 wrong
  commits of 52 (P(Bin(52, 0.01) ≥ 3) = 0.0154) or k ≥ 3 wrong photos of 68 (p = 0.031), the
  train certificate is contradicted by heldout at δ = 0.05 and the mapping must be reported as
  in-sample only. Today's k = 1 (p = 0.407) contradicts nothing and certifies nothing.
- **F3 (reachability).** Any implementation that prints a photo-unit (0.01, 0.05) certificate at
  n = 250 photos is arithmetically impossible (k = 0 gives UCB 0.0119) and is a bug, not a result.
- **F4 (unit drift).** If the cell-unit and photo-unit bounds ever coincide to four decimals on a
  run with any photo committing 2+ cells, the grouping has silently collapsed to cells.

## 7. Cost

- **Latency.** Nothing in this row runs on the capture path. The interval is closed-form Wilson
  (a sqrt and two divisions) or a ~60-iteration bisection on a binomial CDF (lgamma from Darwin,
  no new dependency), executed inside the L5 harness print; the livePath run's own cost
  (tens of seconds, unchanged) dominates it by five orders of magnitude. No Release latency number
  changes and none is owed; if the owner later moves the gate's comparison to the lower bound, the
  device-side cost is one closed-form expression at launch (inference from the formula, not
  measured: nanoseconds).
- **Bundle.** +0 bytes if the interval stays in the test bundle (the expected case); ~1-2 KB of
  TankbookCore Swift only if the gate rule changes to read a lower bound.
- **New code to maintain.** Roughly 80-120 lines in `PumpReaderTestSupport`/the pipeline tests:
  `wilson(x:n:z:)`, `cpLower(x:n:alpha:)`, `binomUCB(k:n:delta:)`, the per-photo loss aggregation,
  and the `PUMP_DETECTOR` override (5 lines, mirroring PumpReaderPipelineTests.swift:78-79). No
  C/C++ target, no Accelerate, no Core ML change; iOS 18.0 / iPhone 12 constraints are not engaged
  because no part of this ships to the device.

## 8. Adaptations, named (the fence)

Each is a departure from the published method; anything the implementer adds beyond this list
needs the product owner's OK.

- **A1 (not a departure, stated to keep it one).** Certifying a fixed λ is LTT with |Λ| = 1
  (Theorem 1, no multiplicity correction), not CRC/RCPS λ-selection. Using CRC eq. (4) or RCPS
  §2.2 to "certify" the shipped windows would misapply a selection guarantee to a non-selection.
- **A2. Calibration on in-sample data.** Papers: calibration exchangeable with test and not used
  to fit (RCPS Remark 2, LTT §1.1, CRC Theorem 1). We: calibrate on train per the row, label the
  certificate in-sample. Why: heldout is the frozen ratchet tier (decision 9,
  PumpReaderTestSupport.swift:39-48) and spending it on calibration would consume the only
  unbiased measurement; the label, not silence, carries the cost.
- **A3. LTT over the window grid as the owner's upgrade.** If a deployment-facing claim is wanted
  without new data, run the family version (Bonferroni δ/|Λ|, LTT §2.1 step 3) over candidate law
  windows and deskew modes. Departure from the row's singleton phrasing; published method.
- **A4. Photo as calibration unit, per-photo losses.** Papers use per-point losses on i.i.d.
  points. We group cells into photo losses (binary primary, fractional secondary). Why: the law
  commits pairs/triples jointly (PumpReadingLaw.swift:8-14), so cell losses are dependent and the
  exchangeable object is the capture.
- **A5. δ = 0.05 printed alongside δ = 0.10.** LTT §1.1 names 10% as representative; the row's
  "95% Wilson" fixes δ = 0.05 for the printed interval. Cost is a log(1/δ) factor only; both
  columns are printed so the choice is visible.
- **A6. One-sided lower bound for the gate, two-sided printed.** BCD evaluates two-sided coverage
  and warns (via Hall 1982, §2.2) that one-sided intervals carry the skewness error; our decision
  ("is precision at or above 0.99") is one-sided. Print both, gate faces the one-sided number.
- **A7. Wilson to estimate, exact binomial (CP-type inversion) to certify.** BCD §4.2.1 rejects CP
  as an estimation interval; RCPS App. B mandates the exact binomial UCB for binary loss. Both
  stand, in different roles; the implementer must not substitute one for the other.
- **A8. "Wrong" is the scorer's tolerance, not 0/1 truth.** Losses inherit
  `CorpusScorer.tolerance = 0.005` (CorpusABScorer.swift:175) and 0.1 for derived cells
  (PumpReaderPipelineTests.swift:210); a commit 0.004 off counts correct. The papers' losses are
  exact indicators; ours is a corpus convention the interval inherits.
- **A9. Domain and device.** Seven-segment pump displays instead of the papers' vision/NLP tasks
  costs nothing statistically (all four methods are distribution-free); no on-device component, so
  no iOS/Core ML adaptation exists to name.
- **A10. Accepting a wider certificate than the papers' calibration sizes.** gentle §3.2 Table 1
  and RCPS §3.4 put α = 0.01 at thousands of calibration points; we have 668 cells / 250 photos.
  We report the bound with its reachability table (§5.1) instead of treating it as tight; hiding
  that gap would be the invented-method failure mode this note exists to prevent.
