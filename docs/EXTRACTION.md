# Extraction: image to pre-filled fields

The single authority for **how a photo becomes a set of suggested field values** – the
stages, what each one is allowed to decide, how the arithmetic cross-check is interpreted,
and where a trained model does and does not belong.

**What this doc does NOT own**, so there is one place for each thing:

| Question | Owner |
|---|---|
| Which of two unmarked operands is the price (the resolution ladder, price bands) | `SCHEMA.md` -> Fuel price bands |
| Whether an on-device LLM is in the pipeline at all; capability tiers | `VISION.md` -> capability tiers |
| The wording of any message this pipeline causes | `ERRORS.md` |
| The `/extract` HTTP contract and its device-side budget | `API.md` |
| Ground truth, per-fixture findings, accuracy scores | `Spike/ReceiptSpike/fixtures/*/README.md` |

Conflict rule as everywhere: the more specific doc wins, and the stale one gets fixed in
the same change.

## The one-sentence version

Vision reads the characters; **the hard part is deciding what each number means**, and every
value this pipeline produces is a suggestion the user can overwrite forever (hard rule 13).

## Measured reality, 2026-09-05

| class | score | note |
|---|---|---|
| receipts | **188/220 cells (85%)** | 33 of 48 fixtures resolve every asserted cell (69%) |
| fiscal | 5/5 | |
| screenshots | 35/40 | |
| pump | **24/178 numeric cells** | committed 24, correct 24 - see the gate note below |

Receipts were **101/210 (48%)** on the morning of 2026-09-04 and the corpus has only grown since,
so the movement is the parser, not the fixtures (`Spike/ReceiptSpike/fixtures/high-water.json`
carries the per-change breakdown). **The total column now misses nothing**, and the class holds no
confident-wrong value: every remaining miss is an honest abstention.

**The pump number is scored differently on purpose (B1, 2026-09-04).** The old pump mark - "53/261,
20%" - was a recall average over a denominator that mixed the 178 numeric cells the mode exists to
read, a near-free `currency` marker lookup (66 cells), and `fuelKind` (17), which this document
says a pump parser must never produce. Worse, recall scores a correct `nil` as a miss and a
confident-wrong value as a hit - hard rule 13 inverted - and the two idle pumps' ground-truth zeros
made it reward logging a zero-litre fill. `PumpPhotoGate` now measures **precision on committed
numeric fields plus a coverage floor**: today 24 of 24 committed cells are correct (100% precision)
at 13% coverage, so the mode stays off, below the 0.60 floor.

**Two things measured and closed, so they are not re-proposed:**

- **Image preparation and recognition knobs are no-ops for receipts.** Every operand the parser
  misses is already recognised at confidence 1.00; the losses are in role assignment, not reading.
- **Cropping a pump display's number window and re-reading it is not an accuracy stage**
  (`diagnostics/RESEARCH-pump-B3-crop-experiment.md`, measured over all 66 pump fixtures). Of 148
  separator-less digit runs, a crop recovers a separator on 19 and the *correct* value on only 7 -
  while producing ten wrong ones, several off by a factor of ten. Upscaling makes it strictly
  worse (7 correct at 1x, 5 at 2x, and 4 outright regressions), because interpolating a
  seven-segment glyph invents edges that were never photographed. A 1x crop is usable only as a
  candidate generator for the scale search, never as a value source.

## Measured reality, 2026-08-26

Scored by `AccuracyRatchetTests` over `Spike/ReceiptSpike/fixtures/`, field-by-field against
hand-checked ground truth. These are the recorded high-water marks; the live score is at or
above each. The screenshots mark was raised 7/24 -> 18/24 on 2026-08-27 by P2.12 (the
four-outcome cross-check and the `L`/`Gab.` discriminator); receipts, pump and fiscal are
unchanged by that task.

| Class | Fixtures | Fields resolved | Where it fails |
|---|---|---|---|
| `receipts` | 35 | 45/93 (48%) | Interpretation. Vision reads the glyphs at confidence 1.00 |
| `screenshots` | 8 | 18/24 (75%) | Interpretation. The source is rendered text - there is nothing to misread |
| `pump` | 17 | 1/46 (2%) | **Recognition.** Seven-segment glyphs, glare, and forecourt adverts in frame |
| `fiscal` | 2 | 1/3 | Text layer where there is one |

**Read the split, because it decides everything downstream.** On receipts and screenshots the
characters are already correct and the parser assigns them wrongly. On pump displays the
characters themselves are wrong. These are two different problems and they do not have the
same solution.

