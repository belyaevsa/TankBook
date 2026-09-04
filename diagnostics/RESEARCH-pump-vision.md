# RV.58 - What is the right algorithm to read a pump display, and is 95% reachable?

## The honest number, first

The brief frames it as "53/261 (20%)". The evidence `diagnostics/pump-ocr-dump.txt`
(regenerated this run, summary at the bottom) says something materially worse, and the
difference is not noise - it is the frame itself.

| what is counted | cells | correct | rate |
|---|---|---|---|
| all five columns (liters, unitPrice, total, fuelKind, currency) | 261 | ~53 | 20% |
| **the three numbers the mode exists to read** (liters, unitPrice, total) | **178** | **4** | **2.2%** |
| arithmetic cross-check `liters x unitPrice == total` | 66 | 0 | 0% |

`expected.csv` non-empty by column: liters **66/66**, unitPrice **51/66**, total **61/66**,
fuelKind **17/66**, currency **66/66** (I re-counted the file directly; 178 is the numeric
sum, 261 the all-columns sum).

Where the "20%" comes from, and why it is misleading:

- **Currency** (66 cells) is read from the `€` / `РУБЛИ` / `ТЕНГЕ` / `EUR` marker printed next
  to the numbers. It is nearly free and mostly locale-inferable - it is not the thing a pump
  photo is for. Counting it makes the mode look ~25x better than it reads.
