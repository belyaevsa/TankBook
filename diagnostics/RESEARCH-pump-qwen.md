# RV.58 - Pump displays: the right algorithm, and whether 95% exists

Verdict up front: **the pump problem is a recognition problem, the dump understates how much
information the photographs actually carry, and the 95% gate as currently scored is unreachable by
any algorithm - including a perfect one - because 29 of the 261 cells are either forbidden to the
pump parser by product decision or physically absent from the photo.** The honest move is a
per-window recognition pipeline (rank 1-3 below) shipped under a *precision* gate, not a recall
gate. Details follow.

## 1. What the photographs show that the dump cannot

I opened all fifteen named fixtures (see "What I actually looked at"). The single most important
observation, repeated across most of them, is:

**The decimal separators are in the pixels.** On `pump-001` all three dots are visible at full
resolution (`125.22`, `67.00`, `1.869`); on `pump-005` every window shows its dot; on `pump-010`,
`pump-034`, `pump-057`, `pump-058`, `pump-063` the commas/dots are visible to a human (and to me).
Vision's whole-image pass drops them per-field at confidence 1.00 - the dump shows `12522` and
`1869` for a display whose dots I can point at. So "lost separators" is usually not lost
information; it is a **resolution/attention failure of the text recogniser on small glyphs**, which
is exactly the kind of failure crop-and-upscale fixes. The dump's framing ("the separator is simply
not in the recognised text") is true of the *text output*, not of the image.

The exceptions are real and must be designed for separately:

- `pump-003`'s small price window shows `2450` with **no decimal point physically present** - no
  image processing recovers it; only a prior (KZT band) or the display's fixed-width convention can.
- `pump-006`'s price is an integer by KZT convention and is bezel-clipped (though complete).
- `pump-052`/`pump-053` totals are genuinely destroyed by sky reflection - I cannot read them
  either; litres are crisp. Honest output is "litres only".
- `pump-063`'s occluded digit is on a *board* price the parser must not read; the transaction
  windows are clean.

Second observation: **the make logo and the field labels are the most reliably read text on every
fixture.** `GILBARCO VEEDER-ROOT`, `Wayne`, `DRESSER`, `TOKHEIM`, `ADAST`, `SCHEIDT&BACHMANN`,
`ТОПАЗ` and the labels `SUMMA/LIITRIT/HIND/1L`, `РУБЛИ/ЛИТРЫ/ЦЕНА/ЛИТР`, `€/L` survive in nearly
every dump, including the bad ones. Make + labels are free, deterministic anchors: make selects a
display template (which windows exist, their fixed widths and decimal counts), labels assign
operands to windows. The current parser uses almost none of this; it is the cheapest accuracy
available.

Third: **orientation matters and is free.** `pump-001` reaches Vision rotated 90 degrees (EXIF
orientation not applied); it still reads the digits but loses two dots. Applying orientation before
recognition costs nothing and removes one whole class of stress.

Fourth, confirming the README: board prices are traps. On `pump-034` I verified the four boarded
prices (1.934/1.834/1.819/1.759) and the arithmetic 160.53/87.29 = 1.839, which is on no board.
Unit price must come from the transaction's own price window (Gilbarco's `€/L` window carries it on
`pump-057`, `pump-058`) or be nil (Wayne layouts print no transaction price at all).

## 2. Where the 261 cells go - the ceiling argument

The scorer (`CorpusABScorer.swift`) counts non-empty `liters/unitPrice/total` (178) + non-empty
`fuelKind` (17) + `currency` (66) = **261**. Two structural facts:

1. **17 fuelKind cells can never be hits.** The pump parser must not attempt fuel kind (hard rule
   13 reasoning, `EXTRACTION.md`: badges belong to every nozzle). Those cells were settled by paired
   receipts or nozzle badges, not by the display.
2. **~12 numeric cells are not in the photo.** `pump-021/022/023` (litres+total, six cells - the
   README records them as past photographic recovery, supplied by the photographer at the pump),
   `pump-012` total, `pump-014` price+total, `pump-038` total, `pump-052` total, `pump-053` total.
   I confirmed the illegibility of 052/053 with my own eyes.