## The pipeline

```
  image
    |
 1. acquire      downscale, orient, (cloud path only) JPEG-compress
    |
 2. recognize    Vision VNRecognizeTextRequest -> [OCRLine] (text + normalised box)
    |
 3. classify     receipt | pump | screenshot | fiscal  -> ExtractionSource
    |
 3b. clean       ReceiptNoiseFilter tags the lines that can carry no value
    |            (RV.48; the value finders read the tagged-clean subset,
    |             the EVIDENCE gates keep reading the raw lines)
    |
 4. resolve      per-field role assignment  (the bulk of the logic)
    |
 5. cross-check  liters x unitPrice vs total -> lock | reconciled | mixed | mismatch
    |
 6. hand off     ExtractionMeta + per-field confidence -> Confirm screen pre-fill
```

Stages 3 to 5 are pure functions over `[OCRLine]` with no Vision and no network, which is why
they are unit-testable and why `FuelExtractor` takes `[String]` as a convenience overload. Keep
it that way: **a decision that can only be reached through an image cannot be regression-tested.**

### 1. Acquire

Full resolution into Vision. Downscaling changes what OCR sees, so a downscaled fixture measures
a different problem than the app has - which is why the corpus keeps originals.

Compression belongs only to the cloud path, where `API.md` sets the envelope cap and the 3 s
per-attempt budget.

### 2. Recognize

`VNRecognizeTextRequest`, available since iOS 13, so nothing load-bearing sits above the iOS 18
floor (`VISION.md`). Output is `OCRLine`: text plus a **normalised bounding box**.

The box is not decoration. Three rules in the current parser are geometric and cannot be
expressed on text alone:

- **Reading order is not document order.** Vision emits a value before its label often enough
  that array position cannot be trusted. The total-finder pairs a label with the nearest
  same-baseline value to its **right** (`abs(midY - midY) < 0.012`), and only falls back to
  array adjacency.
- **A labelled column is a column.** `Цена | Кол. | Сумма` is resolved by comparing each
  number's `midX` against the header's `midX`, not by word order.
- **A `/L` label names the value directly below it**, in the same column, never the one above -
  where the row's sum lives.

### 3. Classify

`ExtractionSource` (`.receipt`, `.pump`, `.screenshot`, `.fiscal`) changes what is allowed to be
inferred. Today the one hard consequence is:

**Never infer fuel kind from a pump photo.** A multi-product pump shows the labels of *every*
nozzle it has. `pump-001` OCRs to `miles+`, `miles`, `miles+`, `miles`, `95` and the fill was
diesel. A visible grade is evidence the station **sells** it, never that this fill used it. The
authority is the receipt line, or the person who filled the tank.

### 3b. Clean (RV.48, 2026-09-04)

A fuel receipt prints far more numbers than it prints facts, and until this stage existed every
one of them was a candidate operand. The cost was not a missed field, which is recoverable, but a
**confident wrong one**, which hard rule 13 forbids outright. Four fixtures measured it:

| fixture | returned | from the line | how |
|---|---|---|---|
| receipt-023 | volume `32986034` | `wNLL32986034/90` | the lone-marker volume path |
| receipt-046 | volume `10180925` | `Reg.kood 10180925, KMKR nr• EE1003L` | the lone-marker volume path |
| receipt-041 | volume `5.000` | `2X5LT6` - a card **authorisation code** | it parses as the operand pair `2 X 5L`, marker and all |
| receipt-044 | volume `1.000`, kind `lpg` | `1 ед.=1 литр для нефтепродуктов/суг` | the footnote states the document's units, and `суг` reads as LPG |

`ReceiptNoiseFilter` classifies a line into one of five witnessed noise classes - Russian fiscal
identifiers, Estonian registration, card-terminal furniture, unit-convention footnotes, contact
details - or leaves it alone. Two properties are load-bearing and neither is optional:

**It tags, it never deletes.** The raw OCR text is kept in full. It is the evidence that lets a bad
parse be re-examined, and the four named failure modes below are pinned to it.

**The evidence gates keep reading the RAW lines.** `CurrencyDetection` resolves a Russian receipt's
currency precisely *from* its `ИНН`, `ККТ` and `ОФД` lines - the very lines this filter calls
valueless. Cleaning before that gate would delete the evidence the gate runs on, so `FuelExtractor`
passes raw lines to currency and date detection and cleaned lines only to the value finders.

