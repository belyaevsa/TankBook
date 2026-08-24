# Receipt photos (the L5 accuracy gate corpus)

Photos of paper receipts - the class the accuracy gate scores (`docs/TESTING.md`,
`docs/PHASES.md` → P2). Ground truth in `expected.csv`; `*.qr.txt` holds the
fiscal QR payload where the photo's QR decoded, so a P2.6 QR-parser test has real
input without re-decoding an image.

## Baseline, 2026-08-25: 25/68 fields (36.8%), cross-check 9/25

Measured with `swift run ReceiptSpike fixtures/receipts`. Before this batch the
corpus was **one** photo scoring 3/3, which is arithmetic rather than a gate. The
number dropped because the corpus finally has breadth - 15 receipts across 16
files, 12 brands, 5 years, Cyrillic throughout, two VAT rates, four fuel kinds
including LPG.

**P2.2 ported the parser into `TankbookCore` and fixed the failures below: the
receipts class now scores 29/47 (61.7%).** The 18 remaining misses are all the
same honest answer - the unmarked `цена*количество` receipts where the ladder
(`docs/SCHEMA.md` -> Fuel price bands, steps 1/2/5) leaves litres and price nil
rather than guess. The total-finder, the swap ladder and the fuel-kind mapping
are fixed; see the notes at the end of each failure below.

Split by field, which is more useful than the headline:

| | correct |
|---|---|
| **total** | 11 / 16 |
| **litres + unit price** | 3 / 16 receipts fully right (001, 003, 016) |
| extracted litres/price at all | 6 / 16, and **2 of those 6 are swapped** |
| fuel kind normalised to the SCHEMA vocabulary | 0 / 16 |

**Provenance is no longer uniform.** `receipt-017` and `receipt-019` through
`receipt-022` were **not photographed by the maintainer** - they come from public
web sources (oil-club.ru, otzovik.com, drive-data.ru). They are kept because they
add years the corpus lacked (2018, 2020, 2024), the `СКИДКА` discount mechanism,
and a second `АИ-100` data point. `receipt-019/020/021` carry **totals only**,
taken from their fiscal QR, which is authoritative; their litres and unit price
are deliberately blank because nobody has read the line items yet. Anyone adding
those values should read the photo, not infer them.

**A note on the falling headline.** The percentage keeps dropping as the corpus
grows - 38.3% over 16 files, 32.2% over 22 - because new fixtures arrive faster
than the parser learns them, and several carry blank ground truth that can never
be scored as a hit. **This is the corpus working, not the parser regressing.** The
ratchet deliberately guards absolute hits rather than the percentage for exactly
this reason (`../HIGH-WATER.md`).

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

### 5. The second mixed receipt, and it is mixed a different way

`receipt-025` (Татнефть, МКАД 38км, 20.03.19) is the corpus's **second** mixed
fixture, and it breaks two assumptions `receipt-009` alone would have baked in:

```
Услуга по регистрации покупки
  69.28 X 1                         =69.28 РУБ
ТРК-2 АИ-95-К5
  43.38 X 38.28                   =1660.59 РУБ
ИТОГ:                             =1729.87 РУБ
```

- **The non-fuel line is a SERVICE, not a product.** `receipt-009`'s extra line
  was a bottle of water; this one is a purchase-registration fee. A detector
  keyed on "is this aa product name" misses it.
- **It comes BEFORE the fuel line.** On `receipt-009` the water follows the fuel.
  Position is not a signal.

The fill-up amount is the **fuel line, 1660.59**, never the 1729.87 grand total
(hard rule 4) - and the QR agrees with the grand total (`s=1729.87`), so the QR
cross-check classifies it `suggestsMixedReceipt` exactly as designed.

It is also the corpus's **hardest swap case**. The operands are `43.38 X 38.28` -
both two decimals, both the same order of magnitude, no unit marker. Neither
decimal count nor position resolves it. Only a price prior does: Moscow АИ-95 in
March 2019 was about 43.4 ₽/L, so 43.38 is the price and 38.28 the volume. Get it
backwards and you store a 43 L fill as 38 L at the wrong price, and the
cross-check still passes because `a x b == b x a`.

### 6. A third way for ИТОГ to differ from the line extension: СКИДКА

`receipt-017` (Татнефть, 24.06.20) prints `48.09 X 20 = 961.80`, then a
**`СКИДКА =-0.80 РУБ`** line, then `961.00` - and the QR agrees at `s=961.00`.

That is now **three unrelated mechanisms** by which a fuel-only receipt's grand
total legitimately differs from its own line extension:

