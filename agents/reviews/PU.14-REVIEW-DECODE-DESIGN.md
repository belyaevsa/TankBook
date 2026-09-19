# PU.14-REVIEW-DECODE-DESIGN - the end-to-end decode and gate design, reviewed BEFORE the build

Read-only design review, 2026-09-19. Scope: what PU.5 must specify - the decoder's output contract,
decimal recovery, row assignment, `PumpPhotoGate` semantics for an abstaining reader, the interaction
with the cloud arm and manual entry, and the row split. Sources read: `docs/EXTRACTION.md` -> "The
pump reader" and "The constraint no model changes", `docs/TASKS.md` -> PU (all rows, incl. the open
PU.17-PU.20), `HANDOVER.md` -> the pump-reader tranche, both sibling reviews
(`agents/reviews/PU.11-REVIEW-IMPL.md`, `PU.12-REVIEW-DATA.md`), `ml/pump-reader/REPORT.md`,
`model.py`, `glyph.py` (`decode_constrained`), `score.py`, the Swift side (`PumpPhotoGate.swift`,
`CrossCheck.swift`, `DigitRepair.swift`, `PumpExtractor.swift`, `NumberScanner.swift`
(`PumpNumber`), `FuelExtractor.swift`, `ExtractionAssembler.swift`, `ConfirmPrefill.swift` (core and
app), `GatewaySuggestionPolicy.swift`, `CapturePipeline.swift`, `PumpGlyphSlicer.swift`,
`PumpPanelLocator.swift`, `AccuracyRatchetTests.swift`, `CorpusPumpScorer.swift`, `CorpusABScorer.swift`),
`Spike/ReceiptSpike/fixtures/pump/{expected.csv,windows.json}`, `fixtures/high-water.json`,
`FuelPriceBands.seed.json`, `docs/JOURNEYS.md` J3/J3b/J4, `docs/ERRORS.md` -> Capture and Confirm
tables. No fixture image was opened; the corpus stays held-out. One file written: this one.

## Method, and the numbers I measured myself

Every corpus number below was computed in this session from the committed annotations only
(`expected.csv` + `windows.json` + `FuelPriceBands.seed.json` + `high-water.json`) with throwaway
Python; the full rule definitions are quoted inline so the orchestrator can reproduce any of them.
No training, no model runs, no repo writes beyond this file, no gates run (nothing compiled
changed). The three measurements that carry the review:

1. **The oracle-digits ceiling of the arithmetic** (section 2): given the annotated display strings
   as digit-only reads (dp dropped, the honest worst case - PU.11 F2: the dp bit is at chance, AUC
   0.520), the proposed candidate+uniqueness law resolves **94 of the 95 legible three-window
   fixtures to a UNIQUE triple, zero ambiguous**, and commits **313 of the 320 asserted numeric
   cells with 310 correct (precision 0.9904)** when a derived price is allowed, or **281 committed /
   278 correct (precision 0.9893)** without. All three wrong cells are the corpus's own declared
   artefact exceptions (pump-031, pump-065, pump-073). **The arithmetic is not the bottleneck and
   never was; the digits are.**
2. **The fragility of that law under misreads** (section 2.5): 13,230 single-digit mutations and
   40,000 sampled double mutations through the same law - the exact tier commits a wrong value on
   **1.5 %** of single mutations and repairs **78.5 %** back to the truth; the unconditional
   display-rounding tier roughly triples the wrong rate; the derive-without-price branch is the
   single largest confident-wrong source (**8.5 %** of commits wrong under mutation).
