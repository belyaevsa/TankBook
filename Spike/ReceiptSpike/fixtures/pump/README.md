# Pump-display photos

Photos of the pump readout, for the **pump-photo mode** that `docs/VISION.md`
gates hard: it ships only at **>=95%** accuracy, or the mode stays off
(`docs/TASKS.md` P2.7 - "the gate IS the check").

## The flag's contract (P2.7, recorded 2026-08-25; re-scoped 2026-09-04)

Pump mode is a **feature flag** with this contract, enforced by code and by a
build-failing test rather than by prose:

- **Defaults off.** The bundled config ships `pumpPhoto` disabled; the app is
  fully usable with it never turning on.
- **The gate is a property of the build, not a runtime opinion.** The measured
  pump accuracy is compiled into `PumpPhotoGate` and asserted against the live
  corpus score by the Vision-gated ratchet test. A remote config document may
  only ever turn the flag **down** while the gate fails, never up -
  `ConfigStore.isEnabled(.pumpPhoto)` is false regardless of rollout below the
  threshold. This is the same reasoning as `docs/CONFIG.md` -> "Config can
  never disable a security control".
- **Off is not a dead end (hard rule 15).** A pump capture with the flag off
  routes to the ordinary manual form, pre-filled with nothing and with no
  message - the feature is simply not offered, and there is no error to show.
- **On (developer builds) still obeys hard rule 13.** Extraction may pre-fill,
  but every field is a default input the user edits; a pump **volume in
  particular** must never be written without the user seeing it, because the
  factor-of-ten ambiguity (`pump-003` above) is invisible on a Confirm screen.

### The gate's metric, since 2026-09-04 (B1)

The gate is no longer a recall average. The old `measuredHits / measuredTotal >=
0.95` scored a denominator of three different things - the 178 numeric cells,
a near-free `currency` marker lookup, and `fuelKind`, which a pump parser must
never produce - and recall itself was the wrong shape: it scores a correct
`nil` as a miss and a confident-wrong value as a hit, and on the two idle pumps
(`pump-016`/`pump-017`, ground truth `0.00`) it actively rewarded logging a
zero-litre fill.

The pump class is now scored on its **178 numeric cells only** (`liters`,
`unitPrice`, `total`; blanks skipped). `fuelKind` is dropped from the pump score
and `currency` is reported separately, never in the gate. Three numbers replace
the single average, all over the 178:

- **precision** = `committedCorrect / committed` - of the numeric fields the
  parser returns non-nil, the fraction that are correct.
- **coverage** = `committed / 178` - the fraction of numeric cells it commits
  to. A correct refusal (idle pump, factor-of-ten tie) lowers this, never
  precision.
- **recall** = `hits / 178` - the old number, kept for legibility.

`PumpPhotoGate` ships the mode only when **committed-value precision is at or
above ~99% AND coverage clears the 60% floor**. The threshold's *meaning*
changed, not just its number: "never a wrong fill-up" is a precision property,
not a recall average. The 60% floor is a product decision, not a derived number
- it is what the deterministic ladder reaches on the OCR text that already
exists, and the floor below which a three-in-five pre-fill stops being a head
start worth offering. Raising precision above 99% while clearing the floor is
the only way the flag can turn on - and it must land in the same change as the
parser fix that earned it, together with the recorded high-water mark and this
README. The mode stays off; nothing here turns it on.

## What is here

`pump-001.heic` - Circle K, Tallinn, Wayne/Dresser pump. **The same transaction
as `../receipts/receipt-001.heic`**, so the paper receipt is independent ground
truth for the display, and vice versa. Pairs like this are worth collecting
deliberately: neither photo alone could settle what the fuel actually was.

`pump-002-lukoil-spb-ru.png` - ЛУКОЙЛ, СПб, Gilbarco Veeder-Root. **The same fill
as `../receipts/receipt-007-lukoil-spb-100-ru.png`**, and the pair is what proved
the parser returns litres and unit price *swapped* on that receipt: the pump states
`ЛИТРЫ 43.61` and `ЦЕНА/ЛИТР 99.40` on separate labelled lines, which the receipt's
`43.61 X 99.40` cannot settle on its own. Note the two disagree on the total by
design - the pump reads `4334.83`, the receipt `4334.00`, because ЛУКОЙЛ rounds the
fiscal total down to the whole rouble (`../fiscal/README.md`).

`pump-004-kz-95-kzt-tokheim.jpg` - Kazakhstan, АИ-95, KZT, **Tokheim** LCD (not a
seven-segment display). Truth: `12.38 L x 243 KZT/L = 3008.34`, shown as
`Стоимость 3008` - the pump **truncates its total to whole tenge**. Its failure
mode is different from every other fixture and is the most important one in the
corpus - see "Confidence is not correctness" below.

`pump-003-kz-95-kzt.jpg` - Kazakhstan, АИ-95, **KZT**, Gilbarco Veeder-Root. The
only non-RUB, non-EUR fixture in the corpus, and the worst decimal-point loss seen
so far (all three fields). Truth: `85.25 L x 245.0 KZT/L = 20886.25`, displayed as
`20886.3` - so the pump itself rounds the total to 1 dp, which is a third,
independent reason a pump total and a receipt total can legitimately differ.

## The preset-amount fill: where litres x price genuinely cannot equal the total

`pump-010` (Scheidt & Bachmann) reads `Итого 1000.00 / Количество 13.17 /
Цена за Л 75.95`, and **13.17 x 75.95 = 1000.26**, not 1000.00.

Nothing is misread. The customer asked for exactly 1000 roubles, the pump
dispensed `1000.00 / 75.95 = 13.1666...` litres, and the display **rounds the
volume to two decimals**. The rounded volume no longer reproduces the total.

This is the case that was wrongly hypothesised for `fiscal-002` and disproved
there (that one was ЛУКОЙЛ rounding the total down). Here it is real, and it is
the mirror image: on `fiscal-002` the TOTAL moved, on `pump-010` the VOLUME is
displayed rounded while the total is exact. A parser cannot tell them apart by the
gap alone - both are under a rouble.

Consequence: **do not "correct" a volume to make the cross-check close.** The
honest record is the displayed 13.17 with the exact 1000.00, and CHECK 3's
tolerance (`max(0.02, amount x 0.005)` = 5.00 here) absorbs it.

## Two more display conventions

`pump-009` (Gilbarco) **zero-pads everything**: `02038,00 РУБЛИ`, `00040,00
ЛИТРЫ`, `050,95 ЦЕНА/ЛИТР`, and its four grade prices read `060,80 / 050,95 /
055,90 / 072,88`. Leading zeros plus comma decimals. A parser stripping zeros
naively on a price like `050,95` is fine; one that treats the string as an integer
count of digits is not.

`pump-008` (Топаз) is the extreme of the "pump surrounds are advertising" finding:
the display **is** a video screen, and the numbers are overlaid on a cartoon that
happens to be playing. The values also appear twice - once in a stylised overlay
on the video, once in the LCD strip beneath. `20.00 x 54.90 = 1098.00` checks out
in both places, so the redundancy helps, but the background is arbitrary moving
imagery rather than a fixed surround.

## Comma decimals on a pump, and the same station twice

`pump-007` (Gilbarco Veeder-Root, **АЗС № 78154** - the same ЛУКОЙЛ station as
`pump-002` and `receipt-007`) uses **commas** throughout:

```
61,68  67,62  68,48  76,24        the four grade prices
       4593,46  РУБЛИ
         60,25  ЛИТРЫ
         76,24  ЦЕНА/ЛИТР         the selected one, shown separately
```

Two things follow.

**Separator style is a property of the device, not the country.** `pump-002` at
this very station prints periods (`4334.83 / 43.61 / 99.40`); this pump prints
commas. `receipt-030` prints commas while every other Russian receipt prints
periods. Same country, same brand, same forecourt - different convention. A parser
that decides "RU means comma" or "RU means period" is wrong roughly half the time
here.

**This pump resolves the four-price ambiguity itself.** Unlike `pump-005`, which
showed four prices and left you to work out which applied, this one repeats the
selected price under ЦЕНА/ЛИТР. So the four-price problem is not universal: read
the labelled ЦЕНА/ЛИТР when it exists, and fall back to the cross-check when it
does not. `60,25 x 76,24 = 4593,46` confirms it.

The two visits to АЗС 78154 also show grade prices are not stable: `pump-002`
recorded АИ-100 at 99.40, and none of this display's four prices is 99.40.

## Three formats on one display, and a clipped price

`pump-006` (Adast, KZ, nozzle labelled **92**) reads:

```
10980   СУММА          integer - KZT has no subunit in practice, so this is NOT a lost separator
45.00   ЛИТРЫ          two decimals
  244   ЦЕНА/ЛИТР      integer, and its digits are CLIPPED by the display's own bezel
```

Three different numeric formats on one display, so a parser cannot infer a
document-wide convention here any more than it can on receipts. And the price line
is **physically cut off** - not blurred, not glare, but clipped by the frame, which
is a capture failure no amount of image processing recovers. `45.00 x 244 = 10980`
confirms the reading; without the cross-check there would be no way to know the
clipped digits were complete.

The nozzle label is worth noting against the corpus's own numbers: it says **92**,
yet 244 KZT sits between the two АИ-95 prices already recorded (243.0 on a Tokheim,
245.0 on a Gilbarco). Either Kazakh grade pricing is nearly flat, or the label is
again not the fill - which is exactly why `pump-001`'s finding says a pump parser
must not attempt fuel kind at all.

## The four-price display: where the cross-check finally earns its keep

`pump-005` (Dresser Wayne, RU) shows **four prices at once** - one per grade -
above a single СУММА and ЛИТРЫ:

```
СУММА   4621.08
ЛИТРЫ     87.92
ЦЕНА ЗА ЛИТР   52.06   55.18   49.32   52.56
```

Only one was dispensed, and the display does not say which. This is the sharpest
form of a finding the corpus already had (`pump-001`: grade labels belong to every
nozzle, not to the fill) - here there is not even a label to be misled by, just
four candidate numbers.

**Position does not help**: the correct price is the *last* of the four. A parser
taking the first gets 52.06, and if it then derives litres from the total it gets
`4621.08 / 52.06 = 88.76 L` - plausible, self-consistent, and wrong by 0.84 L.

**But the cross-check resolves it exactly**, and this is the one job it is good
at. Of the four candidates only `52.56 x 87.92 = 4621.08` reproduces the total;
the others miss by 44 to 285 roubles. So the honest summary of the cross-check
across this corpus is:

| task | cross-check |
|---|---|
| choosing among **discrete candidates** (this fixture) | **solves it outright** |
| catching a **misread digit** (`pump-004`) | catches it |
| detecting a **swapped** volume/price pair | blind - `a x b == b x a` |
| reconstructing **lost decimal separators** (`pump-003`) | blind - scale-invariant |

Note the decimal points are all intact here, unlike `pump-003` where every one was
lost. Separator loss is a property of the display, not of pumps.

## Current parser result: fails, instructively

```
liters 0.700   unitPrice –   total –   cross-check ✗
```

Truth is `67.00 L x 1.869 EUR/L = 125.22 EUR`. Two distinct failures, and
neither is a tuning problem.

**Pump class baseline, 2026-08-25: 0/30 fields (0.0%), cross-check 0/10.** All ten
pumps fail completely - receipts score 36.6% by comparison. Pump extraction is a
harder problem than receipt extraction, not the same problem with worse input.

