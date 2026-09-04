# RV.58 - the pump-display algorithm: what is right, and whether 95% is reachable

**Verdict up front.** The pump path is not failing where everyone assumed. The dump shows the
digits are *present* in Vision's output for roughly three quarters of the corpus - they are
thrown away one layer later, because the number tokenizer requires a decimal separator that
seven-segment displays routinely lose. A deterministic ladder (separator-liberal tokens +
scale search + label geometry + the existing cross-check and digit repair) lifts the numeric
score from ~4/178 to ~110/178 **on the OCR text that already exists**, with every ambiguity
that survives being one the product must abstain on anyway. Recognition work (find the panel,
crop, re-read) adds perhaps twenty more. And 95% as the gate is currently scored is
**arithmetically unreachable**: ~24 of the 261 scored cells are forfeited by the product's own
correct rules or encode values the photographs do not carry, putting the ceiling at ~91%
before any algorithm runs. The gate is measuring the wrong thing; the mode should stay off
until the metric and the first two items below land - and whether it ever ships should be
decided by the re-scoped number, not by effort spent.

One corpus note: the folder now holds **66** images and the gate scores **261** cells
(pump-065/066 landed 2026-09-04). The brief's "64 fixtures / 53-261" is the same corpus one
day earlier; everything below is counted against all 66.

---

## 1. Where the loss actually is - a decomposition, not a guess

The 261 scored cells are not three equal columns. They are:

| column | cells | today's hits | note |
|---|---|---|---|
| `liters` | 66 | a handful | the money column |
| `unitPrice` | 51 (15 legitimately empty) | a handful | |
| `total` | 61 (5 legitimately empty) | ~4 | |
| `currency` | 66 | ~45-50 | the marker words (`РУБЛИ`, `€`, `ТЕНГЕ`) read well |
| `fuelKind` | 17 | **0, by design** | the pump parser must never produce it (below) |

So "53/261 (20%)" is flattered by currency. On the three numeric columns - the only columns
that make a fill-up - the live score is approximately **4-8 of 178 (2-4%)**. The spike
harness's own footer says 4/178 (2.2%). That is the number the 95% question is really about.

Walking the pipeline (`OCR -> tokenize -> assign roles -> cross-check`) against the dump and
the photographs:

**Layer 1 - Vision recognition.** The glyphs are mostly read. The decimal *point* - a small
isolated square on a segment display - is dropped **per field, not per image**, exactly as the
brief says: pump-001 keeps `67.00` and loses the point on `12522` and `1869` in the same
exposure. I opened the photographs: the points are visibly *there* (pump-005's `4621.08` is
pin-sharp; pump-009's `02038,00` glows at night). Separately, whole-frame Vision floods the
line set with forecourt advertising (`Wrapper ja jook 0,5-0,7l`, Red Bull, the 40-line
keyboard instruction manual on pump-007), and it genuinely misreads some readable digits at
confidence 1.00 (pump-052's `34.64` -> `7464`; pump-004's `3008` -> `1408`).

**Layer 2 - number tokenisation. This is where the corpus actually dies.**
`NumberScanner.decimals` requires `[.,]` and `NumberScanner.value` reads only a decimal or a
hyphen-decimal. A bare digit string - `12522`, `8525`, `462108`, `005580` - is **not a
value**, so it never reaches a label, a candidate set, or the cross-check. Counting the dump:
on roughly 45 of the 66 fixtures every transaction digit is present in the OCR text, and on
most of those at least one field is separator-less and therefore discarded. The parser is
blind to exactly the strings seven-segment displays produce.

**Layer 3 - role assignment.** Pump displays print no `A x B` operand line, so the receipt
ladder never fires. What they print instead are *labels* - `SUMMA`/`LIITRIT`/`HIND/1L`,
`Стоимость`/`Количество`/`Цена за 1 литр`, `РУБЛИ`/`ЛИТРЫ`/`ЦЕНА/ЛИТР` - and the dump shows
Vision reads those labels well. The label->value geometry exists in the app
(`pricePerUnitValue`, `quantityValue`), but it calls `NumberScanner.value`, so it inherits
the layer-2 discard. Role assignment is a *smaller* problem than tokenisation: fix the
tokens and most roles fall out of the labels.

**Layer 4 - arithmetic.** The cross-check (consistency, candidate choice) and P2.13 digit
repair are sound and already shipped. They are simply starved: with the tokens discarded,
there is nothing to check.

**The conclusion this forces:** the pump problem today is ~60% a *parser* problem (layers
2-3, deterministic, free), ~25% a *recognition* problem (layer 1, the crop/CNN work), and
~15% *unwinnable cells* (photographs that do not carry the value, plus cells the product
rules forfeit). The receipt lesson - "recognition was not the bottleneck" - turns out to be
true of pumps too, just one layer earlier in the pipeline.

---

## 2. The ranked list

Each entry: what it is; the layer it acts on; the gain **counted per fixture** (the full
66-row table is §3); cost including iPhone 12 (A14) runtime; wrong-answer risk and what
abstains; whether it generalises past these 66 photographs.

### 1. Re-scope the gate metric before touching the algorithm - it cannot pass as built

- **What:** change what the 261-cell score counts, in three ways: (a) drop the 17 `fuelKind`
  cells, or produce kind only where the display itself names it; (b) treat the two idle-zero
  fixtures as *refusal* successes rather than misses; (c) correct or empty the three cells
  where `expected.csv` contradicts its own stated convention ("a value the photo does not
  carry stays empty").
- **Layer:** measurement. No algorithm.
- **The arithmetic, counted per cell:** 17 fuelKind cells the pump parser may not produce
  (corpus rule + hard rule 13: a grade badge belongs to every nozzle, not to the fill); 4
  idle-zero cells (pump-016/017 L+T) the `total == 0 -> nil` rule - correct for receipts -
  forfeits; **pump-003 total** (the display reads `20886.3`, the CSV scores `20886.25` -
  unwinnable by any reading); **pump-054 total** (flare hides the digit; the paper says
  `51.71`, the arithmetic says `51.70` - unwinnable both ways); **pump-021 total** (the
  photograph does not carry it at any zoom; the CSV is the photographer's reading at the
  pump). That is **24 cells**, so the ceiling today is 237/261 = **90.8% < 95%** - no
  algorithm can pass the gate as scored. (With policy stretches - badge-settled kinds, a
  pump-scoped zero - the ceiling is 255/261 = 97.7%, but that demands flawless reading of
  every remaining photo; see §4.)
- **Gain:** zero cells; it decides the ship question honestly. Without it, every algorithm
  below is measured against a bar that is unreachable by construction.
- **Cost:** hours - a scorer change, three CSV cells corrected or emptied (they break the
  corpus's own pump-012 convention), `PumpPhotoGate` and the README updated in the same
  change. No runtime.
- **Wrong-answer risk:** none. It removes misses that are correct behaviour (an abstention
  scored as a failure is what pushes teams toward guessing).
- **Generalises:** it is what makes any future number - from any arm, on any corpus -
  meaningful.

### 2. The deterministic ladder: separator-liberal tokens + scale search + label pairing

This is the brief's direction 1, evaluated. The naive form - "the cross-check reconstructs
the scale" - is already falsified in the README (12 solutions on pump-003). The form that
works is a **constraint solver with abstention**, not a decoder:

1. Tokenise bare digit strings as candidate operands with *unknown scale* (keep the OCR
   string; the token's digit count is evidence, below).
2. Assign roles by label geometry (`SUMMA`/`Стоимость` -> total, `LIITRIT`/`Количество` ->
   volume, `HIND/1L`/`ЦЕНА за 1 литр`/the `€/L` window -> price; the grade boards become a
   *candidate set*, never "the price").
3. Search scale assignments (`10^0..10^-3` per field) filtered by: the currency's price band
   (the bundled pack: EUR 1-3, RUB 40-500, KZT 100-1000 - it pins pump-003's `2450` to
   `245.0` and rejects `24.5`/`2450`), a plausible-fill volume band (2-150 L - the floor is
   2, not 5: pump-014 is a real 3.92 L and `Vmin 2 LIITRIT` is printed on the pumps), and a
   plausible-total band; then close `liters x price = total` at the display's own money
   precision, tolerating the display's rounding (pump-010's legitimate non-closure is
   *tolerated*, never "fixed" by moving the volume).
4. Run the existing digit repair over the *candidate set* (pump-015: `1.884 -> 1.889` is the
   only substitution that closes at 2 dp) - the shipped P2.13 engine, fed with candidates
   instead of a resolved pair.
5. Where exactly one field is unreadable, **derive** it from the other two and mark it
   derived (`T = L x P`, `L = T/P`, `P = T/L`) - a suggestion, never a lock: pump-054's cent
   (`51.70` computed vs `51.71` paper) is the standing warning, and the residual stays on
   the Confirm screen.

- **Layer:** parser (tokenisation + role assignment + arithmetic). No new recognition - this
  runs on the OCR text in today's dump.
- **Gain, counted per fixture (§3 has all 66 rows):** **110/178 numeric cells (62%)** -
  99 from tokens+labels+scale+band+cross-check, +1 digit repair (pump-015), +10 derived
  fields - against today's ~4/178. On the 17 fixtures of the P4.12 sweep the same ladder
  scores ~28/46 (61%), versus DeepSeek's 31/46 (67%) - i.e. the deterministic ladder
  **ties the cloud VLM within noise** without its silent swaps, decimal shifts,
  non-determinism, 12-36 s latency, or per-call cost.
- **Cost:** parser-only, pure functions over `[OCRLine]` - the search is ~10^2-10^3
  assignments with a multiply each. Microseconds. iPhone 12 runtime: unmeasurable. The work
  is vocabulary (labels already exist for three languages) and the scale-search engine.
- **Wrong-answer risk and what abstains:**
  - the factor-of-ten volume tie (pump-003: `85.25 L` vs `8.525 L` both close) survives
    every automatic filter - it **abstains**, or resolves against the vehicle's tank
    capacity in-app (a fill cannot exceed the tank; the corpus harness has no vehicle, so
    there it abstains). This is the single worst error the app can make and it stays a
    refusal;
  - swapped operands are invisible to the cross-check (`a x b == b x a`) - the band and the
    volume range carry the assignment, and a symmetric pair abstains;
  - derived fields are flagged, shown with their residual, and re-checked - a derivation
    that misses by more than the display's rounding abstains;
  - **pump-031 is the trap to pin in tests**: Vision's `0 -> 8` misread (`32.50 -> 32.58`)
    accidentally *closes* the arithmetic the truth legitimately breaks (a loyalty discount
    sits between board and charged price). Repair abstains (two consistent values), the raw
    read is wrong-but-consistent, and nothing automatic catches it. The total on a discount
    display is offered, never locked;
  - two closing repairs abstain (the existing exactly-one rule), as does any scale tie.
- **Generalises:** fully. It assumes nothing about language (labels are a vocabulary, already
  per-script), font, vendor, or separator style - only that `liters x price = total` within
  the display's rounding, which is every pump everywhere.

### 3. Find the LCD, then read it (crop, deskew, upscale, re-recognize)

- **What:** detect the display panel(s) - bright, high-local-contrast, fixed-aspect
  rectangles (`VNDetectRectanglesRequest`, or plain contour/threshold heuristics), crop with
  margin, perspective-correct, upscale 2-4x, and re-run Vision on the crops; union the
  results with the whole-frame pass. `docs/EXTRACTION.md` parked exactly this "for the pump
  class, where the deficit is measured". The deficit is measured: here is where it pays.
- **Layer:** recognition.
- **Evidence the surroundings confuse the recognizer (from the dump and the photographs):**
  the advertising is parsed *as data* (`0,7l` -> `0.700` litres on pump-001 - cropping
  deletes the entire failure class, not just this instance); values I can read in the
  photographs are absent or mangled at whole frame - **pump-063** (`13.15` / `7.17`, both
  legible through glare, *absent* from the OCR), **pump-052** (`34.64` legible, read as
  `7464`), **pump-034** (`160.53` / `87.29` legible, read as `160.5` / `729`), **pump-018**
  (the total absent - and the README records the ground truth itself was "read at 5x crop,
  not from the whole frame": the corpus maintainers have already validated the method by
  hand); **pump-006**'s panel is ~8% of the pixels. Keystone matters too: pump-010's
  `1000.00` read as `00.0U` is an angle failure before it is an OCR failure.
- **Gain, per fixture:** recovers something on pump-012 (+1-2), 018 (+1), 034 (+2), 041 (+1),
  042 (+2), 044 (+1-2), 049 (+1-3), 051 (+2), 052 (+1), 055 (+1), 056 (+2), 063 (+3),
  065/066 (+1-2 each) - **+15-25 cells, to ~130/178 (73%)** cumulative with item 2. It does
  nothing for the saturated-glare class (pump-021/022/023 are past recovery at any zoom -
  the README is explicit that "try harder at 5x" is the wrong lesson).
- **Cost:** rectangle detection tens of ms; 2-6 crop re-recognitions ~100-400 ms total on an
  iPhone 12 - inside the capture budget, and parallelisable with the whole-frame pass.
- **Wrong-answer risk:** a crop can miss a field (the union strategy keeps the whole-frame
  result), or frame an advert instead of the panel (the downstream band/cross-check filters
  it exactly as today). No new confident-wrong paths; abstentions unchanged.
- **Generalises:** "a small bright rectangle in a noisy frame" is every pump on Earth. The
  one honest limit: pump-008's video overlay has no panel at all - but its values are
  printed twice and read well already.

### 4. Seven-segment recognition proper, on the panel windows

- **What:** the narrow classifier `docs/EXTRACTION.md` already nominated: 12 classes (10
  digits, decimal point, blank), trained on **synthetic** renders (seven-segment fonts +
  glare/blur/perspective/LCD-ghosting/backlight-bloom augmentation), run per window after
  item 3's crop, emitting per-digit posteriors that order the digit-repair candidates
  (glare `9 <-> 4` gets a posterior instead of a guess). Segmentation is nearly free:
  seven-segment windows are fixed-pitch, so projection profiles split digits reliably.
- **Layer:** recognition (replaces Vision *on the panel windows only*).
- **Gain, per fixture:** the residual after items 2-3 is mostly Vision misreading digits it
  can see (052's `3 -> 7`, 019's `7 -> 9`, 060's `7 -> 9`, 044's `5 -> 9`) plus the
  lowest-contrast LCDs (049, 058-style ghosting - where *unlit* segments stay faintly
  visible and a text recognizer sees noise). Estimate **+10-20 cells over item 3, to
  ~145-155/178 (81-87%)**.
- **Cost:** the only multi-week item here - a renderer, a training run, a few-hundred-KB
  Core ML model; runtime on iPhone 12 is single-digit milliseconds per window, offline, free.
  The data wall that blocks receipt-side training is absent (synthetic data), and the 66
  real photos stay a genuine held-out set precisely because nothing trains on them.
- **Wrong-answer risk:** a classifier can hallucinate a digit on an empty or saturated
  window - mitigations: the `blank` class, a margin abstention, posteriors feeding repair,
  and the cross-check disposing at the end. It must never emit a value the segment evidence
  does not support.
- **Justified?** Only after items 1-3 are measured, and only if the product still wants the
  mode then. It is the only path that plausibly approaches ~90% numeric; if the re-scoped
  gate (item 1) plus items 2-3 lands the mode at ~75% with zero confident-wrong values, the
  product call may be that the remaining cells belong to the user (hard rule 15) rather than
  to a model.

### 5. Multi-frame voting at capture time

- **What:** hold the camera on the display for ~1 s, take 3-5 frames, vote per window.
  Glare and reflections move with the hand; a digit saturated in frame 1 is often clean in
  frame 3.
- **Layer:** capture (feeds whichever recognizer exists).
- **Evidence:** the corpus already contains the proof of angle-dependence - pump-016/017 are
  the same pump family where one angle reads `1.889` clean and the glared one reads it as
  `1.884`; pump-015/016/017 as a set is how the README settled the glare-`9`-as-`4` trap.
- **Gain:** unmeasurable from stills; it targets exactly the glare class (021-023, 041, 052,
  053) that items 2-3 cannot reach. Bounded by saturation: a pixel blown out in every frame
  votes for nothing, and the README says 021-023 are past that point.
- **Cost:** a capture-session change plus alignment (the display is static; per-frame OCR
  and per-window vote). iPhone 12: 3-5 Vision passes is ~1-2 s - acceptable only as a
  pump-mode flow, or cheap with item 4's CNN per frame.
- **Risk:** none new - voting is a precision-improver; a window with no majority abstains.
- **Generalises:** yes, and it compounds with items 3-4 rather than competing with them.

### 6. The cloud/gateway arm as a late second opinion - never the gate

- **What:** `/extract` with `kind: "pump"` exists; the RV.51/RV.57 pattern (local result
  now, better answer in the inbox later) applies to pump captures exactly as to receipts.
- **Layer:** gateway.
- **Evidence:** P4.12 measured **31/46 (67%)** numeric on the old 17 fixtures. Item 2's
  ladder estimates **~28/46 (61%)** on the same set - the deterministic parser ties the VLM
  within noise, and the VLM's measured failures (five silent swaps, the pump-009 decimal
  shift, run-to-run non-determinism, 6.5-40 s latency, per-call cost, `0.0` confident zeros)
  are precisely the failure shapes hard rule 13 forbids and this mode exists to avoid.
- **Gain:** marginal over item 2 - worth it only as the inbox's "a better reading may
  arrive" for the hardest photos (the 044/065/066-class small, angled, night shots).
- **Cost:** already built; per-call money; 12-36 s means it is never present at the pump
  (RV.51 measured it), which is fine for an inbox answer.
- **Risk:** it must cross-check and suggest, never trust - the gateway's own recommendation
  in `docs/EXTRACTION.md`. Hard rule 1 caps it at fallback status forever: pump mode is a
  local-first feature or it is nothing.
- **Generalises:** as infrastructure, yes; as the pump answer, no.

### 7. The paired-receipt trick as a product answer

- **What:** when a pump capture under-delivers, offer the paper door: "receipt printed? scan
  it - it reads better." Six matched pairs exist in the corpus; the receipt path scores 82%
  and is still rising, and the pairs prove the paper is the better document for the same
  transaction *when it exists*.
- **Layer:** product flow.
- **Gain:** zero pump cells - it routes around the problem instead of solving it. That is
  not a criticism: J4's own trigger is "station prints no receipt / receipt skipped", and
  the second half ("skipped") is a user who has the better document in hand.
- **Cost:** a caption and a flow branch; hours.
- **Risk:** it must never read as "scanning failed, use the fallback" (hard rule 15) - it is
  offered as a peer door, and the pump photo stays attached either way.
- **Generalises:** only where paper exists. For the genuine no-receipt stations (J4's first
  half), the honest answer is item 8.

### 8. Refuse honestly - and count what the user actually loses

- **What:** keep the flag off until the re-scoped metric says otherwise; the off path (the
  ordinary manual form, photo attached, no error) is already built and L4-verified.
- **Layer:** product decision.
- **What the user loses with the mode off:** ~15-30 seconds of typing three numbers per
  receipt-less fill, with odometer as the only typed fourth field. What they would gain at
  the realistic ceiling (~85% numeric with rigorous abstention): a pre-fill that still
  requires a glance on ~5 of 6 fills, and nothing on the sixth. What they gain *wrong* if
  the mode ships loose: a volume wrong by 10x sitting invisible on a Confirm screen,
  corrupting consumption for the life of the vehicle. Hard rule 13 makes the abstention the
  correct output exactly where the display does not settle the value - the corpus's own
  number for that is the pump-003 tie.
- **Gain:** trust, the asset the Confirm screen runs on. A mode that is right 80% of the
  time and visibly wrong 20% teaches users to retype everything - which is the mode being
  off with extra steps.
- **Cost:** nothing; it is the shipped state.
- **Generalises:** it is the frame every other item is evaluated inside.

**The six directions, mapped:** 1 -> item 2 (works, as a constraint solver with abstention,
not a decoder); 2 -> item 3 (yes, with per-fixture evidence); 3 -> item 4 (justified only
after 2-3, the only path near ~90%); 4 -> item 7; 5 -> item 8; 6 -> items 5 plus the
anything-else notes below.

**Anything else the photographs suggest:**

- **Window format carries scale.** A six-digit zero-padded Gilbarco window (`005580`) is
  always 2-decimal; the four-digit `€/L` window (`1759`) is always 3-decimal; the Wayne
  board window is always `X.XXX`. Fixed-pitch windows carry their own format: digit count +
  the field's plausible range resolves most scales *without* the cross-check, which then
  verifies rather than searches. This shrinks the ambiguous set before arithmetic runs.
- **Vertical order is a weak prior, never a rule.** On every Gilbarco/Wayne/Tokheim stack I
  opened, total sits above volume (SUMMA/LIITRIT, Стоимость/Количество, € over L) - useful
  when labels fail. pump-008's horizontal triple (СУММА | ОБЪЁМ | ЦЕНА) falsifies it as a
  rule in one photograph.
- **The previous-customer trap bounds every algorithm.** A display holds the last
  transaction until the next fill starts, so even a perfect read can be the wrong person's
  fill. Nothing in the pipeline can see this; the guards are the odometer delta on the
  Confirm screen ("+N km since last") and hard rule 13. This is a correctness ceiling no
  accuracy number includes.
- **Redundancy votes.** pump-008 prints every value twice (video overlay + LCD strip); two
  windows asserting the same value is a per-field vote. Partial generalisation.
- **Per-vendor parsers are a trap.** One forecourt already mixes two vendors, two separator
  conventions, and five board orders (pump-045..064); the generic window+format+ladder
  approach covers them all, and a vendor table would rot.

---

## 3. The per-fixture count behind item 2

Columns: the three truth values the photograph carries (blank = cell legitimately empty, not
scored); what the ladder wins out of the scored numeric cells; the blocker for the rest.
"derive" = the field is computed from the other two and flagged, never locked.

| fixture | L | P | T | ladder | what blocks the rest |
|---|---|---|---|---|---|
| 001 | 67.00 | 1.869 | 125.22 | 3/3 | - |
| 002 | 43.61 | 99.40 | 4334.83 | 3/3 | - |
| 003 | 85.25 | 245.0 | 20886.25 | 1/3 | 10x volume tie abstains; CSV T is the arithmetic, display reads 20886.3 |
| 004 | 12.38 | 243.0 | 3008.00 | 1/3 | T misread 1408 at 1.00; L truncated to `12,` |
| 005 | 87.92 | 52.56 | 4621.08 | 3/3 | (cross-check picks 52.56 of four) |
| 006 | 45.00 | 244.0 | 10980.00 | 3/3 | - |
| 007 | 60.25 | 76.24 | 4593.46 | 1/3 | T misread 4553.46 (9->5, not in repair table); L `602` |
| 008 | 20.00 | 54.90 | 1098.00 | 3/3 | - |
| 009 | 40.00 | 50.95 | 2038.00 | 3/3 | - |
| 010 | 13.17 | 75.95 | 1000.00 | 1/3 | T `00.0U`, L `13.1` - angled glass; preset non-closure never reached |
| 011 | 11.01 | 1.789 | 19.70 | 3/3 | - |
| 012 | 5.63 | 1.789 | | 0/2 | both unread at whole frame; fragments only -> item 3 |
| 013 | 7.34 | 1.779 | 13.06 | 0/3 | three simultaneous misreads; repair is one-deep by design |
| 014 | 3.92 | | | 0/1 | `392` -> 3.92 vs 39.2, no second operand; abstains |
| 015 | 15.89 | 1.889 | 30.02 | 3/3 | (repair 4->9 on 1.884, exactly one, 2 dp-exact) |
| 016 | 0.00 | | 0.00 | 0/2 | idle zero; zero->nil rule forfeits (design) |
| 017 | 0.00 | | 0.00 | 0/2 | same |
| 018 | 25.00 | 99.99 | 2499.80 | 2/3 | T absent from OCR (reflective LCD; truth itself read at 5x crop) -> item 3 |
| 019 | 45.22 | 1.754 | 79.32 | 2/3 | T misread 99.32 (7->9, not in repair table) |
| 020 | 10.76 | 1.859 | 20.00 | 3/3 | - |
| 021 | 8.09 | | 15.00 | 1/2 | T not in the photograph at any zoom (photographer's reading) |
| 022 | 30.01 | | 52.49 | 1/2 | L fragment `300|` -> 30.0 (misses by 0.01) |
| 023 | 29.65 | | 51.71 | 0/2 | photograph past recovery |
| 024 | 9.79 | 1.789 | 17.51 | 3/3 | (T derived: read `175` = 17.5 misses by 0.01) |
| 025 | 22.91 | 1.789 | 40.99 | 0/3 | L `22.`, T `4094`, price unchoosable without operands |
| 026 | 53.81 | 1.924 | 103.53 | 1/3 | L truncated `0053,8`; T misread `10359` |
| 027 | 46.86 | 1.859 | 87.11 | 3/3 | (T derived: read `0087/` truncated) |
| 028 | 25.51 | 1.924 | 49.08 | 3/3 | (L derived: read split `0025,5 1`) |
| 029 | 57.00 | 71.18 | 4057.26 | 3/3 | (T derived: glare, no token) |
| 030 | 54.00 | 68.44 | 3695.76 | 1/3 | L `40` (digit dropped); P `844` (leading 6 lost) |
| 031 | 16.80 | 1.939 | 32.50 | 2/3 | T trap: misread 32.58 closes what the truth breaks (discount); repair abstains |
| 032 | 11.38 | 1.759 | 20.02 | 3/3 | - |
| 033 | 42.87 | 1.759 | 75.41 | 0/3 | fragments only |
| 034 | 87.29 | | 160.53 | 0/2 | both truncated at whole frame; legible in photo -> item 3 |
| 035 | 44.96 | | 82.01 | 1/2 | T truncated 82.0 (misses by 0.01) |
| 036 | 12.73 | 1.759 | 22.39 | 0/3 | L misread `1277`; T absent; price unchoosable |
| 037 | 11.05 | 1.834 | 20.27 | 3/3 | - |
| 038 | 44.03 | 1.759 | 77.45 | 3/3 | (T derived: reflection, no token) |
| 039 | 11.47 | 1.839 | 21.09 | 3/3 | - |
| 040 | 8.07 | 1.849 | 14.92 | 3/3 | - |
| 041 | 30.62 | 1.784 | | 0/2 | L `1.bc`; board price unchoosable without operands |
| 042 | 11.34 | | 20.00 | 0/2 | L fragment `34`; T absent |
| 043 | 60.58 | 1.784 | 108.07 | 3/3 | (T derived: read `1080`+`8`) |
| 044 | 25.00 | 68.30 | 1707.50 | 0/3 | L misread 29.00 (5->9); P `68,` dropped; T absent - 87 KB frame |
| 045 | 16.29 | 1.799 | 29.31 | 3/3 | (T derived: read truncated `00293`) |
| 046 | 12.63 | 1.759 | 22.22 | 3/3 | (P derived: read `1059`, 7->0) |
| 047 | 33.16 | 1.759 | 58.33 | 3/3 | (P derived: read `4959`, 1->4) |
| 048 | 10.58 | 1.889 | 19.99 | 1/3 | L `10,5 B` - a B/8 rejoin would yield 10.58 and derive P=1.889; not counted |
| 049 | 5.81 | 1.889 | 10.98 | 0/3 | faintest LCD in the corpus; garbage tokens |
| 050 | 10.54 | 1.929 | 20.33 | 3/3 | - |
| 051 | 15.61 | | 30.42 | 0/2 | T `00.42` (3 lost); L `15.6` (1 lost) |
| 052 | 34.64 | | | 0/1 | L misread `7464` (3->7 at 1.00); legible in photo -> item 3 |
| 053 | 38.88 | | | 1/1 | - |
| 054 | 26.94 | 1.919 | 51.71 | 1/3 | P not read; T: flare + the cent (51.70 computed != 51.71 paper) |
| 055 | 56.05 | | 108.68 | 1/2 | T misread 108.58 (6->5; no third number to anchor a repair) |
| 056 | 38.32 | | 72.00 | 0/2 | L `8.32` (3 lost); T `2.0` garbage |
| 057 | 55.80 | 1.799 | 100.38 | 3/3 | - |
| 058 | 20.02 | 1.969 | 39.42 | 3/3 | - |
| 059 | 54.23 | 1.899 | 102.98 | 3/3 | - |
| 060 | 48.75 | 1.894 | 92.33 | 3/3 | (L derived: read `0048,95`, 7->9) |
| 061 | 33.84 | | 62.40 | 2/2 | - |
| 062 | 20.88 | 1.894 | 39.55 | 3/3 | - |
| 063 | 7.17 | 1.834 | 13.15 | 0/3 | T/L legible in photo, absent from OCR -> item 3 |
| 064 | 46.45 | 1.834 | 85.19 | 3/3 | - |
| 065 | 53.00 | 71.05 | 3765.65 | 1/3 | T `$966`; L absent - 113 KB frame |
| 066 | 15.00 | 69.50 | 1042.50 | 1/3 | T `194588`; L absent - 137 KB frame |
| **sum** | | | | **110/178 (62%)** | |

The 110 decomposes as: 99 tokens+labels+scale+band+cross-check, +1 repair (015), +10
derived (024T, 027T, 028L, 029T, 038T, 043T, 045T, 046P, 047P, 060L). With currency at its
current ~50/66 and fuelKind at 0 by rule, the whole-corpus number after item 2 is roughly
**160-170/261 (~63%)** against today's 53/261.

---

## 4. Is 95% reachable?

**No - and the number that matters is 90.8%, not 20%.**

Three ceilings, in order:

1. **As scored today: 90.8%.** 24 of the 261 cells are forfeited by the product's own rules
   (17 fuelKind, 4 idle-zero) or unwinnable (pump-003 T, pump-054 T, pump-021 T). No
   algorithm passes a 95% gate whose denominator includes them. The gate, as built, cannot
   open - which is a finding about the gate, not about effort.
2. **With every policy stretch: 97.7%.** Badge-settled fuel kinds (~8 of 17), a pump-scoped
   zero return with idle refusal (4). Reaching it requires reading *everything else*
   flawlessly - every dirty LCD, angled night shot, and zero-padded comma display in the
   set. Arithmetically open; practically a claim of perfection on 66 photos.
3. **The human ceiling on the numeric columns: ~97%.** 4-6 of the 178 numeric cells sit in
   photographs that do not carry them (pump-021 T, 022 L, 023 L+T, plus the two
   contradiction cells). A shipped algorithm reading everything a human can is years of
   corpus growth away from being *proven*; the realistic excellent pipeline (items 2-4
   landed) lands **~80-87% numeric, ~75-80% on the full 261**.

So the 95% coverage bar is the wrong shape for this mode, and the product has three honest
options:

- **Re-scope (recommended).** The bar's *intent* - never a wrong fill-up - is precision, not
  coverage. Express the gate as: precision ~100% (zero confident-wrong values; the four
  named failure modes stay empty and every scale tie abstains), refusal behaviours pinned
  (idle pump, unreadable photo, factor-of-ten tie), *then* a coverage floor on the cells the
  mode may produce (~80-85%). On that metric items 1-3 plausibly pass within a phase. A mode
  that pre-fills four fills out of five and never writes a wrong digit is worth shipping;
  calling that "95%" was never what the 95% was for.
- **Keep it off permanently.** Defensible: the receipt path (82% and rising) plus the two
  doors carry the product, J4 remains typed, and nothing in the corpus says pump capture is
  worth a model project. The mode has been off since it was written at no measured cost.
- **Spend for the ceiling.** Items 4-5 chase the last ~10% toward the human floor. That is a
  multi-week model programme for one screen - justified only if the re-scoped mode ships and
  users actually capture pumps (the J4 metric, pump-photo share of captures, exists to
  answer exactly that before the spend).

What the product should do with a mode that cannot pass its own gate: fix the gate (item 1),
land the free 60 points (item 2), measure the crop work (item 3), and only then re-ask the
ship question with an honest number. Do not lower the bar to open it.

## 5. What I would not do

- **Chase the corpus number.** No tolerance loosening (0.005 is what a cent of money needs),
  no "correcting" a volume to close the arithmetic (pump-010's gap is real), no treating
  derivation as reading (pump-054's cent is the permanent counter-example).
- **Trust Vision's confidence.** pump-004 misreads at 1.00; thresholding on it is dead on
  arrival, and no remote-tuned `ocrConfidenceThreshold` resurrects it.
- **Trust the cross-check as correctness.** It is scale-blind and swap-blind by construction,
  and pump-031 adds a third blindness: a misread can *accidentally restore* the consistency
  a discount legitimately breaks. It is a consistency check and a candidate picker; nothing
  more.
- **Ship the cloud VLM as the pump answer.** Its measured pump edge (31/46) is within noise
  of the deterministic ladder on the same fixtures (~28/46), and its failure shapes (silent
  swaps, scale shifts, non-determinism) are the ones this mode exists to avoid. Inbox
  second opinion at most.
- **Infer fuel kind from a pump photo.** The rule is right; the 17 CSV cells it costs the
  gate are the gate's problem, not the rule's.
- **Derive-and-lock.** Derived fields are suggestions with a visible residual. Locking them
  reintroduces the confident-wrong-value class under a new name.
- **Train on this corpus.** It is the test set. A model that memorises it turns the ratchet
  into a lie.
- **Vendor-specific parsers.** One forecourt already contradicts every vendor-level
  generalisation (separator, board order, grade set).
- **A 5-litre volume floor.** pump-004 is a real 12.38 L, pump-049 a real 5.81 L, pump-014 a
  real 3.92 L, and the pumps themselves print `Vmin 2 LIITRIT`. The floor is 2 L, and small
  fills are data, not noise.
- **pgrep -f anything.** (Obeyed: no `git`, no builds, no tests, no Vision runs - another
  agent is implementing on this machine.)

## 6. What I actually looked at

**Photographs: 18 opened and read by eye.** Directly via the Read tool (JPEG/PNG):
pump-003, 004, 005, 006, 008, 009, 010, 021, 025, 034, 052, 053, 057, 058, 063. HEIC does
not read directly, so I converted five to JPEG with `sips` into a temp directory (fixtures
untouched, nothing written into the corpus) and viewed pump-001, 012, 016. That covers all
fifteen the brief highlighted, plus 012/016/021 for the glare and idle classes. Where this
report says "legible in the photo" (063's 13.15/7.17, 052's 34.64, 034's 160.53/87.29,
018's five-x-crop total) it is because I read the digits myself in the image; where it says
"past recovery" (021/022/023 totals) it is because I could not read them either.

**Text, in full:** `diagnostics/pump-ocr-dump.txt` (all 66 blocks + summary),
`Spike/ReceiptSpike/fixtures/pump/README.md` (696 lines), `expected.csv`,
`docs/EXTRACTION.md` (533 lines), the spike's `OCR.swift`/`Parser.swift`/`main.swift`,
`FuelExtractor.swift`, `NumberScanner.swift`, `FuelExtractorLabelValue.swift`,
`DigitRepair.swift`, `CorpusABScorer.swift`, `AccuracyRatchetTests.swift`,
`PumpPhotoGate.swift`, `FuelPriceBands.seed.json`, and the pump-relevant hits of
`TASKS.md`/`PHASES.md`/`JOURNEYS.md`/`PRACTICES.md` (P2.7, P4.12, P4.13, RV.48, RV.51,
RV.57, the launch triage).

**Not done, per the brief:** no `git`, no `swift build`/`test`, no `xcodebuild`, no
`swiftlint`, no edits to `TASKS.md`/`agents/briefs/`/any `expected.csv`/any fixture. Sibling
RV.58 reports in this directory (pro/qwen/vision) were not read; this analysis is
independent. One file written: this one.