3. **The load-bearing priors, ablated** (section 2.4): removing the volume 2-decimal convention
   opens 17 of 95 fixtures to ambiguity; removing the price band opens 14; the money-shape total
   rule alone (today's `PumpNumber.moneyCandidates`) **commits a 10x-shrunk WRONG triple on
   pump-108** - each prior is measured, not asserted.

State of the reader in one paragraph, for the record: constrained digit-only decode is **0.666** on
count-correct windows (0.698 on the 192 count-correct transaction windows - PU.18's baseline),
count agreement **259/433 (0.598)**, dp agreement **1/422** and dp bit **AUC 0.520** (dead),
locator median IoU **0.008** (a stub), model confidence barely ranks real-cell errors (PU.11 F11:
0.763 accuracy at 30 % coverage vs 0.612 at 100 %, a flat curve), rules arm at **53/320** with
precision 0.946 / coverage 0.175 (`high-water.json`, `PumpPhotoGate.swift:39-64`), cloud arm at
**31/46** with five confident swaps and the pump-009 decimal shift (P4.12). The gate is precision
>= 0.99 on committed cells plus coverage >= 0.60 (`PumpPhotoGate.swift:71,81`), and the flag ships
off (`Config.default.json:13`).

---

## 1. The decoder's output contract

### The three options, against DigitRepair and the cross-check

**(a) Argmax digit per cell.** The cheapest interface and the wrong one. It throws away exactly the
information the design law is built on ("a `9` whose segment `e` is uncertain is a `4` *candidate*
with a known posterior, not a confident wrong digit", `docs/EXTRACTION.md` -> the pump reader,
point 3). With argmax-only, `DigitRepair` stays what it is today - a fixed 7-pair table
(`DigitRepair.swift:61-69`) substituting blind, in table order - and the measured confusions the
table lacks (`4<->1`, `0<->7`, `8<->2` in PU.11 F13's census) stay unreachable. The law of section 2
also starves: a beam needs ranked alternatives, and with argmax a window whose string does not
close has nothing to search. Reject.

**(b) Ranked digit list with posteriors per cell.** The proposal. Constrained decode over the ten
valid patterns (PU.16's shipped rule - `glyph.py:293-316`, and PU.16's own check column: "PU.5's
Swift decoder must use the same rule") produces, per cell, all ten digits ranked by joint
log-likelihood `sum(log p_i for on-bits) + sum(log(1-p_i) for off-bits)` plus the runner-up margin.
This feeds (i) the candidate beam of section 2, (ii) the repair ordering that replaces the fixed
table (rank substitutions by candidate posterior; keep `DigitRepair`'s uniqueness LAW - "exactly
one substitution closes, two means nil", `DigitRepair.swift:98-110` - untouched), and (iii) PU.20's
future calibrated abstention signal (the margin is the raw material; F11 says it does not rank yet,
so it must not be the committer).

**(c) Raw 8 probabilities.** Keep them - but as the layer BELOW (b), not instead of it. Two
consumers need the raw vector: PU.19's per-frame fusion (median of the 8 probabilities over Live
Photo frames happens before decoding, or the fusion is decoding N times and voting, which loses the
soft information), and provenance for diagnostics dumps. Nothing in the law itself reads raw
sigmoids once ranked candidates exist. So the contract is two-layered: the Core ML wrapper emits
raw probabilities; the decoder emits ranked candidates; the law consumes candidates.

### Proposed Swift types (all in `TankbookCore/Extraction/PumpReader/`, all pure, all L1-testable)

```swift
/// The classifier's raw output for one glyph cell: the exported 8 sigmoids.
/// Order a,b,c,d,e,f,g,dp - the `PumpSegments.mlpackage` contract (REPORT.md -> Export).
public struct PumpCellProbabilities: Sendable, Equatable {
    public let segments: [Float]        // count == 7, validated at init
    public let decimalPoint: Float      // a HINT, never a constraint, until PU.17 lands (AUC 0.520)
}

/// One digit hypothesis for one cell, scored by PU.16's constrained decode.
public struct PumpGlyphCandidate: Sendable, Equatable {
    public let digit: Int               // 0...9; blank is the slicer's call, never a decode output
    public let logPosterior: Double
}

/// Everything the law knows about one cell.
public struct PumpCellReading: Sendable, Equatable {
    public let probabilities: PumpCellProbabilities   // raw provenance (layer c)
    public let ranked: [PumpGlyphCandidate]           // all ten, best first (layer b)
    public var top: PumpGlyphCandidate { ranked[0] }
    public var margin: Double { ranked[0].logPosterior - ranked[1].logPosterior }
}

/// A window's cells. The digit COUNT is a slicer fact, not a hypothesis - it is the
/// external scale pin the cloud model never had (PU.11 F13).
public struct PumpWindowReading: Sendable, Equatable {
    public let cells: [PumpCellReading]
    public var digitCount: Int { cells.count }
}

/// Why a field holds the value it holds. Rides into FuelExtraction provenance and
/// decides the Confirm screen's treatment (section 4).
public enum PumpFieldProvenance: Sendable, Equatable {
    case read                            // unique arithmetic close over the candidate grid
    case repaired(PumpGlyphSubstitution) // exactly one single-cell substitution closed it
    case derived                         // computed from the other two fields (NEVER cross-check evidence)
}

public struct PumpGlyphSubstitution: Sendable, Equatable {
    public let field: ManualFillUpMath.Field
    public let cellIndex: Int
    public let fromDigit: Int
    public let toDigit: Int
}

public struct PumpFieldReading: Sendable, Equatable {
    public let value: Decimal?           // nil IS the abstention (hard rule 13)
    public let provenance: PumpFieldProvenance?
    public let logPosterior: Double      // joint over the winning string's cells; 0 for .derived
}

/// The reader's whole answer for one photo.
public struct PumpDisplayReading: Sendable, Equatable {
    public let liters: PumpFieldReading
    public let unitPrice: PumpFieldReading
    public let total: PumpFieldReading
    public let rowAssignment: PumpRowAssignment?   // section 3; nil when no assignment survived
}

/// The one function PU.5 builds. Pure: windows + currency in, reading out.
public enum PumpReadingLaw {
    public static func resolve(
        windows: [PumpLocatedWindow],          // section 3's output: geometry + cells
        currency: CurrencyCode?,
        beamWidth: Int = 3                     // top-k per cell entering the grid; 3 covers 99 %+ of mass
    ) -> PumpDisplayReading
}
```

`PumpLocatedWindow` carries the window's quad (or its cluster/row identity), its assigned field
role, and its `PumpWindowReading`. The currency comes from the device/car context exactly as today
(`FuelExtractor` detects it from OCR lines; a pump display prints no currency, so the rules arm's
detection and the car's home currency are the inputs - the law never guesses one).

### The abstain rule per glyph

**There is no per-glyph abstain, and that is deliberate.** A hard per-cell threshold is the F11 trap:
today's margins do not rank errors (flat coverage curve), so any per-cell cut either abstains
everywhere or nowhere. Instead:

1. **Every cell emits candidates, never a refusal.** The beam takes the top `min(3, k)` digits plus
   any digit whose segment pattern is within Hamming distance 1 of the top pattern (the physical
   single-segment-failure neighbourhood - this is what makes the repair channel complete without
   enumerating all ten everywhere).
2. **Abstention is a property of the FIELD, produced by the uniqueness law** (section 2): the field
   commits only when exactly one (string, placement) triple closes. A cell the model is unsure
   about contributes two strong candidates; two candidates that both close make the solution
   non-unique; non-unique is nil. Uncertainty becomes abstention through arithmetic, not through a
   threshold nobody can calibrate yet.
3. **The margin is recorded and reported, not gated on.** When PU.20 delivers a signal that ranks
   (TTA spread, a softmax head, temperature), the commit rule gains one conjunct - "every cell of
   the winning string clears tau" - and tau is set from the measured precision-coverage frontier.
   Until then tau is absent, and the law's uniqueness is the only committer. This is the honest
   reading of F11: **no abstention policy on the current outputs can reach 0.99 by itself**; the
   domain priors of section 2 are what substitute for calibration.
4. **A window the slicer marks unreadable (no cells, or a count the convention rejects - section 3)
   abstains the whole field.** PU.11 F4c's rule stands: the 23 unreadable annotated windows count
   as forced abstentions in coverage, never as skips.

### Interaction with DigitRepair (P2.13)

The fixed table does not get deleted; it gets **demoted to one ordering provider of two**. Extract
the uniqueness law - "substitute single digits; accept only when exactly one substitution
reproduces the total; two or more is nil" - into the shared seam, and inject the substitution
source:

```swift
public protocol PumpSubstitutionOrdering: Sendable {
    /// Candidate substitutions for one cell of one field, best first.
    func substitutions(for cell: ..., field: ...) -> [PumpGlyphSubstitution]
}
// Rules arm (Vision OCR text, no posteriors): the fixed confusable table, as shipped.
// Reader arm: the cell's own ranked candidates within segment-Hamming <= 2, by posterior.
```

`DigitRepair.apply` (`DigitRepair.swift:81-111`) keeps its signature and its law for the rules arm;
the reader arm runs the same law with posterior ordering. This is the sibling-fix discipline in the
fence: one law, two orderings, never a fork where one arm gets the uniqueness check and the other
does not. Two properties must survive in both: the repair is pump-source only, and a repaired
commit keeps `crossCheck` a `mismatch` carrying the read residual (`FuelExtractor.swift:123-138`) -
the Confirm sheet never locks a repaired triple.

### Interaction with the cross-check

`ExtractionCrossCheck.evaluate` runs on the committed triple exactly as today, and one structural
fact must be written down because it changes what the lock MEANS for this arm: **every `.read`
commit closes by construction** (closure is the commit law), so the cross-check will report `.lock`
on all of them. That is honest - the arithmetic genuinely agrees - but it means the lock no longer
carries independent evidence for reader commits, and the dimming gate
(`ConfirmConfidenceGate.confidence`, `ConfirmPrefill.swift:56-66`) shows reader-committed fields at
full opacity. Two rules keep that from becoming a lie:

- **`.derived` is never cross-check evidence.** A derived price (p = t/v) "locks" circularly. The
  dimming gate gains a provenance clause: a `.derived` field renders `.unconfirmed` (dimmed,
  editable) whatever the cross-check says. This is a new call site in `ConfirmPrefill.swift` and the
  app's Confirm sheet, and it is the one UI change PU.5 owns.
- **`.repaired` keeps the mismatch** (existing law, unchanged).

---

## 2. Decimal recovery

### 2.1 What the corpus displays (measured from `windows.json` strings, 114 fixtures)

The display conventions are near-deterministic per field and currency, and they are the strongest
prior the reader has. Measured over all legible transaction windows:

| field | EUR (EE faces) | RUB (RU faces) | KZT (KZ faces) |
|---|---|---|---|
| liters | **2 decimals, 80/80** | **2 decimals, 31/31** | **2 decimals, 3/3** |
| unitPrice | **3 decimals, 56/56** (+7 windows shown WITHOUT any separator: "1789") | 2 decimals x28, 1 decimal x3 | 1 decimal x1 ("245.0"), 0 decimals x2 ("243", "244") |
| total | **2 decimals, 75/75** | **2 decimals x11, 1 decimal x20** (the Wayne/Tokheim/Scheidt truncated faces: "3765,7", "02049.0") | 0 decimals x2 ("3008", "10980"), 2 decimals x1 ("20886.25") |
| board cells | 3 decimals, 102/102 | 2 decimals, 11/11 | - |

Zero-padding: 42-43 of the 75-80 Gilbarco EUR total/liters windows are zero-padded ("02038,00",
"00040,00"); padded zeros are visible ink (PU.11 F6's measurement), so **a padded zero is a cell
and the digit count includes it**. Digit-count signatures worth wiring as slicer cross-checks: the
EUR unitPrice window is **exactly 4 digits in 63/63** fixtures; EUR liters is 3, 4 or 6 (padded);
EUR total is 3-6 (padded to 6 on Gilbarco).

This calibration is aggregate-statistics-only over the held-out annotation (no per-fixture label is
used at inference), which is the regime the product owner already signed off as "decision 3" for
PU.17/PU.18. The convention table should ride the `FuelPriceBandPack` seed-and-update mechanism
(`FuelPriceBands.seed.json`), not become a new hardcoded constant - `docs/PRACTICES.md`'s
constants-placement policy wants that choice named; question Q4 below.

### 2.2 The candidate set and the search

For a field whose cells decoded to digit string `d` (padding included), `place(d,k) = value(d)/10^k`:

```
liters:    { place(d,2) }                            ∩ [2, 150]        (PumpExtractor.volumeRange)
unitPrice: { place(d,k) : k ∈ conv[currency].price }  ∩ band[currency]  (currencyBand's union band:
                                                      EUR [0.4,3.0], RUB [15,500], KZT [50,1000])
total:     { place(d,k) : k ∈ conv[currency].total },  t > 0
           conv: EUR price {3}, total {2}; RUB price {1,2}, total {1,2}; KZT price {0,1}, total {0,2}
           unknown currency -> k ∈ {0,1,2,3} for all three (today's PumpNumber behaviour)
```

A visible dp (if PU.17 ever makes the bit live) collapses a field to the single shown placement;
until then the dp probability is a ranking hint inside ties, never a filter. Acceptance tiers, in
strict order:

- **T1 exact.** `round(v x p, 2) == t` - `DigitRepair.reproduces`'s rule, the only tolerance that
  pins a value (`PumpExtractor.swift:340-353`'s ground 1, unchanged).
- **T2 display rounding, shape-conditional.** `|v x p - t| <= 0.005 x p + 0.5 x 10^-k(t)`, accepted
  **only when t's placement is rounding-explained**: `k(t) < 2` (a 0- or 1-decimal total: the KZT
  whole-tenge truncation "3008" = 3008.34 truncated, the RU 1-decimal faces "3765,7") or `t` is
  integral (a preset stop). The physics: the volume display rounds to 2 decimals (half-step
  0.005 L -> 0.005 x p in money) and the total display rounds/truncates at its own last digit
  (half-ULP). A 2-decimal non-integral total gets NO tier - it must close exactly. That condition
  is load-bearing: measured, unconditional T2 triples the wrong-commit rate under mutation
  (section 2.5), and it is what keeps pump-060's `48.75 -> 48.95` class out (residual 0.38 vs tier
  0.0145).

**The commit law.** Enumerate the grid (at most 2 x 2 x 2 = 8 triples under the conventions; the
beam of section 1 multiplies this by the per-cell alternatives - the whole search is dozens of
Decimal multiplies, trivially on-device). Then:

1. Exactly one triple passes T1 ∪ T2 -> commit all three fields, provenance `.read`.
2. Zero pass -> run the repair channel: single-cell substitutions across the three fields,
   posterior-ordered (section 1), each substitution re-run through the grid; **exactly one**
   substituted triple closes -> commit with provenance `.repaired`; zero or two-plus -> all three
   fields nil.
3. Two or more pass -> all three fields nil. **Never max-posterior among closing solutions.**
   "Not unique -> nil, never a guess" is the design law (`docs/EXTRACTION.md` point 4) and the
   measurement backs it: every ambiguity the corpus can produce is a 10x-scale family (section 2.4)
   where the posterior difference between the two solutions is one cell's margin - exactly the
   signal F11 proved untrustworthy.

**What "not unique -> nil" costs, measured: nothing on this corpus.** Zero of 114 fixtures are
ambiguous under the conventions (2.4). The uniqueness rule is free here BECAUSE the conventions are
strong; if a future face (a 3-decimal RUB total, say) opens a family, the cost appears as coverage,
and the ratchet of section 4 shows it per field.

### 2.3 The four named fixtures, worked

**pump-009 (Gilbarco zero-padded RU; the cloud arm's decimal-shift victim).** Display:
total "02038,00", liters "00040,00", price "050,95", plus four board cells. Dp dropped:
`dT="0203800"`, `dV="0004000"`, `dP="05095"`. Candidates: V = {40.00} (k=2 only; 400.0 would need
k=1, not in the liters convention, and 400 ∉ [2,150] anyway); P = {509.5, 50.95} ∩ RUB band =
{50.95}; T = {20380.0, 2038.00} (RUB k∈{1,2}). Closes: 40.00 x 50.95 = 2038.00 -> T1 exact on
2038.00; 20380.0 has no partner. **Unique, all three commit, and the cloud's `400.0 / 50.95 /
20380.0` shift is impossible by construction twice over** - it needs k=1 on the volume (convention
forbids) and a 400 L fill (range forbids). This is F13's "the factor-of-ten class dies at the
architecture" made concrete: the cell count fixes the digit string, the convention fixes the scale,
and the arithmetic audits the result.

**pump-003 (KZ, KZT; the brief's "12 valid solutions").** Display "20886.25" / "85.25" / "245.0";
dp dropped: `dT="2088625"`, `dV="8525"`, `dP="2450"`. The solution count is entirely a function of
the candidate rule, measured three ways: **free placement** (every k on every field): 24 exact
triples - the scale-invariant family (v/10, p x10, t) and its iterates, since the cross-check is
blind to a common scale; **today's parser rules** (`PumpNumber`: operand k<=3, total money-shaped
k∈{0,2}, plus band and range): 6 exact triples; **the conventions above** (liters k=2, KZT price
k∈{0,1} ∩ [50,1000] -> {245.0} alone, KZT total k∈{0,2}): **1 - unique, commits 85.25 / 245.0 /
20886.25**. I could not reproduce "12" under any of these definitions (nor under the loose
cross-check tolerance, which adds nothing at these magnitudes); Q10 asks which rule produced it,
because PU.5's row text must pin the rule - the same fixture abstains or commits depending on it.

**pump-031 (Circle K discount; "does not multiply out by design").** Display "0032,58" / "0016,80" /
"1,939"; 16.80 x 1.939 = 32.5752 -> T1 rounds to 32.58 -> the display triple closes EXACTLY and
commits. The problem is the scorer, not the arithmetic: `expected.csv` asserts the receipt's
discounted 32.50, and PU.2 already declared this ("a pump reader is right to read 32.58 - the CSV
scores the wrong artefact for that cell"). A display reader that is right is counted
confident-wrong forever unless the PO rules (Q1). Note the same shape on the truncated-total pairs:
the reader commits what the display shows ("3765,7" -> 3765.7) where the CSV holds the paper's
exact product (3765.65) on pump-065/073 but the truncated value on pump-083/106/110 (1437.2 ==
CSV 1437.20). **Three of the 320 cells are unwinnable for any honest display reader; the 0.99
precision threshold has room for exactly two wrong cells at 281-313 committed - the ruling is
gate-decisive, not cosmetic** (section 4.3).

**pump-051 (Wayne four-price board, none matches).** Windows: total "30.42", liters "15.61", four
board cells 1.884 / 1.944 / 1.919 / 2.019, no unitPrice window; `expected.csv` asserts liters and
total, price blank. Under the conventions: V = {15.61} (k=2; 156.1 ∉ range), T = {30.42} (EUR
k=2). Board prices as price candidates: 15.61 x 1.884 = 29.41, x 1.944 = 30.35, x 1.919 = 29.96,
x 2.019 = 31.52 - **none closes even at T2** (tier ~0.0145 vs residuals >= 0.07), so the board
contributes nothing and price stays nil - never the "closest" board cell (pump-035's off-board
1.819-for-1.824 lesson is the reason that rule exists). Liters and total commit via the pair rule
below; the derived price 30.42/15.61 = 1.949 is offerable as `.derived` (dimmed, never
cross-checked) if the PO accepts derivations (Q3) - `expected.csv` leaves the cell blank, so it
neither scores nor penalises.

### 2.4 Ablation: which priors are load-bearing (oracle digits, 95 legible three-window fixtures)

| candidate rule | unique | ambiguous | no-close | committed cells wrong |
|---|---|---|---|---|
| **full law** (conventions + band + range + shape-conditional T2) | **94** | **0** | 1 (pump-054) | 3 (all declared artefacts) |
| drop the liters 2-decimal convention (k∈0..3) | 77 | **17** | 1 | 2 |
| drop the price band | 80 | **14** | 1 | 3 |
| drop the money-shape total rule (k∈0..3) | 94 | 0 | 1 | 3 |
| today's `PumpNumber` rules, no conventions (money k∈{0,2}, operand k<=3, band+range) | 92 | 0 | 3 | **commits a WRONG triple on pump-108** |

Readings: (i) the volume convention and the band each independently hold ~15 fixtures away from
ambiguity - the 17 that open without the liters convention are the RUB 1-decimal-total faces, where
shrinking v by 10x (k=3) drags t (k=2) into a second close ("003249"+"022191": both
(32.49, 68.30, 2219.1) and (3.249, 68.30, 221.91) pass); (ii) the money-shape total rule is
redundant WHEN the conventions hold but is the only thing standing between today's parser shape and
pump-108's 10x-shrunk confident-wrong - keep both, defence in depth against faces the corpus has
not seen; (iii) pump-054 is a real class, not a rule failure: the dispenser's own rounding
(26.94 x 1.919 = 51.698 displays as 51.71, a 0.012 residual on a 2-decimal non-integral total).
The law abstains its 3 cells. A "metering residual" tier (±1-2 cents on 2-decimal totals) would
recover it but re-opens the pump-060 misread class; my recommendation is abstain and let the user
type one field (Q5).

### 2.5 Fragility under misreads (what the law does when the digits are wrong)

Protocol: take each fixture's three annotated strings; substitute one digit (all positions x all
nine alternatives; 13,230 mutations); run the law; then run the repair channel on whatever did not
close; classify against `expected.csv` at the scorer's 0.005 tolerance. A second scan samples
40,000 two-digit mutations (seed 7). Oracle on all non-mutated digits - this isolates the LAW's
behaviour, not the model's error rate.

| law variant | single mutations: commit / of which wrong / repaired-to-truth / abstain | double mutations: commit rate / wrong share of commits |
|---|---|---|
| T1 exact only, no derive | 10,902 / **164 (1.5 %)** / 10,737 (78.5 %) repaired-correct / 2,328 | 1.5 % / **7.1 %** |
| + shape-conditional T2 | 11,814 / 479 (4.1 %) / 11,328 / 1,416 | 2.0 % / 21.2 % |
| + unconditional T2 | ~12,400 / 902 (7.3 %) | - |
| + derive-price branch (no price window) | 11,854-12,481 / **1,010-1,211 (8.5-9.7 %)** | - |

Four conclusions that shape the design:

1. **The repair channel is the coverage engine.** ~80 % of single-digit misreads are recovered to
   the truth by posterior-ordered substitution under the uniqueness law. This is why per-cell
   accuracy of 0.67-0.70 does not translate into per-window accuracy of 0.32 at the field level -
   a window with exactly one bad cell mostly still commits, correctly.
2. **Two-plus misread cells in one fixture mostly abstain** (1.5-2 % commit rate) - but the commits
   that do happen are wrong 7-21 % of the time. At today's accuracy the double-error regime is
   where most fixtures live (P(all 13 cells right) is small; empirically 0.321 of count-correct
   windows are fully right, and errors cluster by photo quality). Precision therefore depends on
   error CONCENTRATION - dirty photos abstain wholesale, clean photos commit - which is plausible
   but unproven until PU.22 scores real reads. The gate's job is to refuse to ship until that is
   measured, and section 4's confident-wrong clause is how.
3. **The derive branch (price missing -> p = t/v) is unverifiable by construction**: any misread
   volume stays in range and produces a band-consistent implied price (pump-021: 809->819 commits
   8.19 L and a "price" of 1.832, both wrong, nothing catches it). It buys ~29 cells of coverage
   ceiling (284 -> 313) and costs the worst wrong-rate of any branch. Recommendation: v1 ships
   WITHOUT derive commits (pair-only fixtures commit liters+total only when the pair is
   convention-pinned AND the implied price is in band - the values commit, the price stays nil);
   derived-price commits wait for PU.20's calibrated signal. Q3 to the PO.
4. **Shape-conditional T2 is a real but bounded trade**: it recovers the KZT-whole, RU-truncated
   and preset classes (~11 fixtures, ~30 cells) at roughly 2.6x the exact tier's wrong-commit rate
   under single mutation, concentrated in the fixtures whose totals carry the tier (a ±1 tenge
   total misread on pump-004 closes at "3007"; a ±2 price misread on the preset pump-010 closes at
   75.93 because the true 75.95 does not close exactly - **on a preset fill the exact tier prefers
   a misread price over the truth**; only T2 admits the truth there). Ship T2 shape-conditional as
   specified, never unconditional; Q5 asks the PO to accept the residual exposure or cut the tier.

### 2.6 Coverage arithmetic for the gate

Asserted numeric cells: **320 = 114 liters + 98 unitPrice + 108 total** (measured from
`expected.csv`; blank cells unscored, matching `CorpusPumpScorer.numericCells`). Oracle-digit
ceiling of this law: **281/320 (0.878) without derive, 313/320 (0.978) with**; the 39-cell gap
without derive is: 23 pair-only cells (12 fixtures with no legible price window), 4 idle-pump
cells (correct abstentions by law - B1's whole point), ~6 cells on the 5 fixtures with unreadable
windows (pump-012/014/041/052/053/067 glare), 3 cells on pump-054, and the KZT/preset abstentions
already counted. Real coverage on real reads = ceiling x P(window legible AND count-correct AND
cells right-or-repairable) - with PU.16/PU.8 numbers that is plausibly **0.15-0.35 today**, below
the 0.60 floor. Say this out loud in PU.6's terms: **the law can clear the gate; the pixels
cannot yet.** PU.17-PU.20 (dp, cell shape, Live Photo fusion, calibrated abstention) and the
locator (Q7) are the rows that move the real number; nothing in the decode design blocks them.

---

## 3. Row assignment

### Measured layout facts (from `windows.json` quads)

- **Vertical order total < liters < price holds on 93 of the 95 fixtures** that have all three
  transaction windows. The two exceptions are orientation artefacts, not layout ones: pump-019 is
  `rotationCW: 90` (y-order computed before rotation is meaningless) and pump-008 is the Topaz
  video-overlay face whose three values sit at y 0.53/0.53/0.54 (one overlaid block). Five
  fixtures carry a `rotationCW` annotation (one at 90, pump-069).
- **Board cells are geometrically distinct**: they cluster in their own column beside the
  transaction stack (pump-009: board x 0.13-0.21 vs transaction x 0.30-0.63) or in a bottom row of
  3-4 evenly spaced cells below it (pump-072: board y ~0.53 vs transaction y 0.265/0.368), and
  they are physically smaller - median window height **0.045 of the image vs 0.065** for the
  transaction price window (113 board vs 97 price windows). 38 fixtures carry 1-4 board cells.
- **Digit-count signatures** (2.1) are per-field: EUR price is exactly 4 digits in 63/63; that is a
  free audit of both assignment and slicing (a 3- or 5-cell EUR price window is a mis-slice or a
  misassignment, not a price).

### The assignment rule (proposed)

1. **Orientation first.** `rotationCW ∈ {0,90,180,270}` from Vision's text orientation on the
   face's label text (every corpus face carries Russian/Latin labels - `ЛИТРЫ`/`SUMMA`/`HIND/1L`;
   the reader is segment-only but the labels are free orientation evidence Vision already reads)
   with an aspect-ratio fallback for label-less crops. `windows.json`'s own annotation keys
   rotationCW, so the harness scores this exactly.
2. **Cluster.** Windows whose x-extents overlap form a column; the transaction stack is the column
   containing the largest cells; a side column or a bottom row of 3-4 equal small cells is a board.
   Board cells are price CANDIDATES (2.3's pump-051 rule: admitted only on a unique close, never
   nearest), never the transaction price by position.
3. **Order.** Within the transaction column, top-to-bottom = total, liters, unitPrice (93/95;
   label text, when Vision reads one - `СУММА`/`ЛИТРЫ`/`ЦЕНА` - outranks position, reusing
   `PumpExtractor.role(of:)`'s vocabulary as a hint source, never as a requirement).
4. **Audit by arithmetic, but never re-assign by arithmetic.** The layout assignment is a
   hypothesis; the section-2 unique close is the confirmation. **If the layout-assigned triple does
   not close but a PERMUTATION of it does, commit nothing.** A permutation that closes is precisely
   the cloud arm's confident-swap failure mode (a x b == b x a; five swaps in P4.12), and the
   volume-range/money-shape asymmetries already make a genuine swap close only when the numbers
   conspire - which is the definition of "the document does not determine the answer". Record the
   disagreement in the diagnostics dump (shape only - counts and codes, never values, hard rule 12).

### The three hard cases

- **Idle pump (pump-016/017, "0.00 / 0.00", board visible).** Every shown digit zero in both
  transaction rows -> the all-zero guard fires BEFORE the law (measured into the ceiling: they
  contribute 4 asserted cells the reader must NOT hit). Committing 0.00 is the confident-wrong that
  made B1 delete recall from the gate ("recall actively rewarded logging a zero-litre fill",
  `PumpPhotoGate.swift:20-22`); `FuelExtractor`'s zero guards (`liters == 0 -> nil`, `total == 0 ->
  nil`) already encode it for the rules arm - the reader's law must carry the same guard, and PU.5's
  check column already says "the two idle pumps commit nothing". Board prices on an idle pump are
  context only; there is no fill to price.
- **Preset-amount fill (pump-010: total round "1000.00", volume derived by the pump; also 020/042/
  056/069/076/078).** Most presets close T1 anyway (the pump's own arithmetic rounds: 29.14 x
  2.059 -> 60.00 exact; 77.56 x 1.934 -> 150.00 exact). The residual class is pump-010, where the
  displayed volume is itself rounded against the preset stop (13.17 shown, 13.1666 true, product
  1000.26 vs displayed 1000.00): T1 fails on the TRUTH and passes on some misreads (2.5, point 4).
  T2's integral-total branch admits the truth (residual 0.26 <= 0.005 x 75.95 + 0.005 = 0.385) and
  the commit is unique. Rule: an integral displayed total enables T2 for that fixture; the field
  rides the ordinary `.read` provenance (nothing UI-visible distinguishes a preset fill - it closed
  uniquely, that is the whole contract).
- **Four-price board, none matches (pump-051; siblings 021/022/023/033/034/035/055/061/104).**
  2.3's worked answer: price nil, liters+total commit on their own conventions when the implied
  price t/v lands in band (it does on all twelve: they are real fills), board cells never adopted.
  The implied-price check is a PLAUSIBILITY gate on committing v and t, not a derivation of p -
  p stays nil unless Q3 says otherwise.

---

## 4. `PumpPhotoGate` semantics for a reader that abstains per glyph

### 4.1 "Committed" - the definition

> A numeric cell is **committed** when the reader emitted a non-nil value for it through the commit
> law - a T1/T2-unique close (`.read`), a unique-substitution repair (`.repaired`), or a PO-approved
> derivation (`.derived`) - and the value is compared against `expected.csv` at the existing 0.005
> tolerance (`CorpusABScorer.tolerance`). Blank CSV cells stay unscored. An abstention - correct or
> not - is non-coverage, never a miss. Idle pumps and all-zero reads commit nothing by law. Every
> reader score names its **window source**: `oracle` (windows.json quads) or `live` (locator
> output); the two are never averaged into one number.

This is B1's definition extended, not replaced: `CorpusPumpScorer.scorePump` already computes
committed / committedCorrect / coverage exactly this way for the rules arm; the reader arm plugs
into the same scorer through the same `ExtractionRecord` shape (that is what the spike harness's
`--reader pump` column emits).

### 4.2 Is precision-on-committed + coverage-floor still the right pair?

**Yes - B1's reasoning survives the new reader intact** (recall still inverts hard rule 13; a
correct nil still must not score as a miss). But the pair needs four additions, and one of them is
a new clause the brief asks about:

1. **Per-field breakdown, reported; floor unchanged pending Q2.** The single 0.60 floor over 320
   hides a structural asymmetry: the price column's ceiling is 98 cells of which 12 fixtures
   (23 cells) have no legible price window at all, so per-field price coverage can never reach
   liters coverage. Report all three (liters/price/total against 114/98/108); keep the gate on the
   aggregate until the PO rules whether the floor is per photo or per field (Q2).
2. **The no-confident-wrong-on-named-fixtures clause, extended and enumerated.** PU.5's check
   already demands zero confident-wrong on pump-004/009/013/015. Extend to: zero confident-wrong
   ANYWHERE except an explicit, test-enumerated artefact list (today: pump-031 total, pump-065
   total, pump-073 total - Q1's ruling may empty or grow it). Enumerating beats averaging: at
   281-313 committed cells the 0.99 threshold tolerates 2-3 wrong cells, so the three artefacts
   alone consume the ENTIRE error budget - 310/313 = 0.9904 passes with zero slack, and one more
   wrong cell anywhere, a real defect, fails the gate while looking like "just another artefact"
   if the list is not enumerated. The clause turns a silent budget consumption into a named list
   the PO owns.
3. **A per-field abstention rate, reported not gated.** The reader's abstentions are structured
   (unique-close failures, repair failures, unreadable windows, idle guards, count-convention
   rejections); the score should say WHICH fired per fixture, because PU.6's ship decision is
   "the measured gap, by failure mode and by make". Gating on abstention rates before PU.20 delivers
   a calibrated signal would just gate on the slicer's count agreement twice.
4. **`.derived` never counts as cross-checked** on the Confirm screen (section 1) even though it
   counts as committed for the gate. The gate measures values; the dimming gate measures evidence.
   Different questions, different answers, both written down.

### 4.3 The gate arithmetic with real numbers

At the oracle ceiling: precision **278/281 = 0.9893 (no derive) - below the 0.99 threshold** - or
**310/313 = 0.9904 (with derive) - above it by one cell's worth of slack**. Both figures are
dominated by the three artefact cells: with Q1 ruled (CSV corrected to the display artefact or the
cells excluded), the law's oracle precision is **1.000**. This is the single sharpest finding of
this review: **the ship gate's precision half is decided by a corpus-bookkeeping ruling, not by
engineering.** The coverage half fails today for the honest reason (pixels, section 2.6), and no
gate change should paper over that - the floor stays 0.60, the mode stays off, PU.6 writes the gap.

### 4.4 Extending the ratchet so the reader lands on the same ratchet as the rules parser

Today: `high-water.json` holds `pump: {hits: 53, total: 320}`; `AccuracyRatchetTests` scores the
rules arm live (Vision OCR -> `FuelExtractor(.pump)`), ratchets hits-not-fall / total-not-shrink,
and `pumpModeShipsOffWhileTheCorpusIsBelowTheGate` binds `PumpPhotoGate`'s four constants to the
live score (`AccuracyRatchetTests.swift:231-249`). Proposal, in the same shapes:

- **`high-water.json` gains a `pumpReader` class**: `{hits, total, committed, committedCorrect,
  windowSource}` - the B1 quantities, not just recall, so the ratchet guards precision-relevant
  numbers too (hits-not-fall AND committedCorrect-not-fall AND committed-not-fall; a reader that
  "improves" by abstaining less and being wrong more must trip a wire). The existing `pump` row
  STAYS: it guards a different engine (rules-on-Vision), and deleting it would hide a rules
  regression behind reader gains - the arms are scored separately or not honestly at all.
- **The gate constants are cut from the shipping arm.** `PumpPhotoGate.measured*` becomes "the arm
  the app runs when the flag is on": while the reader is not wired, that is the rules arm and the
  constants stay 53/56/53/320; when PU.25 wires the reader behind the flag, the constants are
  re-cut from the reader's LIVE-window score (never oracle - an oracle score cannot back a ship
  claim, and the locator's 0.008 IoU means a live score today is ~0, which is the truth). The
  existing test's law is unchanged: constants must equal the live score of the shipping arm, and
  the flag must be off while either half fails.
- **Runtime pinning differs per arm, and the reader arm gets a determinism test instead of a
  runtime restriction.** The rules arm is Vision-measured (`.visionMeasuredRuntimeOnly`, macOS 26
  marks - RV.294/RV.295: macOS 27's Vision reads pump at 13 vs 53). The reader arm is Core ML: no
  Vision, but FLOAT16 outputs (`REPORT.md` -> Export) on heterogeneous Neural Engine/GPU/CPU
  backends are a drift risk of their own. Bind it with a golden vector: one committed strip PNG +
  its expected 8-probability vector within 1e-3, plus the PU.16 decode rule asserted on the
  committed probabilities (mirrors `test_export_roundtrip`; the F5 strip-height ruling - ONE
  contract height, 96 where the slicer demonstrably works - belongs in this test's preamble).
  Q9: re-export FLOAT32; posteriors that drive a 0.99 gate deserve the precision, and REPORT.md
  already flags the one-line change.
- **The per-cell ratchets PU.4/PU.8 set (count agreement 0.59, dp 0.0, locator 0.0) stay where
  they are** (`PumpReaderHarnessTests`); the reader-arm corpus score sits ABOVE them and inherits
  their regressions, which is the correct dependency direction.

---

## 5. Interaction with the cloud arm and manual entry

### Who wins when both return

The policy already exists and needs no new decision, only a new call site: `GatewaySuggestionPolicy`
(P6.3) - the cloud fills **only fields still blank and untouched**, never fights an on-device
result, never arrives after save, and a late answer lands in the inbox as a per-field suggestion
(RV.57/RV.38; J3's "the receipt catches up with you"). The reader is on-device, so:

- **Reader commits beat cloud, always** - they are `onDeviceResolved`, first claim by the policy's
  own text. No merge, no comparison, no UI for "two readers disagree": the cloud simply cannot
  touch a committed field.
- **Reader abstentions are blanks the cloud may fill** - and here is the seam that must not be
  missed: the cloud's pump readings carry the corpus's own failure classes (the pump-009 shift
  `400.0/50.95/20380.0`, five confident swaps, confident zeros on contract pricing,
  non-determinism). Today a fill-blanks prefill accepts them with only the scale-invariant
  cross-check as a net - which the shift passes by construction. **Proposal: the section-2 law
  becomes a VALIDATOR for every pump-source value regardless of producer.** One pure function
  (`PumpReadingLaw.validate(liters:unitPrice:total:currency:)` - conventions, range, band, tiered
  close, uniqueness), called from three call sites: the reader's commit, the rules arm's
  `PumpExtractor.solve` (its grounds 1/2 are already a subset of the law - fold, do not fork), and
  the gateway's pump prefill seam (the fill-up sibling of `ServiceGatewayReading`/
  `ExpensePrefillBuilder.reading(fromGateway:)` - name the seam: wherever a `GatewayExtraction`
  with kind `pump` becomes a form prefill). Measured effect on the committed P4.12 results: the
  pump-009 shift dies (400 ∉ [2,150]; 20380.0 has no closing partner), the swaps die (permutation
  closes are not adoptions, section 3), confident zeros die (t > 0 and the idle guard). The cloud's
  honest 31/46 keeps its value; its silent classes stop reaching the form. This is the fence's
  sibling rule applied: the law exists for the reader, and the gateway reads pumps through the same
  door or not at all.
- A cloud value that fails validation is **not shown as a rejected suggestion** - it is not shown.
  Nothing to decide, nothing to dismiss; the field stays blank and editable. (An inbox "yours vs
  the receipt" card for a value the law rejected would invite the user to adopt a factor-of-ten
  error; hard rule 7's next-step naming does not apply because there is no error surface - the
  absence of a prefill IS the honest state, exactly like the reader's abstention.)

### Hard rule 15 on the Confirm screen

The two doors stay peers with zero new UX machinery, and J4/ERRORS.md already carry the rows:

- The reader's output rides `PumpPhotoCapture.prefill(pumpPhotoEnabled:extraction:)` - flag off
  (today, and until the gate passes) means nil, which renders the **ordinary manual form with no
  message**: the feature is not offered, nothing is framed as a failure (`PumpPhotoGate.swift:127-143`).
- Flag on: the extraction pre-fills the same `ConfirmManual` sheet every other door lands in (J3b:
  "one screen, not a lesser one"). Committed fields show per section 4.2's dimming rules; abstained
  fields are **blank and focusable, never 0** (`ConfirmFormat.decimal(fromExtraction:)` passes nil
  through - the existing contract); a fully abstained photo degrades to `ConfirmEmptyScanCaption`'s
  "Couldn't read this one - type it, the photo stays attached" with Total focused - the caption
  fires only when `hasPhoto` and nothing resolved, and never on the typed path (the rule-15 clause
  is already in `ConfirmPrefill.swift:239-254`).
- Per-field abstention is therefore **already the sheet's native language** (dimmed / blank /
  caption are shipped states) - Q1 of the brief's example list ("is per-field abstention acceptable
  UX") has this answer from the code: it is not a new UX, it is the existing one, and the reader
  merely produces more of it. What the PO still rules on is the GATE consequence (Q2: floor per
  field or per photo) and the derive question (Q3), not the screen.
- The capture review step (RV.5) and the alpha disclosure (`ERRORS.md` -> Capture) are unchanged;
  the disclosure's pump number is stale (see "Found and not fixed") and PU.6 rewrites it from the
  new score either way.
- Monetization appears nowhere in this path (rule 7): the cloud arm's unavailability hint ("check
  these - enhanced reading unavailable right now") already exists and already carries "never an
  upsell here" (`ERRORS.md` -> Confirm).

---

## 6. Sequencing - splitting PU.5 into rows that each move one measurable number

PU.5 as filed bundles six deliverables (decoder port, law, row assignment, wiring, gate re-cut,
harness column) and one of them - "precision >= 0.99, coverage vs 0.60" - cannot be reached in one
row because it depends on rows that are not PU.5's (PU.17-PU.20, the locator). HANDOVER's guidance
("PU.5 should not start until per-glyph is above ~0.8 on clean windows") is right for the
END-TO-END claim and wrong for the law: the law is pure, oracle-scored, and every accuracy row
downstream needs its numbers to be measurable at all. Split, in dependency order (ids are
suggestions; PU.17-PU.20 are taken):

| # | Row | Depends on | The ONE number it moves | Oracle / mutation |
|---|---|---|---|---|
| 1 | **PU.21 - the law in Swift, scored on oracle strings.** Port PU.16's constrained decode (same rule, golden vectors from committed annotation strings), `PumpReadingLaw` (conventions table seeded into the band pack, T1/T2, uniqueness, posterior-ordered repair via the shared `DigitRepair` seam), all pure L1 types of section 1. Harness mode: windows.json strings in, `ExtractionRecord` out, scored by `CorpusScorer.scorePump` unchanged | nothing (start now) | **reader-arm gate-mirror score on oracle digits**: committed 281 (or 313 with Q3) / 320, precision 0.9893-0.9904, confident-wrong = exactly the 3 enumerated artefacts | mutation: swap the liters/total convention tables -> pump-108 flips to the 10x-shrunk triple, test red; delete T2's shape condition -> pump-060's 48.95 class closes, test red; delete the permutation ban -> a swapped triple commits, test red |
| 2 | **PU.22 - real cells through the law.** Classifier posteriors on committed `slices.json` cells (oracle windows), beam decode, the law, the F4c gate-mirror report PU.11 asked for (precision-coverage frontier printed, by-name confident-wrong list, `by_name` committed per F4d) | PU.21; inherits PU.17/18/20's accuracy as it lands | **reader-arm committed-correct cells on real reads** - starts near 20-80 of 320, that IS the measurement; every accuracy row downstream now moves a gate-unit number, not a per-glyph proxy | mutation: argmax-only decode (beam off) -> committed falls, red |
| 3 | **PU.23 - row assignment and boards.** Section 3's rules on windows.json quads (orientation from Vision labels, column clustering, y-order, digit-count audit, board classification); no locator dependency (oracle quads), scored per fixture | none (parallel with 1-2) | **row-assignment accuracy vs the field annotations**: starts at the layout prior's 93/95, ratcheted; board-vs-transaction classification accuracy reported beside it | mutation: drop the rotation step -> pump-019/069 misassign, red; treat the board cluster as the transaction column -> pump-009 assigns a board price, red |
| 4 | **PU.24 - the locator row** (file it; PU.11 F14 has no owner and PU.6 was told to file "from the measurement" - this review IS a measurement). Vision-as-proposer first (boxes, not strings; the reader's own likelihood disposes), user-tapped crop as the rule-15 peer pending Q7 | none | **locator median IoU 0.008 -> ratcheted**; the live-window score of PU.22 becomes computable, which is what the ship gate needs | mutation: existing PU.4 harness mutations still red; proposer off -> IoU collapses to the classical stub, red |
| 5 | **PU.25 - wiring and the gate re-cut.** `.pump` source decision in the capture path (today `CaptureFillUpScan` hardcodes `source: .receipt` - the reader running and finding windows IS the pump detection; one arm per capture, reader when it ran, rules-on-Vision when no display was found, selection logged shape-only, never a silent fallback), `PumpPhotoGate` constants re-cut from the shipping arm's LIVE score, `high-water.json` `pumpReader` class, `pumpModeShipsOff...` extended, spike harness `--reader pump` fourth column, FLOAT32 re-export (Q9) | PU.21-24 | **the gate constants match the live shipping-arm score** (the existing test's law, now over two arms); flag stays off until they clear | mutation: neuter `PumpPhotoGate.violation` -> the ship test red (the mutation P2.7 already proved); wire the reader WITHOUT the live/oracle distinction -> constants cannot match, red |
| 6 | **PU.26 - the law as the gateway's pump validator** (section 5; shippable as soon as PU.21 exists, independently of everything optical) | PU.21 | **cloud-arm pump score re-measured through the validator** on the committed `vision-ab` JSONs: 31/46 -> the post-law number, with pump-009's shift and the five swaps structurally excluded (re-scoring offline pays no API cost) | mutation: bypass the validator on the gateway seam -> a fixture JSON with the shift pre-fills 400.0, red |

PU.5 itself is then an umbrella: it closes when 21-23 and 25 land (the end-to-end reader on oracle
windows, wired, gated), and PU.6's ship decision reads PU.24's live numbers. Each row above is one
PR, one number, one named mutation - the unit of work the conventions demand - and rows 1, 3, 6 are
safe to dispatch IMMEDIATELY because nothing they do depends on the model getting better; rows 2's
number will look bad until PU.17-PU.20 land, which is exactly what makes it the right dashboard for
PU.6.

---

## What I would need to know or have (ranked)

1. **The artefact ruling, before anything computes a precision figure** (PU.2 declared all three,
   PU.6 was told to decide, PU.11 Q8 asked; now it is gate-decisive): for pump-031 (display 32.58
   vs CSV receipt 32.50), pump-065/073 (1-decimal truncated display vs CSV exact product) and the
   truncated-total family generally - does `expected.csv` score the DISPLAY or the PAPER? Options:
   correct the three CSV cells to the display artefact (my recommendation: a pump reader can only
   ever read displays, and the paired receipts exist as receipt fixtures already), or exclude the
   cells with a `notOnDisplay`-style key, or keep them and accept that oracle precision is 0.9893 -
   **below the 0.99 threshold by construction**, i.e. the flag can never turn on however good the
   reader gets. One sentence decides whether the gate is reachable.
2. **Is the 0.60 coverage floor per photo or per field?** Measured structure: 320 cells = 114
   liters + 98 price + 108 total; the price column has a hard ceiling of ~75-86 % (12 fixtures have
   no legible price window at all). A per-field floor of 0.60 is reachable for liters/total and
   borderline for price; an aggregate floor lets a strong liters column carry a weak price column.
   Both are defensible; the gate code differs.
3. **May a derived value ever be a committed value?** p = t/v when liters and total close uniquely
   (RV.282 does exactly this on receipts; pump-072's loyalty price 1.894 = 18.96/10.01 exactly).
   Measured cost: the derive branch is the largest confident-wrong source under mutation (8.5-9.7 %
   of its commits) because it has no arithmetic left to fail. My recommendation: v1 derives nothing
   on pumps (pair-only fixtures commit the pair, price stays nil; ~29 cells of coverage forgone);
   revisit when PU.20 delivers a signal that ranks. If the PO wants derivations, they must be
   `.derived`-provenanced, dimmed, and never cross-check evidence (section 1).
4. **Which countries' decimal conventions must v1 handle, and where does the table live?** The
   corpus pins EE/EUR (price 3 decimals, total 2), RU/RUB (price 2, total 1-2 - the 1-decimal
   truncated faces are 20 of 31 RUB fixtures), KZ/KZT (total 0-2, price 0-1). v1 shipping these
   three is a decision to write down; a fourth country (PLN? USD gallons with 3-decimal prices and
   2-decimal gallons?) changes the table, not the law. And per `docs/PRACTICES.md`'s
   constants-placement policy, name the placement: my proposal is the curated `FuelPriceBandPack`
   mechanism (seeded compiled, updatable without a release), since the conventions are exactly the
   same kind of fact as the bands and are keyed by the same currency.
5. **The two acceptance-tier rulings the measurements turned up** (both bounded, both real):
   (a) preset/integral totals need T2 or the truth does not close (pump-010: the exact tier prefers
   a misread price over the true one - measured); (b) pump-054's dispenser-rounding class (a
   2-decimal total 0.012 off the product) abstains under the proposed law - accept the abstention
   (my recommendation) or authorise a ±1-2 cent metering tier and re-open the pump-060 misread
   class?
6. **Is `board` in the ship gate?** (PU.12 Q1, still unanswered.) 130 board windows, 73 % of their
   cells wrong, a different display family (pylon signs, dot-matrix, distance shots). This review
   assumes boards are context/price-candidates only and the gate scores the three transaction
   fields - one sentence should make that official before PU.22 prints its first table.
7. **The locator ruling** (PU.11 Q6, still unanswered, and PU.24 needs it): is a two-tap
   user-framed crop an acceptable v1 locator peer path? It converts the 0.008-IoU stub from a ship
   blocker into a convenience metric and is itself a rule-15-shaped answer (the user's frame always
   works). If no, the Vision-proposer is the only row and its hit rate is unknown.
8. **Live Photo fusion order** (decision 2 / PU.19): fuse the raw 8-probability vectors across
   frames BEFORE decoding (median per segment - my recommendation; it keeps the soft information
   the beam and the repair ordering need) or decode per frame and vote? The `PumpCellProbabilities`
   contract should say which, because the second throws away the posteriors section 1 is built on.
9. **FLOAT32 re-export approval** - one line in `export.py` (`ct.TensorType(name="segments",
   dtype=np.float32)`), flagged by REPORT.md itself: posteriors driving a 0.99 gate should not ride
   float16, and the golden-vector test (4.4) wants a stable target.
10. **Which candidate rule produced "12 valid solutions" for pump-003?** Measured under three
    defensible rules: 24 (free placement), 6 (today's `PumpNumber` shapes + band + range), 1 (the
    conventions). Not 12 under any variant I could construct. The discrepancy matters only because
    PU.5's row text quotes the number - the row should quote the RULE instead, and this review's
    table (2.4) is the proposed one.

---

## Checks run (all read-only; no build gates - nothing compiled changed)

| measurement | input | result |
|---|---|---|
| display-convention table | windows.json strings x expected.csv currency | liters 2dp 114/114; EUR price 3dp 56/56 + 7 no-separator; RUB total 1dp x20 / 2dp x11; KZT total 0dp x2 / 2dp x1; boards EUR 3dp 102/102 |
| oracle-digits law, exact-cent only, PumpNumber-style candidates | windows.json digits | 92 unique / 0 ambiguous / 15 no-sol; **pump-108 commits a 10x-shrunk wrong triple** |
| oracle-digits law, conventions + shape-conditional T2 | same | 94 unique / 0 ambiguous / 1 no-close (pump-054) / 12 pair-only / 2 idle / 5 unreadable = 114 |
| gate-mirror at the ceiling | + expected.csv | no-derive: committed 281, correct 278, wrong 3 (artefacts); derive: 313 / 310 / 3; precision 0.9893 / 0.9904; coverage 0.878 / 0.978; denominators 114+98+108=320 |
| prior ablation | same | no-liters-convention: 17 ambiguous; no-band: 14 ambiguous; no-money-shape: unchanged (redundant under conventions) |
| single-digit fragility | 13,230 mutations | exact: 1.5 % of commits wrong, 78.5 % repaired-to-truth, 10.4 % abstain; +shape-T2: 4.1 % wrong; +derive: 8.5-9.7 % wrong; unconditional-T2 examples verified by hand (pump-001 total, pump-002 price) |
| double-digit fragility | 40,000 sampled (seed 7) | exact: 1.5 % of pairs commit, 7.1 % of those wrong; shape: 2.0 % / 21.2 % |
| layout statistics | windows.json quads | total<liters<price y-order 93/95 (exceptions: pump-008 overlay, pump-019 rotationCW 90); board height median 0.045 vs price-window 0.065; board columns/rows spatially separate |
| reproduction | - | all of the above from committed files with throwaway Python; rule definitions quoted in sections 2-3; no fixture image opened, no writes outside this file |

## Found and not fixed (this review writes no code)

| finding | owner |
|---|---|
| `docs/ERRORS.md:273` alpha-disclosure quotes "pump 21/84, receipts 88/175" - stale against `high-water.json` (53/320, 286/345); the disclosure copy will also need the reader's numbers | PU.6 ("docs rewritten from the new numbers") |
| `docs/JOURNEYS.md` J4 still promises "the spike's ~95 % gate applies before this ships" - the gate was re-scoped by B1 to precision 0.99 + coverage 0.60, and J4's own success metric "extraction accuracy >= 95 % on the confirm screen" has no test binding it to the gate's meaning (DEFECT-PATTERNS #3 shape) | PU.6's doc reconciliation; flag to the orchestrator now |
| `CorpusPumpScorer.swift` header comment says "178 numeric cells" while the scored denominator is 320 | comment drift, no row - fold into PU.21/PU.25's scorer touch |
| `NumberScanner.PumpNumber.moneyCandidates` (k∈{0,2}) commits a 10x-shrunk triple on a 1-decimal-total shape (measured on pump-010's neighbour pump-108 via the annotation digits). Not live today (the rules arm commits nothing on the new RU fixtures - `high-water.json` note 2026-09-18), but it is a sibling defect for every future consumer of that function | name the seam in PU.21: the law's convention table supersedes `moneyCandidates` for the reader arm; whether the rules arm adopts it is PU.25's merge decision |
| pump-054's dispenser-rounding class (2-decimal total, 0.012 residual, truth on display) has no acceptance tier in the proposed law - abstains 3 cells | Q5 to the PO; no row |
| the locator has no row past PU.4's partial (`PumpPanelLocator` median IoU 0.008; PU.11 F14; PU.6 was to file "from the measurement") | PU.24 proposed above |
| pair-only fixtures (12, ~23 cells) have no commit path without the derive ruling | Q3 to the PO; PU.21 implements whichever way it lands |
| `CaptureFillUpScan.swift:28` hardcodes `source: .receipt` - there is no pump-source decision anywhere in the app today, and the `.pump` path exists only in the corpus harness and the `-seedPumpCapture` dev door | PU.25 (named in its scope above) |
| J4's Fallbacks/station text is rich but the journey has NO status line and no scenario review; every PU row names J4, so J4's completion review fires when PU.6 closes - the orchestrator walks it (`REVIEW-SCENARIO`, standing instruction 2026-09-10) | orchestrator, at PU.6 |
