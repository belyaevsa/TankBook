# Expense-kind OCR fixtures (RV.200, extended RV.277, photo-input RV.278)

The `receipts/`, `pump/`, `screenshots/` and `fiscal/` folders score the fuel
pipeline over **photographs**. This folder exists because the corpus held
**zero non-fuel receipts** when RV.200 was filed: the receipt images are all
fuel (or mixed fuel + one non-fuel line) and the pump displays are fuel by
definition, so a vocabulary that reads the KIND of an expense had nothing real
to be measured against. Ten fixtures are hand-authored **OCR-text**, not
photographs - the input is the lines a receipt of that kind prints, and the
ground truth is the file NAME plus `expected.csv`, written by hand, never by
running the extractor.

**Which file is the input depends on whether a photograph exists (RV.278):**

- **A `.txt` with no image beside it is hand-authored** and is the extractor's
  INPUT by construction. There is no photograph to read.
- **A `.jpg` or `.png` is the INPUT**, and the sweep OCRs it through Vision at test time -
  the same `VisionTextRecognizer` the fuel classes use. The `.txt` beside it is
  the **Vision dump**, kept for debugging and compared with the fresh OCR: a
  difference is reported as **drift** (the OCR changed under the fixture) and is
  never scored. Regenerate a drifted dump with
  `swift run ReceiptSpike fixtures/expenses --dump-text`.

The oracle rule in `../README.md` still holds: scoring a vocabulary against the
values the extractor produced measures nothing.

**Three photographs have arrived.** The first, `parking-tallinn-airport-et.jpg`,
is a Tallinn Airport (Tallinna Lennujaam AS) car-park ticket, 10/09/2026, 20
minutes, `PARKIMISTEENUS 2.00 EUR`, KM 24%. The second,
`parking-tallinn-airport-et-2.jpg`, is the same car park on 13/09/2026, whose
paper prints `TASU: 4.00 EUR` / `MAKSTUD: 4.00 EUR` and names no fuel-receipt
total word - the fixture that taught the shared finder the expense vocabulary
(RV.277). Their `.txt` files are the Vision dumps (the `--dump-text` shape, one
line per recognised box) and their `.jpg` files are the scored input. The first
is also the first fixture that named its kind **only in Estonian** -
`PARKIMISTEENUS` (parking service) and `Lennujaam parkla` (airport car park) -
which the RU/EN vocabulary abstained on until the two Estonian stems
(`PARKIMI`, `PARKLA`) were added. Converted from HEIC to full-resolution JPEG
with EXIF and ICC stripped before commit.

The third, `parking-snabb-tallinn-et.png`, is the class's first invoice-shaped
document: Snabb OÜ invoice C2654962727, 14.09.2026. Its two rows are parking
`4,00` and service fee `0,39`; the expense truth is the paid grand total
`Kokku maksudega / Tasutud 4,39 EUR`, never the `0,00 EUR` balance due or the
parking row alone. It is also the first Estonian-only invoice vocabulary
(`PARKING`, `Sõiduki numbrimärk`, `TASUTUD`). Vision's committed 67-line dump
is `parking-snabb-tallinn-et.txt`. The production extractor scores 4/4 and moves
the class 29/29 -> 33/33; the diagnostic Spike parser commits VAT `0,08` as the
total, so its separate sweep is 32/33 and `recognised.csv` records that finding.

Since RV.277 the folder is a **scored corpus class**, ratcheted by
`AccuracyRatchetTests` against `../high-water.json`'s `expenses` entry, over
four asserted cells: the kind, `total`, `currency` and `date`. The first score
is **29/29**.

## The loop

```
drop the photo in                 e.g. parking-tallinn-airport-et-2.jpg
swift run ReceiptSpike fixtures/expenses --dump-text
                                  reads the new photo through Vision, prints its
                                  raw OCR and writes its .txt dump beside it
hand-write the expected.csv row   the truth, from the paper, never the extractor
swift test --filter AccuracyRatchet
                                  the gate holds the class at its high-water mark
                                  and fails if a committed dump no longer matches
                                  a fresh OCR (drift)
```

Every run also writes `recognised.csv` beside `expected.csv`: one row per
fixture with what the extractor produced (total, currency, date, kind). It is
committed so a recognition change shows as a diff in review, and it is **never
the oracle** - `expected.csv` stays hand-written from the paper.

```
expenses/
  expected.csv     filename,category,total,currency,date - the ground truth
  recognised.csv   what the extractor produced - a review artefact, never the oracle
  *.jpg            the photograph, and the scored INPUT where one exists
  *.txt            the Vision dump of the .jpg, or a hand-authored fixture with no photo
```

`category` is a stable code, not a localised label:

