# RV.58: what is the right algorithm for a pump display, and is 95% reachable?

Research and design. One question, answered as a ranked list of directions, then
three verdicts. No code changed.

## The number that frames everything

The gate is `PumpPhotoGate` (`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift`):
`measuredHits / measuredTotal = 53 / 261 = 20.3%` against a `0.95` threshold.

The 261 is not one thing. It decomposes as:

| cell class | count | how hard |
|---|---|---|
| `liters` + `unitPrice` + `total` (the three numeric fields, blanks skipped) | 178 | the actual problem |
| `currency` (marker lookup, near-free) | 66 | mostly solved already |
| `fuelKind` (only where a paired receipt or a legible badge settles it) | 17 | mostly blank; never inferred from a pump |

Do the arithmetic on the gate, and the conclusion is uncomfortable before any
algorithm is discussed: **to reach 95% you need 248 hits. Even granting all 66
currency and all 17 fuelKind cells as free hits (83 easy cells), the numeric
fields must land 165/178 = 92.7%.** The "easy" cells do not dilute the problem
enough. The gate, as composed, is effectively a 93% bar on the three fields
where the measured deficit lives. That fact is the whole answer to "is 95%
reachable", and it is stated plainly in the final section.

A second number that matters for reading the rest: the `pump-ocr-dump.txt`
summary says `Ground-truth field accuracy: 4/178 (2.2%)`. That is the
**ReceiptSpike** harness running the receipt-tuned Spike parser
(`Spike/ReceiptSpike/Sources/ReceiptSpike/Parser.swift`), not the app's
`FuelExtractor`. The app's pump path is the 53/261 above. The dump's per-fixture
OCR lines are the evidence that matters; its bottom-line score is a stale parser.

## The finding that reorders the brief

Three prior analyses of the receipt corpus concluded recognition was not the
bottleneck there. On pumps the dump shows recognition *is* lossy, but not in the
way "recognition is the bottleneck" implies. Read the dump for `pump-001`:

```
[1.00] SUMMA
[1.00] 12522      <- truth 125.22
[1.00] LIITRIT
[1.00] 67.00      <- survives intact
[1.00] 1869 HIND/1L   <- truth 1.869
```

Vision **finds every digit at confidence 1.00**. What it drops is the decimal
point, per field, not per image. That is not "the digits are wrong" in the
general sense, and it is not fixable by a better *reader* alone, because the
loss is deterministic on a seven-segment dot that Vision's text model treats as
noise. The immediate consequence is a code-level one the brief does not list and
which is cheaper than any of its six directions:

**`NumberScanner.decimals(in:)` (`ios/Sources/TankbookCore/Extraction/NumberScanner.swift:13`)
requires a `[.,]` separator and therefore silently discards `12522`, `208863`,
`8525`, `2450` and every other separator-less number the dump shows.** The pump
path is not just "Vision loses the dot"; the tokenizer then throws the number
away entirely. That is why the Spike parser is at 2.2%: the receipt-shaped
number scanner is a wall the pump numbers never cross. This is the single most
important finding in this note, and it is a ten-line fix that precedes every
direction below.

The same receipt-shape assumption breaks the rest of the pump path.
`FuelExtractor.extract` with `source == .pump` is *the receipt parser* with two
switches (`ios/Sources/TankbookCore/Extraction/FuelExtractor.swift:33` skips
fuel kind, `:75` enables `DigitRepair`). Its operand pairing needs an `x`/`×` or
a marker, its `loneMarkers` needs an `L` or a `/L` label, its total-finder needs
a `ИТОГ`/`SUMMA` label. A pump writes three bare numbers under three labels in a
foreign layout, with no operand operator and a decimal point that is often
absent. The pump problem is **the parser is receipt-shaped**, not "the OCR is
bad". Everything below is evaluated against that.

---

## Ranked list of directions

Each entry: what it is; the layer it acts on; expected gain counted per fixture
against the 66 photographs (the folder holds 66, not the 64 the brief cites –
`pump-001` … `pump-066`); cost including iPhone 12 (the floor device) runtime;
wrong-answer risk and what abstains instead; whether it generalises past these
66.

### 1. Pump-shaped number tokenizer + decimal-scale reconstruction, pinned by the currency price band

**What it is.** Two deterministic changes that are really one: (a) a pump number
scanner that emits *every* digit run as a candidate value with unknown scale –
`12522` becomes "the integer 12522, scale unknown" instead of being dropped; (b)
a scale-assignment pass that, for the three fields, searches divisors `10^0..10^3`
and rejects every assignment that a `liters × unitPrice == total` relation plus
a currency-keyed price band does not survive. This is the brief's direction 1,
with the arithmetic demoted from "the solver" to "a filter".

