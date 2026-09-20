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

## What a receipt says besides the numbers (RV.115, 2026-09-07)

The pipeline exists to fill a fill-up's fields, but the same OCR pass carries two facts worth using
elsewhere, and both are free once the text is read:

- **The station.** The slip names it (`Circle K Järvevana teenindusjaam`, `ООО "Газпромнефть-центр"`),
  and that string is exactly what the station **brand matcher** consumes (`docs/API.md` ->
  `GET /reference/station-brands`). A matched brand makes the fill groupable; an unmatched name stays
  the user's own station, which is a first-class state, not an error.
- **The country.** Not from a field, but from the combination the corpus already demonstrates:
  currency, VAT rate, script and phone format. `receipt-051` is Cyrillic + RUB + a Russian fiscal
  block; `receipt-049`/`-050` are Estonian + EUR + "24% KM".

**Why it matters for ordering**: when the user is capturing, they are standing at the station, so the
receipt is a present-tense local signal that beats device region and beats any IP-derived hint. Both
facts stay **default inputs the user can change** (hard rule 13) - a receipt read is a suggestion,
and the corpus records Vision misreading a digit at confidence 1.00.

### The station line, extracted (RV.161, 2026-09-10)

The fuel path now resolves the station identity line the receipt prints - `ООО "Газпромнефть-центр"
... Место расчетов АЗС №12089`, `Circle K Sikupilli teenindusjaam` - as `FuelExtraction.stationName`,
and it reaches the entry only through the Confirm pre-fill, where the user sees and can change it
(hard rule 13). It is stored as the `Station`'s **name**, the string `ImportStationResolver` keys on,
so a scanned name and a typed one resolve to one deterministic id (RV.156) instead of duplicating.
Splitting that line into a canonical `brand` and a `site` is RV.115's brand list, deliberately not
forked here.

**It is also written to the attachment's stored assignment (RV.184, 2026-09-10).** `ScannedSavePlanner`
records the station beside the six value fields in `Attachment.extractionMeta`, so the viewer's "What
was read" page can show what the scan concluded about the station exactly as it does for the total or
the date. That record is presentation only: the value is the scan's own proposal (what was READ),
`userCorrected` marks a name the user changed, and it never feeds back into the entry (hard rule 13).

**One heuristic, two callers.** The shape - letters, at most six tokens, at most one numeric token,
not a date, not a document label - lives in `CompanyNameLine.isCompanyName`, shared with the
service-invoice vendor finder (`InvoiceSplitter.detectVendor`). The fuel extractor adds exactly three
rules the invoice path does not need, and they are the whole difference:

1. **A confidence floor (0.5).** A fuel receipt photographs a pump and a counter, so low-confidence
   fragments sit above the brand (`G Э` at 0.30 on receipt-060).
2. **A receipt-furniture deny list.** `КАССОВЫЙ ЧЕК`, `ИНН`, `ЗН ККТ`, `СПАСИБО`, card-terminal
   boilerplate and address lines all have the shape of a company name; an invoice prints its vendor
   first, so the shared predicate alone is enough there.
3. **A person-name and currency-figure filter.** A cashier line (`НАФАНАИЛОВА Т.В.`) and a bare
   amount (`79,32 EUR`) have the same shape.

**NOT measured - and the corpus deliberately carries NO station column yet.** The first attempt
added one and reported **46/46**, which was a tautology rather than an accuracy: the cells were
filled from the extractor's own output, so on `receipt-007-lukoil` the cell was left blank while the
OCR's first line reads `"ЛУКОНЛ-СЕВЕРО-ЗАПАДНЕФТЕПРОДУКТ"` - a miss recorded as "no ground truth" -
and values like `ПИТАЛ` and `Крым` are parser fragments no human would write. The scorer skips an
empty cell rather than counting it a miss, which is what let the blanks hide the misses. The column,
its scorer support and the moved mark were all reverted; the receipts mark stands at **240/280**,
unchanged by this row.

Ground truth here has to come from something the extractor cannot see: the fixture **filenames**,
which the product owner wrote from the images before any station extractor existed, cross-checked
against the OCR. That is **RV.179**, and it landed 2026-09-19: **measured, 31 of 59 (53%)** on
macOS 27 (the one mark not measured on macOS 26 - `docs/TESTING.md` names the exception). The
column is the `station` cell of `receipts/expected.csv` - the paper's brand as the normalised token
runs (`StationBrandMatcher.normalisedTokens`) the extracted line must contain, `|` between the
spellings a receipt may print (`lukoil|lukoyl`) - written from the filename and cross-checked line
by line against the OCR dump; **14 of 73 cells are blank**, each with its reason in
`receipts/stations.md` (seven where the read carries no trace of the brand, seven where the
filename names a city or nothing - three of those print a chain the filename does not, and are
named there for renaming). It is scored as its **own class** (`stations` in `high-water.json`) so the
receipts marks keep their cell counts, an abstention against an asserted cell is a **miss**, and
`stationMarkIncludesAMiss` prints every miss - a fresh class at 100% is circularity, not quality.
What the misses say: the extractor offers a cashier line, an address, a card-terminal fragment or a
fiscal label where the paper prints the chain on another line, and OCR misspells the chain itself
(`ЛУКОНЛ-СЕВЕРО-ЗАПАДНЕФТЕПРОДУКТ`, `ТАЗПРОМНЕФТЬ`) or glues the legal form on (`ОООКРЫМ ОИЛ`). The
first measurement also fixed one matcher blind spot: a Latin look-alike inside a Cyrillic word
(`PН-Тверь` with a Latin P, which every RN slip prints) is now read as the Cyrillic it stands for
before transliteration, 29 -> 31.