1. **Seven-segment displays lose the decimal point.** OCR reads `SUMMA 12522`
   and `1869 HIND/1L` - the separator that makes them `125.22` and `1.869` is
   simply not in the recognised text. `LIITRIT 67.00` came through intact, so on
   this pump it is per-field rather than global. On `pump-003` (KZ) it is
   **total**: `208863`, `8525` and `2450` for `20886.3`, `85.25` and `245.0` -
   all three separators gone, and each field needs a *different* divisor
   (10^1, 10^2, 10^1). A pump parser cannot trust the decimal point to exist.

   **An earlier version of this file claimed the cross-check reconstructs the
   scale, "picking the only consistent placement". That is wrong, and it is worth
   being precise about why.** `liters x price = total` is invariant under scaling:
   multiply litres by 10^a and price by 10^b and the equation still holds once the
   total moves by 10^(a+b). Brute-forcing `pump-003` over divisors 10^0..10^3 per
   field gives **12** solutions, not one:

   ```
   8525.0 L x   24.5 = 208863.0
    852.5 L x  245.0 = 208863.0
     85.25 L x 245.0 =  20886.3   <- the truth
      8.525 L x 245.0 =  2088.63
   ... 8 more
   ```

   The cross-check narrows 64 candidates to 12, which is useful but not an answer.
   Layering the disambiguators from `docs/SCHEMA.md` → Fuel price bands:

   | filter | remaining |
   |---|---|
   | cross-check alone | 12 |
   | + KZT petrol band (180-320) | 3 - price pinned to 245.0 |
   | + plausible car volume (5-120 L) | **2** - `85.25 L` vs `8.525 L` |

   A **factor-of-ten ambiguity in volume survives every automatic filter**, and
   that is the single worst error the app can make: it does not look wrong on the
   Confirm screen and it corrupts consumption outright. The remaining tie needs the
   car's actual tank capacity, which the app already holds per vehicle - or the
   user, which is the correct fallback.

   And the small-fill branch cannot simply be ruled out as implausible:
   `pump-004` is a real **12.38 L** fill. Small top-ups happen, so "nobody buys
   8.5 litres" is not available as a tie-breaker.

   This is direct evidence for the standing decision that **pump mode ships only
   if it clears >=95%, or stays off** (`docs/PHASES.md` → P2). It also means a pump
   capture must never write a volume the user has not seen and confirmed.

   The corpus now carries **two independent KZ АИ-95 datapoints from different pump
   makes - 245.0 and 243.0 KZT/L** - which is what a curated band is built from, and
   a useful demonstration that two fixtures constrain a band far better than one.

   `pump-003` is additionally the only non-RUB, non-EUR fixture (KZT), and it shows
   why the bands are keyed by currency: the correct KZT band resolves the price,
   while applying the RUB band to it leaves both 85.25 and 245.0 inside the range
   and decides nothing.
2. **Confidence is not correctness - Vision misread a digit at 1.00.**
   On `pump-004` the display reads `Стоимость 3008`. Vision returns **`1408`**, at
   **confidence 1.00**. Not a lost separator - a wrong digit, asserted with full
   confidence. It also returned `Количество` as `"12,"`, dropping `38` entirely,
   again at 1.00.

   This matters beyond one photo, because `ocrConfidenceThreshold` is a remotely
   configurable key (`docs/CONFIG.md`). **Thresholding on Vision's confidence would
   not have caught this**, and no threshold setting can: the value is already at
   the maximum. Any design that gates "do we trust this extraction?" on the OCR
   confidence score is resting on a number that is 1.00 while being wrong.

   What *does* catch it is the cross-check: `12.38 x 243 = 3008.34`, which is
   nowhere near `1408`. That sharpens what the cross-check is actually for, given
   the retraction above:

   | error class | cross-check |
   |---|---|
   | a misread digit (inconsistent triple) | **catches it** |
   | swapped volume/price | blind - `a x b == b x a` |
   | lost decimal separators (scale) | blind - the equation is scale-invariant |

   So the cross-check is a **consistency** check, not a correctness one. It is
   worth keeping and worth not overtrusting.

3. **Pump surrounds are covered in advertising.** The parser returned 0.700
   litres from `Wrapper ja jook 0,5-0,7l` - a sandwich-and-drink promo printed
   beside the display. Receipts have no equivalent noise, which is why a
   receipt-tuned parser scores far worse here than its receipt numbers suggest.

These argue that pump mode needs its own extraction path rather than the receipt
parser pointed at a different photo - and they are exactly why the >=95% gate
exists before the mode ships.

## A third trap: grade labels are not the dispensed fuel

This display OCRs to `miles+`, `miles`, `miles+`, `miles`, `95` - the labels of
every nozzle on a multi-product pump. This fill was **diesel**. Reading the
visible `95` as the fuel kind is a mistake already made once against this very
fixture, and it is worth stating plainly: a grade shown on the pump means the
station sells it, never that this fill used it.

So pump-photo extraction should not attempt fuel kind at all. The receipt line
is authoritative, and where there is no receipt the user picks it - which is what
`docs/CLAUDE.md` hard rule 13 says anyway: the app suggests, the user decides.

## Adding more

Keep the original resolution, name in sequence (`pump-002-lukoil-spb-ru.png`...), and put the
truth in `expected.csv` beside the images - the harness looks for it in the
folder it is pointed at. Leave a field empty rather than guessing. **The JSON and CSV are a dump
of `../corpus.sqlite`** (`scripts/corpus_db.py`): add a still through the annotator or
`corpus_db`, never by editing the file, and run `corpus_db.py dump` (or `check`, which fails a
stale file) so the file matches the database.

Breadth that matters here: different pump makes (Wayne, Gilbarco, Tokheim),
sunlight and glare on the glass, angled shots, and displays that show the
running total mid-fill rather than the final one.

## `pump-011` .. `pump-017` - seven Estonian Circle K displays, and a seven-segment trap

Added 2026-08-26. All seven are Estonian Circle K forecourts, EUR, comma or dot
decimals, shot in daylight through glass. Two makes: Gilbarco Veeder-Root
(`pump-011`, `pump-012`, zero-padded `0019,70` / `0011,01`) and Dresser Wayne
(`pump-013` .. `pump-017`, `SUMMA` / `LIITRIT` / `HIND/1L` labels).

### The trap: a glare-lit `9` reads as a `4`

This is the finding that matters, and it is why three of these rows carry values
that a first reading of the photo does not give:

`pump-015` shows `SUMMA 30.02`, `LIITRIT 15.89`, and four price displays that
read `1.884 / 1.824 / 1.834 / 1.774`. But `15.89 x 1.884 = 29.94`, not `30.02`.
`15.89 x 1.889 = 30.02` exactly. The price is **1.889**, and the terminal `9` is
being read as a `4` because glare fills the segment that distinguishes them.

`pump-016` and `pump-017` settle it independently: the same pump family shot at a
different angle, out of the glare, shows `1.889` and `1.769` unambiguously.

The same correction then resolves `pump-013`: `7.34 x 1.779 = 13.06`, matching its
displayed `SUMMA`, where the naive `1.774` gives `13.02`.

**What this means for the parser.** Cross-multiplication is not only a confidence
check on a good read - on a seven-segment display it is a *digit repair*. When
`liters x unitPrice` misses the total by roughly one least-significant step of one
operand, the likely cause is a single misread segment, not three independent
errors. The candidate correction is testable: substitute each 4/9, 8/9, 3/9, 5/6
pair in turn and see whether one makes the product close. That is a legitimate
suggestion under hard rule 13 - offer the repaired value as a pre-fill, never
apply it silently.

### The two idle pumps are negative fixtures

`pump-016` and `pump-017` show `0.00 EUR` and `0.00 LIITRIT` - a pump standing
ready, not a fill. Their `unitPrice` is deliberately **blank** in `expected.csv`:
three prices are displayed and none of them is "the" price, because nothing was
dispensed.

The behaviour these two exist to pin down is **refusal**, not extraction. A scan
of an idle pump must not produce a zero-litre fill-up; it must say so and offer
the manual door (hard rule 15). A parser that happily returns `0.00 / 0.00` and a
screen that accepts it are both bugs, and `pump-017` adds an angled, keystoned
view of the same situation so the refusal cannot be keyed on a straight-on frame.

### Fields left blank, and why

- `pump-012` **total**: glare sits on the last digit, which reads as `10,00` or
  `10,07`. Litres (`0005,63`) and price (`1,789`) are clean. `5.63 x 1.789 = 10.07`
  says which it is, but that is a *derivation*, and this file's job is to be
  ground truth for exactly that derivation - so the field stays empty rather than
  quietly encoding the answer to its own question.
- `pump-014` **unitPrice and total**: `LIITRIT 3.92` is clean, `SUMMA` reads
  `7.0?` with the last digit lost, and no candidate price closes the arithmetic
  against 3.92. Two unknowns and one equation; both stay empty.

`pump-011` is fully clean and cross-checks: `11.01 x 1.789 = 19.70`.

## `pump-018` – the money line rounds, and the paper does not

`pump-018-gilbarco-tatneft-tver-98-ru.jpeg` – Татнефть АЗС-172, Тверская обл.,
Gilbarco Veeder-Root seven-segment. **The same fill as `../receipts/receipt-036`
and `../receipts/receipt-037`** – a *triplet*, and the only one in the corpus
where all three views are of one transaction on one day.

Truth: `РУБЛИ 2499,8` · `ЛИТРЫ 25,00` · `ЦЕНА/ЛИТР 99,99`.

`25.00 x 99.99 = 2499.75`, and the pump shows **2499,8** – it rounds its money
line to 0.1 ₽ while the receipt prints the exact `2499.75`. That is the second
independent instance of the pump and the paper disagreeing on the total *by
design* (`pump-002` is the first, where ЛУКОЙЛ rounds down to the whole rouble),
and the two round in **opposite directions**. So a cross-check that compares a
pump total against a receipt total must tolerate the display's own rounding, and
must not treat the difference as a misread digit.

**The last digit is why this fixture was nearly recorded wrong.** At thumbnail
scale the `8` reads as a `0`, because the display is a reflective LCD whose
*unlit* segments stay faintly visible – so a `0` and an `8` differ only by a
middle bar that glare washes out. It resolves only at full zoom. Ground truth
here was read at 5x crop, not from the whole frame, and `2499,0` would have been
a permanent lie the ratchet measured from.

The parser resolves **none** of its three fields, which is what moved the class
from 1/46 to 1/49 – eighteen devices now, still one hit.

## `pump-019` … `pump-023` – Circle K Sikupilli, and three displays nobody can read

Five displays from one forecourt (Tartu mnt 86, Tallinn), 2026-08-27, in bright
low-angle morning sun. They split into two very different groups, and the split
is the finding.

**Two are clean and scored:**

- `pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg` - `€ 79,32 · L 45,22 ·
  €/L 1,754`. **The same fill as `../receipts/receipt-038`**, and the two agree
  to the cent. Of the corpus's three matched pump/receipt pairs, this is the only
  one where the totals match: `pump-002` differs because ЛУКОЙЛ rounds the fiscal
  total down to the rouble, and `pump-018` differs because the pump rounds its
  money line up to 0.1 ₽. Agreement is one outcome of three, not the norm.
- `pump-020-gilbarco-circlek-sikupilli-pump7-ee.jpg` - `€ 20,00 · L 10,76 ·
  €/L 1,859`, a round-money preset fill (10.76 x 1.859 = 20.003). Self-consistent
  without needing a second document.

**Three are sun-glared Wayne/Dresser displays, and they are the reason this
README carries a correction:**

`pump-021-wayne-circlek-sun-glare-ee.jpg` (15,00 € / 8,09 L),
`pump-022-wayne-circlek-pump1-glare-ee.jpg` (52,49 € / 30,01 L) and
`pump-023-wayne-circlek-glare-ee.jpg` (51,71 € / 29,65 L).

**They were first committed with every field empty**, because the orchestrator
cropped and enlarged them to 5x and still could not read the SUMMA/LIITRIT area
under the reflected sky. The person who took the photos read them off the pump
and supplied the values, which is the only reason this class gained its second
hit ever. **The lesson is not "try harder at 5x"** - it is that a photo can be
past the point where any amount of zooming recovers it, while the human standing
at the pump has no difficulty at all. That is precisely the situation hard rule
15 exists for: the capture is a head start, and the user is the authority.

The first attempt also reasoned wrongly about the arithmetic. `pump-022`'s
52,49 / 30,01 works out to **1,749 €/L**, which matches none of the four prices
printed beside it, and that was briefly taken as evidence of a misread digit.
It is not, because **those four panels are a grade price BOARD** - badged 95,
95 miles+, 98 and D - **not the transaction's unit price.** `receipt-038` settles
it independently: that fill was charged **1,754 €/L**, a number that appears
nowhere on the board either. So on this forecourt the customer's price routinely
differs from the posted one.

**Hence their `unitPrice` column is empty and their liters/total are not.** A
display of this layout does not print a transaction unit price at all, and a
parser that scrapes "the price" off one of these four panels has a one-in-four
chance of being right. That is a concrete extraction hazard, recorded here
because no other fixture in the corpus shows it.