**Two layers, because neither covers the other's cases.** Alongside the line classes, a unit marker
must be a **standalone token**: `2X5LT6`'s `L` is followed by a letter, and `wNLL32986034`'s is
preceded by one. But `EE1003L` ends in a token-final `L` and passes that test, so it needs the
`Reg.kood` line class instead. Removing either layer puts a wrong volume back.

**What must never be tagged**: the product line, the operand line, the total label and its value,
the date, the discount line, a stranded marker line (`л =5380.00`), the `Цена за ед.` reference
block - which is the *only* source of receipt-023's and receipt-044's unit price - and above all
**bare short-decimal value lines**, because a bare `5380.00` IS the total on receipt-015. The
bare-identifier rule is bounded at 14 digits for exactly that reason.

### 4. Resolve

Per field. Each returns `nil` rather than guessing.

**Volume and unit price** are the dangerous pair and their ladder is normative in
`SCHEMA.md` -> Fuel price bands. Not restated here. The one thing worth repeating is *why* it
exists: `a x b == b x a`, so the arithmetic cross-check **cannot** detect a swapped pair. A
parser that guesses wrong stores 99.4 L at 43.61 instead of 43.61 L at 99.40 and computes
consumption wrong by 2.3x with every check green.

**Total** is modal over labelled candidates, preferring the primary labels (`ИТОГ`, `TOTAL`,
`KOKKU`, `SUMMA`), with VAT, rounding, change and "received" lines excluded by name.

**Currency, date, fuel kind** are marker lookups. Two traps already paid for:

- A fuel abbreviation must be followed by a non-letter. `ДТ` inside `ПОДТВЕРЖДЕНА` is not diesel.
- A bare `L` inside a word (`Tallinn`, `ЛУКОЙЛ`) is not a volume marker.

**A printed zero is not a value.** B2B contract fuel cards print `30.61 X 0.00` and `ИТОГ 0.00`
under "Цена определена договором". Storing 0.00 is a confident wrong value and it biases stats
silently - cost/km keeps the fill's odometer span in the denominator while contributing nothing
to the numerator. Zero totals and zero unit prices are returned as `nil`.

### 5. Cross-check: four outcomes, not two

`liters x unitPrice` against `total`. **The confirm-screen lock has historically treated this as
a boolean, and that is wrong.** There are four outcomes:

| Outcome | Condition | Behaviour |
|---|---|---|
| **lock** | product == total within tolerance | High confidence. Lock the three numbers together |
| **reconciled** | product - total equals a discount line on the document | Also correct. **Not an error** |
| **mixed** | product < total and the gap is explained by other priced lines | The fuel amount is the fuel line (hard rule 4) |
| **mismatch** | none of the above | Show the residual, name the next step, never block |

**`reconciled` is not theoretical - it is the majority case on loyalty receipts.** All five
Circle K app screenshots in the corpus fail a naive cross-check, every one of them by exactly
the printed discount, while every field was read correctly:

| fixture | line | product | discount | total |
|---|---|---|---|---|
| `screenshot-004` | 1.884 x 67 | 126.23 | 1.01 | 125.22 |
| `screenshot-005` | 2.159 x 58.01 | 125.24 | 4.06 | 121.18 |
| `screenshot-006` | 1.799 x 68 | 122.33 | 1.02 | 121.31 |
| `screenshot-007` | 1.614 x 64 | 103.30 | 1.92 | 101.38 |
| `screenshot-008` | 1.924 x 59.78 | 115.02 | 2.39 (fuel share) | 112.63 |

A gate that refuses to lock here is refusing five perfect scans.

`reconciled` is decided **by the residual, not by the existence of a discount line** - and on a
mixed receipt the residual is the fuel's *share* of the printed discount, so the check is the
whole document accounting: `product + shopList == grandTotal + discount`. `screenshot-008`
passes it completely (115.02 + 11.14 == 122.99 + 3.17, where the residual 2.39 is the fuel
share and 0.78 the shop share). The counter-example is `receipt-038`: it prints
`EXTRA SOODUS -0,23 EUR` beneath the item while `K O K K U` still reads 79,32 - the discount is
printed but **not subtracted from the total**, which already equals `45,22 x 1,754`. A rule
that reconciled because a discount line exists would call that a reconciled; the residual-driven
rule locks it, because the residual is ~0 and the total is already the product.

It follows that **a document can carry two truthful unit prices**. `screenshot-004`,
`receipt-001` and `pump-001` are the same fill: the app prints the list price 1.884, the receipt
prints the effective 1.869, and the 1.01 discount is the difference. Neither is wrong. Which one
the app stores is a product decision, not a parser bug - and the residual is what makes it
visible either way.