**Layer.** Recognise → resolve boundary, i.e. the tokenizer, plus resolve (uses
the `SCHEMA.md` fuel price bands). Pure functions over `[OCRLine]`; no Vision, no
network.

**Gain, per fixture.** The dump lets me count the cells whose digits are correct
and whose *only* defect is a lost separator (SEP cells). Reading fixture by
fixture: `pump-001`(price,total), `002`(liters,total), `003`(all three), `005`
(liters,total), `007`(liters), `008`(price), `009`(all three, zero-padded),
`011`(liters), `014`(liters), `019`(price), `020`(price,total), `024`(price),
`027`(price), `028`(price,total), `029`(liters,price), `031`(price,total),
`032`(total), `037`(liters,price), `038`(price), `039`(liters,total), `040`(all
three), `041`(price), `043`(price), `045`(price,total), `046`(total),
`047`(liters,total), `050`(total), `053`(liters), `054`(liters,price),
`057`(liters,total), `058`(total), `059`(all three), `060`(total),
`062`(liters,price), `064`(price) – **about 55 of the 178 numeric cells**.
Add the bare-integer cells that are already correct as integers and only need a
tokenizer that accepts them (`pump-004` price 243, `pump-006` liters/price/total)
– about 4 more. So this direction alone is the difference between 2.2% and
roughly a third of the numeric corpus.

**Wrong-answer risk and what abstains.** The arithmetic is scale-invariant and
swap-blind, so unconstrained reconstruction is the 12-solutions trap the README
documents for `pump-003`. The pin that collapses 12 to an answer is the
currency-keyed price band (KZT 180–320 → price is 245.0, not 24.5 or 2450). The
**volume** scale is *not* pinned by the band: `pump-003` leaves `85.25 L` vs
`8.525 L`, a factor-of-ten that survives every automatic filter and needs tank
capacity or the user. So the rule is: price and total scale are decided by band +
product; the volume scale is decided only by band-adjacent plausibility plus the
vehicle's tank capacity, and where that does not settle it the field stays `nil`
(the README's own "small fills happen" note, `pump-004` at 12.38 L, forbids the
"nobody buys 8.5 L" tie-break). Nothing here is allowed to guess a volume.

**Cost.** A day of deterministic rules plus the band pack (direction 2). Runtime
on an iPhone 12: a divisor search over a handful of candidates is microseconds;
the cross-check is already O(n²)-ish and untouched.

**Generalises?** Yes – it is device-agnostic arithmetic plus a currency-keyed
data table. Every pump make in the corpus that loses a separator is covered, and
a new country is covered the moment its band row exists.

### 2. Wire the fuel price band pack into the pump path

**What it is.** Direction 1's pin is `SCHEMA.md → Fuel price bands`, and the
ladder that uses it is currently dead: `resolveUnmarked` begins
`guard let provider = bandProvider else { return (nil, nil) }`
(`FuelExtractor.swift:225-228`) and nothing injects a `bandProvider`
(`docs/EXTRACTION.md` notes this as the largest remaining receipt block). Making
the band live is a data + wiring deliverable, not new extraction logic, and it
is a hard prerequisite for direction 1 to do more than enumerate candidates.

**Layer.** Resolve, steps 3/4 of the ladder, plus the reference-pack delivery
(`GET /reference/fuel-price-bands`, bundled seed) that already exists on paper in
`SCHEMA.md:684`.

**Gain, per fixture.** Not additive in the same way: it converts direction 1
from "filter to 12 solutions" to "filter to 2", and it independently fixes the
receipt swap class (a pair resolved by band instead of abstained). Counted
against the pump corpus it is the difference between direction 1 scoring the
price/total SEP cells and scoring none of them, because a scale whose pin is
absent is a scale the parser must refuse.

**Wrong-answer risk.** The band's own spec is explicit: unknown fuel kind means
no band, bands rank never veto, and a pump never infers fuel kind – so the band
cannot be used to pick a grade. A band keyed by currency only (not fuel kind and
era) is the LPG-at-23.99 mistake already documented. The safe shape is
already written; this direction is "ship the spec", not "invent one".

**Cost.** Server curation is coarse (quarterly, "separate 30 from 100"), the seed
pack is a few hundred KB, and device cost is a table lookup. iPhone 12 runtime:
negligible.

**Generalises?** Entirely – it is reference data, and it is the same mechanism
the receipt path needs regardless of pumps.

