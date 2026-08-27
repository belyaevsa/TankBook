# My Fuel Manager export – the real fixture (P5.4)

A genuine My Fuel Manager export, supplied by the product owner 2026-08-27. It is what
`docs/SCHEMA.md` → Import mapping meant by *"schema TBD from real export"*: the schema is no
longer TBD, and it is written below from the file rather than guessed.

**What was changed before committing, and what was not.** Four real registration numbers were
replaced with placeholders (`AA000AA`, `BB111BB`, `CC222CC`, `DD333DD`), and **`trips.csv` was
removed entirely** – there is no `Trip` entity in `docs/SCHEMA.md`, the importer never reads it,
and it carried 19 dated city-to-city movements with exact timestamps. **Nothing else was touched.**
In particular the odometer defect below is deliberately preserved, and so are all 260 notes,
because both are things the importer has to survive.

## The files

| file | rows | maps to |
|---|---|---|
| `vehicles.csv` | 5 | `Vehicle` |
| `fuel.csv` | 513 | `FillUp` |
| `costs.csv` | 262 | `ServiceRecord` / `Expense` |
| `incomes.csv` | 0 | nothing – income is out of scope in v1 |
| `reminders.csv` | 0 | `Reminder` |

Each file uploads **separately** (the product owner's note), so the importer takes one file at a
time and must work with `fuel.csv` alone – vehicle metadata is not guaranteed to be present.

## Five things about this format that a parser gets wrong on the first try

1. **The header is on line 2, not line 1.** Line 1 is a title: `My Fuel Manager - Fuel`. A
   standard CSV reader takes it as the header and produces one column.
2. **The delimiter is `;`, not `,`.** With a comma reader every row is a single field.
3. **Dates are `M/D/YYYY`** – `8/24/2026`. Ambiguous against `D/M/YYYY` for any day ≤ 12, and this
   file contains such dates. This is exactly the F6 "ask once per file" ambiguity, and guessing it
   silently shifts a year of history by up to eleven months.
4. **There is no unit-price column.** `fuel.csv` carries `Fillup volume` and `Total price` only, so
   price per litre is *derived*. Anything asserting a printed unit price will find nothing.
5. **`Fuel` and the vehicle's fuel field are codes, not names** – `1`, `2`, and `00100003` on the
   vehicle. They are a bitmask/enumeration, not free text, and they do not map to `FuelKind` by
   string comparison.

Also: `Tank status after fillup` is `F` or `P` (full / partial) with a separate `%` column, which is
what `docs/SCHEMA.md` means by *`Tank status after fillup` → `tankLevelAfterPct`* and the full-tank
flag; `Currency` reads `USD` on every row regardless of where the fuel was actually bought, so it is
a default the user must be able to correct (hard rule 13, and the F6 currency question).

## The odometer defect – keep it

`fuel.csv` holds two Volvo rows whose odometer is not on the car's timeline:

```
4/14/2025   odometer 9        68 L    97.85     <- the defect
            odometer 11436    ...               <- and this one
            the rest of that car runs 71 449 -> 121 727
```

An importer that takes the odometer span naively computes **121 718 km** for 4 146 L and reports
**3.4 L/100km for a Volvo**, which is impossible. This is the single most valuable row in the file:
it is a real user's real typo, and it is exactly what the import preview's derived-consumption
figure exists to catch (`docs/JOURNEYS.md` F6a – *"Does that look like your car?"*).

**Do not clean it, and do not special-case it.** A fixture that only contains well-formed rows
measures a problem the app does not have.

## The acceptance number

`docs/TASKS.md` P5.4 asserts the real export reproduces **8.222 L/100km**. Note that this is **not**
total-volume-over-odometer-span: that naive figure is 8.241 for the LADA and nonsense for the two
cars with the odometer defect. 8.222 is what the **consumption engine** produces – rolling 90 days,
floor 3, full-tank segments only (`docs/SCHEMA.md` → consumption). The test must run the engine, not
arithmetic, which is the point: it asserts the import lands data the engine reads correctly, not
that a CSV was read.

## The parse output fixture

`parsed.json` in this directory is the **server's** parse of `fuel.csv` (the wire envelope of
`POST /import/parse`: `importId` is a fixed placeholder, `format`, `scope`, `candidates`,
`unparsed`, `ambiguities`). It is committed so the iOS side can assert the engine's 8.222 against
the candidates **offline**, the way the receipt corpus scores without a model call – it must not be
hand-edited, only regenerated from the parser. The other files' parse outputs are not committed;
the server tests drive the real files directly.
