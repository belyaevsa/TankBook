# Pump-display photos

Photos of the pump readout, for the **pump-photo mode** that `docs/VISION.md`
gates hard: it ships only at **>=95%** accuracy, or the mode stays off
(`docs/TASKS.md` P2.7 - "the gate IS the check").

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

## Current parser result: fails, instructively

```
liters 0.700   unitPrice –   total –   cross-check ✗
```

Truth is `67.00 L x 1.869 EUR/L = 125.22 EUR`. Two distinct failures, and
neither is a tuning problem.

**Pump class baseline, 2026-08-24: 0/12 fields (0.0%), cross-check 0/4.** All four
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