Where the outcome is not `lock`, the residual is the honest thing to show: *"1.01 less than
67 x 1.884"* names its next step; a bare amber "mismatch" does not (hard rule 7).

### 6. Hand off

`ExtractionMeta` plus per-field confidence, into the Confirm screen as **already-editable
pre-fill**. Hard rule 13 governs everything the pipeline produces, from any source - rules, cloud
model, QR, or a future on-device model. Once the user changes a value it is theirs permanently:
no re-scan, improved parser, pack update or late gateway answer may overwrite it.

And hard rule 15: **a capture is a head start, not an answer.** A poor scan must degrade to
"correct two fields", never to "start over", and manual entry is never the failure branch.

### The Expense-mode hand-off (RV.62)

An Expense-mode capture runs the same pipeline as any receipt - but the hand-off into the
expense form is **deliberately narrower**. A shop receipt is not a fuel receipt: liters, unit
price and fuel kind are meaningless on it. The product-owner decision (2026-09-04) is that the
expense form receives exactly **total, currency and date** - the three `ExtractionAssembler`
already resolves. `ExpensePrefillBuilder` (core) is the one seam where a `FuelExtraction`
becomes an `ExpensePrefill`, and `ExpensePrefill` has **no liters / unitPrice / fuelKind
members** - the boundary is structural, not a discipline: piping the fill-up prefill across is
not a mistake that could slip through review, it is something the type refuses to express.
Those fuel fields are still extracted by the shared parser on a fuel-looking receipt; they are
dropped HERE, by construction, before anything app-side can read them.

Two fields are **not** resolved, deliberately: merchant and category. Category is the user's
pick on the form (`ExpenseCategory.entryCases`); guessing one from a shop receipt is a NEW
extraction problem with its own corpus and its own failure modes, and it was not assumed into
this change.

The contract that bounds the expense hand-off is the fill-up path's own:
- An extraction that resolves nothing becomes an all-nil `ExpensePrefill` - the expense form
  opens EMPTY, never an error (hard rules 7 and 15). The F1 caption belongs to the fill-up
  Confirm sheet; the expense form has no caption of its own.
- Every carried value is default input the user edits (hard rule 13): the amount and the date
  land in the form and stay editable, and the snapshots for the discard guard are taken after
  the pre-fill so a scan never counts as an edit.
- Currency is carried so the form can be honest about it: the expense form is home-currency
  only (it has no conversion card), so a total the recognition priced in another currency is
  NOT offered as if it were home money - the amount stays blank for the user to type. A nil
  currency is treated as "no evidence to the contrary", exactly as the fill-up form does.

## Cross-multiplication as digit repair

New, 2026-08-26, and specific to seven-segment displays.

`pump-015` shows `SUMMA 30.02`, `LIITRIT 15.89`, and a price display that reads `1.884`. But
`15.89 x 1.884 = 29.94`, and `15.89 x 1.889 = 30.02` exactly. The price is **1.889** - glare
fills the segment that separates a `9` from a `4`. `pump-016` and `pump-017`, the same pump
family shot out of the glare, print `1.889` and `1.769` unambiguously. The same correction then
resolves `pump-013`: `7.34 x 1.779 = 13.06`, where the naive `1.774` gives `13.02`.

So on a pump display the cross-check is not only a confidence signal, it is a **repair
candidate generator**:

> When `liters x unitPrice` misses `total` by roughly one least-significant step of one operand,
> the likely cause is a **single misread segment**, not three independent errors. Substitute the
> visually-confusable seven-segment pairs in turn - 4/9, 8/9, 8/6, 8/0, 3/9, 5/6, 1/7 - and test
> whether exactly one substitution closes the arithmetic.

Two constraints on using it:

- **Exactly one candidate may close.** If two substitutions both reconcile, there is no repair,
  only a choice, and the fields stay `nil`.
- **It is a suggestion, never a silent overwrite** (hard rule 13). The repaired digit is offered
  as a pre-fill on a field the user can see and change. A parser that quietly rewrites a digit it
  believes it misread is exactly the confident-wrong-value failure the whole design avoids.