- **fuelKind** (17 cells) is a column the design says a pump parser must **not** fill at all
  (`docs/EXTRACTION.md` line 113: "Never infer fuel kind from a pump photo"; `docs/SCHEMA.md`
  - the grade badges belong to every nozzle, not to the fill). The current parser still emits a
  grade guess on many fixtures (the dump's `Fuel` column shows `95`, `SUPER`, `АИ-92`), so it
  is also being scored on behaviour the spec forbids.

So the honest statement is: **the pump mode reads 4/178 numeric fields (2.2%), its cross-check
passes 0/66, and every widely-quoted "20%" on this class is mostly currency detection plus a
grade guess.** The 95% gate, wherever its denominator is set, should be measured on the 178
numeric fields - not on currency, and not on fuelKind.

(One more distortion that cuts the other way and is worth naming now: `pump-016` and `pump-017`
are **idle** pumps showing `0.00`/`0.00`, and their 4 numeric cells (liters+total on each) are
ground-truth zeros. A field-recall metric rewards a parser that returns `0.00` for them - which
the README, `JOURNEYS.md` F-notes and hard rule 15 all say is the exact bug to avoid: an idle
pump must be **refused**, not logged as a zero-litre fill-up. So recall actively rewards the
design-violating output. This is one of two reasons the gate's instrument is wrong - see the
95% section.)

## What the photographs actually show

I opened 19 fixtures at full frame (listed in "What I actually looked at"). The display
hardware splits into four glyph families, and the split matters because no single recognizer
covers all four:

1. **Classic seven-segment, black-on-light-grey** (Dresser / Dresser-Wayne, some Gilbarco):
   `001 005 013-017 021-025 029 033-038 041-043 051-056 061-064`. In this family the decimal
   separator is a **small, cleanly printed dot or comma** beside the digit, and - this is the
   point - it is usually physically present and clearly legible in the source photo.
2. **Zero-padded, comma-separated, bright-segments-on-dark** (Gilbarco Veeder-Root):
   `009 011 012 019 020 026-028 031 032 039 040 045-050 057-060`. Leading zeros, comma
   decimals ("`02038,00`"), same digit family as (1).
3. **Dot-matrix / custom LCD** (Tokheim, Adast, Scheidt): `004 006 010 030 065 044`. Crisp
   dark-on-amber or on-white - better text contrast than (1), but the digits are *two or three*
   segments wide, and on Tokheim the separator is a full-size comma rendered below the baseline.
4. **A video screen** (Topaz): `008` - the numbers are overlaid on cartoon footage, and also
   repeated in a small LCD strip beneath; the strip is the authoritative readout.

### The decisive observation: the separator is lost by *Vision*, not absent from the display

The brief's framing ("the decimal point is not in the recognised text at all") is subtly wrong in
a way that changes the answer. I looked specifically for whether the displays genuinely lack a
separator. They do not. `pump-005`, `pump-009`, `pump-057`, `pump-058`, `pump-030`, `pump-065`
all render a **clear** dot or comma in the source; `pump-005`'s dots on `4621.08` and `87.92` are
unmistakable, a human reads them instantly. Vision still returned `462108`, `8792`, and on
`pump-009` `0203800` / `05095`.

That is falsifying evidence for one whole candidate fix: **cropping and upscaling the LCD window
and re-running Vision will not recover the separator.** The separator was already large and clean
in `pump-005` and Vision swallowed it anyway. Vision is a *text* recognizer; the small dot is not
a character it emits, and making it bigger does not make it a character. A different instrument
is needed for the separator.

And it is per-field, not per-image: `pump-058` kept the comma on liters (`0020,02`) and price
(`1,969`) and dropped it on the total (`003942`); `pump-057` kept it on the `€/L` price (`1,799`)
and dropped it on `10038`/`005580`. `pump-007` printed clean commas and Vision read the total
`4553.46` with its comma but split the liters row into `602` + garbage. So the separator loss is
0-2 cells on a single display, stochastic, and clustering on exactly the arrowhead that carries
the field's meaning.

The second broad failure, equally visible: **the digits themselves are misread under glare or low
contrast**, independent of the separator. `pump-004` (Tokheim) shows `3008`; Vision returned
`1408`. `pump-052` shows liters `34.64`; Vision returned `7464`. `pump-049` (the faintest LCD)
returns nothing useful at all (`74798` for a display that reads `0010,98 / 0005,81 / 1.889`).
`pump-022` (glare) returns `30|` / `52.49` / nothing for values the photographer read off the
pump. So recognition is genuinely the bottleneck here - but it is a *composite* of (a) separator
loss, (b) single-digit misread under glare, and (c) whole-field wash-out at low contrast. Each
needs a different lever.

The third, already-named failure is that **the forecourt is the frame**: on `pump-001` the parser
picked `0,5-0,7l` out of the sandwich promo "Wrapper ja jook" as 0.700 litres, and the dump is
full of insta-advertising (`Hot dog ja jook`, `RedBull`, `SOAPBOX`, `RACE`, `VISA`,
`Vali maksemeetod`, `Kviitung väljastatakse peale tankimist`) plus pump serial numbers
`AE0105xx` / `M26` and nozzle badges. The ROI idea is real and cheap, but it addresses this third
failure, not the first two.

## The ranked list

Ranked by honest upside per unit of risk and cost. They are not competitors - the first three are
stages of one pipeline and they compose - but they are ranked by what a rational, single-owner
build order would do, and by whether the gain is *real* (a value the photo actually carries)
rather than an artifact of the metric.

---

### #1. A narrow per-digit classifier that treats the separator as a first-class class
**What it is.** Not a general OCR - a tiny CNN (a few hundred KB, Core ML) that classifies
*one glyph cell* as blank / 0-9 / decimal / separator (dot or comma, one class either way). This
is exactly what `docs/EXTRACTION.md` → "Where a trained model fits" already recommends for
pump (step 4), and it is the only instrument that can honor a separator that Vision cannot.

**Layer.** `2. recognize` (it replaces the Vision pass over the display region).

**Expected gain, counted per fixture.** The separator loss is the single largest *systematic*
miss in the class - it touches tens of cells and, when lost, silently re-scales the field (10x,
100x). It is also the second-largest source of *wrong* values after the glare misread. Reckoning
per fixture against the current 4/178:

- Recovers the separator on the (roughly) 35-40 fixtures whose display carries it cleanly but
  Vision dropped it - this is most of `001 002 003 005 006(KZT: total integer is not a lost
  sep, see note) 009 013-015 026-028 029 033 034 036-040 043 045-047 050-057 058-064`. Each
  such fixture gains 1-3 correct cells (the ones where the separator was the only loss). Call it
  **+55 to +75 cells**.
- Recovers the glare-misread digit on the handful of fixtures where a segment is filled by light
  (`004`, `015`), because a per-digit classifier has per-digit posteriors and can be thresholded
  to abstain on a low-attention glyph. **+3 to +5 cells**, and - the more important part - it
  converts a *confident wrong* into *nil* on the rest.
- Does nothing for the wash-out / faint tier (`049`, `022`), which needs contrast conditioning
  (option #2) not a better glyph classifier.

Net: roughly **+60 to +80 cells, taking the class from 4/178 to ~64-84/178 (~36-47%)** by
itself, and it removes most of the confident-wrongs. That is a large jump, but note it is still
*below* 95% - because a recognizer that reads a display correctly is not the whole problem (see
the 95% section).

**Cost.** Highest of the six: a synthesized-data training pipeline (render unlimited seven-segment
glyphs with glare, blur, perspective, ghosting, canopy reflection), a small CNN, and a Core ML
conversion. `EXTRACTION.md` already scopes this as a few-hundred-KB model, offline, no gateway.
**Runtime on iPhone 12:** milliseconds for a model that size on a cropped region; the run is
bounded and comfortable on the floor device.

**Wrong-answer risk.** Low, *provided* two rules are enforced (both are `EXTRACTION.md` rules):
(a) a per-digit posterior above a generous threshold is required before a digit is committed -
below it, `nil`, never a best-guess; (b) the separator is a class, and a *plausible-but-unseen*
separator position is never injected. The digit-repair rule then orders the candidates from the
posteriors rather than a fixed confusion table, which is a strict improvement.

Abstains instead: any glyph with low posterior, any cell where two substitutions both close
(exactly-one rule), any field where the scale is not uniquely pinned after the band + tank
capacity.

**Generalizes.** Fully for seven-segment (families 1 and 2 above - Wayne, Dresser, Gilbarco,
covering essentially all the EE/EU fixtures and the RU/KZ Gilbarco ones). It does **not** cover
family 3 (Tokheim / Adast / Scheidt dot-matrix) or family 4 (Topaz video) - those are a *different*
glyph set and need either text-OCR (which reads their digits fine: `004` is only *digit*-confused
because a segment folds, not because the font is unreadable) or a second detector. So the reader
alone gets you to ~47%, and the RU/KZ dot-matrix tier caps the ceiling on the remaining six.

---

### #2. Display-region detection + per-field crop + upscale, used to *segment* not to decide
**What it is.** Detect the bright, high-local-contrast, fixed-aspect LCD rectangle (Vision region
proposal or a simple geometry/brightness detector); crop each labelled window (SUMMA/value,
LIITRIT/value, €/L or ЦЕНА/value); upscale; run the classifier from #1 on that window, and feed
the *result* to the resolver. The crop is used to isolate the glyphs - never to choose which
number is the field.

**Layer.** `1. acquire` and `2. recognize`.

**Expected gain.** Kills the **"surroundings are data"** failure, which is failure mode 3 in
`EXTRACTION.md` and produced the `0.700` litres on `pump-001` and the four-price-board-as-price
errors on `005`/`034`. The dump is unambiguous that the frame is the confounder: the parser's
non-values on dozens of fixtures are adverts, serials, payment furniture and nozzle badges, all
of which a display-only crop removes. Counted: `001` (0.700 → nil, and the real 67.00 becomes
reachable), and the four-price fixtures where the board price was scraped as the transaction
price. Roughly **+25 to +40 cells** (mostly by letting the true value through and by de-noising
the resolve stage), and it prevents a large set of confident-wrongs.

**Cost.** Low: Vision-based region proposal + affine crop + upscale, no training. **Runtime on
iPhone 12:** tens of milliseconds, CPU/CoreML - the cheapest real win on this list.

**Wrong-answer risk.** Low *only if* the crop is never used as evidence of identity. A crop
narrows the OCR to one window; it does not know that window is "SUMMA". The label association
must stay where it is today (geometric label pairing in the resolver). If it is also used to
decide, it becomes a way to swallow a board price.

Abstains instead: if a display panel cannot be detected, or a labelled window's crop comes back
empty/low-contrast, the whole display abstains and the manual door opens (rule 15).

**Generalizes.** Yes, but it must be pump-family aware (the window layout differs by make:
Wayne stacks SUMMA/LIITRIT/HIND over four board prices; Gilbarco stacks total/L/€/L with an
activity strip). A generic "bright rectangle" detector plus geometric label pairing covers the
corpus; a fixed layout per make is the cap on how much it buys.

**Critical caveat, restated because it is the tempting wrong path:** this fix does **not**
recover the separator. `pump-005` had large clean dots and Vision still returned `462108`; a crop
of `4621.08` upscaled still runs through Vision and still drops the dot. #2 must be paired with a
recognizer that emits the separator (#1), not substituted for it.

---

### #3. Arithmetic recovery as a bounded solver, with abstention
**What it is.** `liters x unitPrice == total` over unknown decimal placement: search plausible
powers of ten (10^0..10^3 per operand) for the scale that closes, then disambiguate with the
price band for the currency, the car's tank capacity (the app already holds it per vehicle), the
plausible-volume band, and the exactly-one digit-repair rule. This is partly built: P2.13 (digit
repair) already implements the exactly-one-substitution rule.

**Layer.** `4. resolve` and `5. cross-check`.

**What it resolves, and its exact limits** (this is the part the brief asks to be precise about):

- **Resolves a single misread digit** (`pump-004` 1408 vs 3008; `pump-015` 1.884 vs 1.889;
  `pump-025`'s destroyed total digit, recovered as `40.99 / 22.91 = 1.789` = the Futura 95 board
  price; `pump-013` 7.34 x 1.779 = 13.06). The cross-check is the one thing that catches a digit
  error *at confidence 1.00*.
- **Resolves discrete-candidate choice** - the one job it unambiguously does. On
  `pump-005` only `52.56 x 87.92` reproduces `4621.08`; on `pump-034` the four board prices are
  1.934 / 1.834 / 1.819 / 1.759 and none is the charged 1.839, so here it must **not** be used
  to pick - the honest output is `nil` price (the receipt is the only source; `expected.csv`
  leaves it empty).
- **Is blind to scale and to swap.** `liters x price == total` is invariant under scaling
  (multiply either operand by 10^n and the equation still holds), so on `pump-003` brute-forcing
  over 10^0..10^3 per field gives **12 solutions**, narrowed to 2 by the KZT band + plausible
  volume, and one of those two is `8.525 L` vs `85.25 L` - a **factor-of-ten ambiguity in volume
  that survives every automatic filter**. And `a x b == b x a`, so a volume/price **swap** is
  invisible to it. These two are exactly why the resolver ladder (unit markers, price band, tank
  capacity) and the user are non-optional.

**On `pump-010` (the preset), it must NOT "fix" anything.** `13.17 x 75.95 = 1000.26` against a
printed total `1000.00`. Nothing is misread: the customer asked for exactly 1000 ₽, the pump
dispensed `1000.00/75.95 = 13.166...` L and rounded the volume to two decimals. The gap (0.26) is
real and the display - not the parser - is the lossy party. The exactly-one repair rule finds no
single-digit substitution that reproduces 1000.00 exactly, so the engine **abstains from repair**
and the honest `13.17 / 75.95 / 1000.00` stands (cross-check = `mismatch`, fields correct). The
killer is that `pump-010`'s gap (0.26) and `pump-015`'s real misread gap (0.08) are both "under a
rouble", so **the gap alone cannot distinguish a preset rounding from a misread** - `EXTRACTION.md`
says this explicitly. Only the exactly-one rule and a hard "repair only when it reproduces the
total at the display's two-decimal money precision" boundary keep them apart, and both are already
specified.

**Expected gain.** **+30 to +50 cells** on top of #1+#2, and - the load-bearing value - it turns
the *wrong values* that #1/#2 still produce into `nil` on ambiguous or inconsistent triples
(`pump-003`'s volume, `pump-034`/`-051`/`-055`/`-056`/`-061`'s off-board price, `pump-010`'s
preset, `pump-031`'s discount mismatch, `pump-042`/`-056`'s reverse-inference preset).

**Cost.** Low-to-medium: most of the solver already exists (P2.13); the genuinely new parts are
the tank-capacity tie-break and the abstention-on-ambiguity policy. Runtime negligible (a 4x4
power-of-ten search over a few operands is microseconds).

**Wrong-answer risk.** **High if ever applied silently** - this is the single most dangerous
routine in the pipeline, because it is exactly the thing that can fabricate a plausible wrong
fill-up (`pump-003`: `4621.08/52.06 = 88.76 L` is self-consistent and wrong by 0.84 L if you pick
the wrong of four prices). Every automatic output here is a **suggestion** the user sees (hard
rule 13), and the abstain-on-ambiguity rule (`nil` where scale or candidate is not unique) is the
part that keeps it from inventing digits. The one-safe exception is when separators were **read**
(not guessed) by #1: then the arithmetic is a genuine consistency check again, not a blind
search - which is the strongest argument for #1 over #3 as the centre of the solution.

**Generalizes.** Yes, but only as a *constraint* layer, and it is currency/price-band dependent
(the KZT vs RUB band difference is what resolves `pump-003`'s price but not its volume). It does
not generalise to a "trust it" posture on any currency; it generalises as "check and refuse".

---

### #4. The paired match as ground truth, and as a fallback when the pump is unreadable
**What it is.** Use the six-plus deliberate pump/receipt pairs (`001`+`receipt-001`,
`018`+`receipt-036/037` (a triplet), `019`+`receipt-038`, `034`+`receipt-042`,
`054`+`receipt-045`, `057`+`receipt-046`, `002`+`receipt-007`, `044`+`receipt-044`,
`065`/`066`) as independent truth. `pump-054` is the worked case: the display's total is hidden by
flare, litres 26.94 and price 1.919 are readable, `26.94 x 1.919 = 51.6997 -> 51.70`, but the
paper says **51,71** - so the pair records reading, and computing would have been wrong by a cent.

**Layer.** Product-level, not a single pipeline stage.

**Expected gain.** Small as a *scoring* lever (the pairs already pass/fail in the corpus), and it
is the reason the corpus carries them. As a *product* answer it is weak: a pump scan exists for the
**no-receipt** case (J4), so the matched-pair path only helps where the paper exists - the exact
opposite of J4's trigger. It cannot rescue the glare trio (`021/022/023`), which have no receipt.

**Cost.** Low (harness + a "if the paired receipt is legible, trust it over the pump" rule).

**Wrong-answer risk.** Low. But it must still apply hard rule 13: a paired receipt settles an
*otherwise-ambiguous* value, it does not auto-trust it into the log.

**Generalizes.** Not as a production algorithm - the fixture-level pairs are a validation harness
and a way to pin down "same fill, two views". It is worth building for its value as a test
oracle (and it is the only way to get pump `unitPrice` on the off-board fixtures), but it is not
the answer to "how do I read a pump".

---

### #5. Detect and refuse the non-fill states (idle, previous customer, zero)
**What it is.** A guard that classifies the display state before any field is extracted: an idle
pump (`016`, `017` - `0.00`/`0.00`), a previous customer's transaction (a pump readout persists
until the next fill starts), and a genuine zero. On any of these the correct output is a refusal
and a prompt to the manual door (hard rule 15), never a zero-litres fill-up.

**Layer.** `3. classify` / `4. resolve` (a state gate before the value finders).

**Expected gain.** Not a cell-count gain - it is a *wrong-value* elimination. The two idle
fixtures are the reason this matters: returning `0.00 / 0.00` for them is the exact bug the README
warns about, and the current scorer would actually reward it (see the number table above). It
also prevents silently using a prior user's numbers as "the" fill, which is the harder of the
two (the README's "an earlier customer's transaction" note).

**Cost.** Very low: a zero-total / zero-volume / all-zero-window detector.

**Wrong-answer risk.** None if it only refuses *obvious* zero/idle states and abstains otherwise.

**Generalizes.** Broadly, and it is a genuine product-correctness rule rather than an accuracy
tweak.

---

### #6. Refuse honestly, or re-base the gate (the real decision)
**What it is.** Change the *instrument* rather than the algorithm: the mode is worth shipping the
moment it returns **correct** values on the fields it commits to and abstains on the rest - the
value of a pump capture under hard rule 15 is a *head start*, i.e. a pre-fill the user confirms,
not an auto-trusted entry. See the 95% section for the argument and the concrete re-basing.

**Layer.** Product definition / the gate in `PumpPhotoGate`.

**Expected gain.** Zero on cells; maximal on ship/no-ship correctness.

**Cost.** Low (a gate-instrument change, copy, and the ratchet's definition).

**Wrong-answer risk.** None.

**Generalizes.** To any feature whose truthful ceiling is below its stated gate, and to the
decision the milestone actually needs: the pump mosaic has a hard ceiling (below) and the product
should decide explicitly what to do with a mode that cannot pass its own gate, rather than leave
it dark forever or silently weaken the gate.

---

### "Anything else the photographs suggest"

- **Never infer fuel kind from the pump.** Family 1 and 2 displays carry nozzle badges (95, 98,
  D, miles+) that belong to *every* nozzle; the four-price board order differs per pump and even
  per visit (README: `pump-061..064` show the same five grades in different orders, and some
  boards omit a grade). This is already a hard rule; the dump shows the parser still guesses. Leave
  fuelKind empty from a pump only where a paired receipt settles it.
- **Separator style and zero-padding are per-pump, never per-locale.** `002` (dots) vs `007`
  (commas) at the same station and brand; `pump-045..050` (Gilbarco, commas, padded) vs
  `pump-051..056` (Wayne, dots, unpadded) at one forecourt. The pipeline must infer the convention
  from the recognised field's own geometry (which separator class fired in #1, leading-zero
  pattern), never from the locale.
- **Several numeric formats on one display.** `pump-006` (KZT) is integer total `10980` (KZT has
  no subunit in practice - **not** a lost separator), two-decimal `45.00` litres, integer price
  `244` (clipped by the bezel). A parser cannot infer a document-wide convention; it must label
  each field from its own marker, and the cross-check (`45.00 x 244 = 10980`) is the only reason a
  clipped price can be trusted as complete.
- **Boards price a different product than is charged.** The Wayne forecourts (`034`, `051`,
  `054`, `055`, `056`, `061`) advertise prices, and the charged price is frequently *none* of
  them (`pump-057`'s `1.799` is absent from every board on the site; `receipt-042`/`-046` settle
  it). A parser that resolves a fill against a boarded price is wrong a large share of the time.
  Read the **transaction price window** (Gilbarco's `€/L` window) when it exists, and leave
  `unitPrice` empty when it does not.
- **The video/duplicated display** (`008`): prefer the physical LCD strip over the stylised
  overlay; the values appear twice and agree, so the redundancy is a free cross-check on a family
  that otherwise has none.

## "Is 95% reachable?"

**Not on the live corpus - and there is a structural reason, not just a hard one.**

Compute the ceiling honestly. The scorer measures the *numeric* fields that `expected.csv` says the
photo carries = **178 cells**. Of those, a handful are ground truth that is **not in the image**:

- `pump-021`, `pump-022`, `pump-023` carry litres and total values that the **photographer read
  off the pump**, not off the photo - the README says so explicitly ("a photo can be past the
  point where any amount of zooming recovers it, while the human standing at the pump has no
  difficulty at all"). That is 6 cells (litres+total x 3) that no recognizer can turn into hits,
  because the digits are not in the image.

Even with a **perfect** reader on every other cell, the ceiling is therefore
`(178-6)/178 = 172/178 = 96.6%`. That is *above* 95% but by **one and a half points** - leaving
about **three cells of slack for the entire real world**.

Now add the tier that a real reader cannot clear: the faint LCD (`049`), the glare-washed
`052`/`053`/`054`/`022`/`025`/`041`/`035`/`038`, the reflective `0`/`8` (`018`), the occluded or
clipped (`063` board, `006` price). Eyes on these: `pump-052`'s litres `34.64` are readable but
under a big reflection; `pump-049` is genuinely grey-on-grey. A strong pipeline recovers maybe
60-75% of this hard tier, and that is what costs the other point or two. A realistic, well-built
reading of the corpus lands **~91-94%**, i.e. **at or just below the line**, on the 178 cells.

But the honest, load-bearing argument is that **95% is the wrong instrument**, and getting the
instrument right matters more than chasing the last points:

1. **Recall rewards what the design forbids.** Field-recall counts a cell correct if the returned
   value equals ground truth. That rewards returning `0.00` on the two idle pumps (the exact bug
   the README and hard rule 15 call out) and rewards a confident-wrong guess that the user fails
   to catch on the Confirm sheet - while punishing a correct `nil` (an honest abstain) on the
   factor-of-ten (`pump-003`), the off-board price (`pump-034`/`-051`/`-056`), and the preset
   (`pump-010`/`-042`). Hard rule 13 states the opposite value order explicitly: **a confident
   wrong value is worse than `nil`.** A metric that scores `nil` as a miss and a confident wrong as
   a hit is measuring the wrong thing.
2. **The pump's arithmetic leaves interpretation ambiguity no recognizer removes.** Scale
   (factor-of-ten survives every filter), swap (`a x b == b x a`), preset-vs-misread (gap alone
   cannot tell), and off-board price. On all of these the correct output is `nil` + the user -
   which is a field-recall *miss*. So even a 100%-correct recognizer cannot reach 100% recall,
   because correct recognition is sometimes "I don't know, and I will not guess".
3. **The value the feature provides is precision-with-abstention, not recall.** Under rule 15, a
   pump scan is a "head start, not an answer": the user reviews the pre-fill on the Confirm sheet.
   What the user needs is that the values the app *does* offer are right and that it never writes
   a wrong fill-up silently - that is a **precision** property, and precision is driven to ~100%
   by abstaining on anything ambiguous. A 75%-recall / ~100%-precision pump reader is a large,
   genuinely useful win over the manual form; a 95%-recall / 90%-precision one is a data-poisoning
   hazard.

**The answer the product should give.** Re-base `PumpPhotoGate` on **precision on committed
fields** (of the numeric fields the pipeline returns as non-nil, how many are correct), with a
floor on the *pre-fill share* and an explicit abstention-for-anything-ambiguous policy (which the
exactly-one repair rule and the band + tank-capacity + `nil` ladder already enforce). Set the gate
to "commit only what is uniquely pinned; shipped when committed-value precision >= ~99% and at
least ~60% of the three numeric fields are committed". Under that gate the feature **can** ship,
and it ships honest: it never fabricates a fill-up, it pre-fills what is certain, and everything
else is a field the user types (rule 15). Alternatively, if the product insists on a raw >=95%
field-recall gate, then the honest status is the current one - **the mode stays off** - and the
95% target should be recorded as unreachable on this corpus and re-baselined against a subset of
fixtures the photo actually carries cleanly (which is also a defensible, smaller gate, but it must
be said out loud that it is a smaller gate).

Do not ship a mode that clears 95% by your *number* but writes a factor-of-ten `85.25` as a
factor-of-ten somewhere it can't be seen - that is the outcome the existing design exists to
prevent, and it is the reason the gate is the check.

## "What I would not do"

- **Do not try to make Vision emit the separator by cropping/upscaling it.** `pump-005` already
  falsified this: the dots were large, clean and readable at full frame and Vision still returned
  `462108`. You would spend real effort and the separator loss survives.
- **Do not build the arithmetic solver as the centerpiece and trust it.** It is scale- and
  swap-blind (`pump-003` = 12 solutions, factor of ten; `a x b == b x a`), it cannot distinguish a
  preset rounding from a misread (`pump-010` vs `pump-015`), and it will happily produce a
  self-consistent wrong fill-up (`4621.08 / 52.06 = 88.76 L`). It is a constraint layer that ends
  in `nil`, never an answer. The centre of the solution must be a recognizer that actually *reads*
  the separator; arithmetic then becomes a free consistency check again.
- **Do not threshold on Vision's confidence.** `pump-004` returned a wrong digit (`1408` for
  `3008`) at confidence **1.00**, and `ocrConfidenceThreshold` is a remotely-configurable key. No
  threshold exists that catches a 1.00 wrong. Only the cross-check and the per-digit posterior of
  a dedicated classifier (which does have a real, trainable confidence) can.
- **Do not attempt fuel kind from the pump.** The badges and the four-price boards belong to every
  nozzle; the order and the grade set are unstable; the fill is frequently diesel where the board
  says 95. Empty `fuelKind`, and let the receipt or the user settle it.
- **Do not resolve a fill against a boarded price.** On the Wayne forecourts the charged price is
  routinely *none* of the boarded prices (`034`, `051`, `054`, `055`, `056`, `061`), so picking the
  nearest board price to close the arithmetic will be wrong a large share of the time. Read the
  transaction price window if it exists; otherwise `nil` (and the receipt settles it).
- **Do not patch the metric instead of the algorithm.** A 95% gate that counts currency and
  fuelKind is already, in effect, a 95% gate on the wrong thing - the "20%" headline is largely
  currency detection. Re-basing the gate must be done deliberately and in the same change as the
  reasoning, not quietly so the number turns green.
- **Do not treat a matched pair as a reason to lean on the receipt side.** The pair path is a
  validation oracle; J4's whole trigger is the *absence* of a receipt.

## "What I actually looked at"

**I opened the photographs - 19 images directly** (this brief explicitly said a text dump is not a
substitute, so I looked; I did not use the `read` tool on more than these, but I cross-checked the
rest against the dump and README):

`pump-001` (converted `.heic`->`.jpg` to view), `pump-003`, `pump-004`, `pump-005`, `pump-006`,
`pump-008`, `pump-009`, `pump-010`, `pump-022`, `pump-025`, `pump-030`, `pump-034`, `pump-049`,
`pump-052`, `pump-053`, `pump-057`, `pump-058`, `pump-063`, `pump-065`.

From those I confirmed: the separators are physically present on the seven-segment family and
dropped by Vision (clear on `005`); the dot-matrix/backlit Tokheim/Adast/Scheidt family is a
different glyph set (`004`, `006`, `010`, `030`, `065`); the glare wash-out (`022`, `052`, `053`,
`025`) and the faint LCD (`049`) are contrast, not geometry; the insect occlusion (`063`) and the
bezel-clipped price (`006`) are capture failures no processing recovers; and `057`'s `€/L` window
is the only place the transaction price lives on a Gilbarco.

**I also read, in full:** `Spike/ReceiptSpike/fixtures/pump/README.md` (all 696 lines - the
single most valuable document here, and it is what saved me from re-proposing several already
falsified ideas), `Spike/ReceiptSpike/fixtures/pump/expected.csv` (re-counted the cells by hand),
`diagnostics/pump-ocr-dump.txt` (all 2071 lines, including the summary table), and
`docs/EXTRACTION.md` (the pump sections and the "Where a trained model fits" / P4.12 / P4.13
conclusions). I cross-examined the pump gate contract in `docs/TASKS.md` P2.7 and the J4 journey
in `docs/JOURNEYS.md`.

**What I did NOT do:** run `git`, run `swift build`/`swift test`/`xcodebuild`/`swiftlint` (another
agent is implementing here and Vision tests serialise badly), touch `docs/TASKS.md`,
`agents/briefs/`, `expected.csv` or any fixture image, or use `pgrep -f`. The only filesystem
write was `diagnostics/RV.58-pump-vision.md`. The `.heic` you asked me to read I converted to a
temporary `.jpg` under the pre-approved temp directory, and did not modify the corpus file.
