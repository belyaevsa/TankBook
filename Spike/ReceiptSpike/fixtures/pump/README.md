# Pump-display photos

Photos of the pump readout, for the **pump-photo mode** that `docs/VISION.md`
gates hard: it ships only at **>=95%** accuracy, or the mode stays off
(`docs/TASKS.md` P2.7 - "the gate IS the check").

## The flag's contract (P2.7, recorded 2026-08-25)

Pump mode is a **feature flag** with this contract, enforced by code and by a
build-failing test rather than by prose:

- **Defaults off.** The bundled config ships `pumpPhoto` disabled; the app is
  fully usable with it never turning on.
- **The gate is a property of the build, not a runtime opinion.** The measured
  pump accuracy is compiled into `PumpPhotoGate` (`measuredHits` / `measuredTotal`,
  0/30 today, and asserted against the live corpus score by the Vision-gated
  ratchet test). A remote config document may only ever turn the flag **down**
  while the gate fails, never up - `ConfigStore.isEnabled(.pumpPhoto)` is false
  regardless of rollout below the threshold. This is the same reasoning as
  `docs/CONFIG.md` -> "Config can never disable a security control".
- **Off is not a dead end (hard rule 15).** A pump capture with the flag off
  routes to the ordinary manual form, pre-filled with nothing and with no
  message - the feature is simply not offered, and there is no error to show.
- **On (developer builds) still obeys hard rule 13.** Extraction may pre-fill,
  but every field is a default input the user edits; a pump **volume in
  particular** must never be written without the user seeing it, because the
  factor-of-ten ambiguity (`pump-003` above) is invisible on a Confirm screen.

Raising `measuredHits` above 28/30 (95%) is the only way the flag can turn on -
and it must land in the same change as the parser fix that earned it, together
with the recorded high-water mark and this README.

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

Keep the original resolution, name in sequence (`pump-002.heic`...), and put the
truth in `expected.csv` beside the images - the harness looks for it in the
folder it is pointed at. Leave a field empty rather than guessing.

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

**Nine `.heic` fixtures still carry EXIF.** They cannot be stripped without
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
