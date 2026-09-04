# OCR fixture corpus

Real receipt and pump-display photos with hand-checked ground truth. This is the
corpus the **L5 accuracy gate** scores against (`docs/TESTING.md`, `docs/PHASES.md`
→ P2): receipts at the recorded high-water mark, pump photos ≥95% or the mode
stays off.

```
fixtures/
  receipts/   receipt photos + expected.csv      -> Vision OCR (L5 accuracy gate)
              48 files, RU + EE + KZ, 6 years. Score 180/220 - see its README
              receipt-036 is the first NON-FISCAL terminal slip: no QR, no VAT, no fiscal ids
              receipt-047/048 are matched pairs with pump-065/066 (see high-water.json):
              048 sweeps 5/5, 047 abstains on both operands - they bracket the RUB band
  pump/       pump-display photos + expected.csv -> Vision OCR (L5, >=95% or the mode stays off)
              66 displays, 6 makes, EE/RU/KZ. Score 53/261. pump-016/017 are idle - negative fixtures
              pump-021/022/023 are sun-glared; their values came from the photographer, not the photo
              pump-002 is the SAME fill as receipt-007: independent ground truth
  fiscal/     OFD documents + expected.csv       -> text layer where there is one, OCR where there is not (P2.6)
  screenshots/ e-receipt screenshots + expected.csv -> Vision OCR, rendered text
              8 screens, RU + Circle K EE/LV/LT. See its README on discounts vs the cross-check
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

1. Drop it in the right folder, named `receipt-NNN-<slug>.<ext>` /
   `pump-NNN-<slug>.<ext>` in sequence - the slug names the brand, site and
   whatever the fixture exists to prove. Keep the original resolution -
   downscaling changes what OCR sees, so a downscaled fixture measures a
   different problem than the app has. **Do not route a photo through a chat
   app**: Telegram recompresses to 1280 px and strips EXIF, which is below even
   the gateway's own 1800 px rendition (receipt-047/048 and pump-065/066 came in
   that way and are marked as such in high-water.json, so a MISS on those four
   cannot be blamed on the parser alone).
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
the first line as a header and needs six columns per row.

```csv
filename,liters,unitPrice,total,fuelKind,currency
receipt-001.heic,67.00,1.869,125.22,diesel,EUR
```

- `fuelKind` is written as the canonical `FuelKind` raw value
  (`diesel`, `petrol92`, `petrol95`, `petrol98`, `petrol100`, `lpg`, `cng`,
  `e85`, `electricity` - exactly as `docs/SCHEMA.md` spells them), `currency`
  as the ISO-4217 code (`RUB`, `EUR`, `KZT`, ...). Both are compared exactly,
  never with the numeric tolerance.
- On a **pump display** `fuelKind` stays empty for every row: the grades shown
  belong to every nozzle, not to this fill, so no pump photo carries a
  claimable fuel kind (`pump/README.md`). The receipt or the user decides.
- `currency` is claimed wherever the document or its paired fixture settles the
  money's denomination (a `₽`/`РУБ`/`€`/`EUR`/`ТЕНГЕ`/`KZT` marker, or a
  matched pair whose sibling states it). Where neither exists it stays empty.

**Leave a field empty rather than guessing.** A wrong ground truth is worse than
a missing one: the gate ratchets against it, so a guess becomes a permanent lie
the accuracy number is measured from. An empty field is simply skipped for that
file.

## A matched pair is worth more than two photos

`pump/pump-002-lukoil-spb-ru.png` and `receipts/receipt-007-lukoil-spb-100-ru.png`
are the same purchase. So are `receipt-001`, `pump-001` and
`screenshots/screenshot-004` - a **triple**, and the third view is what finally
explained the other two: the app record shows a `1.01 EUR` discount line, so the
receipt's `1.869` is the effective price and the pump's `1.884` is the list
price. Neither was wrong. See `screenshots/README.md`. That is what proved the parser returns litres and unit
price **swapped** on receipt-007 - the pump states them separately and labelled,
so it settles what no amount of re-reading the receipt could. `receipt-001` and
`pump-001` are the other such pair. Prefer shooting both when you can.

Note the two disagree on the total *by design*: the pump reads 4334.83, the
receipt 4334.00, because Лукойл rounds the fiscal total down to the whole rouble
(`fiscal/README.md`). Same fill, both correct, ~1 ₽ apart.

`receipt-038` and `pump-019` are a matched pair that **agrees to the cent** - the
only one of the three pump/receipt pairs that does. `pump-002` differs by a fiscal
rounding rule and `pump-018` by display rounding, so agreement is one outcome of
three rather than the expected case.

`receipt-036`, `receipt-037` and `pump-018` are a **triplet of one transaction**
(Татнефть АЗС-172, 25.00 L x 99.99 ₽): the card-terminal slip, the fiscal cheque
and the pump display of a single fill. It is the corpus's sharpest evidence that
**operand order carries no information** - the slip prints `x25.00 лит x99.99 РУБ`
and the cheque prints `99.99 X 25 Л`, one minute apart on one till - and it adds a
second, opposite rounding direction: this pump rounds its money line **up** to
0.1 ₽ (2499,8 against the paper's 2499.75) where Лукойл's rounds **down** to the
rouble. See `receipts/README.md` for why it also undercuts the decimal-count
heuristic P2.9 rests on.

## The corpus is the unblocking task for P2

Most of P2 cannot be built honestly without it. Confidence thresholds tuned
against imagined data produce a gating rule that looks principled and behaves
badly on the first real receipt, and `≥95%` means nothing measured over one
image. Breadth matters more than count: brands, countries, languages, lighting,
crumpled paper, thermal fade, and the mixed receipts (fuel + car wash) that
hard rule 4 exists for.

## Known gaps in the current corpus

- **Breadth is still the limit, not count.** Every accuracy figure below a few
  dozen images per class is anecdote, not measurement. As of 2026-08-26 the
  corpus holds 35 receipts, 17 pump displays, 8 screenshots and 2 fiscal
  documents.
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