| chain | mechanism | example |
|---|---|---|
| ЛУКОЙЛ | `ОКРУГЛЕНИЕ` - rounds down to the whole rouble | 1680.38 → 1680.00 |
| Татнефть | `СКИДКА` - an explicit discount line | 961.80 → 961.00 |
| Газпромнефть | bonus-points redemption | 4353.93 → 3058.00 |

Two of the three are under 1 ₽ and one is 1295.93, so **the size of the gap tells
you nothing about its cause**. A parser must find the *labelled* total rather than
infer it, and must not treat a mismatch as a parse failure.

It is also the fixture that most cleanly **confirms the price-first reading of the
unmarked format**. `48.09 X 20` has the same shape as Крым Оил's `205.00*20` - no
`л`, no `руб`, no labelled column. Price-first gives 20 L of diesel at 48.09 ₽/L
in June 2020, which is the correct Russian diesel price for that month;
quantity-first gives 48.09 L at 20.00 ₽/L, which is below cost. Independent
confirmation from a different chain, six years earlier, on a historically
checkable price.

Two smaller things it carries: **20% VAT** (the pre-2026 rate - the corpus now has
both 20% and 22%), and a **fuel grade in the product name**, `ДТ-Е-К5 Танеко` -
diesel with the marketing tier `Танеко`, which belongs in `fuelGrade`, not
`fuelKind` (`docs/SCHEMA.md`).

**Provenance:** unlike every other fixture, this photo is **not the maintainer's
own receipt** - it was published on the oil-club.ru forum. Kept because it adds a
2020 price point and the СКИДКА mechanism, but flagged here so the corpus's
provenance is not assumed uniform.

### 7. Non-fiscal receipts exist, and they have no QR at all

`receipt-016` is a **НЕФИСКАЛЬНЫЙ ОТЧЁТ** - a corporate fuel-card order receipt
(РН-Карт) from АО "РН-Москва". It prints a fiscal `ФН`, but it is explicitly a
non-fiscal report and **carries no QR code**. `docs/JOURNEYS.md` J5 assumes a
fiscal QR; fuel-card purchases simply do not have one, so they fall to the OCR
path with no exact-fill shortcut available. Worth knowing before J5's "scan the
QR, done" is treated as covering every Russian fill.

`receipt-023` (АО "РН-Тверь", 23.08.26) is the second of the class and adds a
layout the corpus did not have: **labelled columns where the unit price is not on
the item line at all.**

```
Товар        единиц      СУММА
АИ-95         20.00     1366.00
Итого                   1366.00
---------Справочная информация---------
Цена за ед.                 68.30
```

The line carries quantity and sum; the price lives in a separate "reference
information" block below the total. A parser that expects `price x quantity` on
one line finds only two of the three numbers, and the third is further from the
item than the grand total is. It also has **no QR**, being a fuel-card slip, so
the anchor cannot supply the total either.

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

### 8. Fuel kind is not normalised

The parser emits `100`, `95`, `АИ-92`, `ДТ` and `98` as raw strings. `docs/SCHEMA.md`
defines the FuelKind vocabulary; nothing maps `ДТ`/`Диз.топл.`/`ДТ-Л-К5` → diesel
or `АИ-92-К5` → petrol92. LPG (`СУГ`, `receipt-012`) is not recognised at all.

**Fixed in P2.2.** `FuelKind` gained `petrol92` and `petrol100` - the vocabulary
was missing the two most common Russian petrol grades, which this corpus exposes
(`receipt-006` is АИ-92, `receipt-002`/`receipt-007` are АИ-100). The normaliser
maps `ДТ`/`Диз.топл.`/`ДТ-Л-К5` → diesel, `СУГ` → LPG, `АИ-NN-К5` → the matching
petrol grade, and is anchored to the product line so `АЗС-98`/`ТРК №3` never name
a grade. On a pump display no fuel kind is attempted at all (grades there are
every nozzle's, not this fill's).

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

This adds a case the ladder has to name: a **`без скидки` line prints the list
price, not the price paid.** `63.000 л X 69.11` is marked "без скидки", so 69.11
is the pre-discount price and 63 × 69.11 = 4353.93 is the pre-discount extension,
not the fuel amount - the 3058.00 paid is the fiscal total minus the 1295.93 bonus
discount. The ported parser therefore reads the volume (63.000) from that line but
returns `unitPrice = nil` and the grand total when it sees "скидка", treating the
list price as a suggestion the user may correct, never a fact (hard rule 13).
