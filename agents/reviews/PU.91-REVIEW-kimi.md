# PU.91-REVIEW (kimi) - the row locator: is the problem stated right, and what should the next round do?

*Independent review, read-only. Evidence base: the ten ledgers in
`ml/pump-reader/runs/2026-09-30/ledgers/` diffed pairwise with `scripts/pump-live-diff.py`,
`ml/pump-reader/runs/2026-09-29/pu91-r2-live-diff.txt`,
`ml/pump-reader/runs/2026-09-30/seg-r2-disagreements.json`, `ml/pump-reader/REPORT.md` (round
protocol at line 2279, PU.91 round-2 entry at 2302, PU.73 at 2261), `agents/research/PU.90.md`,
and the pipeline code (`PumpDisplayCapture.classify`, `PumpReader`, `PumpReadingLaw`, `segnet`,
`segtrain`, `rowtrain`). All photo-level counts below were recomputed from the ledgers, not copied
from the round table.*

## 1. Verdict on the problem statement: partly right

The facts in the table reproduce from the ledgers, but the framing "is the bottleneck the locator,
the margin, the verifier, or the law" misses the component the evidence actually indicts: **the
row reader's sensitivity to where the digits sit in the warped strip**, interacting with a law
that (correctly) refuses whatever does not close. The locator is guilty of a different sin than
the one its gate measures. Detail:

**(a) The r1-vs-r2 difference is noise at the unit that matters.** Cells inside one photo are not
independent - the law couples them (`total = volume x price`), and the ledger diffs confirm it:
photos flip as whole triples, not single cells. Recomputed per photo (all three fields right vs
not):

| pair | photos gained | photos lost |
|---|---|---|
| r1 -> r2 | 4 (089, 104, 120, 170) | 4 (068, 095, 165, 201) |
| r1 -> r1-F | 4 (089, 120, 170, 175) | **0** |
| r2 -> r2-F | 3 (068, 165, 201) | **0** |
| r1-F -> D-F | 1 (104) | 3 (050, 120, 165) |
| r1-F -> B-F | 1 (104) | **9** (068, 095, 116, 165, 174, 186, 194, 198, 201) |

