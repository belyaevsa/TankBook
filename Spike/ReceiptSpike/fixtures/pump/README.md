# Pump-display photos

Photos of the pump readout, for the **pump-photo mode** that `docs/VISION.md`
gates hard: it ships only at **>=95%** accuracy, or the mode stays off
(`docs/TASKS.md` P2.7 - "the gate IS the check").

## What is here

`pump-001.heic` - Circle K, Tallinn, Wayne/Dresser pump. **The same transaction
as `../receipts/receipt-001.heic`**, so the paper receipt is independent ground
truth for the display, and vice versa. Pairs like this are worth collecting
deliberately: neither photo alone could settle what the fuel actually was.

## Current parser result: fails, instructively

```
liters 0.700   unitPrice –   total –   cross-check ✗
```

Truth is `67.00 L x 1.869 EUR/L = 125.22 EUR`. Two distinct failures, and
neither is a tuning problem:

1. **Seven-segment displays lose the decimal point.** OCR reads `SUMMA 12522`
   and `1869 HIND/1L` - the separator that makes them `125.22` and `1.869` is
   simply not in the recognised text. `LIITRIT 67.00` came through intact, so
   this is per-field, not global. A pump parser therefore cannot trust the
   decimal point to exist; it has to reconstruct scale, most reliably by using
   the cross-check itself (`liters x price = total` picks the only consistent
   placement).
2. **Pump surrounds are covered in advertising.** The parser returned 0.700
   litres from `Wrapper ja jook 0,5-0,7l` - a sandwich-and-drink promo printed
   beside the display. Receipts have no equivalent noise, which is why a
   receipt-tuned parser scores far worse here than its receipt numbers suggest.

Both argue that pump mode needs its own extraction path rather than the receipt
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