### 3. Seven-segment digit recognition proper (Core ML, synthetic-trained)

**What it is.** The brief's direction 3, and the one `docs/EXTRACTION.md` already
endorses ("Pump displays: this is where training is actually the right tool"). A
narrow classifier – ten digits plus blank and decimal point – trained on
synthesised seven-segment glyphs with glare/blur/perspective/LCD-ghosting
augmentation, run via Core ML, emitting per-digit posteriors. The corpus's 66
photos stay a held-out test set precisely because nothing was trained on them.

**Layer.** Recognise (replaces Vision for the digits), with a detector/segmenter
front-end that first localises the digits and groups them into fields – which is
itself a layout problem direction 4 has to solve anyway.

**Gain, per fixture.** It targets the class direction 1 cannot touch: digits
that are *wrong*, not merely scaled. Counted per fixture: `pump-004` (total
`1408` for 3008 at confidence 1.00), `pump-007` (total `4553.46` for 4593.46),
`pump-013`/`pump-015` (the 9-as-4 and its repair), `pump-019` (`99.32` for
79.32), `pump-025` (`1889` for 1789), `pump-026` (`103.59` for 103.53),
`pump-047` (`4959` for 1.759), `pump-052` (`7464` for 34.64), `pump-055`
(`108.58` for 108.68), `pump-060` (`48.95` for 48.75) – **about 15–20 cells**,
on top of deterministically emitting the decimal point that direction 1 must
otherwise reconstruct. It also upgrades `DigitRepair` (already shipped,
`ios/Sources/TankbookCore/Extraction/DigitRepair.swift`) from a fixed confusion
table to a posterior-ordered candidate list.

**Cost.** The honest one. It is a real ML engineering project: synthetic data
generation, training, Core ML conversion, a detector, calibration, and a
validation story that survives the "66 images is the test set" problem by virtue
of synthetic training. iPhone 12 runtime is the cheap part – a few-hundred-KB CNN
runs in single-digit milliseconds, offline, no gateway, no image leaving the
device, which is also the property that keeps it legal under hard rules 1 and 11.

**Wrong-answer risk.** Low for the digit *classes* it models, but a classifier
does not remove the interpretation failures: it cannot fix a value that is not on
the photograph, a preset fill whose arithmetic does not close, or a
previous-customer display. A per-digit posterior is a *stronger suggestion*, not
a fact (hard rule 13), and the cross-check + band still own correctness.

**Generalises?** Better than any other direction – synthetic training means it is
not pinned to these 66 makes, and it composes with the repair rule. It is also
the most expensive direction and the one to do last.

### 4. Find the LCD, then read it (region detection, crop, upscale)

**What it is.** The brief's direction 2: detect the display panel and recognise
only that region, upscaled, rather than handing Vision a whole forecourt.
`docs/EXTRACTION.md` records image preparation and region re-recognition as
no-ops *for receipts* and explicitly untouched for pumps, so this is genuinely
unattempted on this corpus.

**Layer.** Recognise (region-of-interest), and indirectly resolve (removes the
advertising that feeds failure mode 3 – `0,5-0,7l` reading as 0.700 litres).

**Gain, per fixture.** The dump is the evidence, and it is *not* what the "the
surroundings confuse Vision" hypothesis would predict. Vision already reads the
LCD digits correctly (modulo separators) at full frame; the surroundings appear
as *separate lines* (`Wrapper ja jook`, `Hot dog`, `Red Bull`, `SOAPBÜX RACE`,
`s/kWh`, promo `1,5`/`0,5`) that poison the *parser*, not the LCD recognition.
Cropping would not have recovered `pump-003`'s separators (Vision simply does not
emit a seven-segment dot) nor `pump-004`'s wrong digit at 1.00. It would help
the genuinely faint or dirty displays (`pump-049`, `pump-058`) and the reflective
totals (`pump-018`), and it is the necessary front-end for direction 3 – **about
5–10 cells directly, plus it removes the parse-noise that costs a few more**.

**Cost.** LCD-panel detection across six manufacturers, including a video screen
(`pump-008`) and glare-washed panels, is itself a small vision problem, not a
"bright rectangle with a fixed aspect" heuristic. Moderate. iPhone 12 runtime: a
second Vision pass on a crop, tens of milliseconds.

**Wrong-answer risk.** Low by itself; its failure mode is "wrong region", which
degrades to the current whole-frame path. But it is best treated as an enabler
for direction 3, not a standalone lever.

**Generalises?** Weakly on its own – the detector would be tuned to the makes in
the corpus. Its real value is generic noise removal for any subsequent reader.

