# PU.78 research note - a last-digit misread validated as agreement

*RESEARCH-TO-CODE run for `PU.78` (`docs/TASKS.md:1065`). Product owner, 2026-09-23: "review the
published research to apply it into the code, instead of coming up with our own solution."
Populations and every measured number in this note are at commit `47ff7a10` (HEAD when this note
was written; a concurrent annotator session holds uncommitted `windows.json` changes that move the
reviewed counts - the implementer re-counts at their own build commit with the same filter, §5).
Evidence rule: every claim cites a fetched paper section/equation, a `file:line`, or a number
measured in this run; inference is labelled. This run wrote no code and ran no builds; the only
writes were `/tmp` scratch (trace outputs, replication scripts - volatile, named below) and this
file. The `pump-read` binary existed and was newer than every source under `ios/Sources` (built
19:51:13, newest source 19:51:08, both 2026-09-23), so it was used as-is per the brief.*

## 0. First task: the eight wrong cells, traced to the tier and rule that admitted each

The brief says "seven cells"; the enumerated list holds **eight** (seven train cells in five
photos - the certify wrong list, `/tmp/agentlogs/pu68-pipeline.log:62-68` - plus the heldout
deskew-on cell pump-275). All eight were traced.

**Method.** The app's own entry point was run per fixture: `pump-read --trace-serve` (which calls
`PumpDisplayCapture.classify` with a `PumpTrace` observer, `TraceServe.swift:78-80` - the same
entry the harness measures, `PumpReaderPipelineTests.swift:566-572`), detector
`ml/pump-reader/.out/det/DigitRows.mlmodel` (the harness's own, `PumpReaderTestSupport.swift:35`),
stdin `{"image":..., "deskew":"off", "currency":...}` per still (`"onRefusal"` for pump-275, the
arm PU.67 measured), currency from `expected.csv` (GBP for pump-137, EUR the rest). Traces:
`/tmp/pu78-trace/replies.jsonl` (volatile). The trace carries each committed field's value,
provenance, reason and log-posterior, and each cell's top-3 ranked digits with log-posteriors -
exactly the inputs the law consumes. The law's arithmetic was then **replicated in Python from the
traced posteriors** (`/tmp/pu78-count/replicate-law.py`, volatile; constants and structure copied
from `PumpReadingLaw.swift`) and reproduces the observed verdict on all six fixtures **to the
nat**: pump-137 `-12.234401` vs observed `-12.234401477523217`; pump-251 `-14.069815` vs
`-14.069815078854333`; pump-099 liters `-1.0374669` / total `-5.5979240`; pump-264 `-3.0557770` /
`-3.7791355`; pump-266 `-2.3865735` / `-3.6885052`; pump-275 `-5.3227156` / `-8.7636541`. Tier
attributions below are therefore arithmetic, not inference.

### 0.1 The attribution table

| Photo, wrong cell(s) | Tier that committed | The rule that admitted it | Evidence |
|---|---|---|---|
| pump-099 total 20.27/20.21 | **pair tier, validation branch** | `pairValidationTolerance` 0.05: implied 20.27/10.64 = 1.90508, nearest shown board 1.949, rel. gap **2.31 %** <= 5 % -> commits with `.shownPriceDiffers` | `PumpReadingLaw.swift:262,:293-296,:305-307`; observed caution `shownPriceDiffers(shown: 1.949, implied: 1.905)`; replication: cleanBoardClose found 0 closes, so `resolveWithoutPrice:207` fell to `pairOutcome` |
| pump-137 liters 5.2/52.3 + total 9.5/95.6 | **main triple tier** | `closingSlack` 0.011 admitted miss **0.0100**: 5.2 x 1.828 = 9.5056 -> product 9.51 vs shown 9.50 (the close is floor-shaped, `exactClosing` false). The correct-scale triple (52.0 x 1.828 -> truncated 95.0) sits **8.0 nats** under `topRead` = outside `readWindow` 6.0, because its price AND total placements each pay `decimalMarkPenalty` 4.0. Replication: 15 triples close, exactly 1 survives the `:91` filter | `PumpReadingLaw.swift:27,:38,:43,:89-91,:398-413`; trace lp -12.2344 = replication |
| pump-251 total 75.36/75.35 | **main triple tier** | One beam substitution closes inside the slack: total cell5 reads 8 at margin **0.012** (runner-up 9 a hair behind - the reader is coin-flipping), its rank-3 digit 6 makes "007536" -> 75.36; 35.90 x 2.099 = 75.3541 -> product 75.35, miss **0.0100** <= 0.011, subs = 1 <= `maxSubstitutions`. The TRUE total 75.35 is unreachable: digit 5 is rank >= 4 on cell5 (top-3 = 8/9/6, `beamWidth` 3), and 8->5 is a two-segment edit absent from the confusion table (`DigitRepair.swift:67-75`), so the repair tier could not reach it either - and never runs, because the main tier closed. Sole survivor -> all three fields commit, provenance `.read` (a main-tier beam substitution is invisible in provenance, `commit():452-453`) | `PumpReadingLaw.swift:22,:89-94,:406-413`; replication: 5 closes, 1 kept (gap 4.734 <= 6.0) |
| pump-264 total 59.9/55.4 | **pair tier, validation branch** | Two misread total cells (cell1 9-for-5 margin 1.83, cell2 9-for-4 margin **0.23**) -> implied 59.9/28.87 = 2.07482; nearest shown board 1.981, gap **4.52 %** <= 5 % -> `.shownPriceDiffers` commit | `PumpReadingLaw.swift:293-296`; observed caution `(shown: 1.981, implied: 2.075)` |
| pump-266 liters 36.28/36.29 + total 66.79/66.74 | **pair tier, validation branch** | Both misreads (margins 0.809 rank-3-truth and **0.331** rank-2-truth) move the implied ratio by 0.1 % (66.79/36.28 = 1.84096 vs truth 66.74/36.29 = 1.83907); shown board 1.919, gap **4.24 %** <= 5 %. This is the fixture the 5 % band was tuned for (its TRUE state is a 4.35 % loyalty discount, `PumpReadingLaw.swift:256-261`) - the misreads hide inside the legitimate gap | `PumpReadingLaw.swift:262,:293-296`; observed caution `(shown: 1.919, implied: 1.841)` |
| pump-275 total 103.31/103.37 (heldout, deskew `.onRefusal` only; the seed attempt refused `nothingClosed`, the "turned" retry committed) | **pair tier, agreement branch** | `pairAgreementTolerance` 0.005: implied 103.31/51.71 = 1.99787 vs shown board 1.999, gap **0.056 %** <= 0.5 % -> bare agreement, price abstained with no reason. A 0.5 % band at this magnitude admits +-0.52 on the total; the 6-cent error passes with 8.6x margin. Note what the arithmetic almost did: cleanBoardClose missed by 6 cents (51.71 x 1.999 = 103.368 -> 103.37 != shown 103.31, miss 0.06 > 0.011) - had the total read correctly, the board close would have committed all three fields exactly | `PumpReadingLaw.swift:267,:301-304`; trace attempt 0 law `nothingClosed`, attempt 1 committed; observed `unitPrice {value: null, reason: null}` - the agreement branch's bare `.abstained` (`:302`) |

**The row's working inference is confirmed for five of the eight cells and refuted for three.**
The pair bands admitted 099/264/266/275 (5 cells). pump-251 and pump-137 (3 cells) are the
brief's other horn: **the triple arithmetic itself closes on a misread** - in both cases at miss
exactly 0.0100, inside `closingSlack` 0.011 by 0.001. Two different problems, two different fixes
(§4).

### 0.2 The per-cell measurements the fix design runs on

Margins (nats, `PumpCellReading.margin` = lp0 - lp1, `PumpReadingTypes.swift:109`) from the
traces; "true rank" is where the true digit sits in the cell's ranked list:

| Cell | read | true | margin | true rank |
|---|---|---|---|---|
| 099 total cell3 | 7 | 1 | 0.582 | 2 |
| 137 liters cell2 | 0 | 3 | 0.531 | **out of beam** (>3); 3 is a 3-segment edit from 0, not in the confusion table |
| 137 total row | 3 cells "9.50" | display "95.60" (4 digits) | - | **slicer framing defect**: a cell of the total row was never cut; also its dp mis-sits (mark cell0), and the price row's dp mis-sits (mark cell2 vs expected cell0) |
| 251 total cell5 | 8 | 5 | **0.012** | **out of beam**; runner-up is 9 at 0.011 nats - the reader is coin-flipping |
| 264 total cell1 | 9 | 5 | 1.828 | 2 |
| 264 total cell2 | 9 | 4 | 0.230 | 2 |
| 266 liters cell3 | 8 | 9 | 0.809 | 3 |
| 266 total cell3 | 9 | 4 | 0.331 | 2 |
| 275 total cell4 | 1 | 7 | 0.957 | 3 |
| 275 dp bits | total mark seen cell0 (expected cell2); liters mark seen cell3 (expected cell1) | - | - | dp false positives; the dp bit's AUC on real cells is 0.52-0.55 (PU.73 row, `docs/TASKS.md:1072`) |

Photo-level minimum margin over committed cells: 099 **0.582**, 137 **0.207**, 251 **0.012**,
264 **0.230**, 266 **0.331**, 275 **0.790** (its liters cell0 - a CORRECT digit). Against that,
the heldout's 17 committing photos (swept this run, §6) have minimum margins: pump-139 **0.200**,
pump-014 0.289, pump-030 0.300, pump-083 0.366, pump-112 0.461, pump-119 0.587, pump-065 0.710,
pump-062 0.785, pump-080 0.825, pump-165 0.897, pump-180 0.987, pump-106 1.014, pump-186 1.253,
pump-031 1.546, pump-061 1.813, pump-281 1.864, pump-079 1.883. **The distributions overlap
almost completely**: the wrong photos span 0.012-0.790, the correct heldout photos reach down to
0.200. Since `p_max <= sigmoid(margin)` for the SR statistic (the softmax max is bounded by the
top-2 logistic), the overlap carries over to the paper's SR too. This single measurement kills the
naive reading of the row's citation - a per-cell confidence gate cannot separate these populations
at any threshold that keeps the heldout floor - and it shapes everything in §4.

## 1. The citations, checked

| Citation | Fetch result | Verdict |
|---|---|---|
| Geifman & El-Yaniv, *Selective Classification for Deep Neural Networks*, NeurIPS 2017, arXiv:1705.08500 | arXiv abs page fetched: title exact, authors Yonatan Geifman, Ran El-Yaniv, v1 23 May 2017, cs.LG/cs.AI. Venue not on the abs page; confirmed from SelectiveNet's fetched reference list: "In Advances in neural information processing systems, pp. 4878-4887, 2017" (secondary, fetched). **Full text read** via ar5iv (LaTeXML rendering of v2) | **Correct as cited.** |
| *SelectiveNet*, ICML 2019, arXiv:1901.09192 | arXiv abs page fetched: full title is *SelectiveNet: A Deep Neural Network with an Integrated Reject Option* (the row cites the short name), same two authors, Comments field: "Accepted to ICML 2019". **Full text read** via ar5iv (v4) | **Correct as cited** (short title). |
| Hokamp & Liu, ACL 2017, arXiv:1704.07138 | arXiv abs page fetched: *Lexically Constrained Decoding for Sequence Generation Using Grid Beam Search*, Chris Hokamp, Qun Liu, Comments: "Accepted as a long paper at ACL 2017". **Full text read** via ar5iv (v2) | **Correct as cited** (PU.74's paper, as the row says). |
| Guo et al., ICML 2017, arXiv:1706.04599 | arXiv abs page fetched: *On Calibration of Modern Neural Networks*, Chuan Guo, Geoff Pleiss, Yu Sun, Kilian Q. Weinberger, Comments: "ICML 2017". **Full text read** via ar5iv (v2) | **Correct as cited** (PU.72's paper). |
| Meter/display reading with a redundancy check (the brief's search) | arXiv API + Crossref searched (§2.6-2.8). Fetched in full: **Laroca et al. 2021**, *Towards Image-based Automatic Meter Reading in Unconstrained Scenarios*, arXiv:2009.10181, IEEE Access 9:67569-67584 (journal_ref on the arXiv page). Abstracts fetched: Salomon/Laroca/Menotti 2022 arXiv:2201.02850 (Measurement 204:112025); Shenoy & Aalami arXiv:1807.04888 (AMIA 2017:1564-1570); Moreira arXiv:2210.01325. Crossref metadata only (full texts NOT read): Kanagarathinam & Sekar 2019 Energy Reports 5:842-852 (CC-BY, DOI 10.1016/j.egyr.2019.07.004); Bell 1966 *Single-digit-correcting decimal codes*, Electronics Letters, DOI 10.1049/el:19660319; Fratini 1989 *Error detection in a class of decimal codes*, IEEE Trans. IT, DOI 10.1109/18.42228; Legind Larsen 1983 BIT DOI 10.1007/bf01934459; Narasimhan & Jordache 1999 *Data Reconciliation and Gross Error Detection* (Gulf Publishing) chapters incl. *Introduction to Gross Error Detection* DOI 10.1016/b978-088415255-2/50008-2 | Mixed - each row's fetch depth is stated; nothing below is described beyond what was fetched. |
| Exact-check primary: **Luhn, US patent 2,950,048**, *Computer for verifying numbers*, filed 6 Jan 1954, granted 23 Aug 1960, assignor to IBM | **Full text fetched** (Google Patents) | **Correct primary source** for the zero-tolerance arithmetic-check paradigm (§3.1). |
| Metrology family: JCGM 100:2008 (GUM) and JCGM 106:2012 (*The role of measurement uncertainty in conformity assessment*) | BIPM catalog page fetched: both titles, editions and DOIs (10.59161/JCGM100-2008E, 10.59161/JCGM106-2012); the DOI resolves to a citation stub. **PDFs not text-extractable in this environment** (no pdftotext; the fetched bytes are raw streams) | Existence and titles verified; **their internal formulas are NOT cited as verified** - the coverage-factor constants (k=2 ~95 %, k=3 ~99 %, rectangular a/sqrt(3)) are stated in §3.2 as commonly-reproduced GUM values, labelled unverified here, and the nominated method does not depend on them. |
| El-Yaniv & Wiener 2010, *On the Foundations of Noise-free Selective Classification*, JMLR 11(53):1605-1641 | JMLR abstract page fetched (title, authors, pages). PDF fetched but not text-extractable here | Abstract read (it defines the risk-coverage trade-off framing both G&S papers build on); body NOT described. |
| Gascuel & Caraux 1992 (the tight binomial bound inside SGR) | Not fetched independently; its statement is G&S Lemma 3.1 eq. (4), which WAS fetched, and G&S's reference list gives *Pattern Recognition Letters* 13:757-764 | Method sourced through G&S, stated as such. |
| Chow 1957/1970 (the reject-option origin) | Not fetched; appears in the fetched G&S and SelectiveNet reference lists and their introductions' description of the cost-based family | Not relied on. |
| ISO 7064 (check character systems) | iso.org returned 403 to the fetcher | **Not verified; not relied on.** |

Caution carried over from the PU.68 note (it cost that run two fetches): arXiv ids guessed from
memory resolve to unrelated papers. Every id above was fetched by id or found by title/author
search, never recalled.

## 2. The methods as published

### 2.1 The exact redundancy check (zero tolerance) - Luhn patent, full text

The published check-digit paradigm, from the fetched patent text: a check digit is appended at
the right end, computed so that "in verifying the number by cross addition of the multiple digits
of the number and the check digit, in accordance with a rule of substitution, the result will be a
zero"; verification is the equation itself - "if it is a -0- the number is verified, if it is not a
-0- some transposition of the digits has occurred in copying the number." The stated motivation is
exactly this row's defect class: single-digit and transposition errors introduced "in copying a
number". **The tolerance of the check is zero; its resolution is the last digit by construction.**
The decimal-codes literature (Bell 1966 "single-digit-correcting", Fratini 1989 "error detection",
titles verified via Crossref, bodies not read) is the same family; at title level it documents
that the family both DETECTS and CORRECTS single-digit errors - correction by an exact equation
admits at most one repaired value, which is the rule this repo already implements in
`DigitRepair.swift:17-23` ("accept a repair only when **exactly one** substitution reproduces the
total ... if two different substitutions both close the arithmetic, the document does not
determine the answer").

The property that matters for the law: an exact equation used **as a gate on a read** rejects
every single-digit error of the checked value; the same equation used **as a search constraint**
(generate candidates until one satisfies it) has the power of the candidate set, not of the
equation - pump-251 measured it: the beam supplied a wrong last digit and the 0.011-slack equation
"validated" it. Constrained decoding (Hokamp & Liu, §2.5) is the published name for
constraints-in-search; the check-digit family is the published name for constraints-as-gate. The
defect is what happens when a gate is run as a search with a tolerance wider than the resolution
it protects.

### 2.2 Selective classification with guaranteed risk - Geifman & El-Yaniv 2017 (full text)

Setting (§2): selective classifier (f, g), coverage phi(f,g) = E[g(x)], selective risk
R(f,g) = E[l(f(x),y) g(x)] / phi(f,g) (eq. 1); goal (eq. 2): Pr_{S_m}{R(f,g) > r*} < delta.
Selection function (eq. 3): g_theta(x) = 1 iff kappa_f(x) >= theta, for ANY confidence-rate
function kappa_f - §3 states explicitly "We do not assume anything on kappa_f"; the ideal kappa is
loss-monotone, and footnote 1 warns a severely skewed kappa yields a bound far from the target.
**SGR (Algorithm 1)**: sort the labeled calibration set S_m by kappa; binary-search the index z
over k = ceil(log2 m) steps; at each step theta = kappa(x_z), r_hat_i = empirical selective risk on
the g-projection, b*_i = B*(r_hat_i, delta/ceil(log2 m), g_i(S_m)); if b*_i < r* set z_max = z else
z_min = z; output (f, g_k) and b*_k. **Lemma 3.1** (Gascuel-Caraux, eq. 4): B* is the b solving
sum_{j=0}^{m r_hat} C(m,j) b^j (1-b)^{m-j} = delta - "the tightest possible numerical
generalization bound" in this setting (Hoeffding-style bounds "incur some slack"). **Theorem 3.2**:
the union over the k search steps keeps Pr{exists i: R(f|P_{g_i}) > B*(r_hat_i, delta/k, .)} < delta.
Confidence functions (§4): **SR** = max softmax response; MC-dropout = minus response variance
over dropout passes; SR wins decisively on ImageNet (at 60 % coverage top-1, SR error 10 % vs
MC-dropout > 20 %), so the paper's own experiments keep only SR. Parameters the authors chose:
delta = 0.001 in every application (footnote 2); calibration size ~5,000 (half of CIFAR-10
validation) and ~25,000 (ImageNet). Measured results (Tables 1-6): CIFAR-10 r* = 0.01 at test
coverage 0.7856, bound 0.0099; ImageNet top-5 r* = 0.02 at coverage ~0.535 (VGG-16) / 0.594
(ResNet-50 top-5 r*=0.02); bounds were never violated by test risk. **Equivalence already in the
tree**: Lemma 3.1's B* is the exact binomial tail inversion `PumpPrecisionBounds.binomialUCB`
(PumpPrecisionBounds.swift:65-68, shipped under PU.68, which sourced it from RCPS App. B eq. 42 -
the same inversion), and SGR over a threshold family is Learn-then-Test with a Bonferroni
correction over the search path (PU.68 note §2.6; `trainSplitRiskBound` runs the |Lambda|=1 case,
PumpReaderPipelineTests.swift:117-157).

### 2.3 SelectiveNet - Geifman & El-Yaniv 2019 (full text)

Training-time alternative: objective (eq. 2) min R(f_theta, g_theta) s.t. phi(g_theta) >= c; loss
(eq. 3) L = r_hat_l(f,g|S_m) + lambda * Psi(c - phi_hat(g|S_m)), Psi(a) = max(0,a)^2 (an interior-point
variant); total loss alpha*L_(f,g) + (1-alpha)*L_h with an auxiliary full-coverage head h;
alpha = 0.5 in all experiments, lambda = 32. Three heads; the selection head ends in one sigmoid
neuron; inference abstains iff g(x) < 0.5. Post-training coverage calibration: tau = the
100(1-c) percentile of g over an independent unlabeled set V_n, with a Hoeffding coverage-violation
bound epsilon = sqrt(ln(2/delta)/(2n)) (the ar5iv rendering prints the exponent sign positive and
drops the sqrt - both read as rendering artifacts of Hoeffding (1963); labelled as this note's
observation, not the paper's text). Measured on
SVHN / CIFAR-10 / Cats-vs-Dogs (VGG-16 variants) + one UCI regression: e.g. CIFAR-10 coverage
0.70: risk 0.32 % vs SR 0.42 % vs MC-dropout 0.43 %; Cats-vs-Dogs coverage 0.80: 0.35 % vs SR
0.68 % (48 % improvement). Its own framing (§1): "Existing rejection mechanisms are based mostly on
a threshold over the prediction confidence of a pre-trained network. In contrast, SelectiveNet is
trained ... end-to-end."

### 2.4 Calibration - Guo et al. 2017 (full text)

Perfect calibration (eq. 1): P(Y_hat = Y | P_hat = p) = p. ECE (eq. 3): sum over M equal-width bins
of |B_m|/n * |acc(B_m) - conf(B_m)|; the paper uses M = 15. Temperature scaling (eq. 9):
q_hat = max_k sigma_SM(z/T)^(k), T > 0 fitted by NLL on a hold-out validation set; "the parameter T
does not change the maximum of the softmax function ... temperature scaling does not affect the
model's accuracy" (§4.2) - within a cell it also cannot change the RANKING, so a per-cell reject
threshold's guarantee is untouched by T; T changes the cross-cell comparability of kappa and the
coverage achievable at a given risk. Measured (Table 1, ECE %): CIFAR-100 ResNet-110 16.53 -> 1.26;
ImageNet DenseNet-161 6.28 -> 1.99, ResNet-152 5.48 -> 1.86; temperature scaling beats or ties
histogram binning, isotonic, BBQ, vector and matrix scaling on nearly every vision task; vector
scaling recovers the same solution ("network miscalibration is intrinsically low dimensional").
Cost: one-dimensional convex optimization, ~10 conjugate-gradient iterations. Method assumption:
train/validation/test from the same distribution (§4).

### 2.5 Grid Beam Search - Hokamp & Liu 2017 (full text)

Algorithm 1: beams indexed by (t, c) - output timestep x number of constraint tokens covered; open
hypotheses generate from the model or START a constraint, closed hypotheses CONTINUE one;
Grid[t][c] = k-argmax over the union by model.score; top-level beams (c = numC) hold the
constraint-satisfying hypotheses; best = argmax score among finished. generate = k-argmax over the
softmax (eq. 4); start/continue index specific token scores. beamSize 10 in all experiments (§3.4);
complexity O(k t c) vs O(k t) (§3.3). Measured on EN-DE/FR/PT NMT: pick-revise editing
+9.20/+8.64/+8.25 BLEU in the first cycle (Table 1); automatic terminology (NPMI >= 0.9, eq. 6)
+1.82/+2.59/+13.73 BLEU (Table 2). Relevance here is structural, not directly implementable: GBS
enforces REQUIRED content during generation; PU.74 owns applying that to role x digit-count x
decimal conventions.
What PU.78 takes from it is the limit: a constraint at generation time cannot conjure a token the
per-step k-best excludes - pump-251's true digit 5 sits rank >= 4 in a beam of 3, and no constraint
set fixes that; the published responses are a wider k (cost, §3.3) or rejection (§2.2).

### 2.6 The deployed meter-reading answer: reject on confidence, not bands - Laroca et al. 2021 (full text)

The largest fetched field study of reading numeric displays in production (Copel: >4 million meter
readings/month; Copel-AMR dataset: 12,500 field images, 50,000 labeled digits, 2,500
illegible/faulty). Their pipeline rejects twice: a legibility classifier (CDCC-NET) refuses 98.9 %
of illegible/faulty meters before recognition while accepting 99.82 % of legible ones; then, for
readings themselves, **a threshold on the per-digit prediction confidence of Fast-OCR**: Table 8 -
rejecting the lowest-confidence 0/5/10/15/20 % of images lifts end-to-end recognition from
94.75/96.98 % to 99.22/99.44 % (UFPR-AMR/Copel-AMR; average 95.87 -> 99.33 %); "recognition rates
above 99 %, which are acceptable to service companies, are achieved by setting a confidence
threshold that rejects 15 % of the images." The stated rationale is this row's defect, verbatim
(§6): "very few reading errors are tolerated in real-world applications due to the fact that
**a single digit recognized incorrectly can result in a large reading/billing error**." How they
set the tolerance: they do not - the threshold is set by a REJECTION-RATE budget (the business's
re-capture cost), not by a statistical guarantee; G&S's SGR (§2.2) is the guarantee-carrying
version of the same mechanism. No arithmetic redundancy check appears in the fetched text.

### 2.7 What the other fetched display-reading papers do, and what was searched

Shenoy & Aalami (AMIA 2017, abstract): a smartphone engine reading seven-segment medical monitors
at 98.2 % digit accuracy - no consistency check in the abstract. Moreira 2022 (abstract):
EfficientDet-lite reading medical-device displays, 100 % digit classification on 104 images / 438
digits - none. Salomon/Laroca/Menotti 2022 (abstract): dial-meter regression; their METER-LEVEL
metric is scored "with an error tolerance of 1 Kilowatt-hour (kWh)" - the field's scoring tolerance
is the last digit's resolution, not a percentage. Kanagarathinam & Sekar 2019 (metadata only):
energy-meter seven-segment detection/recognition; its reference list (fetched via Crossref) maps
the AMR literature and contains no arithmetic-validation work. Receipt/invoice KIE on arXiv
(SROIE competition report 2019, AMuRD 2023, Chargrid-reconstruction 2021, DocReL 2022 - abstracts
fetched): evaluation is key-field F1; **no fetched paper in this family publishes a tolerance for
"total = sum of lines"** - that check lives in the exact-equation tradition (§2.1) and in
paywalled engineering literature this run could not read. Data reconciliation / gross-error
detection (Narasimhan & Jordache 1999, chapters verified via Crossref) is the family that derives
test thresholds from propagated measurement uncertainty; its full text is paywalled and was NOT
read, so its method is not described here. The metrology standards that formalize
uncertainty-derived acceptance zones (JCGM 106:2012; GUM JCGM 100:2008) were verified
bibliographically only (§1).

### 2.8 The answer to the brief's literature question

"How do published systems set the tolerance of a redundancy check relative to the resolution of
the last digit and the reader's per-digit confidence?" - three published answers, and none of them
is a relative percentage band:

1. **Zero.** Where the redundant quantity is computed from the same digits (a check digit; a
   display's own total = its operands' product), the check is an exact equation and catches every
   single-digit error (Luhn, fetched; decimal-codes family, title level). Tolerance wider than the
   resolution admits exactly the error class the check exists to catch: a one-cent misread of a
   two-decimal total produces a residual of exactly one cent, which any band >= 0.01 validates.
   pump-251 and pump-137 are that sentence, measured (miss 0.0100 vs slack 0.011).
2. **Derived from uncertainty, with a published coverage factor.** Where the compared quantity is
   itself a measurement (our pair tier compares a ratio of two READ values against a third READ
   value), conformity assessment carries each reading's uncertainty into the acceptance zone
   (JCGM 106:2012 - title verified, text not read here). For quantized displays the uncertainty
   component is the half-ULP of each operand; for pump-275 the propagated relative bound on
   total/liters is sqrt((0.005/103.31)^2 + (0.005/51.71)^2) = 0.0108 % and the observed gap is
   0.056 % (5.2x the bound - a contradiction); for pump-014 (a CORRECT heldout pair commit) the
   bound is 0.145 % and the observed gap 0.269 % (1.85x - also a contradiction, because its BOARD
   price is the misread value). So a resolution-derived band separates the two only for a coverage
   factor k in (1.85, 5.19) on these numbers - and the GUM-standard k = 2 or 3 applied to the
   rectangular-distribution form (a/sqrt(3); constant labelled unverified, §1) does NOT separate
   them. Recorded as a measured alternative, not nominated (§5-A8).
3. **No tolerance - refusal.** Deployed AMR controls the wrong-READ rate by rejecting
   low-confidence readings at a coverage budget (Laroca 2021 Table 8), and the finite-sample way
   to set that threshold from data is SGR: pick (r*, delta), get theta and a proof
   Pr{selective risk > r*} < delta (G&S Algorithm 1, Theorem 3.2). Per-digit confidence enters
   here directly - and §0.2's measured overlap says that on THIS corpus, with TODAY's classifier,
   it cannot reach the row's gate. The instrument still ships (§4-M3), because the risk-coverage
   curve is what turns "the bands feel too loose" into an owner-visible price list.

## 3. Mapping onto this code

Three mechanisms, each published, composed in the order the law runs. What each retires is named.

### M1 - the two-decimal close becomes the exact set {round2, floor2} (Luhn paradigm, §2.8-1)

`closingTriples` (`PumpReadingLaw.swift:392-430`): the interval test
`miss = |product - t|; miss <= closingSlack` (:406-413) becomes membership:
`t == round2(l x p)` OR `t == floor2(l x p)`, where product already rounds to cents (:398) and
floor2 is the same value floored to cents. `closingSlack` (:27) **retires as an interval**; the
`exactClosing` flag (:412, :336) becomes the round-branch of the predicate and
`commit()`'s exact-preference logic (:444-446) simplifies (every close is exact by construction;
keep the flag only if the floor branch needs distinguishing - implementer's call, no behaviour
depends on it once the interval is gone). The truncated branch (:415-425) is ALREADY the exact
paradigm (floor-or-round of the product to the display's decimals) and does not change; M1 makes
the two-decimal branch consistent with its own sibling. The repair tier (:107-151) calls
`closingTriples` unchanged and inherits exactness - its comment "the arithmetic still has to
close to the cent (no tolerance widening)" (:112-114) becomes literally true. The preset tier
(:99-105, slack = closingSlack + 0.005 x price, :399) keeps its resolution-derived half-step term
(half of the volume display's 0.01 L step times the price - already a quantity computed from
resolution, §2.8-2's principle) and loses the additive closingSlack term; pump-010 (the preset
fixture) is re-measured by name (A14).
Measured effect (§5 tables): pump-251's only close (miss 0.0100, neither round2 = 75.35 nor
floor2 = 75.35 equals 75.36) disappears -> the mechanically-enumerated alternatives find nothing
either (`/tmp/pu78-count/verify-m1m2.py`: zero exact-set closes among all <= 1-substitution beam
candidates of the main tier, and zero exact closes in the repair tier's single-confusion
substitutions - 8->{6,0,9} give 75.36/75.30/75.39, none in {round2, floor2} = {75.35}) -> abstains
`nothingClosed`. pump-137 SURVIVES M1 (9.50 = floor2(9.5056) - a genuine
floor-shaped close of a fabricated scale; the verify script confirms) -> M5. All 15 heldout
triple-family closes are exact or derived (measured, §5) -> zero heldout cost.

### M2 - the pair tier: exact agreement, then unique repair, then the owner's band

`pairOutcome` (`PumpReadingLaw.swift:276-308`) is restructured into three ordered steps:

1. **Exact agreement** replaces the 0.5 % band (:301-304): the top-read pair commits as agreement
   iff the committed total is in {round2, floor2}(liters x shown) for some shown price (the shown
   list is built at :206; band-filter it as the main tier filters prices). `pairAgreementTolerance`
   (:267) **retires**.
2. **Unique single-confusion repair against a shown price** - a new step, and the only mechanism
   measured that fixes pump-275 at zero heldout cost: substitute ONE cell of the liters or total
   window with a `DigitRepair.confusablePartners` partner (`DigitRepair.swift:63-75`), keep every
   other cell at its top read, and require an EXACT product against a band-filtered shown price.
   Commit iff exactly one distinct repaired pair closes (the repo's own published rule,
   `DigitRepair.swift:17-23`; the correction half of the single-error-correcting-codes family,
   §2.1); provenance `.repaired(cellIndex:from:to:)` on the substituted field
   (`PumpReadingTypes.swift:126-130`), so the form pre-fills an editable suggestion (hard rule 13;
   decision 11 holds: the shown price never overwrites the paid one, unitPrice stays abstained).
   This extends the main path's existing repair tier (:107-151) to the no-price branch; it is not
   a new invention, and A6 records it as an adaptation because the paper family (check-digit
   correction) does not specify a beam/confusion-table search.
3. **Band fallback**: today's validation branch (:293-296, :305-307) with
   `pairValidationTolerance` 0.05 unchanged - an owner product constant, measurably load-bearing
   (heldout pump-061 at 1.63 %, pump-014 at 0.269 %; train pump-266's TRUE discount at 4.35 %).
   The unconditional-5 % reading of the constant retires only in the sense that steps 1-2 now run
   first; the value stays (A7: no band value separates wrong pairs from legitimate discounts on
   this corpus - measured).

Measured effect: pump-275 -> step 2, **mechanically enumerated** (`/tmp/pu78-count/verify-m1m2.py`,
which enumerates every single-confusion substitution of the liters and total windows against every
band-filtered shown price): total cell4 partner 1->7 (in the table, `"1": ["7"]`) gives
"10337" -> 103.37 = round2(51.71 x 1.999) = round2(103.36829) exactly, and it is the **UNIQUE**
close -> commits 51.71 / 103.37, both CORRECT, provenance `.repaired`. PU.67's deskew arm goes
52/51 -> **52/52**, which is PU.67's reopen condition met by correction rather than refusal.
The same enumeration is **EMPTY** for pump-014 and pump-061 (the two heldout pair commits: the
needed edits are not confusions - partners of 7 are {1}, of 2 are {}) -> they fall to the band and
keep committing (014 as validation-with-caution instead of bare agreement; the reason histogram and
the caution change, the committed cells do not), and EMPTY for pump-099/264/266 -> band ->
unchanged (still wrong; M5/M6 own them). No band commit anywhere measured can be hijacked by a
fabricated repair.

### M3 - SR + SGR as the instrument that governs any confidence threshold (G&S 2017)

kappa per cell: the SR analogue **p_max = softmax over the ten pattern log-likelihoods** that
`PumpSegmentsModel.rank` already computes (`PumpSegmentsModel.swift:59-71`); `margin`
(`PumpReadingTypes.swift:109`) is reported beside it (p_max <= sigmoid(margin), so the measured
margin overlap bounds SR's too - §0.2). Fitting: SGR (Algorithm 1) over the reviewed TRAIN split
only (the heldout is the test, decision 9 - theta is never fitted on it), one app-path pass
collecting (kappa_photo = min kappa over the cells of the fields the law commits, photo wrong 0/1
under `CorpusScorer.tolerance` 0.005, `CorpusABScorer.swift:175`, compared at
`PumpReaderPipelineTests.swift:600`); B* per step = `PumpPrecisionBounds.binomialUCB`
(:65-68 - Lemma 3.1 eq. 4, §2.2); delta = 0.001 with the ceil(log2 m)-step union correction
(Theorem 3.2); r* = 0.01 (the 0.99 precision floor the pipeline already asserts,
`PumpReaderPipelineTests.swift:58`). Owner sets (r*, delta); nothing else is chosen by hand.
Photo-level is the primary unit (A3, PU.68's A4 precedent); a cell-level curve is printed as
secondary. **Ship rule: theta ships only if the heldout gate passes at it** - and §0.2's overlap
predicts it will not (theta > 0.790 needed to catch all six wrong photos; heldout pump-139 commits
correctly at 0.200): the artifact is the risk-coverage CURVE, the price list the owner reads, and a
red gate that keeps the law honest if a future classifier (PU.66/PU.73/PU.77) separates the
populations. If the fit surprises and a theta passes both gates, it ships as a compiled constant
with the fit's provenance in its comment (the `committedFloor` precedent) and a new
`PumpAbstentionReason` case names the refusal (`PumpReadingTypes.swift:23-54`; implementer checks
the reason never crosses a payload/API boundary - it is diagnostic, hard rules 9/16).

### M4/M5/M6 - what is measurably NOT this row's to fix

- **M4, the dp bit**: a hard dp-consistency refusal (a committed placement contradicting the seen
  mark refuses the reading) would catch 099/137/251/275 - and would refuse FOUR correct heldout
  photos (pump-014 total, pump-062 liters, pump-112 price, pump-180 price; measured this run by the
  dp-consistency replication in `/tmp/pu78-count/analyze-rules.py`), ~11 of 45 cells at photo-level
  refusal. The dp classifier's AUC is 0.52-0.55 (PU.73). Blocked on PU.73; recorded with numbers
  so PU.73 can re-propose it when dp earns a hard check. `decimalMarkPenalty` stays soft (:43).
- **M5, pump-137**: survives M1 (floor-exact), unreachable by kappa at any gate-passing theta
  (its photo min margin 0.207 vs pump-139's correct 0.200 - a 0.007-nat window), unreachable by
  repair (0->3 is not a confusion; the true liters digit is out of beam; the total row was framed
  with 3 cells for a 4-digit display - a slicer defect). It is PU.74's shape (role x digit-count x
  decimal conventions, GBS-enforced at generation: a 3-cell GBP total is what a constraint set
  rejects) plus the classifier/beam rows for the unreachable digit. Filed to PU.74 with this
  evidence; PU.78 does not duplicate GBS.
- **M6, pump-099/264/266**: pair-validation commits with NO exact redundancy available (the paid
  price is not displayed, or its board is misread). Measured: wrong-photo gaps 2.31/4.52/4.24 %
  against a legitimate heldout 1.63 % and pump-266's own true discount 4.35 % - **no band value
  separates them**; kappa overlaps (§0.2); dp is blocked (M4). Their fix is read quality
  (PU.73 dp, PU.66/PU.73 classifier margins - all five of their misread cells carry the true digit
  at rank 2-3, gaps 0.23-1.83 nats), not tolerance design. Recorded so nobody re-litigates the band.

## 4. Adaptations, named and justified (the fence)

A departure the implementer adds that is not on this list needs the product owner's OK.

| # | Paper | We do | Why |
|---|---|---|---|
| A1 | SR = max softmax of a trained classifier (G&S §4) | p_max = softmax over the ten seven-segment pattern log-likelihoods of the Bernoulli-segment decoder (`PumpSegmentsModel.rank:59-71`), computed from the same 8 segment probabilities | Our classifier emits segment sigmoids, not digit logits; the pattern likelihood IS the decoder's ranking and what the law already consumes. G&S require only a coherent ranking (§3). |
| A2 | SGR calibrates on a set independent of training (G&S §5.1: half the validation set) | theta is fitted on the reviewed TRAIN split, which the shipped classifier trained on - IN-SAMPLE, labelled as such in every print | No second labelled split exists; heldout stays frozen (decision 9) and is the gate, not the fit. PU.68's A2 precedent. The guarantee degrades to an in-sample statement; the heldout gate is the real control. |
| A3 | Losses i.i.d. per sample (G&S §2) | Photo is the primary unit (kappa_photo = min over committed cells; 0/1 photo loss); cell-level secondary | Cells within a photo are dependent - PU.68's A4, already the shipped certificate's stance (PumpReaderPipelineTests.swift:140-146). |
| A4 | delta = 0.001, r* per application (G&S §5.1) | delta = 0.001 with the Theorem-3.2 union correction; r* = 0.01 | The paper's own delta; r* = 0.01 is the repo's existing 0.99 precision floor (:58), not a new number. Both remain owner-settable. |
| A5 | Luhn: ONE exact equation | Close set {round2, floor2}: two exact values | The head's rounding mode is per-head unknown and the law documents flooring heads (:25-26, :333-337). The set is the union of the two rounding semantics, still zero-tolerance. Enumeration check before shipping: every train/heldout close with miss in (0.0005, 0.011] today is listed and each is floor-or-round explainable, or named to the owner (measured so far: pump-137 floor-shaped, pump-251 neither - dies by design; the full train sweep is the implementer's first check). |
| A6 | Check-digit correction; GBS | Pair-tier repair = unique single-confusion exact close against a band-filtered shown price, provenance `.repaired` | Extends the repo's own measured rule (`DigitRepair.swift:17-23`, P2.13: pump-015, pump-013) to the no-price branch; the papers do not specify a confusion-table search, so this is named as an adaptation. Only mechanism measured that fixes pump-275 at zero heldout cost. |
| A7 | No paper sets a discount band | `pairValidationTolerance` 0.05 kept, unchanged, behind steps 1-2 | A product constant (tuned to pump-266's 4.35 % true discount, :256-261), measurably load-bearing (pump-061 1.63 %, pump-014 0.269 %); no value separates wrong from discounted on this corpus (§3-M6). Never re-fitted to train by this row. |
| A8 | Metrology guard band (JCGM 106 family, text unread) | NOT nominated: the k-coverage-factor variant of the agreement branch | Measured: separates pump-275 from pump-014 only for k in (1.85, 5.19) raw-RSS / (3.21, 9.0) rectangular; the GUM-standard k in {2,3} on the rectangular form fails the heldout gate via pump-014. Exact-set + repair (M2) dominates it with no free parameter. Range recorded should the owner prefer a band. |
| A9 | - | dp-mark consistency stays a SOFT 4.0-nat penalty, no hard check | A hard check refuses 4 correct heldout photos (M4); dp AUC 0.52-0.55 (PU.73). |
| A10 | SelectiveNet trains a selection head end-to-end | Not shipped; SR+SGR (inference-time) is the nomination | SelectiveNet needs retraining the segment model and a head change - PU.73/PU.77 territory; its own §1 frames threshold-on-confidence as the pre-trained-model method, which is what the law is. Named as the published upgrade path. |
| A11 | MC-dropout (G&S §4) | Not shipped | The paper measures it below SR on ImageNet; 100 forward passes per cell (SelectiveNet §6.2's baseline setting) is off-budget for iPhone 12. |
| A12 | Temperature scaling (Guo eq. 9) | Not a prerequisite; PU.72 ordering is an optimization | G&S hold for ANY kappa (§3); T cannot change a within-cell ranking (§2.4). If PU.72 lands first, theta re-fits offline (cheap); if not, M3 fits on the uncalibrated statistic and says so. |
| A13 | GBS (Hokamp & Liu Algorithm 1) | Not implemented in this row | PU.74 owns constrained generation (role x digit-count x decimal conventions); pump-137 is filed there (M5) with the measured evidence that PU.78's mechanisms cannot reach it under the row's gate. |
| A14 | - | Preset tier keeps the half-volume-step x price term, loses the additive closingSlack term | The half-step term is resolution-derived (volume ULP/2 x price); the additive term is the interval M1 retires. pump-010 re-measured by name. |
| A15 | - | Beam width, nat windows (`ambiguityWindow` :33, `readWindow` :38), confusion table: UNCHANGED | Not this row's constants. Recorded observation: at pump-137 the readWindow 6.0 + two 4.0 mark penalties are what filtered the correct-scale triple (gap 8.0) - if PU.74 or the owner revisits the windows, that interaction is measured and named here. |

## 5. What the papers measured, and what we expect on our corpus

**What they measured**: G&S 2017 - CIFAR-10/100, ImageNet (VGG-16, ResNet-50), calibration 5k-25k
samples; e.g. CIFAR-10 risk 1 % at coverage 78.6 %, bounds never violated (Tables 1-6).
SelectiveNet - SVHN/CIFAR-10/Cats-Dogs/UCI-concrete; 8.5-48 % risk improvement over SR at equal
coverage (Tables 2-5). Guo - 6 vision + 4 NLP datasets; ECE 16.53 -> 1.26 (CIFAR-100 ResNet-110)
and 6.28 -> 1.99 (ImageNet DenseNet-161) (Table 1). Hokamp & Liu - WMT NMT EN-DE/FR/PT; +1.8 to
+13.7 BLEU (Tables 1-2). Laroca - 12,500 field meter images; 94.75/96.98 -> 99.22/99.44 % at
5-20 % rejection (Table 8). Luhn - no dataset; the claim is arithmetic (every single-digit error
and adjacent transposition breaks the zero-sum equation).

**Our populations, counted at commit `47ff7a10`** (filter: `isHeldout` / `isReviewedTrain`,
`PumpReaderTestSupport.swift:83-88`; cells = non-empty liters/unitPrice/total in `expected.csv`
minus `csvDisagrees`, `measureLive` at `PumpReaderPipelineTests.swift:576-608`; counted by
`/tmp/pu78-count/` scripts from `git show 47ff7a10:...` - volatile, re-runnable from this
description):

- **Heldout app path**: `split.csv` 328 data rows (256 train / 68 heldout / 4 heldout2); heldout
  AND reviewed = **68 stills, 183 scored cells** - equal to the shipped gate constants
  (`PumpPhotoGate.swift:86,:91,:95` = 45/45/183). This run re-swept all 68 through
  `pump-read --trace-serve` (the app's `classify`, deskew off, detector
  `ml/pump-reader/.out/det/DigitRows.mlmodel`) and reproduced **45 committed / 45 correct / 183
  cells, 17 photos committing, 0 wrong** - the binary and models in the tree measure what the gate
  says. Deskew-`.onRefusal` arm: **52 committed / 51 correct**, pump-275 the wrong cell (PU.67 row,
  `docs/TASKS.md:1063`); this run reproduced the pump-275 wrong commit under `"deskew":"onRefusal"`
  (seed attempt refused `nothingClosed`, "turned" attempt committed 103.31/51.71).
- **Reviewed train split**: 251 reviewed stills at HEAD, of which **244 carry >= 1 scored cell;
  670 cells** - the certify run's own prints ("34/244 ... of 670", pu68-pipeline.log:42; the 7
  cell-less stills are empty-truth negatives, listed in this run's count output). Shipped numbers:
  **124 committed / 117 correct, 7 wrong cells in 5 photos** (099, 137, 251, 264, 266;
  pu68-pipeline.log:42-43,:62-68). IN-SAMPLE (the classifier trained on these stills).
- **heldout2**: 4 stills (pump-322/323/327/328), frozen, consumed by no filter
  (`PumpReaderTestSupport.swift:83-85` excludes them from both arms).
- The eight traced cells of §0 are the defect population: 7 train cells (5 photos) + pump-275
  (heldout, deskew-on arm only).
- **Working-tree drift warning**: the uncommitted annotator `windows.json` in the tree right now
  would count reviewed-train 255 stills / 680 cells and heldout 67 / 182 (one heldout still's
  reviewed flag flipped, and +4 train reviews). Neither is this note's population; the implementer
  re-counts at their commit (PU.68's precedent, its row records the same move 250/668 -> 244/670).

**Expected result of the nominated method (M1 + M2 + M3-instrument), all measured this run on the
23 photos concerned (17 heldout committing + 6 wrong), extrapolation to the full train sweep
labelled where it occurs**:

| Check | Expectation | Basis |
|---|---|---|
| Heldout live (deskew off) | **45/45 unchanged** | All 15 triple-family closes exact/derived (M1 no-op); pump-062 board-close exact; pump-014 and pump-061 repair-enumerations EMPTY -> band keeps both. Measured per photo, §3-M1/M2 + `/tmp/pu78-count/verify-m1m2.py` |
| Heldout deskew-on arm | **52/52** expected (pump-275 corrected to 103.37 via the unique repair) | §3-M2, mechanically enumerated; PU.67 reopens on "the pump-275 misread is refused" - correction is stronger than refusal; if the implementer's sweep finds the repair non-unique, the fallback is refusal and PU.67's condition is still met. Caveat: the arm's other 7 commits (52 - 45) were not individually re-measured in this run - the implementer re-runs the arm |
| Train wrong cells | **7 -> 6** (pump-251's 75.36 refused); 137 x2, 099, 264, 266 x2 remain, owned M5/M6 | §3-M1/M2; extrapolation to unseen train photos: a train photo whose correct close today rides miss in (0.0005, 0.011] loses its commit UNLESS floor/round-explainable (A5's enumeration check runs first and names every case to the owner before shipping) |
| Train committed count | may FALL (pump-251's 3 cells; pump-137 unchanged; any A5-enumerated casualty) | The row's gate protects heldout commits, not train commits |
| Reason histograms | `nothingClosed` gains pump-251; `priceDisagrees`/caution gains pump-014 (agreement -> validation shape); a new repaired-provenance line appears for pump-275 in the deskew arm | §3-M2 |
| Oracle ratchet (771/889) and fragility <= 0.10 | hold | Oracle cells are `certainDigit` 0.97 (`PumpReadingTypes.swift:101-106`): exact closes by construction; inference - the implementer re-runs both (row gate) |
| M3 risk-coverage curve | No theta passes the heldout floor at r* = 0.01 on today's classifier (prediction from §0.2's overlap: theta <= 0.200 forced by pump-139; wrong photos need > 0.790) | Measured margins; the curve itself is the deliverable |

**What falsifies the row** (beyond the row's own gate - zero wrong on heldout, train wrong falls,
heldout commits do not fall, oracle ratchet and fragility hold):
1. Any heldout cell of the 45 lost, or any new heldout wrong cell, at the shipped setting.
2. pump-275 still committing 103.31 in the deskew-on arm (neither corrected nor refused).
3. pump-251 still committing 75.36.
4. M1's enumeration check finding a heldout close with miss in (0.0005, 0.011] - the exact set
   would cost a heldout commit and must go back to the owner before shipping.
5. M2's repair firing non-uniquely or uniquely-WRONGLY on any heldout or train photo (a repaired
   commit that the scorer marks wrong is a new wrong cell - gate 1 catches it; the uniqueness rule
   is the designed defence).
6. The SGR fit certifying r* = 0.01 at a theta that passes the heldout gate would falsify §0.2's
   overlap claim - good news, ship it, and this note is wrong where it says the curve cannot reach
   the gate.

## 6. Cost

- **Latency**: M1 replaces one interval comparison with two equality comparisons per candidate
  triple - nothing. M2's repair step enumerates <= (cells_liters + cells_total) x 3 partners x
  shown-prices exact products - dozens of floating-point multiplies, microseconds; it runs only on
  photos that reach the pair tier and only before the band fallback. M3 ships no runtime code
  unless a theta passes the gate (then: one comparison per cell at commit). This run's Debug
  wall-times per still through the full app classify (trace-serve, model cached): 104-623 ms on
  this Mac - Debug, indicative only; **the Release number is owed by the implementation** (the
  row's gate; for scale, PU.75's row records today's Release decision 13-73 ms and read 112-164 ms
  on a Mac). The SGR fit is one train-split app-path pass (~30 min Debug, the certify precedent,
  `PumpReaderPipelineTests.swift:124`) plus seconds of threshold arithmetic over the collected
  (kappa, label) pairs - offline, opt-in like `PUMP_CERTIFY=1`.
- **Bundle size**: +0 bytes. No model change; theta (if it ever ships) is a compiled Double;
  everything else is law arithmetic.
- **New code to maintain**: M1 ~30 changed lines in `closingTriples` + the preset term; M2 ~80-120
  lines (pair restructure + repair step + one new `PumpFieldProvenance` use site + reason-case
  addition); M3 ~150-250 test-only lines (fit harness + curve print, reusing
  `PumpPrecisionBounds`); named fixture tests for pump-251 (refuses), pump-275 (repairs to
  103.37), pump-014/061/062 (keep), pump-137 (still commits - the M5 marker test that goes red
  when PU.74 lands), plus the mutation each promise needs (restore the 0.011 interval -> pump-251
  green-wrong again; break repair uniqueness -> pump-275 abstains).

## 7. Findings recorded, not fixed here

1. **pump-137's total row was framed with 3 cells for a 4-digit display** ("9.50" for "95.60") and
   its price/liters dp bits mis-sit - upstream slicer/dp defects that enabled the scale collapse;
   the law then validated it. The slicer half belongs to the row-framing family (PU.76/PU.77); the
   law half is M5/PU.74.
2. **A main-tier beam substitution leaves provenance `.read`** (`commit():452-453` only maps the
   repair tier): pump-251 committed 75.36 with a substituted cell and no trace of it in the
   reading. Not fixed here (M1 makes the case rarer; changing provenance semantics touches the
   form's confirm logic) - named so the owner can file it if wanted.
3. **`resolveWithoutPrice:206` builds the shown-price list without a band filter** (18.991 and
   61.241 entered the nearest-shown search on pump-099/275; harmless there - the nearest won on
   distance - but a wild board value inside band distance would validate a pair). M2's steps 1-2
   band-filter; the fallback keeps today's semantics unless the owner says otherwise.
4. **Replication-tool artifact**: Swift's `.rounded()` is half-away-from-zero, Python's `round()`
   is banker's - pump-065's truncated close (37656.5 -> 3765.7) only replicates with Swift
   semantics. Any Python replica of the law must force half-up rounding. (pump-065's tier: main,
   truncated-derived close, subs = 1, exact - corrected attribution after fixing the replica.)
5. **The heldout's uncommitted reviewed-flag flip** (68 -> 67 in the working tree) came from the
   concurrent annotator session, not this run; counted at HEAD per the brief.
6. Trace and replication artifacts live in `/tmp/pu78-trace/`, `/tmp/pu78-heldout/`,
   `/tmp/pu78-count/` (volatile - PU.68's review finding 3 applies; every number this note relies
   on is written into the note itself).