An oracle reader that obeys the product rules therefore scores at most
(261 - 17 - 12) / 261 = **88.9%**, and less if the idle-pump refusals (`pump-016/017`, four 0.00
cells) are scored as misses rather than as correct refusals (~87.4%). **95% of 261 is unreachable by
construction.** This is the answer to the brief's central question, and it holds before any
algorithm is discussed: the denominator mixes "what the parser can read" with cells the product has
decided the pump path must not output and cells the photo does not carry.

## 3. Ranked list

Gains are projections from the dump-vs-truth diff and from what I saw in the pixels, counted in
cells of the 261; none are measured. Baseline: 53/261.

### 1. Per-window crop, upscale, multi-scale consensus recognition (make-templated, label-anchored)

- **What:** orient the image (EXIF), run one whole-image Vision pass, use the reliably-read labels
  and make logo to locate each numeric window, crop each window with padding, upscale 3-4x, re-run
  Vision `.accurate` per crop at two or three scales, and take a value only when the scales agree
  (consensus); disagreement demotes the field to "scale/digit uncertain" instead of guessing.
- **Layer:** recognition (the layer where pump actually fails, per `EXTRACTION.md`'s measured
  split).
- **Expected gain:** the separator-loss class (~45 cells: `pump-001` +2, `pump-002` +2, `pump-005`
  +2, `pump-008` +1, `pump-009` +3, `pump-011` +1, `pump-020` +2, `pump-028` +3, `pump-037` +2,
  `pump-043` +2, `pump-045` +2, `pump-053` +1, `pump-057` +2, `pump-059` +3, `pump-062` +1,
  `pump-064` +1, ...) plus truncated-digit recovery where the digits are human-legible (`pump-004`
  +3, `pump-010` +2, `pump-018` +1, `pump-022` +1, `pump-034` +2, `pump-063` +3) plus the
  all-present-but-unparsed fixtures (`pump-032` +3, `pump-050` +3). Projection **+55 to +70 cells**.
- **iPhone 12 cost:** whole-image pass already happens; 4-6 crops x 2-3 scales of ~640 px Vision
  requests is tens of ms each - well under ~0.5 s total, no new dependency, fully offline (rule 1).
  Whole-image 3x upscale is NOT affordable in iPhone 12 memory; crops are.
- **Wrong-answer risk / what abstains:** an upscaled crop could hallucinate a dot; the multi-scale
  consensus is the abstention (disagree -\> uncertain), and every value still passes the cross-check
  and lands as an editable pre-fill (rule 13). Glare-destroyed totals (052/053) stay nil - consensus
  cannot agree on absent pixels.
- **Generalises:** yes - templates key off make logos that Vision already reads; an unseen make
  falls back to label-anchored generic crops. New fixtures of known makes score immediately.

### 2. Deterministic scale resolution: per-make fixed-width templates first, arithmetic + priors second, abstention third

- **What:** (a) where the display format is fixed-width, the separator is a format property, not a
  search: Gilbarco zero-padded windows are always comma-before-last-two (`0203800` -\> 2038.00,
  `05095` in the price window -\> 50.95), Wayne EUR windows are 2dp/2dp/3dp, KZT totals and prices
  are integers. Apply a template only when the make logo is detected AND the digit count matches the
  template width; otherwise abstain. (b) For bare digit strings with no template (the `pump-003`
  shape), run the powers-of-ten search with the cross-check, then currency-keyed price bands, then
  plausible volume, then the car's tank capacity - and when two candidates survive (they will:
  85.25 vs 8.525 L), abstain and let the user decide at Confirm.
- **Layer:** interpretation.
- **Expected gain:** standalone it is the biggest single layer (~+35 to +45, because it converts
  every correct-but-unscaled digit string into a value); **marginal on top of rank 1 it is +10 to
  +15** (the physically-separator-less windows: `pump-003` price +1, KZT integers, zero-padded
  windows the crop still reads dotless, `pump-006`).