| code | `ExpenseCategory` |
|---|---|
| `parking` | `.parking` |
| `toll` | `.toll` |
| `fine` | `.fine` |
| `insurance` | `.insurance` |
| `tax` | `.tax` |
| `parts` | `.parts` |
| `accessory` | `.accessory` |
| `other:wash` | `.other("wash")` - the escape hatch, not a forced case |
| `none` | `nil` - the vocabulary abstains and the form keeps its default |

`total`, `currency` and `date` are blank where the document does not state them;
a blank cell is skipped, never guessed. A `none` category is an assertion (the
vocabulary must abstain) and is scored, unlike a blank cell. A `none` fixture is
as load-bearing as the rest: a vocabulary that always answers is a vocabulary
that guesses.

## Added 2026-09-21 (three Russian parts / accessory documents)

- `accessory-gorunov-roof-rack-invoice-ru.jpg` - a `Расходная накладная` (delivery note) from ИП
  Горюнов, 09.07.2022: four LUX roof-rack lines (adapters, base kit, aero bars, lock set) totalling
  `11 850.00 руб.`, in a plastic sleeve under a window reflection, a blue stamp over the signature.
  Truth `accessory` / 11850.00 / RUB / 2022-07-09. The vocabulary has no roof-rack stem (`ДУГ`,
  `БАГАЖ`, `АДАПТЕР`) and the invoice prints its total as `Всего :` / `На сумму :`, neither a
  receipt total word - the diagnostic sweep abstains on both, which is the finding.
- `parts-ponyatov-bosch-plugs-lecar-grease-ru.jpg` - a fiscal receipt from ИП Понятов
  (Краснотурьинск), 09.09.26: `Смазка для суппортов "LECAR" 1 x 145.00` and `Свеча зажигания
  Bosch 0241135520 4 x 595.00`, ИТОГ 2525.00, НДС 5%, laid on denim with a screwdriver across it.
  **No currency printed** - the cell is blank. Truth `parts` / 2525.00 / - / 2026-09-09.
- `parts-akhmadullin-kumho-tires-invoice-ru.jpg` - a `Расходная накладная` from ИП Ахмадуллин
  (Tyumen), 09.09.2026: `Автошина Kumho Ecsta PS71 285/45 R20 112Y 4 x 21 900,00 = 87 600,00`
  and six zero-priced fitting lines (weights, disassembly/balancing, removal, and
  `Технологическая мойка колеса`), the fiscal slip stapled on top at a right angle. Truth `parts` /
  87600.00 / RUB / 2026-09-09 - tyres have no category of their own on the expense form
  (`TireSet` is the entity), so `parts` is what a user would pick. Two findings: the **wash rule
  runs first** and reads the wheel-wash line as `other:wash`, and the total is printed with a
  **space thousands separator** (`87 600,00`) after `Итого:`.

Their `.txt` files are Vision dumps taken on macOS 27 (the measured runtime is 26 - the first
26 run regenerates them if they drift). Class cells: 33 → 44, totals only; hits stand.

Three more parts documents the same day:

- `parts-avtozapchasti-mobiletron-filters-act-ru.jpg` - an `Акт сверки № 90065` from ООО
  "Автомобильные запчасти" dated **in words** (`10 августа 2023 19:08:20`): two filter lines (air
  751, oil 1 015), `Итого: 1 766,00`, `В том числе НДС: 294,34`, the buyer's name and phone
  blacked out on the paper. Truth `parts` / 1766.00 / RUB / 2023-08-10. Findings: the diagnostic
  sweep commits the VAT as the total and misses the worded date.
- `parts-avtostart-vologda-28-lines-tovarny-chek-ru.jpg` - a `Товарный чек № 00000001660` from
  ООО "Авто-старт" (Вологда), 31 марта 2026: **28 lines** (a battery, wipers, oils, a timing belt
  kit, a water pump, filters, seals, bolts), `Итого: 73 147,30`, a warranty text block at the
  foot. Truth `parts` / 73147.30 / RUB / 2026-03-31. Finding: the kind reads as `toll` - the
  boilerplate's `БЕСПЛАТНЫЙ` contains the toll stem `ПЛАТН` (RV.301's second declared miss).
- `parts-vag-invoice-page-two-screenshot-ru.jpg` - a **screenshot of the second page** of a
  VAG parts invoice (lines 9-28: DSG oil, a timing kit with a discount column, a water pump,
  filters, brake fluid), `Итого: 4 152,00 | 108 173,00`, then `Сумма документа: 159 373,00` and
  `В том числе скидка: 4 152,00`. The document total is the truth; no date, no currency word on
  the page - both blank. Truth `parts` / 159373.00 / - / -. Finding: the sweep commits the
  discount as the total.

Class cells: 44 → 54 (four + four + two), totals only.
