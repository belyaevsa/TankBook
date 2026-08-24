# Receipt photos (the L5 accuracy gate corpus)

Photos of paper receipts - the class the accuracy gate scores (`docs/TESTING.md`,
`docs/PHASES.md` → P2). Ground truth in `expected.csv`; `*.qr.txt` holds the
fiscal QR payload where the photo's QR decoded, so a P2.6 QR-parser test has real
input without re-decoding an image.

## Baseline, 2026-08-24: 12/30 fields (40.0%), cross-check 5/13

Measured with `swift run ReceiptSpike fixtures/receipts`. Before this batch the
corpus was **one** photo scoring 3/3, which is arithmetic rather than a gate. The
number dropped because the corpus finally has breadth - 12 receipts, 9 brands, 5
years, Cyrillic throughout, two VAT rates, four fuel kinds including LPG.

**Do not "fix" this by tightening the parser against these files.** The failures
below are structural, and each names a decision P2 has to make.

## What the failures actually are

### 1. Litres and unit price come back swapped, and the cross-check cannot tell

`receipt-007` (Лукойл СПб) parses as `liters 99.400, unitPrice 43.610`. The truth
is the reverse - `43.61 л` at `99.40 ₽/L` - and we know it independently because
`../pump/pump-002-lukoil-spb-ru.png` is a photo of the pump for that same fill,
reading `ЛИТРЫ 43.61 / ЦЕНА/ЛИТР 99.40`. `receipt-008` is swapped the same way.

Both still report cross-check **✓**, because `a x b == b x a`. **The cross-check
validates the product, never the assignment.** Nothing downstream of it can catch
this; a fill-up would be stored as 99.4 litres at 43.61, and consumption - the
number the whole app exists to compute - would be wrong by a factor of 2.3 with
every arithmetic check green.

Disambiguation has to come from outside the multiplication:
- the **unit marker's position** - `47.56 л X 129.00` and `62.89*66.810л` both
  attach `л` to the quantity, on opposite sides of the operator;
- **decimal places** - quantities print 2-3 (`66.810`, `63.000`), prices 2-3 too,
  so this is weak on its own;
- a **plausibility prior** on price per litre, which is the only signal that
  works when the marker is absent, and which needs a currency and a year.

### 2. The total-finder grabs the wrong line, three different ways

- **VAT**: `receipt-002` returns `3555.89` (`СУММА НДС 22%`), `receipt-011`
  returns `700.28` (`СУММА НДС 20%`).
- **The rounding line**: `receipt-012` returns `0.08` - the value of `ОКРУГЛЕНИЕ`.
- **The grand total on a mixed receipt**: `receipt-009` returns `6264.00` when the
  fuel line is `6135.24`. This is `CLAUDE.md` hard rule 4 failing in the open.

The mechanism behind the VAT and rounding misses is reading order: in a
right-aligned two-column receipt, Vision emits **value before label**, so a
finder that looks for a number *after* its label lands on the next row's value.

### 3. Fuel kind is not normalised

The parser emits `100`, `95`, `АИ-92`, `ДТ` and `98` as raw strings. `docs/SCHEMA.md`
defines the FuelKind vocabulary; nothing maps `ДТ`/`Диз.топл.`/`ДТ-Л-К5` → diesel
or `АИ-92-К5` → petrol92. LPG (`СУГ`, `receipt-012`) is not recognised at all.

## The two receipts whose ground truth is deliberately blank

`receipt-002/003/004/005` (ООО "Крым Оил") print `цена*количество` with **no unit
marker on either operand** - `205.00*20`, `259.00*20`, `450.00*43.820` - and the
`л` floats near the sum instead. Both readings give the identical total, so the
arithmetic cannot settle which number is which.

Context makes one reading likelier: `receipt-013` (РН-Москва, 13.07.26) prints
**labelled columns** - `Цена за ед. 71.25 | Кол. 50 | Сумма 3562.50` - fixing
АИ-95 at ~71 ₽/L in July 2026, and `fiscal-002` has Лукойл at 73.06 in August. On
that scale the Крым Оил numbers read as price-first at crisis prices (АИ-95 at
205, diesel at 259) with the `*20` pairs being a 20 L rationing cap - all on one
southern road trip, `receipt-006` (а/м "Дон", АИ-92 at 195) included.

**That is an inference, so `liters` and `unitPrice` are left empty.** The corpus
rule is that a wrong ground truth is worse than a missing one, because the gate
ratchets against it and the guess becomes permanent. `total` is recorded for all
four - it is unambiguous, and QR-verified for 002 and 003.

`receipt-010` (Газпромнефть) leaves `unitPrice` empty for a different reason: the
fill has **two** unit prices, 62 L at 48.54 and 1 L at 48.52, against an undiscounted
`63.000 л X 69.11` line and a 1295.93 bonus discount. The 63 L and the 3058.00 paid
are certain; a single "the" unit price is not a thing this receipt has.