### 5. The paired-receipt path (a product answer, not an algorithm)

**What it is.** The brief's direction 4. More fixtures now carry a matching
paper receipt than the brief's "five" – `pump-001`, `002`, `018`, `019`, `034`,
`044`, `054`, `057`, `065`, `066` are all documented pairs. When a receipt exists,
read the receipt (82% and climbing) instead of the pump (20%).

**Layer.** None – it is routing, decided before extraction: "this fill has a
receipt, use it". The pump becomes the fallback, not the primary.

**Gain, per fixture.** It does not add pump cells; it *removes* pump captures
from the pump path entirely, converting their denominator to the receipt
denominator. It is the single most effective "accuracy" move available, because
it is a different, easier problem wearing the pump's name.

**Cost.** Detect the pairing (same station, same day, matching amount) and
surface "this receipt and this pump are the same fill". Small.

**Wrong-answer risk.** Pairing two documents wrongly is the risk; the failure is
contained because the receipt's own parse plus the cross-check still runs, and a
mismatched pair degrades to two independent captures.

**Generalises?** This is the honest framing of the product question: the pump
mode's value proposition – read a fill when there is no paper – is thin precisely
where the paper exists, and the paper is always the better document when it does.

### 6. Refusal and previous-customer detection (correctness, earns no cells)

**What it is.** Two behaviours the corpus demands and the brief's direction 5
rests on: (a) an idle pump (`pump-016`, `pump-017`, all-zero readout) must
refuse and offer the manual door, never produce a 0.00-litre fill; (b) a display
holds the previous customer's transaction until the next fill starts, so the
numbers on a display are not necessarily the user's own.

**Layer.** Resolve/hand-off, and it is a hard-rule obligation (13, 15), not an
accuracy optimisation.

**Gain, per fixture.** Zero cells, by design – it *deliberately misses* the four
`0.00` cells on the two idle pumps because the correct output is `nil`. This
matters for the gate arithmetic in the final section: those four cells are scored
against a value the app is supposed to refuse, so a correct parser is *punished*
for them under the current denominator.

**Cost.** Trivial. iPhone 12 runtime: nothing.

**Generalises?** It is invariant and belongs in every future pump parser.

---

## Is 95% reachable?

**No. The ceiling is roughly 60–70% on the numeric fields, i.e. about 65–75%
overall, and the gap to 95% is not a tuning problem – it is structural.**

The argument, in three steps.

1. **The gate's denominator forces a 93% bar on the hard fields.** 95% of 261 is
   248. Even if all 66 currency and 17 fuelKind cells were free (83 easy hits),
   the numeric fields must reach 165/178 = 92.7%. The easy cells do not dilute
   enough.

2. **The numeric fields cannot reach 92.7%.** The 178 cells break into classes
   counted from the dump:
   - SEP (digits correct, separator lost) – about 55, recoverable by directions
     1–2, but with a residual factor-of-ten volume ambiguity that only tank
     capacity or the user settles.
   - bare integers – about 4, recovered by the tokenizer.
   - misread digits – about 15–20, recovered by direction 3 and `DigitRepair`,
     but not by anything cheaper.
   - already correct – about 25.
   - **photographically unrecoverable** – `pump-021/022/023` (sun-glared Wayne
     displays whose litres and totals exist only in the photographer's memory, 6
     cells), the idle-pump `0.00` cells the app must refuse (4 cells), preset
     truncation (`pump-010`), and the off-by-a-cent recompute (`pump-054`) – about
     12–15 cells that no algorithm can score because the correct answer is
     "abstain" or "ask the user".

   Optimistically summing the recoverable classes gives 55 + 4 + 18 + 25 ≈ 100,
   with overlaps; a hero-effort ceiling is ~110–125/178, i.e. **62–70% numeric**.
   Reaching 92.7% would require near-perfection on the SEP class *and* the
   misread class *and* no factor-of-ten ambiguity anywhere, which the corpus's
   own README refutes in writing.

3. **A 95% field average is also the wrong gate for the actual harm.** A factor-
   of-ten volume error is invisible on the Confirm screen and corrupts
   consumption for the life of the vehicle (the README's `pump-003` note, hard
   rule 13). A gate that tolerates 5% of fills carrying such an error is not
   "95% safe", it is "5% corrupt". The correct safety property is **zero
   factor-of-ten volume errors** and **every value a visible, editable pre-fill**,
   which is an entirely different, and reachable, bar.

**What the product should do with a mode that cannot pass its own gate.** Keep
it off, and change what "worth shipping" means. Three concrete moves:

- **Stop counting currency and fuelKind toward the pump gate**, or better,
  redefine the gate from "95% average field accuracy" to "zero factor-of-ten
  volume errors, and never write a value the user has not seen" – the property
  that actually protects the user. The current denominator actively misleads:
  it makes the mode look healthier than it is (currency pads it) while scoring
  against values the app is *supposed* to refuse (the idle-pump `0.00` cells).
- **Ship the cheap, safe part as a pre-fill**, not the full extraction: a pump
  capture that reliably fills currency and a readable volume, abstains on the
  rest, and never produces a confident wrong number is a genuine "head start"
  under hard rule 15. That is worth shipping well before 93% numeric.
- **Route pump captures to the paired receipt where one exists** (direction 5),
  and to the ordinary manual form otherwise. The user loses nothing when the
  mode is off; the honest framing is that typing three numbers is a peer path,
  not a failure, and a 20% pre-fill that must be re-typed anyway is no better
  than the manual door.

## What I would not do

- **Not a general small language model or a second cloud vision sweep.** The pump
  problem is optical (a lost decimal point, a wrong segment), not linguistic, and
  the P4.12 cloud model was already measured at 31/46 on pumps with five silent
  swaps, a decimal shift, and non-determinism (`docs/EXTRACTION.md`). Trusting a
  model that passes the cross-check while swapping operands or shifting decimals
  is precisely the failure the pump gate exists to prevent.
- **Not "correct" a volume to make the cross-check close.** `pump-010`'s preset
  fill rounds 13.17 × 75.95 = 1000.26 to a printed 1000.00; the honest record is
  the displayed 13.17 and the exact 1000.00, absorbed by CHECK 3's tolerance.
  A parser that rewrites the volume to close the arithmetic stores a wrong
  fill-up forever.
- **Not infer fuel kind from a pump, ever.** The grade badges belong to every
  nozzle, not to the fill; `pump-001` OCRs `95` and the fill was diesel. This is
  already normative and should stay a hard "do not".
- **Not threshold on Vision confidence.** `pump-004` is wrong at confidence 1.00,
  so `ocrConfidenceThreshold` cannot be a trust signal, at any setting. The
  cross-check is the only consistency signal, and even it is blind to swaps and
  scale.
- **Not rebuild `DigitRepair`.** It is already shipped and correct for its job;
  its current limitation is that it never fires because direction 1's tokenizer
  drops the very numbers it would repair. Fix the tokenizer first, then let the
  repair run.

## What I actually looked at

I attempted to open the photographs (both the `.heic` and the `.jpg`/`.png`
fixtures) with the image reader in this session. That is the point of the brief,
and I tried first. The model backing this session has **no image input**, and
the `.heic` files additionally come back as binary; so I could not inspect a
single pixel, and I am not going to pretend otherwise.

Everything above is therefore grounded in text, and only in text:

- `Spike/ReceiptSpike/fixtures/pump/README.md` – read in full, and it is the
  single most valuable document as the brief says (the `pump-003` scale
  retraction, the 9-as-4 repair, the preset-fill trap, the previous-customer
  finding).
- `diagnostics/pump-ocr-dump.txt` – read in full, both the per-fixture Vision
  output and the summary table.
- `Spike/ReceiptSpike/fixtures/pump/expected.csv` – read in full; used to count
  the 178 numeric / 66 currency / 17 fuelKind split and the blank cells.
- `Spike/ReceiptSpike/Sources/ReceiptSpike/{OCR,Parser}.swift` – to see what the
  2.2% parser actually does.
- `ios/Sources/TankbookCore/Extraction/{NumberScanner,FuelExtractor,DigitRepair,
  FuelExtractorLabelValue}.swift` and `Config/PumpPhotoGate.swift` – to see the
  app's actual pump path and gate.
- `docs/EXTRACTION.md` and `docs/SCHEMA.md` (the fuel price bands section).

Two caveats that follow from working off the dump rather than the pixels:

- The cell taxonomy (SEP / bare-integer / misread / unrecoverable) is a
  **classification of Vision's text output**, not of the images. A digit I count
  as "misread" is one where the dump disagrees with `expected.csv`; a digit I
  count as "separator lost" is one where the dump's digits are a prefix/suffix
  of the truth at a different scale. Where a value is absent from the dump I
  treat it as "not recovered", not as "not on the photograph" – the difference
  matters, and only looking at the image could settle it.
- The folder holds **66** fixtures, not the 64 the brief cites; `pump-065` and
  `pump-066` are present and are in `expected.csv`. I counted against all 66.