The class is now **2/61 across 23 devices, 3.3%** - the first movement in
`PumpPhotoGate.measuredHits` since it was written. Two hits in sixty-one fields
is still noise against a **95%** gate, which is why P2.7 ships off.

## 2026-08-28: five Estonian additions, and the corpus is now EXIF-free

`pump-024` .. `pump-028`. Two Wayne displays at a Neste forecourt, three Gilbarco
Veeder-Root at Circle K. Expected values were read off the photographs and every
row was checked as `liters x unitPrice = total` before it was committed.

What they add that the corpus did not already have:

- **A comma decimal separator on a zero-padded readout** (`0103,53` / `0053,81`).
  The corpus had zero-padding and it had comma separators, but not together on a
  Gilbarco.
- **A total whose last digit is destroyed by sun glare** (`pump-025`). Only the
  arithmetic recovers it: `40.99 / 22.91 = 1.789`, and 1.789 is the Futura 95
  price printed on the same panel. This is the cross-check earning its keep on a
  real photograph rather than a constructed case.
- **Three grade prices on one panel** (`pump-024`), so choosing the operand is a
  decision rather than the only candidate.

`fuelKind` is left empty on the three Gilbarco rows on purpose: those panels show
a price but never name the grade, and guessing would put fiction in the ground
truth. On the two Wayne rows the price matches a labelled grade exactly, so
`petrol95` is evidence rather than inference.

**Metadata:** every JPEG and PNG fixture in the corpus has been stripped of EXIF
(device make, lens, capture timestamps). No fixture ever carried GPS - that was
checked, not assumed. Stripping was **lossless and verified**: JPEGs via
`jpegtran -copy none`, PNGs via a re-encode of a lossless format, and each file
compared pixel-for-pixel afterwards (`magick compare -metric AE` = 0). That
matters because the accuracy ratchet is pinned to OCR results on these exact
images; a re-compression would have moved the marks silently.

**Nine `.jpg` fixtures still carry EXIF.** They cannot be stripped without
re-encoding, which is lossy and would perturb the very scores the ratchet
guards. Converting them to JPEG is a deliberate corpus change with a ratchet
re-baseline attached, not a cleanup - it needs its own decision.

## 2026-08-31: eight Circle K Estonia displays (pump-031..038)

Two Gilbarco Veeder-Root and six Dresser Wayne, all Circle K EE. Converted from HEIC to JPEG at
full resolution (3024x4032) with EXIF stripped - **orientation was baked into the pixels first**
(all nine were EXIF orientation 6; dropping the tag without applying it would have left every
fixture rotated, which measures a different problem than the app has).

What they add that the corpus did not have:

- **pump-034 is half of a matched pair** with `receipt-042` - the same fill, 87.29 L of D B0 at
  1.839 EUR/L = 160.53, pump 7, Jarvevana Tallinn. It is the corpus's **third** matched pair and
  its first Estonian one, and it carries a counter-example worth more than the pair itself: the
  pump's four-price board reads 1.934 / 1.834 / 1.819 / 1.759 and **none of them is the price
  charged**, because the product was D B0 while the board prices another diesel. Resolving a fill
  by picking the boarded price nearest the arithmetic would be **wrong here**. Its `unitPrice`
  cell is therefore EMPTY: the photo does not carry it, and the receipt is its only source.
- **pump-035** has the same shape, unresolved: 82.01 / 44.96 = 1.824, on no board. Also empty.
- **pump-031 is a cross-check MISMATCH by design**: 16.80 x 1.939 = 32.575 against a printed total
  of **32.50**. The Circle K extra discount lands between the board price and the charged price,
  so the three printed numbers do not multiply out. It is a real receipt, not a misread.
- **pump-033 / 036 / 038** each show four prices at once and resolve to 95 by arithmetic
  (42.87 / 12.73 / 44.03 L at 1.759); **pump-037** resolves to diesel (11.05 x 1.834 = 20.27).
- **pump-038** has a photographer reflection across the total and **pump-035** was shot in rain,
  with droplets over the digits; **pump-028's** fibre-on-glass problem repeats on pump-038's D price.

Gate moved **26/116 -> 29/151**: the eight scored 3 of 35 new cells, so accuracy fell 22.4% ->
19.2%. That is correct and expected - the ratchet guards absolute hits so that adding hard
fixtures cannot be punished. Pump mode still ships off; the gate is 95%.

## 2026-09-01: five more Circle K Estonia displays (pump-039..043)

Two Gilbarco, three Dresser Wayne. Same conversion as the last batch: HEIC to JPEG at full
resolution, **orientation baked into the pixels first** (all five were EXIF orientation 6), EXIF
stripped, ICC profile kept. Verified per file: zero EXIF keys, no GPS IFD.

Two shapes the corpus did not have:

- **pump-042 is the first PRESET-AMOUNT fill.** SUMMA is a round **20.00** and the volume (11.34 L)
  is what that bought. 20.00 / 11.34 = **1.764**, which matches **none** of the four board prices
  (1.814 / 1.914 / 1.844 / 1.784) - a discount sits between the boarded and the charged price. Its
  `unitPrice` cell is EMPTY: the photograph does not carry it. Note the direction of inference is
  reversed here - on an ordinary fill the volume is measured and the total derived; on a preset the
  total is chosen and the volume derived, so a parser that assumes the total is the computed
  quantity has it backwards.
- **pump-041's total is destroyed by sun glare.** 30.62 L at the boarded 1.784 computes 54.63, but
  the SUMMA digits cannot be read from the photograph, so the `total` cell is EMPTY rather than
  guessed - the pump-012 / -014 / -021 convention for a value the photo does not carry. The
  arithmetic is recorded here, not in `expected.csv`, so the fixture measures reading rather than
  computing.

The other three reconcile exactly: pump-039 (11.47 x 1.839 = 21.09), pump-040 (8.07 x 1.849 =
14.92), pump-043 (60.58 x 1.784 = 108.07). pump-039 charges **1.839** - the same D B0 price
`receipt-042` records at Jarvevana - but this Gilbarco display carries no grade label, so
`fuelKind` stays empty rather than inferred from a price seen elsewhere.

Gate moved **29/151 -> 32/171**: the five added 20 scored cells and 3 hits, so accuracy fell 19.2%
-> 18.7%. Correct and expected - the ratchet guards absolute hits so that adding hard fixtures
cannot be punished. Pump mode still ships off; the gate is 95%.


## pump-044 + receipt-044 - a matched pair, and the price the pump rounds away

`pump-044-rn-tver-chkalovskaya-95-comma-truncated-price-ru.jpeg` - АО "РН-Тверь", АЗК Чкаловская
TN250 (Роснефть, Tver, RU). **The same transaction as
`../receipts/receipt-044-rn-tver-chkalovskaya-95-nonfiscal-terminal-slip-ru.jpeg`**, added
2026-09-03 - the fourth deliberate pair in this corpus, and the reason pairs are worth collecting
is on display here.

The pump reads `Стоимость 1707,5 рублей`, `Количество 25,00 литров`, `Цена за 1 литр 68,3 рублей`.
The paper for the same fill reads `68.30`. Two things follow:

- **The pump truncates the price to one decimal**, and the receipt does not. Numerically 68,3 and
  68.30 are the same, so `expected.csv` carries 68.30 for both - but a parser that assumes a pump
  price always has two decimals will read this display wrong, and only the paired receipt shows
  that the display is the lossy one. This is the failure the pairing exists to catch.
- **The total is also truncated**: `1707,5` on the display against `1707.50` on the paper.
  25.00 x 68.30 = 1707.50 exactly, so the cross-check reconciles - but it reconciles *because*
  trailing-zero loss is numerically harmless, not because the strings agree. A parser comparing
  text would call this a mismatch.

Comma decimals throughout the display, dot decimals throughout the receipt - the same transaction
disagreeing with itself about the separator, which is why `docs/EXTRACTION.md` treats the separator
as a per-image property and never a per-locale one.


## pump-045 .. pump-056 - one Circle K forecourt, two pump vendors, two separator conventions

Twelve displays added 2026-09-03 from a single Estonian Circle K site, deliberately shot across
both vendors on the forecourt. The set exists for one observation the corpus could not make before:
**the decimal separator is a property of the pump, not of the country.**

- The six **Gilbarco Veeder-Root** units (`pump-045`..`pump-050`) print `0029,31` / `0016,29` /
  `1,799` - zero-padded, comma decimals.
- The six **Dresser Wayne** units (`pump-051`..`pump-056`) print `30.42` / `15.61` / `1.884` - not
  padded, dot decimals, under Estonian labels `SUMMA` / `LIITRIT`.

Same brand, same forecourt, same hour. A parser that picks a separator from the locale gets half of
this site wrong whichever way it guesses.

**The Wayne units also carry four grade prices at once** (`95 miles`, `98 miles+`, `D miles`,
`D miles+`), and on five of the six the transaction's own price is **not one of them**:

| fixture | total / litres | implied price | nearest board price |
|---|---|---|---|
| pump-051 | 30.42 / 15.61 | 1.9488 | 1.944 (98 miles+) |
| pump-055 | 108.68 / 56.05 | 1.9390 | 1.944 (98 miles+) |
| pump-056 | 72.00 / 38.32 | 1.8789 | 1.884 (95 miles) |

So `unitPrice` is **empty** in `expected.csv` for those - the display does not carry the number the
transaction used, and inventing it from division would make the fixture measure arithmetic instead
of reading (the `pump-012` / `-014` / `-021` convention). `pump-056` is additionally a **preset**:
`72.00` exactly, the shape `pump-042` records at 20 EUR.

**Glare takes the total outright on two of them.** `pump-052` and `pump-053` have a readable litres
count and a total that is partly behind a reflection, so their `total` is empty too. They are worth
keeping precisely because the litres survive: a capture that yields one operand and not the other is
the ordinary outcome on a sunlit forecourt, and hard rule 15's "a head start, not an answer" is
exactly this case.

`pump-046` is the only one of the twelve whose **grade is legible** (a green `95` badge beside the
nozzle), so it is the only one carrying `fuelKind`. `pump-049` is the faintest LCD in the corpus -
`0005,81` at very low contrast - and `pump-048` stops at `19,99`, a hair under a round preset.

### pump-054 + receipt-045, and why `expected.csv` records reading rather than arithmetic

`pump-054-wayne-circlek-jarvevana-pump7-diesel-flare.jpg` is the same transaction as
`../receipts/receipt-045-circlek-jarvevana-pump7-db0-2694l-ee.jpg` - Circle K Jarvevana, Tallinn,
pump 7, `D B0 miles`, 03/09/2026 10:26. The fifth deliberate pair here, and it settles a question
the other pairs only raised.

Sun flare hides the total's last digit on the display; the litres (`26.94`) and the price
(`1.919`, `D miles`) are both readable. The obvious move is to compute the missing total:

    26.94 x 1.919 = 51.6997  ->  51.70

**The paper says `51,71`.** The pump rounds the product of its own rounded operands, and one cent
falls out of the difference. So `expected.csv` carries `51.71` - established by the *paired
receipt*, which is reading, not by the multiplication, which would have been wrong. This is the
concrete reason the fixtures record what is on the image and the arithmetic lives in this README:
a cross-check that recomputes a total will disagree with the paper by a cent on fills of this shape,
and it is the paper that is right.

## pump-057 .. pump-064 - Circle K Sikupilli, one visit, and an insect on the price display

Eight displays added 2026-09-04 from a single forecourt - **Circle K Sikupilli, Tartu mnt 86,
Tallinn** - shot in one visit across both vendors: four **Gilbarco Veeder-Root**
(`pump-057`..`pump-060` - comma decimals, zero-padded) and four **Dresser Wayne**
(`pump-061`..`pump-064` - dot decimals, unpadded, under `SUMMA` / `LIITRID` / `LIITRIT`).

That is the `pump-045`..`pump-056` separator finding **repeated at a different site**, which is what
it needed: until now "the separator belongs to the pump, not the country" rested on one forecourt
and could have been a property of that forecourt's hardware mix. It is not.

### pump-057 + receipt-046 - the sixth matched pair

`pump-057-gilbarco-circlek-sikupilli-pump5-db0-pair.jpg` is the same fill as
`../receipts/receipt-046-circlek-sikupilli-pump5-db0-5580l-ee.jpg`: pump 5, `D B0 miles`,
`0100,38 €` over `0055,80 L` with `1,799` in the `€/L` window, 04/09/2026 10:20.