And the acceptance standard that keeps it honest (P2.13, 2026-08-27): a substitution "closes" only
when the repaired product **reproduces the total exactly at the display's two-decimal money
precision** - `15.89 x 1.889` rounds to `30.02`, the naive `15.89 x 1.884` does not. That standard,
not the shared cross-check tolerance, is the repair's boundary, and the shared tolerance is
unchanged: the four-outcome cross-check still runs first, and a repair is wired **after** it without
replacing any outcome. Where a repair fires, `FuelExtractor` keeps `crossCheck` a `mismatch`
carrying the read residual (never `.lock`), so the confirm screen cannot treat the corrected triple
as confirmed - the repaired field is a pre-fill the user confirms, and the arithmetic alone is never
enough to lock a repaired digit. The `preset-amount` case (`pump-010`) is protected by the same
exactly-one rule: its rounded volume makes several single-digit substitutions *almost* reproduce
the total but none exact, so the engine abstains and the honest `13.17 / 1000.00` stands.

The same reasoning does **not** transfer to receipts. Thermal print has no segment topology, so
its confusions are different (and `0`/`О`, `3`/`З`, `6`/`б` are language confusions, not optical
ones).

## The four named failure modes

Each is a real, reproduced miss with a fixture behind it. New failure modes get added here with
their evidence, not described in the abstract.

1. **The swap.** Volume and price extracted the right way round only sometimes, with the
   arithmetic unable to tell. `receipt-007` is the worked example, settled only because
   `pump-002` is the same fill and states the two separately. This is the most dangerous failure
   in the product: it is silent, it survives every check, and it corrupts consumption by a
   factor.
2. **The grand total.** On a mixed receipt the fuel amount is the fuel line, never the receipt
   total (hard rule 4). `screenshot-008` reconciles completely - fuel 112.63 plus shop 10.36
   equals the 122.99 total, and the fuel discount 2.39 plus shop 0.78 equals the printed 3.17.
   **Fixed in P2.12** (2026-08-27): the parser once returned 122.99 for it; it now resolves
   `59.78 L x 1.924` and takes the fuel line's own printed amount 112.63, never the grand total.
   The fuel line is the **third** of eight, so "first priced line" and "line nearest the total"
   both fetch a chocolate bar. The discriminator is the unit token: `L` against Latvian `Gab.`
3. **Surrounding text read as data.** A pump forecourt is covered in advertising. The parser
   returned `0.700` litres from `Wrapper ja jook 0,5-0,7l`, a sandwich promo printed beside the
   display. Receipts have no equivalent, which is why a receipt-tuned parser scores far worse on
   pumps than its receipt numbers suggest.
4. **The confident misread.** Vision returns a **wrong digit at confidence 1.00** on `pump-004`.
   Confidence from the recognizer is not evidence about the value; only the cross-check is.

## Where a trained model fits

Recorded as a decision so it is not re-proposed from scratch. Two prior related decisions stand:
Foundation Models was **cut** (no Russian, `VISION.md`), and the cloud LLM gateway is the only
model-assisted path in the product (`P4.10`).

### The question is not "a model or not" - it is which of two problems

The measured split at the top of this doc is the whole argument.

**Receipts and screenshots: do not train anything yet.** Vision already reads these at
confidence 1.00. Every miss is a parser bug with a name, and each one so far has been fixed by a
few lines of deterministic rule - including two named this week (discount reconciliation, the
`Gab.` unit token). Rules are debuggable, mutation-checkable, free at runtime, and they work in
every country. Reaching for a model while the misses are still *nameable* trades a testable
system for an untestable one and buys nothing.

There is also a data wall and it is decisive:

> The corpus is **62 images**, perhaps 200 labelled field decisions. That is far below what
> fine-tuning a structured-extraction model needs, and worse, **the corpus is the test set**. A
> model trained on it cannot be scored by it: `AccuracyRatchetTests` would go green on
> memorisation and tell us nothing. There is currently no honest way to measure such a model,
> which means there is no way to know it helped.

**Pump displays: this is where training is actually the right tool**, and the shape that fits is
**not** an SLM.

A seven-segment digit reader is a narrow classifier - ten classes plus blank and decimal point -
and it clears the exact obstacles that block the receipt case:

- **The data problem disappears.** Seven-segment glyphs are *synthesizable*. Render unlimited
  digits with controlled glare, blur, perspective, LCD ghosting and the reflection of a
  forecourt canopy. The 17 real pump photos then stay a genuine **held-out** test set precisely
  because nothing was trained on them.
- **It is tiny.** A few-hundred-KB CNN via Core ML: milliseconds, offline, no gateway, no
  per-request cost, no image leaving the device - and it works in Russia and Europe, which is
  what killed the Foundation Models path.