**Hard rule 12.** A station name, brand or address is a domain value and is never logged, at any
level, in any build; only counts and confidence are shape. A source-scan gate
(`RV161StationLoggingGateTests`) pins the extraction and pre-fill seams against it.

## The one-sentence version

Vision reads the characters; **the hard part is deciding what each number means**, and every
value this pipeline produces is a suggestion the user can overwrite forever (hard rule 13).

## Measured reality, 2026-09-18

| class | score | note |
|---|---|---|
| receipts | **286/345 cells (82.9%)** | live `TankbookCore` score |
| fiscal | 5/5 | |
| screenshots | 40/45 | |
| expenses | 33/33 | kind, total, currency and date |
| pump | **53/320 numeric cells** | committed 56, correct 53 - see the gate note below |

`Spike/ReceiptSpike/fixtures/high-water.json` carries the per-change breakdown.

**The pump number is scored differently on purpose (B1, 2026-09-04).** The old pump mark - "53/261,
20%" - was a recall average over a denominator that mixed the 178 numeric cells the mode exists to
read, a near-free `currency` marker lookup (66 cells), and `fuelKind` (17), which this document
says a pump parser must never produce. Worse, recall scores a correct `nil` as a miss and a
confident-wrong value as a hit - hard rule 13 inverted - and the two idle pumps' ground-truth zeros
made it reward logging a zero-litre fill. `PumpPhotoGate` now measures **precision on committed
numeric fields plus a coverage floor**: today 53 of 56 committed cells are correct (94.6% precision)
at 17.5% coverage, so the mode stays off, below both thresholds.

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
| receipt-068 | volume `1.000` | `1 ВД.«1 ЛИТР ДЛЯ НЕМТЕПРОДУКТОВ/СУГ`, `1 ед.-1 МЗ для кт` | the same footnote read sideways: `ЕД` -> `ВД`, `=` -> `«`/`-`/`+`, so the glyph-keyed rule never fires and the `1 ... ЛИТР` reads as a marked volume (RV.292) |
| receipt-072 | volume `10630454945` | `0010630454945L` | the `РН ККТ` register number, its label emitted on its own lines and a Latin `L` grown on its tail, so the label-keyed rule never sees the value and the `L` reads as a litre marker (RV.292) |

`ReceiptNoiseFilter` classifies a line into one of five witnessed noise classes - Russian fiscal
identifiers, Estonian registration, card-terminal furniture, unit-convention footnotes, contact
details - or leaves it alone. Two properties are load-bearing and neither is optional:

**It tags, it never deletes.** The raw OCR text is kept in full. It is the evidence that lets a bad
parse be re-examined, and the five named failure modes below are pinned to it.

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
bare-identifier rule is bounded by the **separator**, not only by length: a run of 10+ digits with
at most one letter on its tail is an identifier (no printed money lacks its separator, and no real
volume has more than two digits before it), while anything carrying a `.` or `,` stays a value line
(RV.292). The unit-convention rule is keyed on the footnote's **structure** - a leading `1`, a
`ЛИТР`/`М3` a few glyphs on, a `ДЛЯ` after - because a sideways read keeps the structure and loses
the `=` (receipt-068).