Unlike `pump-054`, nothing here has to be recomputed - `55.80 x 1.799 = 100.3842 -> 100.38` and the
paper prints `100,38`, so the pair agrees to the cent and the Gilbarco's own selected-price window
carries the transaction price outright. What the pair adds is the **other direction** of the `D B0`
finding: the Wayne boards on this same forecourt price `D miles` at `1.874` and list `1.799`
nowhere, so the product actually dispensed is absent from every board on site. That is now the
fifth independent counter-example to resolving a fill against the prices a display advertises.

### The insect - an occlusion class the corpus did not have

`pump-063-wayne-circlek-ee-insect-on-price-display.jpg` has a **dead insect sitting on the
`HIND/1L` window**, covering part of a digit: the `D miles` price reads `1.074` where the identical
badge on `pump-064` reads `1.874`.

This is not glare, not dirt, not defocus, and not a display fault - it is an opaque object on the
glass, and no amount of image processing recovers what is physically covered. It belongs with
`pump-006`'s bezel-clipped price as a **capture failure**, and the corpus had exactly one of those.

The fill itself is untouched (`7.17 L x 1.834 = 13.15`, the `95 miles` price, fully legible), which
is what makes the fixture useful: the occlusion sits on a value the parser must **not** read, so it
measures whether a board price is trusted blindly rather than whether a transaction survives.

### The board order is not stable, and neither is the grade set

The four Wayne boards show the same five grades in **different orders**, each price identified only
by the badge above it:

| fixture | board, left to right |
|---|---|
| pump-061 | `D miles` 1.874 · `D miles+` 1.974 · `98 miles+` 1.894 · `95 miles` 1.834 |
| pump-062 | `95 miles` 1.834 · `98 miles+` 1.894 · `D miles` 1.874 · `D miles+` 1.974 |
| pump-063 | `95 miles` 1.834 · `98 miles+` 1.894 · `95 miles+` 1.884 · `D miles` 1.874 (occluded) |
| pump-064 | `D miles` 1.874 · `95 miles+` 1.884 · `98 miles+` 1.894 · `95 miles` 1.834 |

The price for a given badge is identical everywhere; the **position** is not, and the four pumps do
not even show the same four grades. `pump-005` established that position is unreliable - taking the
first of four was wrong there. This is stronger: position carries **no** information at all, and
only the badge beside a price says what it is.

### Two more shapes

`pump-061-wayne-circlek-ee-discount-below-board.jpg` charges `62.40 / 33.84 = 1.8440`, which is none
of its own four board prices. That is the Circle K discount shape already recorded on `pump-031` and
`pump-042`, so its `unitPrice` cell is **empty** - the display does not carry the number the
transaction used.

`pump-058-gilbarco-circlek-ee-dirty-lcd-1969.jpg` is the **lowest-contrast readable display** in the
corpus: the LCD is filmed with road dirt to grey-on-grey, and a human still reads `0039,42` /
`0020,02` / `1,969`. It is the honest low end of "the photograph does carry the value" - anything
fainter belongs with the blank cells.

### Five prices at one site in one visit