- **It targets the measured failure directly.** The 9-as-4 confusion above is a segment-level
  error, which is what glare augmentation trains against.
- **It composes with the digit repair rule.** Classifier per-digit posteriors give the repair
  candidates an ordering instead of a fixed confusion table.

A general small language model, by contrast, is the wrong instrument twice over: the pump
problem is optical rather than linguistic, and the receipt problem has neither the data nor a
measurable gate.

### What to do first, in order

1. **Keep writing rules** for receipts and screenshots while the misses still have names. Both
   items specified in this doc today - the `reconciled` cross-check outcome and the `L`/`Gab.`
   discriminator - are free and land parser accuracy without any model.
2. **Implement digit repair** (above). Deterministic, testable, costs nothing.
3. **P4.12 is done - see "The P4.12 measurement" below.** The full-corpus A/B against the cloud
   vision model, scored with the same scorer as the rules parser. It read **31/46** pump fields
   where the rules parser scores **1/46**, and it still produced **five** confident swaps and a
   decimal shift that pass the cross-check - so the gateway cross-checks and suggests, it never
   trusts.
4. **Only then**, and only if pump capture still matters after step 3, build the narrow
   seven-segment Core ML reader on synthetic data, validated against the 17 held-out photos.

### The constraint no model changes

Whatever produces a field - rules, cloud model, QR, or a trained reader - it produces a
**suggestion** (hard rule 13), manual entry stays a peer path (hard rule 15), and **a confident
wrong value is worse than a `nil`**. The corpus has the worked example: the cloud model read
`70.44 X 39.000` as 70.44 litres, a clean swap that passes every arithmetic check. The rules
parser's `nil` on the same line costs the user two taps. The swap costs them a silently wrong
consumption figure for the life of the vehicle.

## The P4.12 measurement, and what the gateway must do

P4.12 ran the whole corpus through `deepseek/deepseek-v4-flash-vision-exp` - one complete
sweep, 61 images, 0 errors - and scored both arms with the one shared scorer
(`ios/Tests/TankbookCoreTests/CorpusABScorer.swift`) and one tolerance. Raw results are
committed in `Spike/ReceiptSpike/fixtures/vision-ab/`, per class and per engine, so the next
person re-scores offline and never pays for the sweep again.

| class | rules | cloud model |
|---|---|---|
| receipts | 46/96 | **84/96** |
| pump | 1/46 | **31/46** |
| fiscal | 1/3 | 2/3 |
| screenshots | 7/24 | **22/24** |

The model is stronger everywhere, and the pump gap is not marginal: the rules parser is blind on
pumps (1/46) where the model reads 31/46, including `pump-004` - the fixture where Vision returns
a wrong digit at confidence 1.00 - and the four-price `pump-005`. On receipts it reads the
unmarked pairs the ladder refuses (`receipt-007`, `receipt-008`, `receipt-023`, `receipt-033`)
and the mixed-receipt fuel lines (`receipt-009`, `screenshot-008`) exactly.

**And none of that is a reason to trust it.** The failures are the corpus's own traps, and they
are silent:

1. **The swap, five times.** `receipt-002`, `-014`, `-017`, `-025` and `-035` came back with
   volume and price the wrong way round. On `receipt-035` it read `70.44 X 39.000` as 70.44
   litres - a clean swap that passes the cross-check, because `a x b == b x a`. A swapped fill is
   stored wrong by a factor with every arithmetic check green.
2. **The decimal shift.** `pump-009` (zero-padded) read `40.00 / 50.95 / 2038.00` as
   `400.0 / 50.95 / 20380.0` - a factor-of-ten shift on two fields the cross-check cannot see,
   because `liters x unitPrice == total` is scale-invariant.
3. **Non-determinism.** The probe of 2026-08-26 recorded the shift on `pump-005`; this sweep
   read `pump-005` exactly, three runs in a row, and put the shift on `pump-009` instead - which
   then read correctly on a re-run. Same image, same model, different answers. A reader that is
   not stable cannot be trusted even statistically.
4. **Confident zeros.** `receipt-034` prints `30.61 X 0.00` and `ИТОГ 0.00` (contract pricing).
   The model returned `unitPrice = 0.0`, `total = 0.0` where the rules parser correctly returns
   nil. A zero is a confident wrong value, not a value.
5. **Latency.** Median 6.5-8.3 s per image, max 40 s - above the 3 s per-attempt budget in every
   class. The gateway is a late-answer path, not a synchronous peer of the camera.

