# OCR fixture corpus

Real receipt and pump-display photos with hand-checked ground truth. This is the
corpus the **L5 accuracy gate** scores against (`docs/TESTING.md`, `docs/PHASES.md`
→ P2): receipts at the recorded high-water mark, pump photos ≥95% or the mode
stays off.

```
fixtures/
  receipts/   receipt photos + expected.csv      -> Vision OCR (L5 accuracy gate)
              12 receipts, 9 brands, 5 years, RU. Baseline 40.0% - see its README
  pump/       pump-display photos + expected.csv -> Vision OCR (L5, >=95% or the mode stays off)
              pump-002 is the SAME fill as receipt-007: independent ground truth
  fiscal/     OFD documents + expected.csv       -> text layer where there is one, OCR where there is not (P2.6)
  screenshots/ e-receipt screenshots + expected.csv -> Vision OCR, rendered text
```

`screenshots/` is Vision OCR like `receipts/`, but of *rendered* text rather
than a photographed surface - no glare, no perspective, no crumpling, and app
chrome in the frame instead. Scored separately so neither number flatters the
other.

`fiscal/` is deliberately separate: it is what the app gets after scanning a
fiscal QR, not a photo of paper. Folding a text-layer document into `receipts/`
would inflate the image-accuracy number with a document OCR never had to read.

Note the folder is **no longer uniformly text-bearing**: `fiscal-001` (ofd.ru)
has a text layer, `fiscal-002` (ofd-ya.ru) is image-only and must be rendered and
OCR'd. See `fiscal/README.md`.

## Adding a photo

1. Drop it in the right folder, named `receipt-NNN.heic` / `pump-NNN.heic` in
   sequence. Keep the original resolution - downscaling changes what OCR sees,
   so a downscaled fixture measures a different problem than the app has.
2. Read the values off the photo yourself and add a row to that folder's
   `expected.csv`.
3. Re-run and check the parser against it:

```bash
cd Spike/ReceiptSpike
swift run ReceiptSpike fixtures/receipts              # score
swift run ReceiptSpike fixtures/receipts --dump-text  # raw OCR, to debug a miss
```

## expected.csv

Machine-read, so **no comment lines and no blank lines** - the harness drops only
the first line as a header and needs four columns per row.

```csv
filename,liters,unitPrice,total
receipt-001.heic,67.00,1.869,125.22
```

**Leave a field empty rather than guessing.** A wrong ground truth is worse than
a missing one: the gate ratchets against it, so a guess becomes a permanent lie
the accuracy number is measured from. An empty field is simply skipped for that
file.

## A matched pair is worth more than two photos

`pump/pump-002-lukoil-spb-ru.png` and `receipts/receipt-007-lukoil-spb-100-ru.png`
are the same purchase. That is what proved the parser returns litres and unit
price **swapped** on receipt-007 - the pump states them separately and labelled,
so it settles what no amount of re-reading the receipt could. `receipt-001` and
`pump-001` are the other such pair. Prefer shooting both when you can.

Note the two disagree on the total *by design*: the pump reads 4334.83, the
receipt 4334.00, because Лукойл rounds the fiscal total down to the whole rouble
(`fiscal/README.md`). Same fill, both correct, ~1 ₽ apart.

## The corpus is the unblocking task for P2

Most of P2 cannot be built honestly without it. Confidence thresholds tuned
against imagined data produce a gating rule that looks principled and behaves
badly on the first real receipt, and `≥95%` means nothing measured over one
image. Breadth matters more than count: brands, countries, languages, lighting,
crumpled paper, thermal fade, and the mixed receipts (fuel + car wash) that
hard rule 4 exists for.

## Known gaps in the current corpus

- **1 receipt, 0 pump displays.** Every accuracy figure below a few dozen images
  is anecdote, not measurement.
- `receipt-001.heic` (Circle K, Tallinn, Estonian): the parser reads liters,
  unit price and total exactly, and the cross-check locks
  (67.00 × 1.869 = 125.22). It reports fuel kind **98**, which is wrong - the
  fuel is **diesel**, confirmed by the owner of the receipt. The receipt's OCR
  line garbles to `D BÓ miles`, where `D` is the diesel marker and `miles` is
  Circle K's brand, not a grade.
- **`receipts/receipt-001.heic` and `pump/pump-001.heic` are one fill-up.**
  Collect such pairs deliberately - each photo is independent ground truth for
  the other's *numbers*.
- **But do not infer fuel kind from a pump photo.** This corpus already has one
  worked example of getting that wrong: the display OCRs to `miles+`, `miles`,
  `miles+`, `miles`, `95`, and reading that `95` as the dispensed fuel is
  exactly backwards. A multi-product pump shows the labels of **every** nozzle
  it has, so a visible grade is evidence the station *sells* it, never that this
  fill used it. The authoritative source is the receipt line, or the person who
  filled the tank.
- The receipt carries an `EXTRA SOODUS -1,01 EUR` discount line. Worth keeping:
  discounts are exactly where fuel amount and receipt grand total diverge
  (CLAUDE.md hard rule 4).