Across these eight displays the readouts imply `1.799`, `1.834`, `1.894`, `1.899` and `1.969`, while
the Wayne boards advertise `1.834 / 1.874 / 1.884 / 1.894 / 1.974`. Only `1.894` appears in both
sets. Two explanations both fit and both matter: the fill was an **off-board product** (which
`receipt-046` proves for `pump-057`'s `1.799`), or the display still holds an **earlier customer's
transaction**, since a pump readout persists until the next fill starts. Neither lets a parser
resolve a transaction price from the board, and the second is a reason a capture cannot assume the
numbers on a display belong to the user standing in front of it (hard rule 13 - the app suggests).

## Added 2026-09-09 (owner's own fills)

Four displays, **three paired with the receipt for the same fill** - the pair is worth collecting
because each artefact is ground truth for the other.

- `pump-074-gpn-tver-95-ru.jpg` - Russian pump, Cyrillic labels
  (`Стоимость / Количество / Цена за 1 литр`), comma decimals. `29,00 Литров`, `68,44 Рублей/л`.
  **The same fill as `../receipts/receipt-053-gpn-tver-95-ru.jpg`.**
  **`total` is deliberately left blank.** The cost field photographs as `1984,0` while the receipt
  for the same fill says `1984.76`, and the trailing digit cannot be read from the image with
  confidence. Asserting the receipt's value would score the parser against something the picture
  does not contain; asserting `1984,0` would encode a misread as truth. Blank skips the cell, and
  litres and unit price - both unambiguous - still score.
- `pump-075-gilbarco-circlek-ee-95.jpg` - Circle K, Tallinn, Gilbarco Veeder-Root seven-segment,
  zero-padded (`0089,43` / `0046,24`), price in a separate small LCD (`1,934`). **The same fill as
  `../receipts/receipt-054-circlek-tallinn-95-et.jpg`.**
- `pump-076-gilbarco-circlek-ee-preset-150.jpg` - the same pump model, a **preset-amount** fill:
  `0150,00 €` exactly, `0077,56 L`, `1,934 €/L`. **The same fill as
  `../receipts/receipt-055-circlek-tallinn-98-discount-et.jpg`.** A round total is the shape most
  likely to be mistaken for a price or a litre count by a label-free reader.
- `pump-077-gilbarco-ee-2054.jpg` - Gilbarco Veeder-Root, `0050,41 €`, `0024,54 L`, `2,054 €/L`.
  No receipt for this one. Note the price display is the **four-digit** `2,054` while the cost and
  volume are zero-padded to six - three different digit widths on one facia.

## The 2026-09-09 corpus growth broke precision, and that is the point

Adding `pump-074..077` moved the measured pump numbers to **37/210 numeric recall, 40 committed,
37 committed-correct** - so **precision fell from 100% to 92.5%** and coverage rose 18.6% -> 19.0%.

Precision was the one metric that had held at 100% through B1 and B2, and the READMEs above say so
repeatedly. It was holding on a corpus that did not contain these four displays. Of the eleven new
numeric cells the parser **committed to three and got all three wrong, and resolved none correctly**.

Nothing ships differently: the mode was already off on coverage (19.0% against the 0.60 floor) and
is now off on precision as well (0.925 against 0.99), so no user meets a wrong pre-fill. The gate is
behaving exactly as P2.7 designed it - a corpus that only ever gets easier cannot fail, and these
fixtures are the owner's own fills rather than curated easy ones.

**Which three cells are wrong, and why, is deliberately NOT investigated here** - it needs its own
row. A confident-wrong value deserves more attention than an abstention: abstaining is safe by
construction, while a wrong digit is precisely what hard rule 13 cannot protect a user from, because
a pre-filled volume looks like every other pre-filled volume on the Confirm screen.

## Added 2026-09-10 (owner's own capture session)

Six displays: five Gilbarco Veeder-Root facias at Circle K Peetri (Tallinn) and one Tokheim at
Gazpromneft АЗС №12089, the last of them **paired with a receipt for the same fill**.

The five Estonian displays are **stale reads** - each shows the transaction that ended on that
pump, not a fill the photographer made - which is exactly the state a user photographs when they
walk up to a pump. Note in particular that `pump-078` is **Pump 7 at the same station as
`../receipts/receipt-058-circlek-peetri-98e0-pump7-4353l-ee.jpg`, and is NOT that fill**: the
receipt is 43.53 L at 1,969 and the display reads 31,43 L at 1,909. Same pump, different grade,
different transaction - a reminder that a pump number is not a join key.

- `pump-078-gilbarco-circlek-peetri-pump7-3143l-ee.jpg` - `0060,00 €`, `0031,43 L`, `1,909 €/L`.
  A **round total** (60,00 exactly) that is nonetheless not a preset - the shape most likely to be
  mistaken for a price by a label-free reader.
- `pump-079-gilbarco-circlek-peetri-6900l-ee.jpg` - `0135,86 €`, `0069,00 L`, `1,969 €/L`. The
  mirror case: a **round litre count** with a ragged total. The pump number is cut off at the frame
  edge, so the slug does not claim one.
- `pump-080-gilbarco-circlek-peetri-1039l-ee.jpg` - `0020,15 €`, `0010,39 L`, `1,939 €/L`. Two
  numbered red panels are visible on one facia, so neither is claimable as this pump's number.
- `pump-081-gilbarco-circlek-peetri-pump3-2496l-ee.jpg` - `0049,15 €`, `0024,96 L`, `1,969 €/L`,
  Pump 3. The one shot here with the pump number unambiguous and the whole facia in frame.
- `pump-082-gilbarco-circlek-peetri-1315l-ee.jpg` - `0025,10 €`, `0013,15 L`, `1,909 €/L`. Shot
  close and off-centre: the number panel and the `€`/`L` unit markers are cropped away, leaving the
  digits with **no unit labels in frame at all**. Which number is money and which is volume has to
  come from position and arithmetic alone.
- `pump-083-tokheim-gazpromneft-azs12089-truncated-total-pair-ru.jpeg` - Tokheim LCD, Cyrillic
  labels (`Стоимость / Количество / Цена за 1 литр`), comma decimals, behind glass with the
  photographer reflected in it. **The same fill as
  `../receipts/receipt-060-gazpromneft-azs12089-95-fuelcard-pair-ru.jpeg`.** The display reads
  `1437,2` where the paper reads `1437.24`: this pump **truncates its total to 0,1 ₽**. Ground
  truth records `1437.20` - what the picture contains - following `pump-004`, where a display
  showing `3008` against a true `3008.34` is recorded as `3008.00`. Asserting the receipt's
  `1437.24` would score the parser against something the image does not hold. **Routed through
  Telegram** (1280 px, recompressed).

The parser commits nothing on any of the six (`swift run ReceiptSpike fixtures/pump`), which is the
mode behaving as designed rather than a new regression - pump display recognition is off on both
coverage and precision.

## Added 2026-09-11 (owner's own capture session)

Eleven displays: two Tokheim LCDs paired with `receipt-062`/`063`, seven Scheidt & Bachmann facias
at one Rosneft-branded site (the glass reflects the Pulsar pylon and the forecourt), and two Circle K
Gilbarco Veeder-Root reads, one of them the display half of `receipt-064`.

- `pump-085-tokheim-rn-tver-chkalovskaya-3000l-pair-ru.jpeg` - `Стоимость 2139,0 рублей /
  Количество 30,00 литров / Цена за 1 литр 71,3 рублей`. **The same fill as
  `../receipts/receipt-062-...-pair-ru.jpeg`.** Ground truth records `71.30` and `2139.00` - the
  display drops the trailing zero the paper prints; the values agree exactly.
- `pump-086-tokheim-rn-tver-chkalovskaya-1000l-pair-ru.jpeg` - `713,0 / 10,00 / 71,3`, the Tokheim
  logo in frame. **The same fill as `../receipts/receipt-063-...-pair-ru.jpeg`.**
- `pump-087`, `pump-088`, `pump-090` (`scheidt-bachmann-rn-3000l-6830-reflection-a/b/c-ru.jpeg`) -
  **one fill, three shots**: `Итого 2049.0 Рублей / Количество 30.00 Литров / Цена за Л 68.30`. The
  three differ only in what the glass reflects - a lorry, the photographer, the sky - which makes
  them a controlled test of reflection alone.
- `pump-089-scheidt-bachmann-rn-1500l-6830-ru.jpeg` - `1024.5 / 15.00 / 68.30`.
- `pump-091-scheidt-bachmann-rn-2000l-7135-labels-cropped-ru.jpeg` - `1427.0 / 20.00 / 71.35`. Shot
  close: the row labels are cut at the left frame edge (`Итого` -> `того`, `Количество` -> `ество`,
  `Цена за Л` -> `а за Л`), so a label-anchored reader has only the unit words on the right.
- `pump-092-scheidt-bachmann-rn-3000l-6385-ru.jpeg` - `1915.5 / 30.00 / 63.85`, a cheaper grade at
  the same site.
- `pump-093-scheidt-bachmann-rn-2000l-6385-faded-ru.jpeg` - `1277.0 / 20.00 / 63.85`. The litre and
  money segments are **faded against the sky** behind the glass; the leading `1` of the total is the
  faintest digit in the corpus, and the product `20.00 x 63.85` is what confirms it.
- `pump-094-gilbarco-circlek-ee-4325l-1944.jpg` - Gilbarco Veeder-Root, `0084,08 €`, `0043,25 L`,
  `1,944 €/L`. Shot in the same session as `pump-095` at the same price; no receipt.
- `pump-095-gilbarco-circlek-peetri-pump5-2307l-pair-ee.jpg` - `0044,85 €`, `0023,07 L`,
  `1,944 €/L`. **The same fill as `../receipts/receipt-064-circlek-peetri-db0-pump5-2307l-pair-ee.jpg`**,
  and the two agree to the cent.

`fuelKind` stays empty on all eleven, including the two whose paper half names АИ95 - the rule
above (a visible grade is evidence the station sells it, never that this fill used it) does not
bend for a pair; the receipt carries the kind.

The nine Telegram photos (`085`..`093`) are 1280 px, recompressed, EXIF already absent, committed
byte-for-byte. `094`/`095` were converted from HEIC to full-resolution JPEG with EXIF and ICC
stripped.

**What the batch scored.** The parser commits to six numeric cells and all six are correct - both
Gilbarco reads sweep 3/3 - and it commits **nothing** on any of the nine Russian displays, Tokheim or
Scheidt & Bachmann, glare or none. That is the corpus's sharpest statement of the asymmetry so far:
a Latin-script display with `€` / `L` / `€/L` beside its digits is read; a Cyrillic-labelled one
behind glass is not, and the same `30.00 x 71.30` fill is resolved from the paper (`receipt-063`)
and not from the pump (`pump-086`). Precision 0.940 -> 0.946, coverage 0.216 -> 0.212; the mode
stays off on both.

## Added 2026-09-13 (owner's own fill)

One display, the pump half of a matched pair with `../receipts/receipt-065`.

- `pump-096-tokheim-rn-tver-tc252-2000l-pair-ru.jpeg` - Tokheim LCD, Cyrillic labels
  (`Стоимость / Количество / Цена за 1 литр`), at АО "РН-Тверь", АЗК Тверь-2 ТС252. `1426,0 / 20,00
  / 71,3`. **The same fill as `../receipts/receipt-065-...-pair-ru.jpeg`**, and the paper prints the
  same `20.00 x 71.30 = 1426.00` - the display only drops the trailing zeros, so the pair agrees
  exactly, as `pump-085`/`086` did at the neighbouring station. Shot in daylight with a reflection
  across the glass, slightly from below, which is the ordinary way a driver photographs a pump.

`fuelKind` stays empty, per the rule above - the paper carries `petrol95` and the display never
states it. **The parser commits nothing on any of the three numeric cells**, which is the
Cyrillic-labelled-display asymmetry the 2026-09-11 batch recorded, repeated at a third RN-Tver
station: the same `20.00 x 71.30` fill is resolved from the paper and not from the pump. Numeric
total 264 -> 267, committed 56 and committed-correct 53 unchanged, so precision stays 0.946 and
coverage falls 0.212 -> 0.210; the mode stays off on both.

## Added 2026-09-13 (the Circle K Dresser Wayne set)

Four Estonian displays, all the same **Dresser Wayne Circle K** face: `SUMMA` over `LIITRIT`
(`Vmin 5 LIITRIT`), a row of four price windows under grade badges, and `HIND/1L`. The face
**never names the grade dispensed** - the badges are every nozzle's, per the rule above - and the
transaction's unit price is simply the one price window the `SUMMA / LIITRIT` quotient lands on.
The photographer is reflected in the LCD glass on every one.

- `pump-097-dresser-wayne-circlek-ee-2285l-1899.jpg` - `SUMMA 43.39` / `LIITRIT 22.85`. The four
  windows read `D 2.039 · 95+ 1.949 · 98+ 1.959 · 95 1.899`; `43.39 / 22.85 = 1.899`, so the `95`
  window is the transaction's price. No pump number in frame.
- `pump-098-dresser-wayne-circlek-ee-969l-2039.jpg` - `SUMMA 19.76` / `LIITRIT 9.69`. The windows
  read `D+ 2.139 · D 2.039 · 98+ 1.959 · 95 1.899` (the leftmost partly cut at the frame edge);
  `19.76 / 9.69 = 2.039`, the `D` window. A small top-up, the shape `pump-049` records at 5.81 L.
- `pump-099-dresser-wayne-circlek-ee-pump1-1064l-1899.jpg` - `SUMMA 20.21` / `LIITRIT 10.64`, the
  pump number `1` legible on the red tile. The windows read `D 2.039 · 95+ 1.949 · 98+ 1.959 · 95
  1.899`; `20.21 / 10.64 = 1.899`, the `95` window.
- `pump-100-dresser-wayne-circlek-jarvevana-pump4-6404l-2024-pair-ee.jpg` - `SUMMA 129.62` /
  `LIITRIT 64.04`, pump number `4`, at Circle K Jarvevana. The windows read `95 1.884 · 98+ 1.944 ·
  95+ 1.934 · D 2.024`, and the `D miles` window is the **lit** one; `129.62 / 64.04 = 2.024`
  agrees. The `SUMMA`/`HIND` labels are cut at the right frame edge, so a label-anchored reader has
  only the digits. **The same fill as
  `../receipts/receipt-066-circlek-jarvevana-db0-pump4-6404l-pair-ee.jpg`**, which prints the same
  `64.04 x 2.024 = 129.62`.

`fuelKind` stays empty on all four, including `pump-100` whose paper half names `D B0 miles` - the
rule does not bend for a pair. **The parser commits nothing on any of the twelve numeric cells**:
four more Dresser Wayne `SUMMA`/`LIITRIT` displays whose grade windows it reads as text but never
selects a transaction price from, so numeric total 267 -> 279, committed 56 and committed-correct
53 unchanged, precision 0.946 and coverage 0.210 -> 0.201; the mode stays off on both. The four are
full-resolution JPEGs converted from iPhone HEIC (3024x4032, orientation baked in), EXIF and ICC
stripped, committed byte-for-byte.

## Added 2026-09-14 (the Circle K Gilbarco set)

Five full-resolution Circle K Estonia Gilbarco Veeder-Root displays, on the same
two-line, seven-digit zero-padded face as `pump-094`/`095`:

- `pump-101` - `0035,90 / 0017,65 / 2,034`; tight crop without the `€`/`L`
  labels and with the photographer reflected across the digits.
- `pump-102` - `0019,97 € / 0010,22 L / 1,954 €/L`; the stop button is visible.
- `pump-103` - `0094,93 € / 0048,58 L / 1,954 €/L`, sharp.
- `pump-104` - `0051,65 € / 0026,50 L`, pump 1 at Sikupilli. **The `€/L`
  window is washed out and its expected price cell is blank**; `1,949` belongs
  only to the paired `../receipts/receipt-067-...-pair-ee.jpg`.
- `pump-105` - `0048,52 € / 0025,55 L / 1,899 €/L`, with glare on the total.

The production scorer commits no new numeric value: numeric hits stay 53,
numeric total grows 279 -> 293, and committed/correct stays 56/53. Precision is
still 0.946; coverage falls 0.201 -> 0.191, and the mode remains off. In
particular it abstains on pump-104's price. The diagnostic Spike parser also
misses every asserted numeric cell, but commits a confident-wrong `0.5` litres
on pump-103 and pump-104; that is a harness finding, not scored as a production
commit. The five JPEGs are 3024x4032 conversions with orientation baked in and
EXIF/ICC stripped, preserved byte-for-byte.

## Added 2026-09-18 (Russian faces by Telegram, and four more Gilbarco)

Nine displays. Five reached us **through Telegram** (1280 px, recompressed, EXIF already absent,
committed byte-for-byte after a strip that changed nothing); four are the owner's own HEICs,
converted to full-resolution JPEG (3024x4032, orientation 6 baked in, EXIF and ICC stripped).

- `pump-106-wayne-gazpromneft-gdrive95-5100l-7031-truncated-total-ru.jpeg` - the Wayne
  `СУММА / ЛИТРЫ` face with the grade windows below: `3585.8 / 51.00`, `70.31` lit in the
  `95 G-Drive` window. `51.00 x 70.31 = 3585.81`, so this pump **truncates its total to 0.1 ₽**;
  ground truth records `3585.80`, what the picture contains (the `pump-083` rule). No paper half.
- `pump-107-scheidt-bachmann-rn-tver-azk15-3000l-6830-night-zero-padded-pair-ru.jpeg` - the
  `Итого / Количество / Цена за Л` face at night under the lit `ЗЕРНО` cafe sign, and the first
  Scheidt & Bachmann read that **zero-pads to seven digits**: `02049.0 / 0030.00 / 068.30`. A
  label-free reader that takes digit count as scale has a new trap here. The photographer is
  reflected across the price window. **The same fill as `../receipts/receipt-068` and
  `receipt-069`**, the terminal slip and the order slip of one preset 30-litre fill at RN-Tver
  АЗК 15 on 16.09.2026 21:27. The corpus already held `pump-087/088/090` at the identical
  `2049.0 / 30.00 / 68.30`; that is a different fill on a different day at the same price, with
  no paper, so the values repeat while the shape and the pair are new.
- `pump-108-scheidt-bachmann-rn-3249l-6830-reflection-ru.jpeg` - `2219.1 / 32.49 / 68.30`, the
  daylight face with the photographer and a car reflected. `32.49 x 68.30 = 2219.067`; the
  display shows `2219.1`, recorded as `2219.10`. The `MANN`/`Mönchengladbach` maker plate is at
  the frame's left edge.
- `pump-109-tokheim-gazpromneft-edrovo-4800l-7105-pair-ru.jpeg` - the Tokheim `Стоимость /
  Количество / Цена за 1 литр` face, comma decimals: `3410,4 / 48,00 / 71,05`. **The same fill as
  `../receipts/receipt-070-gazpromneft-edrovo-azs10031-gdrive95-fuelcard-pair-ru.jpeg`**, which
  prints `71.05 x 48.000 = 3410.40`; display and paper agree exactly. Same site and price as
  `pump-065`/`receipt-047`.
- `pump-110-wayne-gazpromneft-gdrive95-4200l-7031-truncated-total-pair-ru.jpeg` - the Wayne face
  again, `2953.0 / 42.00`, `70.31` in the `95 G-Drive` window, the `ДИЗЕЛЬ / 92 / 95 / 95 G-Drive /
  100 G-Drive` grade strip fully in frame. **The same fill as
  `../receipts/receipt-071-gazpromneft-gdrive95-fuelcard-header-cut-pair-ru.jpeg`**, whose
  `70.31 x 42.000 = 2953.02` is the untruncated figure; ground truth records `2953.00`.
- `pump-111-gilbarco-circlek-ee-5046l-1999.jpg` - Gilbarco Veeder-Root, `0100,87 / 0050,46 /
  1,999 €/L`, the corpus's first Gilbarco read above 100 EUR (a seven-digit money field with the
  hundreds digit lit). Sun glare across the lower half of the total.
- `pump-112-gilbarco-circlek-ee-461l-2199.jpg` - `0010,14 € / 0004,61 L / 2,199 €/L`, a top-up
  small enough that five of seven digits are padding, and the highest per-litre price in the
  Estonian set. The last litre digit sits under glare; `10.14 / 2.199 = 4.611` confirms it.
- `pump-113-gilbarco-circlek-ee-522l-2014.jpg` - `0010,51 € / 0005,22 L / 2,014 €/L`, the price
  window glared but legible; `5.22 x 2.014 = 10.513`.
- `pump-114-gilbarco-circlek-ee-6987l-2074-price-glare.jpg` - `0144,91 € / 0069,87 L`, the
  `€/L` window **washed by direct sun** to a faint `2,074`. Unlike `pump-104` the digits are still
  readable and `69.87 x 2.074 = 144.910` closes to the cent, so the price cell IS asserted.

`fuelKind` stays empty on all nine, including the three whose paper halves name АИ-95 / G-Drive
95. **The production parser commits nothing on any of the 27 numeric cells**: numeric total 293 ->
320, committed stays 56 and committed-correct 53, precision 0.946, coverage 0.191 -> 0.175, the
mode stays off. The diagnostic Spike harness reads `pump-112` (4.60 / 2.199 / 10.14, the litres a
hundredth short) and commits confident-wrong values on two others - `102049.000` on `pump-107`,
the zero-padded total with a stray leading `1`, and `0.5` litres on `pump-114` - harness findings,
not production commits.