**Recommendation: the gateway cross-checks and suggests. It never trusts.** Concretely:

- Every field the model returns is a **suggestion** - a default input the user edits (hard rule
  13), never a locked value, no matter how green the cross-check looks.
- The four-outcome cross-check still runs, because it catches the model's genuinely inconsistent
  triples (`pump-011` returned `58.01 x 1.789 = 15.15`; `pump-015` returned `1.589 x 1.144 =
  2000`; `pump-013` abstained entirely). A `mismatch` demotes to nil. That is real value - it
  just is not a correctness test.
- The cross-check must **not** be used to "verify" the operand assignment, because the two
  failures that actually occur both pass it. Volume-vs-price still needs the resolution ladder
  (unit markers, decimal count, price bands) and the user.

**What would change the answer.** Nothing short of removing the silent failures moves it from
"suggest" to "trust". If the operand assignment were anchored to a unit marker or a price band
*before* the model was trusted (so a swap could not occur), and if the scale were pinned by an
external signal the cross-check cannot see (tank capacity, a band), then "cross-check" would
become meaningful. Determinism would help too - a model that returns the same answer for the same
image can at least be measured. And if latency ever drops under 3 s, the gateway becomes a
synchronous peer rather than a background fill-blanks path.

## P4.13 measured: PaddleOCR as a third arm (2026-08-26)

P4.13 ran the same corpus, the same scorer (`CorpusScorer`, tolerance 0.005) and the same
committed-file shape through PaddleOCR in a pinned container. Two arms were specified; one ran,
one could not. Raw results are committed in `Spike/ReceiptSpike/fixtures/vision-ab/` as
`paddleocr-a-*.json` (fields) and `paddleocr-a-runs-*.json` (three runs + latency), scored offline
by `PaddleOCRTests`. The container is `Spike/PaddleOCR/Dockerfile`, started by
`scripts/dev-up-paddleocr.sh` (plain `docker run`, image `tankbook-paddleocr:0.1.0`, base
`python:3.12-slim-bookworm`, `paddlepaddle==3.2.2` pinned because 3.3.x ships no Linux aarch64
wheel).

### Arm A - PP-OCRv5 (server det + `cyrillic_PP-OCRv5_mobile_rec`) -> the existing `FuelExtractor`

| class | rules (Vision) | Arm A (PaddleOCR) | DeepSeek cloud |
|---|---|---|---|
| receipts | 46/96 | **29/96** | 84/96 |
| pump | 1/46 | **2/46** | 31/46 |
| fiscal | 1/3 | 1/3 | 2/3 |
| screenshots | 7/24 | 7/24 | 22/24 |

Arm A does **not** score far better than Vision + parser - it scores *worse* on receipts (29 vs 46)
and within noise everywhere else. So the doc's central claim is **not falsified**: a different
reader does not unlock the parser, which is what "recognition is the hidden bottleneck" would have
required. But "about the same" does not survive either, and the reason is the actual finding: **the
parser is coupled to Vision's output, not reader-agnostic.**

The two couplings, both on real fixtures:

1. **Line segmentation.** Vision emits `1,869` and `EUR/L` as two lines; PaddleOCR's detector (all
   of `PP-OCRv5_server_det`, `PP-OCRv5_mobile_det`, `PP-OCRv4_mobile_det`, `PP-OCRv3_mobile_det`)
   merges them into `1,869 EUR/L`. The parser's `loneMarkers` finds a price "directly below its
   `/L` label", so it cannot resolve the price from the merged line. `receipt-001` (a Latin-script
   Estonian Circle K receipt, not Russian) is the worked example: Vision reads `67,00L` + `EUR/L` +
   `1,869` and the parser resolves 67.00 / 1.869 / 125.22; PaddleOCR reads `67,00.` (the `L` dropped
   by `server_det`) + `1,869 EUR/L`, and the parser returns the discount `1,01` and `100,98`.
2. **Script.** `cyrillic_PP-OCRv5_mobile_rec` is a Cyrillic-only reader; the corpus is mixed
   (RU/KZ receipts, EE/LV/LT screenshots). It reads Latin numbers correctly but misreads labels -
   `ИТОГ` becomes `НТОГ` on `receipt-021`, dropping the primary total label and leaving two payment
   candidates tied.

On receipts where the Cyrillic model reads the operand line cleanly (`receipt-006`, `receipt-022`),
Arm A matches Vision exactly; where the label is legible it is occasionally *better*
(`receipt-018`'s total, `receipt-023`'s volume, both of which Vision gets wrong). The score is not a
flat defeat - it is a reader whose segmentation and script coverage differ from Vision's, and a
parser tuned to Vision.

