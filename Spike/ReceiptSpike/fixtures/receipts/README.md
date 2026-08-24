# Receipt photos (the L5 accuracy gate corpus)

Photos of paper receipts - the class the accuracy gate scores (`docs/TESTING.md`,
`docs/PHASES.md` → P2). Ground truth in `expected.csv`; `*.qr.txt` holds the
fiscal QR payload where the photo's QR decoded, so a P2.6 QR-parser test has real
input without re-decoding an image.

## Baseline, 2026-08-24: 18/47 fields (38.3%), cross-check 6/16

Measured with `swift run ReceiptSpike fixtures/receipts`. Before this batch the
corpus was **one** photo scoring 3/3, which is arithmetic rather than a gate. The
number dropped because the corpus finally has breadth - 15 receipts across 16
files, 12 brands, 5 years, Cyrillic throughout, two VAT rates, four fuel kinds
including LPG.

Split by field, which is more useful than the headline:

| | correct |
|---|---|
| **total** | 11 / 16 |
| **litres + unit price** | 3 / 16 receipts fully right (001, 003, 016) |
| extracted litres/price at all | 6 / 16, and **2 of those 6 are swapped** |
| fuel kind normalised to the SCHEMA vocabulary | 0 / 16 |

**OCR is not the bottleneck.** Vision reads these at confidence 1.00 - including
`Цена за / Кол. / 71.25 / 3562.50` on the labelled-column receipt-013 and
`100.00*30 / Л =3000.00` on receipt-014 - and the parser still returns no litres
and no price for either. Every failure below is a parser failure.

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

**Resolved as a design decision (2026-08-24):** `docs/SCHEMA.md` → Reference data →
Fuel price bands specifies the resolution ladder, and `docs/API.md` registers the
endpoint that serves the bands. Simulated against this corpus, the ladder resolves
**12 of 13** ambiguous fixtures correctly with **zero wrong** and one honestly
undecided (`receipt-008`, 48.89 vs 48.80, where guessing wrong costs 0.2%).

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

### 3. A station number is mistaken for the fuel grade

`receipt-015` returns fuel kind **98**. The receipt is АИ-95, and the `98` comes
from its first line - `ООО"КЕДР" АЗС-98`, the station number - which the parser
reaches before the actual product line `1 Бензин АИ-95-К5 Ультра`. The same digits
appear again lower as `АЗС № 98`.

Any grade detector that scans for a bare `92|95|98|100` anywhere in the document
will hit station numbers, pump numbers (`ТРК №3`), reservoir numbers, till numbers
and street addresses. The grade must be read **from the product line**, anchored to
a fuel word (`Бензин`, `Диз.топл.`, `ДТ`, `СУГ`) or to the `АИ-NN-K5` pattern
specifically - never from a loose digit match.

### 4. Repeated values are free redundancy, and the parser ignores it

On `receipt-015` Vision read one of the three printed totals as **`=5380.0D`** - a
`D` for a `0`, at confidence 1.00, the same misread class as `pump-004`. It did not
matter, because the receipt prints that total **three times** (ИТОГ, БЕЗНАЛИЧНЫМИ,
ПЛАТ.КАРТОЙ) and the other two read cleanly.

That is worth exploiting deliberately: on a receipt, **take the modal value across
repeated occurrences** rather than the first match. It costs nothing and it defeats
exactly the single-digit misread that no confidence threshold can catch. Note the
asymmetry with pump displays, which print each number once and therefore have no
redundancy to fall back on - one more reason pump extraction is the harder problem.

### 5. Non-fiscal receipts exist, and they have no QR at all

`receipt-016` is a **НЕФИСКАЛЬНЫЙ ОТЧЁТ** - a corporate fuel-card order receipt
(РН-Карт) from АО "РН-Москва". It prints a fiscal `ФН`, but it is explicitly a
non-fiscal report and **carries no QR code**. `docs/JOURNEYS.md` J5 assumes a
fiscal QR; fuel-card purchases simply do not have one, so they fall to the OCR
path with no exact-fill shortcut available. Worth knowing before J5's "scan the
QR, done" is treated as covering every Russian fill.

It brings three parsing hazards, all new:

- **A space is used as the thousands separator**: `1 932.00`. A number reader that
  splits on whitespace sees `1` and `932.00`; one that strips whitespace sees
  `193200`. Note the same document also prints `1932.00` unspaced further down, so
  the modal-value rule from item 4 resolves it for free.
- **`руб` labels the price operand**: the line is `руб  64.40 X 30.000`, with the
  currency word marking which operand is money. That is a genuine step-2 signal for
  the resolution ladder, and a second marker family beyond `л`/`L`/`gal`. Vision
  emits `руб` as its **own line**, so using it requires bounding boxes rather than
  string order - the same requirement as the label/value pairing in item 2.
- **The receipt declares its own unit convention**: `1 ед.=1 литр для
  нефтепродуктов/СУГ`, `1 ед.=1 м3 для КПГ`. That is free, authoritative metadata
  when present - and it surfaced a schema gap: CNG is sold by the cubic metre and
  `VolumeUnit` has no `m3` (`docs/SCHEMA.md` → Open questions).

### 6. Fuel kind is not normalised

The parser emits `100`, `95`, `АИ-92`, `ДТ` and `98` as raw strings. `docs/SCHEMA.md`
defines the FuelKind vocabulary; nothing maps `ДТ`/`Диз.топл.`/`ДТ-Л-К5` → diesel
or `АИ-92-К5` → petrol92. LPG (`СУГ`, `receipt-012`) is not recognised at all.

## The operand-order question, and how it was settled

Four ООО "Крым Оил" receipts print `цена*количество` with **no unit marker on
either operand** - `205.00*20`, `259.00*20`, `450.00*43.820` - the `л` floating
near the sum instead. Both readings give the identical total, so arithmetic cannot
settle which number is which, and they shipped with blank `liters`/`unitPrice`.

**The volume on `receipt-015` is user-confirmed at 20 litres**, by the person who
bought it - independent of any inference from the printer format. The unit price is
recorded as 269.00 rather than the 268 they recalled, because the receipt's own
arithmetic pins it: `268 x 20 = 5360`, twenty roubles short of the printed
`ИТОГ 5380.00`, and the printed `СУММА НДС 22% = 970.16` is exactly 22/122 of 5380.
Two independent figures on the receipt agree on the total, and `5380 / 20 = 269.00`.

It is a **regional convention, not one chain's quirk**: `receipt-015` is ООО "Кедр"
(АЗС-98, Симферополь), a different company from Крым Оил, printing the identical
unmarked `269.00*20` for АИ-95 - and the same **20 L** second operand. Two
unrelated operators capping at exactly 20 litres is rationing, which is itself
evidence that 20 is the quantity and not the price.

The two also date the escalation: Крым Оил sold АИ-95 at 205.00 on 01.07.26,
Кедр at 269.00 on 11.07.26, while РН-Москва was at 71.25 the same month. A
curated band built from national averages would have called both impossible,
which is exactly why the bands must rank rather than veto.

`receipt-014` (АЗС "Апельсин", Пенза) settles it. Same printer format, same
missing marker, and it reads **`100.00*30`** for АИ-95. Price-first gives 30 L at
100.00 ₽/L; quantity-first gives 100 L at **30.00 ₽/L**, which is below excise plus
cost and therefore impossible. **The first operand is the price.** The four Крым
Оил rows are filled in on that basis, and `receipt-002`'s 43.820 L corroborates it
independently - a normal car fill, where the alternative reading demands 450 L.

The price *level* on those four is still extreme (АИ-95 at 205, diesel at 259,
АИ-100 at 450, against 71.25 at РН-Москва and 73.06 at Лукойл the same summer).
That reads as shortage pricing along one southern route, `receipt-006` (а/м "Дон",
АИ-92 at 195) included. It does not affect the reading - OCR is confidence 1.00 on
every one of those digits - but it is worth knowing before anyone treats the
corpus as a price reference.

`receipt-010` (Газпромнефть) leaves `unitPrice` empty for a different reason: the
fill has **two** unit prices, 62 L at 48.54 and 1 L at 48.52, against an undiscounted
`63.000 л X 69.11` line and a 1295.93 bonus discount. The 63 L and the 3058.00 paid
are certain; a single "the" unit price is not a thing this receipt has.
