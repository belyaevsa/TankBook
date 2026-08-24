# OCR fixture corpus

Real receipt and pump-display photos with hand-checked ground truth. This is the
corpus the **L5 accuracy gate** scores against (`docs/TESTING.md`, `docs/PHASES.md`
→ P2): receipts at the recorded high-water mark, pump photos ≥95% or the mode
stays off.

```
fixtures/
  receipts/   receipt photos + expected.csv      -> Vision OCR (L5 accuracy gate)
  pump/       pump-display photos + expected.csv -> Vision OCR (L5, >=95% or the mode stays off)
  fiscal/     OFD documents + expected.csv       -> text layer, NOT OCR (P2.6)
```

`fiscal/` is deliberately separate: those documents carry a text layer, so they
are read exactly without OCR. Folding them into `receipts/` would inflate the
image-accuracy number with documents OCR never had to read.

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
  (67.00 × 1.869 = 125.22). It reports fuel kind **98**, which looks wrong - the
  OCR line is `D BÓ miles`, and `D` on a Circle K Estonia receipt is Diesel
  ("miles" is the brand, not the grade). Left out of `expected.csv` rather than
  guessed; confirm from the paper receipt and add a `fuelKind` column when the
  harness scores it.
- The receipt carries an `EXTRA SOODUS -1,01 EUR` discount line. Worth keeping:
  discounts are exactly where fuel amount and receipt grand total diverge
  (CLAUDE.md hard rule 4).