A 4:4 photo split (r2 vs r1) is a fair coin; the "+4 committed / +2 correct" scalar was never
evidence of anything, and the round-2 entry in REPORT.md:2302 already said so in words ("the two
models disagree on 14 stills, not 4 cells"). D vs r1 (1:3 with F held constant) is a lean, not a
result. Only B (1:9) and F (4:0 on r1, replicated 3:0 on r2 - 7:0 across two independent locators,
sign test p about 0.016) clear the noise floor. **So: differences of up to about +-5 cells between
locator re-trains are within noise on this heldout; differences of 10+ cells are real.** With ~8
discordant photos, a McNemar-style sign test needs roughly a 6:2 split for p < 0.1 - that is the
decision rule the next rounds should adopt in place of the scalar.

**(b) What C1/C2 will mean.** Two seeds of r1's exact data:

- If C1 and C2 differ by 0-2 committed cells with no whole-photo flips: the r1/r2 flips are
  data-driven, not seed luck, and the worry "dark data costs ordinary photos" is real - but then
  the mechanism still is not location (observation 3), it is which strip crops the reader happens
  to see.
- If C1 and C2 differ by ~4-8 cells with symmetric whole-photo flips resembling the r1/r2 diff:
  then **r2 is just r1 at another seed**, the entire "new data hurt ordinary photos" conclusion
  collapses, r2's dark gain (19/27 vs 15/27) was free, and every locator round scored on 68 photos
  has been re-measuring seed variance. This outcome is the one the diff shapes predict: r1->r2 is
  4:4 with no locate stage difference (observation 3), which is exactly what a seed pair should
  look like.

Either way, C1/C2 must be read as a **noise calibration**, never as candidates to pick the best
of - selecting the best seed on 68 photos is overfitting the gate.

**(c) The verifier/display decision is a real but secondary leak.** Two of r2's photo losses are
not reads at all: `pump-201` flipped to `notADisplay` (locate flip, 3 cells) and `pump-161` moved
between `notADisplay` and `nothingClosed` across models. The slow-verdict floors (`widestRow >=
0.18`, `>= 2 rows`, `PumpDisplayCapture.swift:53-55`) sit exactly where dark heads land
(`PU.90.md` §1.2: widestRow 0.086-0.160 on `video-050`). Worth fixing, but it explains 1-2 photos
per round, not the 4:4 churn.

**(d) The law is working as designed and should not be blamed or relaxed.** Every "law flip" in
the diffs is a field that was committed-right before and is refused after - which means the
*candidate strings changed* (the law is deterministic given its candidates,
`PumpReadingLaw.resolve`). A refusal of a previously-right read is a **read change**, located
upstream. The law's refusals are the symptom doing its job: B commits 2 new wrong cells
(`pump-035` 82.07, `pump-042` 11.39) where its coverage is best - precision moves the wrong way
exactly when the box metric improves.

**The corrected diagnosis:** the pipeline's fragile joint is *locator-box statistics -> strip
appearance -> CRNN read*. Observation 1 measured this directly on hand boxes: shifted down 8 % of
height costs 159 -> 123, shifted right 3 % of width costs 159 -> 135, 6 % narrower costs 159 ->
129. A median IoU of 0.86 means the typical located box differs from the hand quad by shifts of
exactly this magnitude, so every retrained locator re-rolls the dice on which photos' boxes land
inside the reader's tolerance band. Observation 3 (IoU within +-0.05, whole photos flip) is not a
paradox under this diagnosis - +-0.05 IoU *is* a few-percent shift, and a few-percent shift is
catastrophic per observation 1. Observation 1's other half - "overshooting costs nothing" - is
true only within the reader's training scale band: the reader's real training strips are warped
from hand quads at the standard margin (`rowtrain.py` loads `realglyphs` windows, which come from
annotated quads), so strips widened 3x at read time (A) or padded 3-5 % per side in the locator's
targets (B) are out-of-distribution, and the reads degrade into law refusals. That is why A hurts
as a primary read (126 -> 104..123 across the four settings) yet the *same* h0.3/v0.1 margins gain
13 cells as F's fallback: wide strips are a worse default but a genuinely independent second
opinion.

## 2. Ranked next experiments

Each with expected effect, measurement, cost, kill criterion. The app-path heldout score plus the
per-photo ledger diff remain the right criteria for shipping; what needs replacing is the
*locator-level* gate that decides what reaches a live run at all (recommendation 2).

### 1. Read C1/C2 as the noise floor, and switch model comparisons to photo-level McNemar

- **Effect:** stops the round loop from chasing seed variance; converts the r2 verdict
  ("refused") into either "r2 = r1 at another seed, ship whichever has the dark recall" or "the
  data delta is real, investigate which records". Either answer unblocks the queue.
- **Measurement:** C1 vs C2 ledger diff, counted at photo level like the table in §1(a). The
  diff tooling exists (`scripts/pump-live-diff.py`); the photo-level count is a 20-line script
  over the two ledgers.
- **Cost:** zero - C1/C2 are already training.
- **Kill:** not applicable; this is interpretation, not an arm.

### 2. Replace the locator gate with "read success on the locator's own boxes"

The rotated-IoU gate (median IoU, recall@0.7, false rows/photo) demonstrably does not predict the
app path (observation 4: D wins every locator number and loses 6 cells; B wins coverage and loses
25). The metric that predicts the app path by construction is the app path minus the stages that
are not the locator's: **run reader + law on each candidate model's located rows on the 68
heldout photos, with the display decision forced to "yes"** (feed located rows straight into
assignment and read, no `isPumpDisplay`), and count committed-correct per photo. Call it the
*located-commit score*. It isolates exactly the locator->read joint that §1 indicts, runs on
macOS in one `swift test` arm, and needs no simulator.

- **Validation before adoption (mandatory):** compute it for the four locators whose live scores
  are known (r1, r2, D, B - all with F off, so one more macOS run each for D and B). The known
  live order is r1 (126) > r2 (130, tie) >> D-ish >> B (much worse); the new metric must at
  minimum rank B last by a wide margin and must not rank D clearly above r1/r2. A metric that
  cannot reproduce the four known orderings is not a gate.
- **Effect:** every future locator round is screened on a number that moves *because* reads move,
  at zero simulator cost; the IoU gate demotes to a sanity floor (a model at 0.77 IoU like B
  should still be refused even if the located-commit score were flat - the floor guards the
  verifier's row geometry, which the located-commit score bypasses).
- **Cost:** one new test arm (`PumpReaderPipelineTests` already has the annotated arm to copy);
  ~4 minutes per candidate on macOS.
- **Kill:** the validation misranks the known four, or the score's round-to-round variance on the
  same model (C1/C2) is as large as the live path's - then the fragility is inside the reader
  alone and the locator gate question is moot until recommendation 3 lands.
- **Not** strip-level CTC confidence: the reader misreads at full confidence elsewhere in this
  pipeline (REPORT.md's history; the corpus note that Vision misreads at confidence 1.00), so a
  confidence gate would certify the wrong thing.

### 3. Train the reader on the locator's output distribution, not on hand quads

The highest-leverage training change the code suggests. `rowtrain.py` mixes real strips (30 % of
batch, warped from annotated windows via `realglyphs.py`) with synthetic (70 %); the locator's
actual boxes on train photos - with their real shifts, cuts and overshoots - are in neither.
Generate them: run seg-r1 (and r2, for diversity) over the train stills and verified frames, warp
each located row with the standard margin, keep the hand-truth string for any box with IoU >= ~0.7
to its hand quad, and mix these *located strips* into reader training (or fine-tune the shipped
reader on them). This directly attacks the observation-1 sensitivity: the reader learns that a
digit row shifted 8 % down or cut 6 % short still reads the same string.

- **Expected effect:** the largest available. The sensitivity table says most law flips are
  reader failures on shifted/cut strips; flattening the shift/cut curves converts them back to
  commits without touching the locator at all. This also explains and subsumes F: wide-margin
  strips are just another point on the box-perturbation distribution.
- **Measurement:** (i) re-run the observation-1 sensitivity harness against the retrained reader -
  the shifted-down-8 % and 6 %-narrower arms should move from 123/129 toward 155+; (ii) live
  heldout + ledger diff vs r1-F; (iii) located-commit score (recommendation 2) for r1 and r2 -
  both should rise, and the *gap between locator models* should shrink, which is the real goal.
- **Cost:** one data-generation pass (locator inference over the train set), one reader training
  run, one `rowexport`; no new corpus, no owner time, no GPU-heavy locator work.
- **Kill:** the sensitivity table does not flatten, or live committed does not beat r1-F's 140 by
  more than the noise floor C1/C2 establishes, or any new wrong cell appears.
- **Guard:** hold the hard-example expansion (`realglyphs.expand_hard`) and the heldout strings
  fixed; located strips must never enter validation.

### 4. Let the law choose among candidate strips (F generalised)

F's mechanism - an independent second read, keep the one that commits more - is the only proven
win (4:0 and 3:0 photos, 13 cells gained, 1 cautioned wrong). The principled extension: read each
located row at *both* margins (standard and wide), hand **both candidate sets** to
`PumpReadingLaw.resolve`, and let the exact close arbitrate. This is strictly better than F's
"keep the reading with more committed fields" heuristic, because F compares whole-photo outcomes
and can keep a mixed reading, while the law picks per-field values that jointly close - and it
refuses spurious candidates by construction (`substitutions == 0`, band checks,
`PumpReadingLaw.swift:343`).

- **Expected effect:** F's 13 cells plus the photos where neither single-margin reading commits
  but a per-field mixture closes. Realistically +3-8 cells over r1-F.
- **Measurement:** live heldout + ledger diff vs r1-F (the bar is 140/138, precision >= 0.98).
- **Cost:** about 2x read time on every photo, or F's trigger (second read only when the first
  commits < 3 fields) kept to bound it - the live test's 438 s vs 228 s shows the trigger is the
  right shape; per-field candidate merging adds no extra reads beyond F's.
- **Kill:** any new wrong cell without caution, precision < 0.98, or no gain over r1-F.
- **Precision risk is the reason this is ranked below recommendation 3:** more candidates = more
  chances of a coincidental close. The exact-close requirement plus the price band held so far (1
  cautioned wrong in F), but the kill criterion must be enforced, not assumed.

### 5. E (pseudo-labelled dark frames) - only with a verification gate

The pseudo-label pool is "frames where seg-r2 and the tracker agree" - but the agreement rate is
**68 %** (1415 of 2078 frames across 30 records, `seg-r2-disagreements.json` summed), and
agreement between a drifting tracker and a half-trained model is not correctness; it is correlated
error with extra steps. The tooling to fix this already exists: `segdisagree.py` emits the frames
*worst disagreement first*, and `runs/2026-09-28/pu91-r2-verify.md` is exactly a verification
queue.

- **Effect:** the dark recall gain r2 showed (15 -> 19/27) consolidated into a model that also
  keeps ordinary photos - if recommendation 3 has landed, the ordinary-photo risk of new data is
  much reduced, because the reader stops caring about small box differences.
- **Measurement:** dark heldout2 recall@0.7 (27 windows) as the leading indicator; live heldout +
  ledger diff as the shipping gate. Note 27 windows cannot resolve a 4-window difference (15 vs 19
  is itself within noise) - see recommendation 6.
- **Cost:** owner verifies ~100-200 frames worst-first (the annotator flow already exists); one
  segtrain run.
- **Kill:** the verified sample shows tracker/r2 agreement is wrong more than ~5 % of the time
  (then the pool is poison and E trains on drift), or dark recall does not move.

### 6. Decode-threshold sweep, scored on the located-commit metric

`segeval.py:40` already parameterises `pixel_t`, `link_t`, `min_short`, `min_area`; they were
presumably tuned against the IoU gate that §1 shows is the wrong target. One grid sweep scored on
recommendation 2's metric.

- **Effect:** unknown but cheap; plausible +2-5 cells if the shipped thresholds sit off the
  read-optimal point.
- **Cost:** one macOS evening.
- **Kill:** flat within noise on the located-commit score.

### 7. Display-decision floor for dark heads (narrow fix)

`pump-201` and `pump-161` flipping on `notADisplay`, and `PU.90.md` §1.2's `video-050` frames
sitting at widestRow 0.086-0.160 against the 0.18 floor, say the slow verdict's floors encode the
emissive-head statistics the old corpus had. After recommendation 5 lands (so dark rows are found
at all), re-measure the floor on the negatives set (the 116/128 non-pump photos are the cost of
lowering it) and lower `minimumWidestRowFraction` or make it margin-aware.

- **Effect:** +1-3 photos on the live path (the `notADisplay` flips), and the field family the
  owner actually hits.
- **Kill:** any negative photo starts classifying as a display in the leak battery.

## 3. Corpus growth: yes, but targeted - and fix the measurement first

Direct answer to the owner's question: **grow the corpus, but the binding constraint is not
corpus size, it is that ordinary-head photos cannot currently measure anything.** Priority order:

1. **Grow heldout2-dark before training data.** The dark claim that justifies this whole round
   (r2 finds more dark rows) rests on 5 stills / 27 windows, where 15 vs 19 is noise. 20-40 more
   dark heldout2 stills (black LCD, TFT, night) with hand quads make the dark metric a metric.
   Without this, every dark experiment below reports uninterpretable numbers. Cost: owner capture
   + annotation time only.
2. **Verified dark frames (the E queue), worst-disagreement-first** - per recommendation 5. The
   thousands of tracked-but-unverified frames are only useful through the verifier; pseudo-labels
   at scale without that gate train the locator to agree with itself. Quantity: the ~380 frames
   already listed in `pu91-r2-verify.md` roughly double the verified dark material; that is the
   right next chunk. Expect it to move dark recall, not the 68-photo live number.
3. **More dark stills for train** (the batches-11b-12 pattern): each new physical head is a new
   appearance family; 20-30 train stills per new head type is what got r2 its 4 dark windows.
4. **Synthetic dark-LCD profile:** the renderer has emissive `led`/`vfd` profiles
   (`profiles.py:120-131`) but `PU.90.md` §2.2 shows the corpus's light-on-dark is all emissive;
   the reflective pale-on-black glass of pump-332/334/339/340 is absent. A locator-only synthetic
   profile (row geometry + pale-glyph-on-glass appearance) is plausible because the locator does
   not need photorealism, and it scales without owner time. Rank below real frames: PU.73's
   history is that synthetic-heavy rounds move synthetic metrics more than live ones.
5. **More ordinary stills / more negatives: no.** The 4:4 churn on ordinary heads is not a data
   shortage; it is reader fragility plus seed variance. Adding ordinary data re-rolls the same
   dice.

"How would you tell it helped": dark recall@0.7 on an enlarged heldout2 (recommendation 3.1),
located-commit score (recommendation 2) flat-or-up on the ordinary heldout, live ledger diff with
no ordinary-photo losses beyond the C1/C2 noise band.

## 4. Dead ends (measured or implied)

- **Training the locator for coverage (B's padding), with this reader.** Measured: best coverage
  (195/252), worst live (115/112), 1:9 photos, precision down. The box the reader wants is not the
  box that covers the digits; it is the box whose strip looks like training. Any loss or target
  that pushes boxes outward - including an **asymmetric loss that punishes cutting more than
  overshooting** - reproduces B unless the reader is retrained jointly (recommendation 3 first).
- **Wider read margins as the only read (A).** Measured: all four settings lose (104..123 vs
  126). The same margins win as a fallback (F), which is the whole asymmetry.
- **Warm-start fine-tuning as a safety device (D).** Measured: D wins every locator metric and
  loses 1:3 in photos. The flips were never location.
- **Chasing the IoU gate.** Observation 4 plus the four known orderings: no monotone relation to
  the app path. Keep it as a sanity floor only.
- **A separate dark-display locator or head.** Splitting a 284-still training set into two
  smaller sets for a 0.91 M-param model that is data-starved is the wrong direction; r2's dark
  gain came precisely from pooling dark data into one model.
- **Picking the best of C1/C2/r1 on the 68-photo score.** Selection on noise; the seeds exist to
  size the noise, not to be selected from.
- **Multi-seed ensembling / locator TTA for read quality.** r1 and r2 locate the same rows on the
  photos they disagree on (observation 3), so a union of locator outputs changes the strips
  little; it can fix `notADisplay` edge cases but that is recommendation 7's narrower job. Low
  value for its inference cost as a read fix.
- **Relaxing the law to commit more.** Every refusal in these diffs is a correct refusal of a
  changed read; loosening the close or the band trades the 0.98 precision floor for cells, which
  is the wrong direction for a product where a wrong number costs more than a missing one (hard
  rule 13).

## 5. Things that look wrong or measured wrong

1. **Observation 1's "overshooting costs nothing" does not transfer to read time**, and the round
   table reads as if it should. The sensitivity sweep widened hand boxes by 6-10 %, a modest scale
   change around the reader's training distribution; A widened margins 3-5x and B retrained
   targets 3-5 % per side - both push the strip's digit scale outside that distribution. The
   correct statement is "overshoot within the training scale band is free; outside it, reads
   degrade into law refusals". The coverage column (160/151/171/195) measures the wrong half of
   the trade-off and should be paired with a strip-statistics column (digit height fraction,
   meanMargin distribution vs the training strips) or replaced by the located-commit score.
2. **The dark recall comparison is under-powered.** 15/27 vs 19/27 on 5 stills is a 4-window
   difference; "r2 and D find more dark rows" is a direction, not a measurement. Fix via §3.1
   before any dark conclusion is drawn from E.
3. **macOS screening vs simulator gate.** The platform delta is ~2 cells (126/125 mac vs 128/127
   sim; 140/138 mac vs 142/140 sim) - about half the effect size being ranked between locator
   models. Rounds screened on macOS are being ranked on differences smaller than the platform
   drift. Another argument for the photo-level decision rule and for confirming any ship decision
   on the simulator.
4. **Denominator drift:** the ledgers say 183 scored cells; the round table quotes "ship score
   141 -> 147/186". If 186 includes cells outside the 68-photo heldout (heldout2?), the two
   numbers should not share a sentence without naming the difference.
5. **Adaptive overfitting risk on the 68-photo heldout.** Every round since PU.56 has been
   screened on the same 68 photos; with whole-photo flip variance of +-4 photos per seed, a
   candidate that gains 2-3 photos can be a lucky draw. F is the only change whose evidence
   survives this (replicated across two locators and on the simulator). The located-commit metric
   plus the C1/C2 noise band is the mitigation; a second heldout (the enlarged dark heldout2) is
   the other.
6. **`seg-r2-disagreements.json`'s "agree" needs the verification column before E**: 68 %
   agreement (1415/2078) is quoted in the round table's favour, but until the worst-first sample
   is owner-verified, agreement is an upper bound on usable labels, not a count of them.