- **iPhone 12 cost:** microseconds; pure arithmetic.
- **Wrong-answer risk / what abstains:** a wrong template is a silent factor-of-ten - the worst
  error - hence logo+width gating and abstention on any mismatch. On `pump-010` the arithmetic
  legitimately does not close (13.17 x 75.95 = 1000.26 vs preset 1000.00): the search must treat
  "round total, product within CHECK-3 tolerance" as a *known preset shape* and keep the displayed
  values, never "correct" the volume to close the equation (README's explicit warning).
- **Generalises:** templates per make generalise within make; bands generalise per currency
  (SCHEMA.md's curated bands, keyed by fuel kind and era once known - currency-only bands are not
  enough, per EXTRACTION.md's LPG counter-example).

### 3. Cross-check as candidate selector + single-substitution seven-segment digit repair (P2.13 as specified)

- **What:** choose among discrete price candidates (four-price Wayne boards) by exact product
  match; when the product misses the total by one least-significant step of one operand, try the
  confusable segment pairs (4/9, 8/9, 8/6, 8/0, 3/9, 5/6, 1/7) and accept only if exactly one
  substitution closes the arithmetic at money precision.
- **Layer:** interpretation.
- **Expected gain:** **+6 to +9**: `pump-005` price (if rank 1 leaves it to the board), `pump-015`
  +1 (1.884 -\> 1.889), `pump-013` +1-2, `pump-004` catch of the 1408 misread +1, `pump-037/043`
  board selection +1 each, `pump-025` total recovery +1 (22.91 x 1.789 = 40.99 names the glare-lost
  digit).
- **iPhone 12 cost:** negligible.
- **Wrong-answer risk / what abstains:** the exactly-one rule is the abstention; two closing
  substitutions -\> nil. `pump-010` is protected (several substitutions almost close, none exactly).
  Repaired values are pre-fills with lowered confidence, never locked (hard rule 13), and
  `crossCheck` stays `mismatch` so Confirm never treats them as confirmed.
- **Generalises:** yes for any seven-segment source; explicitly not for receipts (no segment
  topology).

### 4. Narrow seven-segment Core ML digit+decimal-point classifier on synthetic data

- **What:** the EXTRACTION.md-prescribed tool: ten digits + blank + decimal point, trained on
  rendered segments with glare/blur/perspective/dirt augmentation; the 66 real photos stay held-out.
- **Layer:** recognition, digit level.
- **Expected gain:** converts the residual misread class rank 1 cannot fix (`pump-049` faint LCD,
  `pump-052`'s 3-as-7, `pump-046/047` price misreads, `pump-065/066` broken totals) - **+10 to +20
  on top of ranks 1-3** - and gives per-digit posteriors that order rank 3's repair candidates.
  Crucially it also detects the decimal point *as a segment* whenever physically present, which is
  a second, independent separator channel to consensus-vote against rank 1.
- **iPhone 12 cost:** a few hundred KB, milliseconds, offline - the cheap part is runtime; the cost
  is days of renderer/training work and an honest held-out evaluation.
- **Wrong-answer risk:** synthetic-to-real domain gap (road dirt, reflections, insects) is the
  failure mode; mitigated by augmentation breadth and by never letting it override consensus
  without cross-check agreement.
- **Justified?** Only after ranks 1-3 are measured and plateau. It is the right instrument for the
  residual, not for the first move.

### 5. Cloud VLM gateway as asynchronous blank-filler (never a peer)

- **What:** the existing P4.12 arm (31/46 on the old corpus - the best single reader measured),
  invoked only for fields the on-device pipeline abstained on, answers arriving late into an
  editable suggestion.
- **Layer:** recognition/interpretation, off-device.
- **Expected gain:** **+5 to +10** on the D/G fringe; bounded by its own failure signature: five
  silent swaps, scale-invariant decimal shifts, run-to-run non-determinism, 6.5-40 s latency.
- **iPhone 12 cost:** zero device cost; network + Pro-tier quota; rule 1 keeps it out of the
  primary path.
- **Wrong-answer risk:** the highest on this list; anchor before accepting (operand assignment from
  unit markers/bands *before* trust, scale from an external prior), cross-check mismatches demote
  to nil. Its non-determinism also makes it unsuitable as the thing the ratchet measures - a gate
  asserted against an unstable reader is an unstable gate (P2.14's lesson).
- **Generalises:** yes, but as a suggester only.

### 6. The paired-receipt trick

- **What:** when the pump abstains, offer "is there paper? scan it instead".
- **Verdict:** six of 66 fixtures have pairs; J4's trigger is precisely "the station printed no
  receipt", so the overlap with the mode's actual users is small. Worth one line of Confirm-screen
  copy (hard rule 15's peer door), not worth pipeline complexity. Not an algorithm; a courtesy.

### 7. Honest refusal and partial pre-fill as the product contract

- **What:** reframe the mode from "extract the triple at 95% recall" to "emit only what is settled,
  at >=95% precision, and leave the rest empty". Litres-only pre-fill from a sunlit Wayne
  (`pump-052`) is exactly rule 15's "head start, not an answer"; the user loses nothing because the
  manual door is peer and pre-filled with whatever survived.
- **Layer:** product/gate definition, not recognition.
- **What the user loses if the mode stays off:** functionally nothing - typing is a full peer path.
  What they lose is 2-4 tapped values per fill on the good cases, which is the entire value of the
  feature and worth shipping *under a gate that measures what the feature promises* (precision of
  emitted values, coverage reported as telemetry), not a recall denominator that includes cells the
  feature is forbidden to emit.

## 4. Is 95% reachable?

**No - and now provably, not empirically.** The scored denominator is 261 = 178 numeric fields +
17 fuelKind + 66 currency. The pump path is forbidden 17 (fuel kind) and the photo does not carry
~12 more (sun-glare and past-recovery fixtures), so the oracle ceiling is ~88.9% (~87.4% if idle
refusals score as misses). Realistic projection for ranks 1-3 implemented and abstaining honestly:
**~115-130/261 (45-50%)**; adding rank 4, **~55-62%**; the composite never approaches 95%.

What the product should do with a mode that cannot pass its own gate:

1. **Re-score the gate over the cells the mode is allowed to promise**: denominator = numeric
   fields the photo can carry (261 - 17 - the unreadable set, re-derived per corpus change), and
   split it into *precision of non-nil outputs* (the gate, >=95%) and *coverage* (telemetry,
   ratcheted upward but not ship-blocking). This keeps the user-protection the gate was written for
   - no confident wrong values - while stopping the denominator from vetoing an honest partial
   pre-fill.
2. Until that decision is taken, keep the mode off, exactly as committed; nothing in this analysis
   argues for shipping under the current denominator.

## 5. What I would not do

- **Threshold on Vision confidence** - `pump-004` is wrong at 1.00; the number is not evidence.
- **Guess separators from locale** - one forecourt carries both conventions (`pump-045`..`056`,
  repeated at Sikupilli); "RU means comma" is wrong half the time on the corpus's own pairs.
- **Impute unitPrice from the nearest board price** - five counter-examples (`pump-031/034/035/042/
  051/055/056/061`), including a board that prices a different diesel than the one dispensed.
- **Attempt fuel kind from a pump photo** - the badges name the station's products, not the fill.
- **Adjust a volume to close the cross-check** - `pump-010`'s rounded preset volume is the truth.
- **Train anything on the 66-image corpus** - it is the test set; a model trained on it measures
  memorisation.
- **Make the cloud VLM synchronous or trusted** - latency, non-determinism, and rule 1.
- **Silently repair digits** - every repair is a lowered-confidence pre-fill or it is nothing.
- **Upscale the whole 12 MP frame on an iPhone 12** - memory; crops only.
- **Treat the dump's "separator lost" as "separator absent"** - rank 1 exists precisely because
  that equivalence is false on most fixtures.

## 6. What I actually looked at

Opened as images, at full resolution, all fifteen named fixtures: `pump-003`, `-004`, `-005`,
`-006`, `-008`, `-009`, `-010`, `-025`, `-034`, `-052`, `-053`, `-057`, `-058`, `-063` natively
(png/jpg), and `pump-001.heic` via a `sips` HEIC-\>JPEG conversion of a copy written to the
session's approved temp directory outside the worktree (original untouched; the transcode was for
viewing only and is disclosed here rather than claimed as a native HEIC read). I read my own eyes'
output against `expected.csv` before counting any gain.

Read in full: `fixtures/pump/README.md`, `fixtures/pump/expected.csv`, `diagnostics/pump-ocr-dump.txt`
(all 2071 lines), `docs/EXTRACTION.md` (through the P4.13 section). Read by targeted search:
`docs/TASKS.md` (P2.7/P2.13/P2.14, gate rows), `docs/PHASES.md`, `docs/VISION.md`, `docs/JOURNEYS.md`
(J4), `PumpPhotoGate.swift` (53/261 constants), `CorpusABScorer.swift` and
`CorpusScorerFuelKindCurrencyTests.swift` (denominator composition:
178 numeric + 17 fuelKind + 66 currency = 261). I did not run the harness, build, or any git
command; all gain numbers are projections from the dump-vs-truth diff and direct image inspection,
and are labelled as such.