**The whole-class litres property** (`noReceiptCommitsAVolumeItsExpectedContradicts`, beside RV.56's
totals and RV.270's kinds): a committed volume that contradicts `expected.csv` fails the suite on the
measured runtime, so the next confident-wrong litres is a red, not a lower score. Measured once on
macOS 27 as a proxy (2026-09-19, RV.292): 068 and 072 are clean, and **six other receipts commit a
wrong volume on that runtime** - `receipt-003`, `-005`, `-032` (`2.0` for `20.0`), `-040` (`21.18`
for `57.0`), `-057` (`9.05` for `57.0`), `-064` (`23.0` for `23.07`) - which is RV.295's question
(is it the runtime or the parser) with litres now in the evidence, and unverified on macOS 26 until
the measured runtime runs the property.

### 4. Resolve

Per field. Each returns `nil` rather than guessing.

**Volume and unit price** are the dangerous pair and their ladder is normative in
`SCHEMA.md` -> Fuel price bands. Not restated here. The one thing worth repeating is *why* it
exists: `a x b == b x a`, so the arithmetic cross-check **cannot** detect a swapped pair. A
parser that guesses wrong stores 99.4 L at 43.61 instead of 43.61 L at 99.40 and computes
consumption wrong by 2.3x with every check green.

**Total** is modal over labelled candidates, preferring the primary labels (`ИТОГ`, `TOTAL`,
`KOKKU`, `SUMMA`), with VAT, rounding, change and "received" lines excluded by name.

**Currency, date, fuel kind** are marker lookups. Three traps already paid for:

- A fuel abbreviation must be followed by a non-letter. `ДТ` inside `ПОДТВЕРЖДЕНА` is not diesel.
- A bare `L` inside a word (`Tallinn`, `ЛУКОЙЛ`) is not a volume marker.
- A kind may come only from the **product / line-item block**. A unit legend - `1 ед.=1 литр для
  нефтепродуктов/СУГ` - or a fuel token in a slash-list names what the till can *sell*, never what
  this fill used (failure mode 5).

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

### 5b. Printed total vs derived product (RV.125, 2026-09-07)

When a receipt prints a total, that printed total **outranks** a product derived from the two
OCR'd operands. The cross-check exists to catch a bad read, not to second-guess a printed value,
and `receipt-052` is the worked example of why the precedence must be stated and not left to
happenstance: Vision read the price line as `20.31 X 32.000` at confidence 1.00 (the true price
is 70.31) and read the printed `=2249.92` **twice**, both correct - yet the extractor committed
`649.92`, which is exactly `20.31 x 32.000`. A single misread digit in one factor overrode two
independent, correct, high-confidence reads of the printed total, and because the product agreed
with itself the cross-check *confirmed* the wrong number rather than catching it. That is the
worst shape a capture defect takes (hard rule 13: the user then edits a figure that looks
authoritative).

The rule, in one sentence: **a printed total is evidence; a product of two OCR'd factors is a
derivation.** Agreement between two independent reads of the same printed value is corroboration;
a product agreeing with itself is not, because both factors come from the same line and a single
misread digit propagates into both.

The derived product is still used, and still load-bearing, in exactly two places:

1. **No printed total** - a receipt whose total label is obscured or absent (receipt-038) settles
   on the arithmetic fuel line. This is the rescue path and must never be removed.
2. **A mixed receipt** - when the printed total is the *grand* total and a genuine non-fuel priced
   line (a service, a bottle of water) explains the gap, the fill-up amount is the fuel line, not
   the grand total (hard rule 4, failure mode 2). The derived product wins here *only* with
   positive evidence of a non-fuel line.

The defect was in the evidence, not the intent. `resolveTotal` already preferred the printed total
in its fallback; the false positive came from `nonFuelListSum`, the "shop list" that tells the
mixed-receipt branch a non-fuel line exists. It excluded the fuel line by its **volume marker**
only, so an *unmarked* fuel line - `receipt-052`'s `20.31 X 32.000`, receipt-025's
`43.38 Х 38.28` - was counted as its own non-fuel item. That turned a fuel-only receipt into a
"mixed" one and let the derived product outrank the printed total. The fix: the fuel line is
identified by `OperandPair.fuelOperandIndex` (the volume-marked pair, else the operand pair
directly below a product line) and `nonFuelListSum` excludes **that** index, so a fuel line is
never its own non-fuel item and the two halves of the mixed-receipt decision can no longer
disagree about which line is the fuel.

**`DigitRepair` was considered and is correctly not applicable here.** The repair engine is
pump-source only (thermal print has no segment topology, so a receipt is never repaired - a
repair there would be a fabricated number), and `20.31 -> 70.31` is a `2 -> 7` substitution, which
is not in the seven-segment confusion table (a `2` and a `7` differ by more than one lit segment).
The engine's whole premise - a single misread *segment* - does not transfer to receipt glyphs.
The precedence rule is the fix, not digit repair.

### 5c. When the printed total and the product disagree (RV.153, 2026-09-09)

The RV.125 precedence was stated but not fully enforced: `resolveTotal` still let the derived
product win over a present printed total whenever the gap was not reconciled by a discount line,
and it had no answer at all for a fuel-only receipt whose `ИТОГО` label OCR destroyed but whose
line sum printed beside the operand pair. Two 2026-09-09 fixtures reproduced the receipt-052
defect through those two remaining routes, and both committed a confident-wrong total:

- **`receipt-055`** (Circle K, Tallinn): Vision misreads the printed volume `77,56L` as `17,56L`,
  so `17.56 x 1.934 = 33.96` agreed with itself and the cross-check *locked* it - while the
  receipt prints its total twice, `KOKKU 150,00` and `KK MAKSE 150,00 EUR`, both correct.
- **`receipt-057`** (Gazpromneft, Valday): the unit price is under the photographer's thumb, so the
  fuel line OCRs as `.05 x 57.000` and resolves to 5 L at 57 - a product of 285 - while `=3935.85`
  prints beside the pair at confidence 1.00 and again as the ИТОГО value.

The rule, in one sentence: **on a disagreement beyond tolerance the parser prefers the side with
evidence, and when neither side is corroborated it abstains rather than commit a plausible wrong
number.** Concretely, in order:

1. **A verified mixed receipt keeps the fuel line** (hard rule 4) - the product (or the fuel
   line's own printed figure) wins only with positive evidence of a non-fuel line.
2. **A discount that reconciles the product to the total keeps the total** - the charged amount.
3. **A printed total the parser can corroborate wins over the product.** Corroboration means more
   than one independent read settled on the figure: two label-pairings named it (receipt-055's
   `KOKKU` and `KK MAKSE`), or the value is printed more than once among the receipt's value lines
   (the redundancy rule that already existed for the net-versus-gross case). A product agreeing
   with itself is *not* corroboration - both factors come from one line, so a single misread digit
   propagates into both, which is exactly how 33.96 and 285 were "confirmed".
4. **An uncorroborated disagreement abstains** - a single printed read against a single product
   leaves no reason to prefer either, and a confident-wrong total is the one outcome hard rule 13
   rules out. `nil` costs recall, which is recoverable; a plausible wrong total pre-fills the
   Confirm screen looking exactly like a right one.

Two consequences worth naming:

- **A printed figure can now outrank the product without product-closeness.** The fuel line's own
  printed sum - the money value printed to the RIGHT of the operand pair on its own baseline, the
  shape Russian fuel receipts print (`=3935.85` beside the pair on receipt-057) - is read and used
  even when it contradicts `liters x unitPrice`, because a misread factor is exactly when the
  printed figure is the truth. The older Circle-K shape (amount ABOVE the pair) keeps its
  product-closeness guard; both are printed evidence and both outrank the derivation.
- **The cross-check no longer locks the wrong triple.** Before this rule, 055 and 057 both came
  back `lock` on a total that was wrong. With the printed total kept, `liters x unitPrice` no
  longer equals it and the outcome is an honest `mismatch` carrying the residual - the confirm
  screen cannot present the product as confirmed, which is what a `lock` on a wrong total did.

The arithmetic rescue paths are untouched and remain load-bearing: a document with **no printed
total at all** (label-free pump displays, receipt-038) still settles on the product, and the mixed
receipt's fuel amount still comes from the fuel line (hard rule 4). Measured: receipts
**223/265 -> 225/265** (two wrong totals became two correct hits; total-field misses 3 -> 1, the
remaining miss being receipt-056's deliberately-nil zero).

### 5c-ii. The resolved operand pair is never a shop item (RV.291, 2026-09-18)

Rule 1 above - a verified mixed receipt keeps the fuel line - has a precondition the `receipt-052`
fix stated and did not fully close: the non-fuel sum must exclude the fuel line *by identity*.
`nonFuelListSum` excluded the pair `OperandPair.fuelOperandIndex` placed (the volume-marked pair,
or the unmarked pair directly under a product line) and nothing else. On `receipt-069` - an RN-Tver
order slip photographed sideways and routed through Telegram - the pair `63.30 X 30.000` (a
misread of `68.30`) sits under a `КВИТАНЦИЯ ЗАКАЗА` header with a card line between it and the
product line, so `fuelOperandIndex` could not place it; the band ladder still read litres 30 and
price 63.30 from it. `nonFuelListSum` then counted that same line as a priced shop item, rule 1
declared the slip mixed, and the parser committed the pair's own product - **1899** - over a
`2 049.00` the paper prints twice. A misread digit multiplied through and committed as the total,
the exact outcome rule 4 exists to prevent, reached through a door rule 1 held open.

The fix is one identity: `resolveTotal` passes the operands it resolved into `nonFuelListSum`, and
a pair whose two operands are those values in either order (operand order carries no information -
the receipt-036/037 triplet) is the fuel line and is skipped. With the fuel line no longer counted
the slip is fuel-only, rule 3 finds the repeated `2 049.00`, and the total is the printed figure;
the misread `63.30` then fails the arithmetic against it and the price abstains. Measured: receipts
**285/345 -> 286/345**, no other fixture moves, and `RV56TotalPropertyTests` - zero
confident-wrong totals over the whole receipts class - is green again. The cross-check's own call
to `nonFuelListSum` is untouched; its outcomes are pinned separately and were not re-derived here.

`RV291OperandPairIdentityTests` quotes Vision's full read of the fixture with its geometry; a
trimmed subset passed on the mutant, because dropping the card line let `fuelOperandIndex` place
the pair. The test is real only with every line in.

### 5d. A discount line is never the unit price (RV.282, 2026-09-13)

The same asymmetry `RV.270` fixed for `fuelKind` reappeared for money. On `receipt-066` (Circle K
Järvevana) Vision splits the fuel block into one-token lines, and the bare `EUR/L` label's pump form
took the **nearest value line below** it - the `EXTRA SOODUS -0,96 EUR` discount - because
`NumberScanner.value` drops the sign by design (the discount-magnitude path wants `-0,96` as
`0.96`). The true `2,024` sits **above** the label, which the pump form excludes by construction.
The parser committed `unitPrice = 0.96`, a confident-wrong value (hard rule 13), and the ratchet
scored it as a plain miss - it cannot tell a wrong commit from an abstention.

Three changes, in order:

1. **The pump form skips a subtraction line.** `NumberScanner.isSubtractionLine` is now the one
   shared predicate, consulted by the total finder (which already had it) and by the unit-price
   pump form. The sign check lives outside `value(in:)` on purpose: that function drops the sign
   because the discount-magnitude path wants the magnitude.
2. **Derive only a printed price the arithmetic confirms.** When no label named a price but litres
   and total both resolved, the parser matches `total / liters` against a printed value line within
   the cross-check tolerance. The document said the number, so it is the document's price, never a
   bare quotient (a wrong value is worse than a nil). `receipt-066` is caught here: with the
   discount skipped the label yields nil, and `2,024` is the one printed value that equals
   `129.62 / 64.04`. The same step resolves `receipt-062`'s printed `Цена за ед. 71.30`, and derives
   `48.54` on `receipt-010`, whose ground truth deliberately leaves the unit price blank.
3. **A price that is a printed discount's magnitude is dropped.** Belt and braces: a resolved price
   that contradicts `litres x total` by more than tolerance AND equals a discount line's magnitude
   is the discount, not the price. This is the money sibling of the RV.270 fuel-kind guard; it did
   not fire on `receipt-066`, because step 1 had already made the price nil and step 2 supplied the
   printed one.

**Which step caught `receipt-066`: step 2.** The discount skip (step 1) is what lets the derive run
at all - without it the label returns `0.96` and the derive is skipped - but the committed value is
step 2's printed `2,024`. The named mutation is exactly that: remove the skip and the L1 goes red
with `0.96`.

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

**Category is inferred as a suggestion (RV.200).** A parking ticket, a toll, a car wash and an
insurance invoice were indistinguishable to the form that received them, because the scan read
the money and never the KIND. `ExpenseCategoryInference` (core, `Extraction/`, beside
`FuelKindNormalizer` and `StationNameExtractor`) now reads the scan's own OCR lines - the
extractor's INPUT, never a value another extractor already produced - for the separable kinds
`ExpenseCategory.entryCases` names: `parking`, `toll`, `fine`, `insurance`, `tax`, `parts`,
`accessory`, and `.other("wash")` (the escape hatch, not a forced standard case). The vocabulary
is bilingual and the RU set is the load-bearing one, because the product owner's own receipts are
Russian; both the text and every stem pass through `FuelKindNormalizer.canonicalKey`, so a
Cyrillic letter Vision reads as its Latin twin cannot break a match.

The result is a **default input, never a fact** (hard rule 13): it rides
`ExpenseEntrySession.pendingPreset` - the same field the ServiceEntry mode row writes - into the
form's editable category field, and an unrecognised kind leaves it nil so the form opens at its
default and says nothing (hard rule 7). A vocabulary that always answers is a vocabulary that
guesses. The save emits `expense.category.suggest` (docs/LOGGING.md §4): the category CODE and a
`userCorrected` boolean, never the receipt's text, so a future run can measure whether the
suggestion helps at all.

**The corpus could not measure this when RV.200 was filed, and that was the recorded finding.**
Every receipt photograph and pump display was fuel (or mixed fuel plus one non-fuel line), so the
vocabulary's ground truth lives in hand-authored OCR-text fixtures under
`Spike/ReceiptSpike/fixtures/expenses/` rather than in a photograph's filename. The **first non-fuel
photograph** landed there on 2026-09-11 - a Tallinn Airport car-park ticket whose `.jpg` the sweep
OCRs, with its Vision dump kept as the `.txt` beside it - and it named its kind only in Estonian
(`PARKIMISTEENUS`, `parkla`), which
the RU/EN vocabulary abstained on until the Estonian parking stems were added. That is the shape
every next photograph should take: the `.jpg` beside its OCR dump, the category from the file name. Merchant remains **not** resolved: guessing it from a shop receipt is a
separate problem with its own corpus and was not assumed into this change.

**The money fields are the fuel finder's, not a second one (RV.277).** The first ticket
resolved its amount through `redundantValue` (the `2.00` printed twice); the second, a
Tallinn Airport parking ticket of 13/09/2026, printed `TASU: 4.00 EUR` and `MAKSTUD: 4.00 EUR`
and no fuel-receipt total word, so the shared finder abstained and the form opened empty. The
fix is vocabulary, not a second implementation: `TotalLabel.primary` gains the expense words
the corpus prints - `TASU` (fee), `MAKSTUD` (paid), `PAID`, `ШТРАФ` (fine) - and
`TotalLabel.excluded` gains `NETO`, the Estonian net figure the ticket prints beside the
charged amount. The expense read therefore runs the SAME `grandTotalRead` and
`CurrencyDetection` the fill-up path runs; `ExpensePrefillBuilder` maps their result across.
Two markers that agree (`TASU` = `MAKSTUD` here) resolve that value; two that disagree are an
unbreakable tie and the finder abstains (hard rule 13) - `NETO` is never the total, however the
pair falls out. The currency miss was the total's, not `CurrencyDetection`'s: `4.00 EUR` is the
explicit-marker tier and resolved to EUR, so the pre-fill's currency was EUR and the RV.62
home-currency boundary let it through - the amount was blank because the total was nil, and the
expense form has no currency field of its own to show.

**The expense folder is a scored corpus class now (RV.277), and it scores the photograph
(RV.278).** `expenses/expected.csv` gained `total,currency,date` beside `category`, and the
folder is ratcheted as its own class in `high-water.json` (kind + total + currency + date
cells; 29/29 at introduction) by the same `AccuracyRatchet` and `AccuracyRatchetTests` the fuel
classes use. A fixture with a `.jpg` is OCR'd at test time through the same
`VisionTextRecognizer` the fuel classes use, and the extractor's output is scored against
`expected.csv`; the `.txt` beside the photo is a debugging dump, compared with the fresh OCR
and reported as **drift** when it differs, never scored. A hand-authored fixture with no
photograph reads its `.txt` directly - there the `.txt` IS the input by construction. The
spike mirrors the rule: `swift run ReceiptSpike fixtures/expenses` OCRs the photographs,
prints a drift warning and writes `recognised.csv` (what the extractor produced) beside
`expected.csv` for review; `--dump-text` regenerates a photograph's dump. `recognised.csv` is
never the oracle: `expected.csv` stays hand-written from the paper.

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

The same parse feeds the **late** read. When the recognition finishes after the expense is saved,
the inbox offers the amount, the inferred category and the printed date - `ExpenseRecognition`
carries the date as the parsed `Date` the pre-fill already resolved, one shape with the service
recognition. The date is a suggestion the user ticks, never an applied value (hard rule 13), so a
parking ticket dated last week and saved as today can be corrected from the receipt rather than
staying wrong.

**The expense kind reaches the cloud gateway (PJ.29, 2026-09-13).** A shop or parking receipt is no
longer read on-device alone. `CaptureExpenseScan.startExpenseGatewayIfAvailable` starts a
`GatewayScanSession` with `kind: "expense"` as soon as the local outcome lands - the form is already
open on it (F4) - under the same guards the fill-up Confirm sheet uses: `config.allowsServerBacked`
withholds the request under `.required`, a guest gets no transport, and a non-JPEG rendition gets no
call. The provider is asked for the fields that document actually carries
(`total, date, currency, vendor, category`) and never a fuel field, which is what the `expense` kind
exists for; the backend seeds it in `llm_settings` (migration 022).

The answer is bound by the fill-up path's own rules. A within-budget answer fills only the expense
form's **blank AND untouched** amount, currency, date and category, through the same
`GatewaySuggestionPolicy`; a late answer - the budget expired, or the entry was saved first - becomes
an inbox item through `GatewayInboxPolicy.item(recognition:entry:)`, the one policy. The mapping from
`GatewayExtraction` to both the pre-fill and the recognition is a single core function,
`ExpensePrefillBuilder.reading(fromGateway:)`, so the on-time and late routes cannot disagree about
what the receipt said. The category string is decoded against the device's own codes
(`parking, toll, wash, insurance, tax, fine, accessory, parts, other`) and an unknown string is
dropped, never guessed (hard rule 13).

**The invoice kind reaches the same gateway (PJ.29a, 2026-09-13).** A service scan asks `/extract`
with `kind: "invoice"` once the local split has produced its outcome - the form is already open on it
(F4). Only the **first captured page** is sent: an invoice may have several pages, and the header is
on the first. The provider is asked for the header only (`vendor, total, date, currency`) because the
line items are the device's deterministic split (`InvoiceSplitter`, docs/JOURNEYS.md J7); a cloud
answer never carries line items, and `ServiceRecognitionBuilder.reading(fromGateway:)` (core)
produces a header pre-fill with an empty `lineItems` from one decode. The answer is bound by the
fill-up path's own rules: a within-budget answer fills only the service form's **blank AND untouched**
vendor, date and currency through `GatewaySuggestionPolicy` (the total has no standalone field on the
form - the header total is derived from the line items - so it is offered only through the inbox),
and a late answer becomes an inbox item through `GatewayInboxPolicy.item(recognition:entry:)`, the
one policy. The same guards apply: `config.allowsServerBacked` withholds the call under `.required`,
a guest gets no transport, and a non-JPEG rendition gets no call.

**Every page reaches the cloud, and the cloud may read the lines (PJ.301/PJ.302, 2026-09-18;
decided 2026-09-15, product owner).** The paragraph above is the header-only shape an older
client still sends as `image`. The client now sends **every captured page** of an invoice as
`images` (docs/API.md "multi-page invoices"; `GatewayExtractRequest.pages`, capped by the served
`extract.maxInvoicePages`), and the answer carries the line items as `lineItem[n].title/amount/
category` fields, decoded into `GatewayExtraction.lineItems` and, by
`ServiceRecognitionBuilder.reading(fromGateway:homeCurrency:)`, into `ServiceRecognition.lineItems`
- a category the device does not know becomes `.other("")`, a line with no title is not offered, a
line's cost takes the reading's currency, else the car's home currency, else none.

**The line merge outcomes.** The local split stays the form's; the cloud's lines are OFFERS paired
onto it by `LineMatcher` (core, `Inbox/LineMatcher.swift`), and the pairing is deterministic and
**never by position** - the provider's printed order and the splitter's order need not agree, and a
by-position pairing turns one shifted line into a column of wrong offers. Each cloud line resolves
to exactly one of:

| Outcome | Rule | What the user sees |
|---|---|---|
| `sameAmount` | the first free local line with the same amount (CHECK 3 tolerance) | an offer only when title, category or cost differ; a partner that agrees is no offer |
| `title` | no amount match; the free local title with the highest token overlap ≥ 0.5 | the same |
| `new` | neither | a `fillsBlank` offer: a dimmed appended line the user accepts or leaves |

A local line no cloud line pairs with is **left alone** - the cloud never proposes deleting what the
user's split has. Every offer defaults to **keep mine**; `merged(taking:)` re-runs the same pairing
so a ticked line lands on the local line it was shown against. **The arithmetic gate**: a reading
whose lines do not sum to its header total within CHECK 3's tolerance is `doesNotAddUp`; its lines
are still offered, and the total's offer carries `attention` so the copy says *check the lines*
rather than presenting the sum as settled.

**Where the offers render (PJ.303, 2026-09-18).** Two surfaces, one pairing. Within the 3 s budget
`ServiceEntryView.offerLines` runs the same `LineMatcher` over the form's rows and holds the pairs as
`ServiceLineOffer`s BESIDE the form, never in it: a paired offer is the strip under its row (Take /
Keep), a `new` one is a dimmed card after the split (Add / Dismiss), and the flag is an amber line
under the header total. Nothing is written until an answer is tapped, so a save with every offer
unanswered persists the local split unchanged. A late reading goes to the inbox through the one
policy and the card lists the same pairs - the label names the USER'S row (`pairedLocalIndex`), the
"you entered" column shows that row, and an unpaired line is "New line". The capture sends every
page in one request; over the served cap (`extract.maxInvoicePages`, in `AppConfig.maxInvoicePages`)
no call is made - the total sits on the last page, so a truncated reading would fail the arithmetic
gate every time - and the form names the cap while every page is kept and split on the device.

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

## The five named failure modes

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
5. **The boilerplate kind.** A fuel kind read from a till's unit legend rather than from the
   product line. `receipt-062` (RN-Tver Chkalovskaya, 2026-09-11) OCRs its product line as
   `МИ95ФИРМ` at confidence 1.00 (`АИ` -> `МИ`), so the `95` marker is gone, and the parser then
   took `/СУГ` from the footnote `1 ед.=1 литр для нефтепродуктов/СУГ` - a line every slip from
   that till prints, `receipt-063` included - and committed `fuelKind = lpg` on a petrol fill.
   A stored wrong kind is a confident wrong value (hard rule 13), and this is the receipt-side
   twin of the pump rule above: a grade in a legend is evidence the station **sells** it, never
   that this fill used it. Fixed by restricting the marker to the product/line-item block
   (`FuelKindNormalizer.isBoilerplate`); a marker the product line loses now abstains. The paired
   `pump-085` and the slip both say АИ95, and `receipt-063` (same till, two minutes later) still
   resolves `petrol95`.

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
  forecourt canopy. The real pump photos (114 as of 2026-09-18, 17 when this was written) then
  stay a genuine **held-out** test set precisely because nothing was trained on them.
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
4. **Now due (product owner, 2026-09-18).** Steps 1–3 are done and pump capture still matters -
   it is the one capture mode nobody else ships (`docs/VISION.md`) and it is still off. Build the
   narrow seven-segment Core ML reader on synthetic data, validated against the **114** held-out
   photos. The design is "The pump reader" below; the rows are `docs/TASKS.md` → PU.

### The pump reader (decided 2026-09-18, product owner)

**Own library, not OCR alone.** Vision reads a seven-segment display as text and that is the wrong
abstraction: it has no notion of segment topology, so it returns a `4` for a `9` with one dim
segment at confidence 1.00 (`pump-004`), and it drops the decimal point the display renders as a
separate dot, which makes a factor-of-ten volume invisible to the cross-check. The reader is built
on the structure OCR ignores:

1. **Panel locator** - find the display and its number windows: high-contrast rectangular regions
   with a horizontal row structure. Classical CV (`vImage` / Core Image) first; a detector only if
   the corpus proves it necessary.
2. **Digit slicer** - seven-segment glyphs sit on a fixed pitch. Column projection splits a window
   into glyph cells; no character segmentation model.
3. **Segment classifier (Core ML)** - per glyph, **8 sigmoid outputs**: segments a–g and the
   decimal point. The digit is a lookup over the segment pattern, never a 10-class label. This is
   what makes the output compose with digit repair: a `9` whose segment `e` is uncertain is a `4`
   *candidate* with a known posterior, not a confident wrong digit, and P2.13's fixed confusion
   table becomes an ordering by posterior.
4. **Row assignment and decimal recovery** - rows go to total / volume / price by layout and
   `ExtractionCrossCheck`; the decimal point is recovered as the one placement that satisfies
   `volume × price = total` over the candidate set. Not unique → `nil`, never a guess.
5. **Output** - suggestions with per-field posteriors into the `.pump` source. Hard rules 13 and
   15 unchanged; a confident wrong value is worse than a `nil`.

**Training data is synthetic, and the corpus is never trained on.** A renderer draws glyphs from
per-make profiles (segment geometry, slant, pitch, LCD/LED/VFD look) for the makes the corpus holds
and augments with glare, blur, perspective, ghosting, canopy reflection and sensor noise. Every real
fixture stays held-out; the number-window annotations (`fixtures/pump/windows.json`, PU.2) are the
glyph-level test set and the locator's oracle. The gate is the existing `PumpPhotoGate` - precision
on committed cells ≥ 0.99, coverage against the 0.60 floor - scored by the same scorer, so the
reader lands on the same ratchet as the rules parser (53/320 as of this writing).

**Decisions (product owner, 2026-09-19).** (1) **The ship gate scores total, volume and
price only** - the grade-price board cells are annotated (`field: board`) and reported on
request, never in the headline; a board is a different display family (distance shot, often
dot-matrix) and no journey promises reading it. (2) **Capture is a Live Photo**: the product
owner shares HEIC files with the Live record, so the reader may assume several frames of the
panel at inference and fuse per cell (glare and reflections move, digits do not); the corpus
intake keeps the Live record. (3) **Synthetic geometry may be calibrated on the corpus's
aggregate shape statistics** (cell aspect, phase, digit mix, comma rate - from `slices.json`
rects and `windows.json` strings), never on pixels or per-fixture labels; the gate stays on all
114. (4) The locator question - whether a tap-to-frame crop is an acceptable v1 - is open. (5)
The shoot list stands: Scheidt +20, Tokheim +15, Lukoil/Adast +10, night +25, rain +15, KZT +10,
full-resolution originals, and a display-glass make per fixture.

**Decisions (product owner, 2026-09-19, second round).** (6) **The truth for a fill is the
receipt; the pump reading stands only when no receipt was provided.** For the gate that means
`expected.csv` (the receipt's values) stays the oracle - a display that rounds a total
(`pump-003` shows `20886.3`, the receipt says 20886.25) is not "read right" when the reader
commits the display value; the reader is expected to abstain on a truncated total and let the
arithmetic derive it from volume × price, which reproduces the receipt exactly. (7) **While the
gate is off, the app recognises what it can and says so**: a frame classified as a pump display
runs the reader, the Confirm pre-fill carries the reading with an alpha notice ("pump displays
are read in alpha - check every field"), typing stays the peer door, and no pump photo is parsed
as a receipt in silence. (8) **The locator is automatic** - a tap-to-frame crop is not the v1
answer; PU.24 builds the locator, Vision region proposals first.

**Decision 9 (product owner, 2026-09-19, third round): the corpus is split, and the split is
frozen.** The pump corpus was held-out in full - nothing trained on it - which kept every number
honest but left the classifier learning from synthetic renders alone. The owner chose a random
70/30 draw over a provenance cut: `Spike/ReceiptSpike/fixtures/pump/split.csv` names **64 of the
211 stills as `heldout`**, drawn once with a seed and never redrawn, and **every still added
after the draw is `train`**. The train part is the classifier's source of real glyphs (each
annotated window's cells, labelled by its `text`) and of detector boxes; the heldout part is the
only thing a model-scored ratchet may measure (`PumpReaderHarnessTests`,
`PumpReaderPipelineTests`, `PumpDisplayCaptureTests` read the split through
`PumpReaderTestSupport.isHeldout`). Ratchets that run no model - the law's oracle, row
assignment, the windows checker - still walk the whole corpus. A heldout number is therefore
what a user's phone sees; a train number is memorisation and is never written into a mark.

**Decision 10 (orchestrator, 2026-09-20, from PU.32's two reviews): the locator is a learned
row detector, and the verifier no longer judges by the classifier.** Both reviewers found the
same thing in the funnel: the law commits 526/611 on perfect strings, the read commits 66/175
on human quads, the live path committed 11 - the locator and verifier owned a sixfold drop, and
the verifier's margin threshold was fitted to one classifier, so every retrain moved the live
number without the classifier changing. The detector (`PumpRowDetector`, a Create ML object
detector trained on the train split's annotated windows and their tracked Live frames - no new
capture, no new annotation) proposes rows first; a detected row is kept on its cell count and
size alone; Vision's text boxes and the classical projection stay as the fallback under two
rows. Measured: live path 11 → 22 committed on the heldout split, all correct, at 2.4 s a photo
instead of 15. The three-tier ladder (oracle strings / annotated windows / live) is the way the
reader's numbers are read from here: a change is judged by which tier it moves.

**Where it lives.** Training, rendering, export and scoring are Python under `ml/pump-reader/`
(PyTorch → coremltools), outside every gate except their own `pytest`; the exported `.mlpackage` is
an app resource (`PumpSegments.mlpackage`, the cell classifier; `DigitRows.mlmodel`, the row
detector) and the locator, detector wrapper, slicer, decoder and Core ML wrappers are Swift in
`TankbookCore/Extraction/PumpReader/`, on the ordinary iOS gate. The detector's data, trainer and
heldout measurement are `ml/pump-reader/src/pump_reader/detdata.py` and `ml/pump-reader/detector/`. A trained reader is the second
non-rule producer of a field after the cloud model, and the same sentence governs both: it
suggests, it never trusts.

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
- **The inbox is its fourth consumer (RV.288, 2026-09-19).** A late answer that lands after the
  save (`GatewayInboxPolicy.fuelOffers`) runs the same `TimelineValidator.crossCheck` BEFORE it
  offers anything: three numbers that cannot coexist are one bad read, not three plausible
  corrections, so none of the three is offered and the card says the reading does not add up
  (`ERRORS.md` → Inbox). Two read numbers are checked against the user's third; one alone has
  nothing to fail against. A zero read is nil, never an offer - the owner's `0.56 L x 1.954`
  beside a `0.00` total (build 1344, 2026-09-15) is the instance. The confidences still do not
  reach the offer; that is the residual named in the row.
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

### The matched pairs are a check on the oracle (RV.114)

Eighteen pump/receipt pairs of the same fill are registered in `CorpusPairTests`, by name. Two
properties run over them. **Oracle-level, everywhere**: the two `expected.csv` rows of a pair agree
to the cent on litres and unit price, and on the total except where the two papers genuinely
differ - a display that truncates its total (`pump-083` prints `1437.20` for the receipt's
`1437.24`, `pump-110` `2953.00` for `2953.02`) or a receipt that rounds (`receipt-007`'s `4334.00`
for `pump-002`'s `4334.83`), each written beside the pair. A pair whose oracles disagree is a wrong
expectation, and a wrong oracle freezes a defect as the standard. **Extraction-level, on the
measured runtime**: where both halves commit a cell, they commit the same value - a display read
that contradicts the receipt of the same fill is the most provable confident-wrong value the corpus
can produce. Proxy-run on macOS 27 (2026-09-19): no pair contradicts itself; the pumps of the
RV.114 set abstain and their receipts resolve.

### Orientation: Vision handles it, the app does not rotate first (decided 2026-09-19, RV.114)

The corpus holds a 90°-rotated pump (`pump-069`), a 90°-rotated receipt (`receipt-050`), an
upside-down receipt (`receipt-051`) and two sideways terminal slips (`receipt-068`, `-069`).
The fixtures carry the rotation in their pixels (EXIF stripped), `VisionTextRecognizer` hands
the pixels over as they are (a file's EXIF and a camera buffer's `imageOrientation` are honoured,
nothing else is inferred), and the recognizer reads rotated text itself: on macOS 27 `receipt-050`
and `receipt-051` resolve all five cells - the rotation cost nothing. The sideways slips are the
exception, and what they lose is glyph fidelity on a dense Cyrillic print (the RV.292 shapes), not
the layout. So: **no pre-rotation, no orientation question.** A capture goes to Vision as taken;
a poor read degrades to "correct a field" through the same head-start rule as any other (hard rule
15), and the confident-wrong properties (totals, kinds, litres, pairs) are what keep a garbled
rotated read from becoming a value. If a future runtime loses the rotated receipts, that is a
measured regression on the L5 gate, not a reason to add a rotation step ahead of the evidence.

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