**Determinism, measured not assumed.** PaddleOCR's OCR output is byte-identical across three runs
per image. But the three-run sweep surfaced a *pre-existing parser* non-determinism: when
`FuelExtractor.modal` ties two total candidates and no primary label names one, it breaks the tie
via `Dictionary(grouping:)` iteration order, which Swift does not guarantee. Three receipts
(`-021`, `-026`, `-029`) flip their total across process runs, moving the receipt score between
29/96 and 30/96. The coordinate conversion is proven separately by `PaddleOCRCalibrationTests`
(formula + a mutation that inverts the y-flip) - the parser tie is not a coordinate bug.

### Arm B - PaddleOCR-VL -> fields directly

**Blocked in this environment, and that is the finding.** PaddleOCR-VL (`PaddleOCR-VL-0.9B`) does
not run on this machine: `paddlex` calls `paddle.amp.is_bfloat16_supported()` with no place
argument, which raises on paddlepaddle 3.2.2 aarch64 CPU ("Invoked with: Place(undefined:0)");
forcing float32 (the only way past it) makes the 0.9 B model ~3.8 GB of weights plus graph, and the
container is OOM-killed (exit 137) inside the 7.6 GB Docker VM. On this hardware it needs a GPU or
12+ GB RAM to run at all, and float32 CPU inference on a 0.9 B VLM is minutes per image - the full
three-run sweep is not feasible in a session. The `/extract` endpoint, the sweep path and the dump
scaffold are committed; the result files are not, because there are no results.

### The conclusion, stated plainly

Arm A **confirms** the split in the negative sense - recognition is not the lever that unlocks the
parser (a different reader did not score better) - and **corrects** it in the positive: the parser
is coupled to Vision's line segmentation and script handling, so it cannot be fed an arbitrary
reader and score the same. That coupling, not "interpretation is hard" in the abstract, is the
precise reason a different reader does not help.

**The ops cost is not justified.** A Python/PaddlePaddle container adds a third runtime, and the
measurement buys nothing back: Arm A is *worse* than on-device Vision on receipts (29 vs 46), its
median latency (4.5-8.4 s, max 21.0 s) is still above the 3 s budget in every class - self-hosting
does not buy latency back without a GPU - and its per-script recognition models mean a production
deployment needs script detection or a multilingual model just to cover the corpus. Arm B cannot
run on modest hardware at all. The DeepSeek cloud arm (84/96 receipts, 31/46 pump) remains the only
reader that beats the rules parser, and its four problems from P4.12 - silent swaps, decimal
shifts, non-determinism, per-call cost - are the cost of that accuracy. PaddleOCR does not displace
either; on-device Vision stays tier 0, and PaddleOCR does not earn the fallback slot.

## Growing the corpus is the highest-value work

Any path here - better rules, a cloud A/B, a trained reader - is limited by the same 62 images.
Breadth beats count: more makes of pump, more countries and languages, non-CIS receipts, mixed
receipts, and matched pairs or triples of the same fill from different documents. The triple
`receipt-001` / `pump-001` / `screenshot-004` settled a question about list versus effective
price that no amount of re-reading a single document could.

## AdBlue on a receipt (added 2026-08-30)

Vocabulary: `ADBLUE`, `AdBlue`, `AD BLUE`, `AUS 32`, `AUS32`, `DEF`, `HARNSTOFF`, `МОЧЕВИНА`,
`АДБЛЮ`, `AdBlue®`. Price band: roughly 0.5–2.0 per litre in EUR/PLN-equivalent, 50–150 ₽/L -
about half to a third of diesel, so a band rejects it as a diesel price the way it rejects LPG.

Rule: **an AdBlue line is never the fuel line.** On a diesel receipt that carries both, the
diesel line is the fill and the AdBlue line becomes a second `FillUp(.adBlue)` in the same
purchase group (`SCHEMA.md` → AdBlue), each cross-checked against its own litres × price. The
mixed-receipt detector must classify the AdBlue line as a fill, not as an Expense. On a receipt
that carries only AdBlue for a car whose offer set includes it, the fill is `.adBlue` - never
`.diesel` with a suspiciously low price. The Spike parser lists `ADBLUE` among fuel product
words; that entry moves to the AdBlue vocabulary when the task lands, and the corpus gains a
diesel + AdBlue fixture and an AdBlue-only fixture, both asserting the fuel line and the kind.
