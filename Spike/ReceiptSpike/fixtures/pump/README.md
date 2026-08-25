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