## Added 2026-09-19 (two Sikupilli pairs, EXIF stripped)

`pump-115` and `pump-116`: Circle K Sikupilli, Gilbarco heads, 98 miles+ at 1.979 EUR/L - 15.17 L
= 30.02 EUR (pump 7) and 27.86 L = 55.13 EUR (pump 8). Each is a **matched pair** with
`../receipts/receipt-074` / `receipt-075` (the receipts print the same triple, KOKKU 30.02 and
55.13), and each has a Live record and a 4K angle-and-flicker video in `../pump-live/`
(`live-6281`/`6280`, `live-6283`/`6285`). Both stills are JPEG with the orientation baked in and
**every EXIF field stripped** (product owner, 2026-09-19: no GPS, device or timestamp in the
corpus from here on; earlier fixtures keep what they were committed with). Windows annotated in
`windows.json` (+6 windows, 462).

## Added 2026-09-19 (a press photo, and a correction to pump-013)

`pump-117`: Dresser Wayne head at an Alexela station, Estonia, 98 - 52.65 L at 2.165 EUR/L =
113.99 EUR (the arithmetic closes to the cent). **Third-party**: an ERR news photo of 2022-06-16
(`https://s.err.ee/photo/crop/2022/06/16/1512979heedc.jpg`, added at the product owner's request),
the corpus's first fixture that is not the owner's own capture - it has no receipt, so its truth
is display-only, and it is not ours to redistribute; a public release of the corpus leaves it out.
Frontal, sunlit, 2730 x 1535 with no EXIF. The 98 board cell coincides with the transaction
price; the two other grade cells are unlit. Three windows (465).

`pump-013` corrected while the owner reviewed the annotations in `tools/pump-annotate`: the
price cell reads **1.774**, not 1.779. 1.779 was 13.06 / 7.34 - an inference, never on the
display - and none of the four board prices (1.774 / 1.834 / 1.824 / 1.984) reproduces 13.06, so
the transaction price is simply not shown. The cell is now a `board` window, `unitPrice` is
`notOnDisplay`, and the CSV's price is blank (unscored). Pump cells asserted: 326 → 328.

## Added 2026-09-19 (an Instagram photo)

`pump-118`: Dresser Wayne head at Circle K, Estonia, 98 miles+ - 43.23 L at 2.079 EUR/L =
89.88 EUR. **Third-party** (an Instagram post, added at the product owner's request; not ours to
redistribute, same standing as `pump-117`). No receipt; the arithmetic closes to the cent and is
what confirms the total, which sits under a strong window reflection (`legibility: partial`).
Portrait, 3072 x 4096, no EXIF; the 98 board cell coincides with the transaction price, the
other three are unlit. Three windows (468). Pump cells asserted: 328 → 331.

## Added 2026-09-19 (twelve third-party stills: drive2.ru and four pasted)

`pump-119` – `pump-130`, all **third-party** (eight from drive2.ru posts, four pasted by the product
owner; same standing as `pump-117`: not ours to redistribute, a public release leaves them out).
None has a receipt; every price on display closes the arithmetic to the cent, which is the truth.

| id | head / station | shows | note |
|---|---|---|---|
| 119 | Wayne, Circle K EE | 59.58 / 43.52 / 1.369 | 95 miles; three unlit board cells |
| 120 | Wayne, Circle K EE | 56.17 / 41.03 / 1.369 | four lit board prices, portrait, angled |
| 121 | Wayne, Neste EE | 56.55 / 39.77 / 1.422 | `EUR` / `EUR/1L` labels, a second board cell 1.372, `Tb = 15°C` |
| 122 | Wayne, Circle K EE | 56.14 / 39.56 / 1.419 | 98 milesPLUS; one board cell cut by the frame edge (not annotated) |
| 123 | unknown, RU | 1911,53 / 41,70 / 45,84 | comma decimals; price cell cut at the bottom edge (`partial`); board cells cut at the left edge |
| 124 | unknown, RU | 1803,39 / 0040,12 / 44,95 | zero-padded liters; price cut at the bottom (`partial`) |
| 125 | Wayne, Circle K EE | 59.52 / 41.36 / – | **price out of frame** - `notOnDisplay`, CSV blank (59.52 / 41.36 = 1.439 is an inference, not a reading) |
| 126 | Gilbarco, Circle K EE | 0056,76 / 0040,57 / – | zero-padded both rows, comma; price out of frame |
| 127 | Wayne, EE (LõunaLeht photo) | 0.00 / 0.00 / – | idle, three board prices, 636 px - the smallest fixture |
| 128 | Wayne, Gazpromneft RU | 0.00 / 0.00 / – | idle, five board prices 34.00–41.85 |
| 129 | Wayne, Circle K EE | 53.82 / 38.39 / 1.402 | steep angle, price cell at the frame's bottom |
| 130 | Wayne, RU | 1000.22 / 10.42 / 95.99 | a six-cell total with three zeros; car-wash reflection in the glass |

45 windows (513). Pump cells asserted: 331 → 363.

## Added 2026-09-19 (ten third-party stills: six new countries)

`pump-131` – `pump-140`, all **third-party** (pasted by the product owner from the web; same
standing as `pump-117`). The corpus's first heads outside EE / RU / KZ. Truth is the display plus
its arithmetic, as for every third-party still; the CSV `currency` is the display's.

| id | head / place | shows | note |
|---|---|---|---|
| 131 | Wayne, Circle K LT | 48.27 / 32.66 / 1.478 | a whole forecourt: the display is ~2 % of the frame height (below `PumpDisplayCapture.minimumRowHeightFraction` - a far-shot case the classifier is expected to miss); price cell `partial`; a customer from behind, no face |
| 132 | Wayne, Circle K LT | 25.74 / 18.40 / 1.399 | `SUMA` / `LITRAI` labels, 637 px |
| 133 | Wayne, Circle K EE | 30.22 / 22.57 / 1.339 | **total cut by the top edge** (`partial`); four lit board prices, the transaction price is the rightmost (D miles) |
| 134 | Tokheim, Iceland (ISK) | 5000 / 21,45 / 233,1 | a total with **no decimals**, comma decimals elsewhere, labels left of the cells |
| 135 | Tokheim, Turkmenistan (TMT) | – / 14.08 / 1.50 | the display is a few px tall in a full-pump shot: total unreadable (empty text, `partial`), CSV total blank |
| 136 | Wayne, Norway (NOK) | 717.75 / 50.76 / 14.14 | `KRONER` / `LITER` / `Kr/liter` |
| 137 | Wayne, UK (GBP) | 95.60 / 52.30 / 182.8 | **price in pence**: the cell shows `182.8`, the CSV asserts 1.828 (the checker's scale rule); `THIS SALE` / `LITRES` |
| 138 | Wayne, EE, monochrome | 20.23 / 11.77 / – | a black-and-white scan of a print; price not on display (`notOnDisplay`, 20.23 / 11.77 = 1.719 is an inference) |
| 139 | Wayne, France (EUR) | 103.88 / 64.40 / 1.613 | `€uro` / `Litres` / `€uro/litre`, 480 px |
| 140 | Wayne, Circle K LT | 62.30 / 33.69 / (1.849) | **does not close**: 33.69 x 1.849 = 62.29, the display shows 62.30 - the 970 px price cell is the likely misread; price unasserted with a `csvDisagrees` note, window `partial` |

33 windows (546). Pump cells asserted: 363 → 390.

## Added 2026-09-19 (seven third-party stills; two copies declined)

`pump-141` – `pump-147`, **third-party** (pasted by the product owner). Two of the ten pasted were
not added: one was `pump-118` again (dhash distance 1), one the watermarked thumbnail of the
stock photo that became `pump-145`.

| id | head / place | shows | note |
|---|---|---|---|
| 141 | Wayne, Sweden (SEK) | 957.74 / 38.98 / 24.57 | `KRONOR` / `LITER` / `Kr/liter`; the D price cell is **cut by the left edge** (`partial`) |
| 142 | Wayne, RU | (1600.11) / 48.49 / 33.00 | **does not close**: 48.49 x 33.00 = 1600.17, the 680 px total reads 1600.11 under glare - total unasserted, window `partial` |
| 143 | Wayne, RU | 3921.62 / 93.15 / 42.10 | 95; four grade cells, three unlit |
| 144 | Wayne, Alexela EE | 113.99 / 52.65 / 2.165 | **the same fill as `pump-117`** at a wider framing (dhash distance 61 - a different crop, not a copy); not a pair, one document |
| 145 | Tokheim, UK (GBP) | 46,59 / 28,60 / 162,9 | a **watermarked stock photo** - pence with a comma; CSV asserts 1.629 |
| 146 | Wayne, Gazpromneft RU | 1100.26 / 25.12 / 43.80 | 92; a media-outlet watermark in the corner |
| 147 | Wayne, EE | 66.17 / 44.29 / 1.494 | `EUR` / `LIITRIT` / `EUR/1L`, square 1080 px |

21 windows (567). Pump cells asserted: 390 → 410.

## Added 2026-09-19 (nine third-party stills: the Gilbarco Veeder-Root keypad head)

`pump-148` – `pump-156`, **third-party** (pasted by the product owner). Four are a head type the
corpus did not have: the Gilbarco Veeder-Root panel with a keypad, the price ladder as a column
of small cells at the LEFT of the display (not a row under it), and the transaction price in its
own cell under `ЦЕНА/ЛИТР`. Every arithmetic closes.

| id | head / place | shows | note |
|---|---|---|---|
| 148 | Wayne, RU | 1634.66 / 24.46 / 66.83 | 95; 540 px |
| 149 | Wayne, Circle K EE | 97.16 / 76.38 / 1.272 | D miles; portrait, the label column cut by the right edge |
| 150 | Wayne, Finland | 23.55 / 16.20 / 1.454 | `EUROA` / `LITRAA` / `€/litra`; the photographer's reflection over both rows (`partial`, confirmed by the arithmetic); four grades incl. `SMART DI` and `MPO` 0.982 |
| 151 | Gilbarco, Circle K EE | 0093,29 / 0045,64 / 2,044 | zero-padded both rows, comma; the price ladder is a column at the left; a graphic overlay (a quote mark) pasted on the photo |
| 152 | Wayne, RU | 305.88 / 6.73 / 45.45 | a blue-on-white LCD, square |
| 153 | Gilbarco Veeder-Root, RU | 3114,11 / 46,97 / 66,30 | keypad head, three-cell ladder at the left, one of them the transaction price; 1280x576 at night |
| 154 | Gilbarco Veeder-Root, RU | 1494,70 / 30,02 / 49,79 | keypad head, ladder unlit |
| 155 | Gilbarco Veeder-Root, RU | 3055,11 / 60,01 / 50,91 | keypad head, four-cell ladder, the price coincides with the second |
| 156 | Gilbarco Veeder-Root, RU | 934,05 / 23,95 / 39,00 | keypad head, backlit cells at night, three-cell ladder |

43 windows (610). Pump cells asserted: 410 → 437.

## Added 2026-09-19 (four more Veeder-Root heads; pump-153 at full resolution)

`pump-157` – `pump-160`, **third-party**, all Gilbarco Veeder-Root keypad heads in Russia. Of the
six pasted, one was `pump-153` again at 1920 px (dhash distance 0) - the fixture file now IS that
larger version, quads unchanged - and one a tighter crop of the same photo, not added.

| id | shows | note |
|---|---|---|
| 157 | 1747,20 / 44,80 / 39,00 | the price ladder cut by the left edge (no board windows); sunlit, a car reflected below |
| 158 | 9900,0 / 146,84 / 67,42 | **wet panel**, angled; the total has ONE decimal (five cells) - the CSV asserts the product 9899.95 with a `csvDisagrees` note, as `pump-003` |
| 159 | 1932,80 / 20,00 / 96,64 | a **preset** fill of exactly 20.00 L; a customer's torso at the bottom, no face |
| 160 | 00260,86 / 00004,28 / 061,79 | zero-padded all three rows, **does not close** (4.28 x 61.79 = 264.46): every cell is legible, so this is a loyalty discount on the total or a display artefact, like `pump-031`; only the price is asserted, the two other cells are blank |

12 windows (622). Pump cells asserted: 437 → 447.

## Added 2026-09-19 (fifteen third-party stills: the Veeder-Root head in depth, and Australia)

`pump-161` – `pump-175`, **third-party** (pasted by the product owner). Eleven are the Gilbarco
Veeder-Root keypad head in every condition the web offers; three pasted copies of `pump-153` /
`pump-154` were declined by dhash.

| id | head / place | shows | note |
|---|---|---|---|
| 161 | Veeder-Root, RU | (1619,83) / 24,38 / 66,44 | a TV-news still at 800 px with a channel bug; the blurred total reads 1619,83 where 24.38 x 66.44 = 1619.81 - total unasserted (`partial`) |
| 162 | Veeder-Root, RU | 666,36 / 14,19 / 46,96 | backlit night panel, four-cell ladder, a lens flare on the price |
| 163 | Wayne keypad, RU | 1997.93 / 41.00 / 48.73 | a Wayne with `СУММА` / `ЛИТРЫ` on amber LCDs and a keypad at the right, price in the 92 cell |
| 164 | Wayne keypad, RU | 2894.14 / 46.74 / 61.92 | same head; the total under a reflection (`partial`), a customer's torso below |
| 165 | Veeder-Root, RU | 3602,16 / 78,41 / 45,94 | 680 px, four-cell ladder, price coincides with the last |
| 166 | Veeder-Root, RU | 1014,25 / 15,12 / 67,08 | angled 780 px still with a media watermark |
| 167 | Veeder-Root, Shell RU | 2249,27 / 0042,77 / 52,59 | zero-padded liters only |
| 168 | Veeder-Root, Lukoil RU | 01500,52 / 00022,51 / 066,66 | zero-padded all rows and ladder, 1000 px, a 2026 notice below |
| 169 | Veeder-Root, RU | (91225,73) / 00130,72 / 039,90 | a video still; the total shows 91225,73 for 130.72 x 39.90 = 5215.73 - not a misread of a digit but a display artefact or a leading digit from an earlier state; total unasserted (`partial`) |
| 170 | Veeder-Root, Teboil RU | 00560,89 / 00011,00 / 050,99 | zero-padded; a preset of exactly 11.00 L |
| 171 | Veeder-Root, RU | 2843,52 / 39,14 / 72,65 | night, two lit ladder cells |
| 172 | Veeder-Root, Lukoil RU | 3478.82 / 59.99 / 57.99 | **point decimals** on a Veeder-Root; 576 px; two ladder cells legible |
| 173 | Veeder-Root, Australia (AUD) | 406.75 / 158.95 / 255.9 | **cents per litre** (CSV asserts 2.559); tilted ~20 degrees - the quads are skewed parallelograms, the first non-rectangular annotation; three ladder cells, one cut by the top edge |
| 174 | Wayne keypad, Lukoil RU | 2834.56 / 68.80 / 41.20 | 680 px; ЭКТО-ДТ |
| 175 | Veeder-Root, RU | 08038,17 / 00042,53 / 189,00 | zero-padded; 189 per litre |

51 windows (686). Pump cells asserted: 447 → 488.

## Added 2026-09-19 (fourteen third-party stills: Tatsuno, Wayne Pignone, Belarus, Bulgaria, Australia)

`pump-176` – `pump-189`, **third-party** (pasted by the product owner).

| id | head / place | shows | note |
|---|---|---|---|
| 176 | Veeder-Root, RU | 5388,93 / 61,21 / 88,04 | diesel at 88; sunlit |
| 177 | Veeder-Root, Bulgaria (BGN) | 9,99 / 6,89 / 1,45 | `сума` / `литри` / `цена/литър`; 640 px, display ~7 % of the frame |
| 178 | Veeder-Root, RU | (3539,5) / 50,00 / – | a 670 px forecourt shot, the display 8 % of the frame: total blurred to one decimal (`partial`, unasserted), price cell unreadable (empty text) |
| 179 | Veeder-Root, Lukoil RU, winter | 3533,58 / 0065,68 / 53,80 | four-cell ladder, the price coincides with the first; angled, a car below |
| 180 | Veeder-Root, Australia (AUD) | 44.82 / 20.76 / 215.9 | cents per litre (CSV 2.159); a cinema ad above the head, `7` pump number beside the price |
| 181 | Veeder-Root, RU | 1042,00 / 20,00 / 52,10 | a 20.00 L preset, 577 px square, angled |
| 182 | **Wayne Pignone**, Belarus (BYN) | 78.54 / 47.60 / 1.65 | `СУММА` / `ЛИТРЫ` / `ЦЕНА ЗА ЛИТР`, a news-site watermark |
| 183 | Veeder-Root, RU | (0990,88) / (0026,27) / (36,95) | photographed **through a car window** at ~8 % of the frame; all three cells `partial` and unasserted (26.27 x 36.95 = 970.68 does not close either - a misread somewhere) |
| 184 | Veeder-Root, RU | 2354,41 / 37,13 / 63,41 | 1280x576, three-cell ladder, nozzles at the left |
| 185 | Veeder-Root, Australia (AUD) | 101.00 / 71.53 / 141.2 | cents per litre (CSV 1.412); a four-grade ladder with two near-identical cells (141.2 / 141.1) |
| 186 | **Tatsuno**, RU | 887.00 / 22.01 / 40.30 | **amber LED** on black, `СУММА` / `ОБЪЕМ` / `ЦЕНА/Л` with `Руб` / `Л` unit tiles at the left - a head type new to the corpus; night |
| 187 | Tatsuno, RU | 876.00 / 20.00 / 43.80 | same head, further away; 20.00 L preset |
| 188 | Wayne Pignone, RU | 941.60 / 20.00 / 47.08 | `СУММА` / `ЛИТРЫ`, 95 / 92 board, 20.00 L preset |
| 189 | Veeder-Root, RU | 858.20 / 20.00 / 42.91 | point decimals; 20.00 L preset; ladder unlit |

53 windows (739). Pump cells asserted: 490 → 527.

**Row assignment on the ladder heads.** With 30 Veeder-Root panels in the corpus the geometry
pass reads **707/739 (0.957)** - 24 of its 32 misses are the price ladder taken for the board.
`PU.30` is the rule that fixes it; the floor sits at 0.95 until then.

## Added 2026-09-19 (eighteen third-party stills: the Tokheim Quality panel)

`pump-190` – `pump-207`, **third-party** (pasted by the product owner). Sixteen are the Tokheim
Quality panel - `Стоимость` / `Количество` / `Цена за 1 литр` printed LEFT of the cells, the unit
to the right, comma decimals, and a **one-decimal total** on six of them (asserted AS SHOWN, with a
`csvDisagrees` note carrying the exact product - the law reads the display, so the CSV must say what
the display says, as `pump-018` established). The corpus's fourth big head type.

| id | place | shows | note |
|---|---|---|---|
| 190 | Tokheim, Kazakhstan (KZT) | 7200,7 / 49,66 / 145,0 | fog, one decimal on total and price |
| 191 | Tokheim, RU | 500,0 / 10,00 / 50,00 | a 500 RUB preset, frontal, low contrast |
| 192 | Tokheim, RU | 3602,0 / 63,65 / 56,59 | the photographer reflected; 63.65 x 56.59 = 3601.95, the display rounds |
| 193 | Tokheim, RU | 3686,8 / 65,15 / 56,59 | same pump, next fill |
| 194 | Tokheim, RU | 4968,21 / 96,47 / 51,50 | dusk, blue sky |
| 195 | Tokheim, Lukoil RU | 481,01 / 10,63 / 45,25 | night, the price cell backlit green |
| 196 | Tokheim, Lukoil RU | 1895,04 / 49,35 / 38,40 | night, snow on the frame |
| 197 | Tokheim, RU | 3631,4 / 57,55 / 63,10 | amber backlight, a lamp flare above |
| 198 | Tokheim, Lukoil RU | 426,43 / 7,15 / 59,64 | strong reflection over the total |
| 199 | Tokheim, RU | 1630,88 / 30,09 / 54,20 | large cells, frontal |
| 200 | Tokheim, RU | 5232,15 / (990,00) / 52,85 | a CASH/LITRES keypad head; the liters row reads 990,00 for 99.00 (5232.15 / 52.85) - a lit segment or display artefact; CSV asserts 99.00, the window text what is shown |
| 201 | Tokheim, Belarus (BYN) | 64,92 / 24,97 / 2,60 | night, a QR sticker beside |
| 202 | Tokheim, RU | 1000,2 / 25,70 / 38,92 | a 1000 RUB preset, angled, night lamps reflected |
| 203 | unknown three-row head, RU | 960.78 / 44.75 / 21.47 | `РУБ` / `ЛИТР` / `РУБ`, the photographer over the whole display, a review-site watermark |
| 204 | Tokheim, Bashneft RU | 1625,49 / 24,76 / 65,65 | the display 4 % of a portrait frame |
| 205 | Tokheim, RU | 364,45 / 7,94 / 45,90 | 510 px, tilted |
| 206 | Tokheim, RU | 1499,9 / 40,87 / 36,7 | 600 px, blurred; the price cell's last digit dark (`partial`) |
| 207 | Dresser Wayne, RU | 1136.43 / 31.55 / 36.02 | `СУММА` / `ЛИТРЫ`, four price cells below with one lit |

54 windows (793). Pump cells asserted: 527 → 581.

## Added 2026-09-19 (four third-party stills: pesos, reais, and three-decimal cells)

| id | head / place | shows | note |
|---|---|---|---|
| 208 | Veeder-Root, RU | 4816,61 / 97,07 / (49,63) | night, rain streaks; the price cell dim and blurred, 4816.61 / 97.07 = 49.62 - unasserted (`partial`) |
| 209 | Wayne, Philippines (PHP) | 3450.08 / 46.749 / 73.80 | `PESOS` / `LITERS` / `PESOS / LITER`; **three-decimal liters** - a first; a `PUMP UNDER MAINTENANCE` sign beside |
| 210 | Wayne Pignone, Gazpromneft RU | 1610.82 / 31.40 / 51.30 | `СУММА` / `ЛИТРЫ` / `ЦЕНА ЗА ЛИТР`, a reflection over the total |
| 211 | Wayne, Brazil (BRL) | 29,73 / 7,63 / 3,897 | `TOTAL A PAGAR` / `LITROS` / `PREÇO POR LITRO`, three grade cells, **three-decimal price**, 600 px - the price cell 8 px tall (`partial`) |

12 windows (805). Pump cells asserted: 581 → 592. Currencies in the corpus: EUR RUB KZT ISK TMT NOK GBP SEK AUD BGN BYN PHP BRL.

## Added 2026-09-20 (two owner captures; the first full annotation review)

`pump-212`: Dresser Wayne at Circle K EE, D miles - 63.00 L at 2.069 = 130.35 EUR, four board
cells (the D cell is the transaction price, printed `2069` without a point); a Live Photo whose
record is `../pump-live/live-4386.mov` (73 frames). `pump-213`: Gilbarco at Circle K EE, pump 12,
zero-padded `0112,71` / `0063,00` at `1,789` (63.00 L again - the same fill logic, a 63-litre
tank). Both **train** (decision 9). Six + three windows (814). Pump cells asserted: 592 → 599 (pump-104's washed price, read on review as 1,949 and confirmed by `receipt-067`, is asserted too).

The product owner walked the annotator through 108 entries the same day (`reviewed: true`),
tightening quads corpus-wide, and read `pump-015`'s D price cell as **1.884** where the CSV holds
the arithmetic's 1.889 (15.89 x 1.889 = 30.02; 1.884 gives 29.94) - declared in `csvDisagrees`,
window `partial`, until a sharper look settles which digit is which.

## Added 2026-09-20 (four owner captures: the Cyrillic Gilbarco Veeder-Root head, day and night, and an Australian one)

`pump-214`: Gilbarco Veeder-Root at a Russian forecourt (station not named on the head), the
two-line main display `3478,52 РУБЛИ` / `67,14 ЛИТРЫ` with the unit price on its own window
`ЦЕНА/ЛИТР 51,81` - 67.14 x 51.81 = 3478.52 exactly; no zero padding, comma decimals. `pump-215`:
the same head at a Lukoil forecourt, **zero-padded** `00809,59` / `00015,11` at `053,58`, the
four-grade board lit down the left (`053,58` / `045,08` / `048,16` / `053,89` - the first cell is
the transaction's price, so a reader that takes the board's top cell for the price is right here
by accident and wrong on `pump-072`). `pump-216`: the same head **at night**, `1042,00` / `20,00`
at `52,10`, the board unlit, the nozzle rack (ДТ / 95 / 92) in frame. What they add: the
Cyrillic-labelled Veeder-Root face (the corpus's Veeder-Root heads were Estonian and third-party),
the `МИНИМАЛЬНАЯ ДОЗА ОТПУСКА 5Л` legend and the keypad as furniture, one padded and one unpadded
read of the same face, and a night exposure. Telegram-routed PNGs transcoded to JPEG with the APP1
stripped. `pump-217`: the Australian sibling - `$ 277.42` / `196.89 Litres` at `140.9` **cents per
litre** (CSV asserts 1.409, AUD), a four-grade ladder (diesel 125.7, ethanol 85 140.9, unleaded
E10 136.7, unleaded 142.7) with the E85 cell equal to the transaction price, a `1` pump number
beside the `$`, and an ad poster with a face below the head - the head fills the frame, the
poster is furniture. All four **train** (decision 9). Twenty windows, drawn by hand from the
stills (837). Pump cells asserted: 599 → 611, totals only (measured on macOS 27 - hits and commits stand
until the measured runtime runs). Beside them, `../pump-live/video-004`: the Kyrgyz cousin of this
head counting up through a fill (see that README).

## Added 2026-09-21 (an unbranded diesel head under glare - a declared-unreadable still)

`pump-218`: a three-window Cyrillic head (`Итого ... Рублей` / `Количество ... Литров` / `Цена за Л
... Рублей`) at an unnamed Russian forecourt, a `ТКК` sticker on the glass, `ДТ` on the nozzle
rack, an orange Peugeot passing behind. Six-digit zero-padded windows, and the whole face under
sky glare. Only the **price** is asserted: `069.75`. The litres window reads `0007.70` at a
glance, but 7.70 x 69.75 = 537.08 and the total's readable cells are `0054 1_`, which closes only
if the litres' last glyph is a `6` (7.76 x 69.75 = 541.26) - glare has washed a segment out, so
litres and total are **blank, not guessed** (both windows drawn, `legibility: partial`, empty
text). The still is the corpus's cleanest example of a segment lost to glare turning a 6 into a 0
at the digit level. **Train** (decision 9). Three windows (840). Pump cells asserted: 611 → 612,
totals only (macOS 27).

## Added 2026-09-21 (twenty-one pasted stills: the Topaz face, and its neighbours)

Pasted by the product owner in one sitting (sources unstated unless named); PNGs transcoded to
JPEG with no EXIF. The batch's centre of gravity is the **Топаз** three-window face (`СУММА РУБ`
/ `ОБЪЁМ ЛИТР` / `ЦЕНА РУБ/ЛИТР`, a keypad on the right, `СНАЧАЛА ЗАПРАВЬТЕСЬ ПОТОМ ОПЛАТИТЕ`
below) that Gazpromneft's post-pay forecourts run - the corpus had none. All **train**
(decision 9); windows drawn from the stills, none `reviewed`. Every triple closes unless said.

- `pump-219` Gilbarco Veeder-Root, Cyrillic, zero-padded `01984,80` / `00030,00` at `066,16`,
  the keypad's `Рубли` key in frame.
- `pump-220` Topaz at a G-Drive column, dusk, `3011.50` / `45.90` at `65.61`, a `ПИСТОЛЕТ НЕ
  РАБОТАЕТ` sign under the head. `pump-221` Topaz, `2281.02` / `38.24` at `59.65`, the pump
  number `4` lit in red, a `ПОСТОПЛАТА` poster above. `pump-222` Topaz at a truck forecourt,
  **mid-count**: `1078.38` / `17.88` at `60.39` does not close (17.88 x 60.39 = 1079.77) - the
  total window lags the litres by a pulse; transcribed as shown, `csvDisagrees` says why.
  `pump-223` a Gilbarco-style G-Drive head under heavy glare, `2872.57` / `55.03` with the
  price `52.20` in a small cell right of the sum - litres and price `partial`; the triple closes
  to the cent, which is how the litres were confirmed. `pump-224` Topaz at a Gazprom (not
  Gazpromneft) column, a **truck fill**: `34999.72` / `714.28` at `49.00` - five-digit total,
  three-digit litres. `pump-225` Topaz, `3392.47` / `49.01` at `69.22`, the photographer's phone
  reflected in the glass. `pump-226` Topaz in **service mode**: `d732441` / `б-1` / `P-1` - a
  code in the sum window, no fill; every cell blank, no windows.
- `pump-227` Topaz, dusk, `3230.58` / `46.82` at `69.00` - **third-party** (pikabu.ru, the owner
  pasted the link). `pump-228` Topaz at a `DEKO АЗС`, `250.38` / `3.21` at `78.00` - a
  three-litre fill, single-digit litres. `pump-229` Dresser Wayne at Gazpromneft, `1698.00` /
  `40.00`, the price `42.45` in the **92 board cell** under the litres (the other three cells
  dark) - the board IS the price here. `pump-230` Topaz, `2364.43` / `36.17` at `65.37`, a
  taxi reflected. `pump-231` Topaz at G-Drive, a **frame of `../pump-live/video-016`**
  (`2579.70` / `37.07` at `69.59`) - third-party (YouTube). `pump-232` Tokheim at G-Drive,
  `977,0` / `20,46` at `47,75` - a **one-decimal total** (20.46 x 47.75 = 976.97; the CSV carries
  the display's 977.00, `csvDisagrees` says so). `pump-233` Topaz, autumn, `2535.19` / `33.49`
  at `75.70`. `pump-234` Topaz, a **360 px frame of `../pump-live/video-017`** with a QR and a
  red caption band burned in (`409.52` / `5.90` at `69.41`) - third-party (VK).
- `pump-235` Dresser Wayne, **night, Belarus** (`35.84` / `14.75`, the price `2.43` in the ДТ
  board cell; `BYN`) - the corpus's first Belarusian rubles and first sub-10 price on a Cyrillic
  head. `pump-236` Dresser Wayne at Gazpromneft, night, snow on the housing, the blue backlit
  face: `3006.25` / `65.00`, the price `46.25` in a small cell beside the sum. `pump-237`
  Tokheim (Omsk, a `ПОВЕРЕНО 07.06.2018` sticker): `1000,07` / `20,62` at `48,50`. `pump-238`
  Gilbarco Veeder-Root, **France**: `71,82 €` / `39,70 L` at `1,809 €/L` - a three-decimal Euro
  price with comma decimals, `EUR`. `pump-239` Dresser Wayne at G-Drive, `300.18` / `8.54`,
  the price `35.15` in the 95 board cell.

Pump cells asserted: 612 → 672 (twenty triples, `pump-226` none), totals only (macOS 27).

`pump-240` (same day, later): Gilbarco Veeder-Root at a Lukoil column (`ЭКТО` / `95` on the
nozzle boots), Cyrillic, `4693,50` / `90,00` at `52,15` - a 90-litre preset, unpadded, the
`МИНИМАЛЬНАЯ ДОЗА ОТПУСКА 5Л` legend and the keypad in frame, a Kia Soul on the wet forecourt
behind. Train; three windows (903). Pump cells: 672 → 675.

`pump-241` (same day): Dresser Wayne Pignone, **Poland**, the dm³ face (`zł` / `dm³` / `zł/dm³`,
`LICZYDŁO POWINNO WSKAZYWAĆ ZERO`): `24.76` / `5.28` at `4.69`, under a canopy on a wet day - the
total's last glyph is a 6 that reads as an 8 at a glance (the orchestrator first transcribed
24.98; the product owner's review settled it, and 5.28 x 4.69 = 24.76 closes). `PLN`, train;
three windows. Pump cells: 675 → 678.

## Added 2026-09-21 (batch 6: the owner's morning at Peetri, Olerex and a second Circle K - 32 stills, windows pending)

`pump-242`..`pump-273`, every one with a Live record in `../pump-live/` (batch 6 there), all
**train**. Truth rows are written. `pump-242`/`243` were drawn by the product owner; the rest
were **auto-annotated** by the app's live path (`pump-read`, no windows: detector -> verifier
-> row assignment) - every row it assigned became a window with the CSV's text (board rows
with an empty one), none `reviewed`, and the Live records were tracked from those boxes. Eight
stay `pendingWindows` for the owner's hand: `pump-261` (the reader placed no row on the
oblique Wayne face) and seven where an asserted cell got no row (`248`, `249`, `253`, `255`,
`258` the price window; `257`, `267` the total). `pump-263` (the CLOSED negative) carries no
windows and a `negative` note. `pump-264` and `pump-265` are legitimate stills of the same
fill, but their Live records (`live-6321`, `live-6322`, `live-6323`) show the CLOSED text on
their frames - the display changed state inside the Live Photo - so both are `tracking: bad`
(product owner, 2026-09-21): the stills stay truth, the records train nothing. The auto-placed boxes are a head start, not a review: the
owner tightens, retypes the display's own spelling (`0063,27`) and marks processed.

- **Neste, Dresser Wayne** (`EUR` / `LIITRIT`, three-cell board `futura D` / `Neste MY D` /
  `futura 95`, all lit): `pump-242`/`243` one fill twice (24.61 / 13.13), `pump-244` 52.25 /
  27.88 with the photographer in the glass. The price is a board cell (1.874), so `unitPrice`
  is blank the way `pump-021`..`023` are.
- **Circle K Peetri, Gilbarco Veeder-Root** (zero-padded, `€` / `L` / `€/L`): `pump-245`/`246`
  pump 2 (84,80 / 44,19 at 1,919), `247` pump 1 (69,99 / 36,47 at 1,919), `248`/`249` pump 3
  (44,98 / 21,43 at 2,099 - **pair** with `receipt-084`), `250`/`251` pump 7 (75,35 / 35,90 at
  2,099), `252` pump 8 (68,05 / 32,42), `253` pump 5 (35,07 / 17,90 at 1,959 under glare -
  **pair** with `receipt-085`), `254` pump 9 **AdBlue** (3,60 / 3,75 at 0,959 - the corpus's
  first sub-1 price and first non-fuel fill), `255` pump 6 (42,00 / 20,01), `256` pump 6
  (31,91 / 15,20 at 2,099 - **off by a cent**: 15.20 x 2.099 = 31.90, the head rounds on more
  litre precision than it shows), `257` pump 7 (38,69 / 20,32, the price window washed out -
  blank), `258` pump 4 (67,28 / 35,06 at 1,919), `259` pump 8 (131,94 / 62,86 at 2,099).
- **Circle K, Dresser Wayne** (`SUMMA` / `LIITRIT`, four-cell `miles` board, all lit, no price
  window): `pump-260`/`261` pump 5 (20.99 / 10.00), `262` pump 2 (36.17 / 17.23), `263` pump 4
  **negative** - `CLOSED` in the sum window, `-00-` on the board, no fill, every cell blank
  (product owner: a reader must commit nothing here), `264`/`265` pump 4 (55.40 / 28.87), `266`
  pump 3 (66.74 / 36.29 - closes only at **1.839**, the 95 miles 1.919 less an 8-cent loyalty
  discount the board does not show), `267` pump 1 (122.54, litres `58.3?` under glare - blank).
  `unitPrice` blank throughout (board, not a transaction price).
- **Olerex, Dresser Wayne** (`TANKUR N 24 h` label): `pump-268`, `pump-269` **idle** (0.00 /
  0.00, board 2.109 / 1.884), the photographer in the glass.
- **A second Circle K, Gilbarco with the five-grade board down the left** (1.919 / 1.969 /
  1.979 / 2.132 / 2.232): `pump-270` (63,27 / 31,97 at 1,979), `271` (25,11 / 11,25 at 2,232),
  `272` pump 4 (86,32 / 40,49 at 2,132), `273` pump 2 (68,05 / 35,46 at 1,919).

Pump cells asserted: 678 → 753 (32 stills; two idle and one negative assert nothing, three
board-only Wayne heads assert two cells each, two glare stills two). Totals only (macOS 27).
