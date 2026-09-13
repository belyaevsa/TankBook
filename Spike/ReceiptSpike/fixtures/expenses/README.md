# Expense-kind OCR fixtures (RV.200, extended RV.277)

The `receipts/`, `pump/`, `screenshots/` and `fiscal/` folders score the fuel
pipeline over **photographs**. This folder exists because the corpus held
**zero non-fuel receipts** when RV.200 was filed: the receipt images are all
fuel (or mixed fuel + one non-fuel line) and the pump displays are fuel by
definition, so a vocabulary that reads the KIND of an expense had nothing real
to be measured against. Ten fixtures are hand-authored **OCR-text**, not
photographs - the input is the lines a receipt of that kind prints, and the
ground truth is the file NAME plus `expected.csv`, written by hand, never by
running the extractor.

They are the extractor's INPUT, exactly as an OCR dump is. The oracle rule in
`../README.md` still holds: scoring a vocabulary against the values the
extractor produced measures nothing.

**Two photographs have arrived.** The first, `parking-tallinn-airport-et.jpg`,
is a Tallinn Airport (Tallinna Lennujaam AS) car-park ticket, 10/09/2026, 20
minutes, `PARKIMISTEENUS 2.00 EUR`, KM 24%. The second,
`parking-tallinn-airport-et-2.jpg`, is the same car park on 13/09/2026, whose
paper prints `TASU: 4.00 EUR` / `MAKSTUD: 4.00 EUR` and names no fuel-receipt
total word - the fixture that taught the shared finder the expense vocabulary
(RV.277). Each `.txt` is the **Vision dump** of its photo (the `--dump-text`
shape, one line per recognised box), so the sweep reads exactly what the app's
OCR produced rather than what a human would type. The first is also the first
fixture that named its kind **only in Estonian** - `PARKIMISTEENUS` (parking
service) and `Lennujaam parkla` (airport car park) - which the RU/EN vocabulary
abstained on until the two Estonian stems (`PARKIMI`, `PARKLA`) were added.
Converted from HEIC to full-resolution JPEG with EXIF and ICC stripped before
commit.

Since RV.277 the folder is a **scored corpus class**, ratcheted by
`AccuracyRatchetTests` against `../high-water.json`'s `expenses` entry, over
four asserted cells: the kind, `total`, `currency` and `date`. The first score
is **29/29**.

## The loop

```
drop the photo in                 e.g. parking-tallinn-airport-et-2.jpg
swift run ReceiptSpike fixtures/expenses --dump-text
                                  reads the new photo through Vision and writes
                                  its .txt beside it (an existing .txt is kept)
hand-write the expected.csv row   the truth, from the paper, never the extractor
swift test --filter AccuracyRatchet
                                  the gate holds the class at its high-water mark
```

Every run also writes `recognised.csv` beside `expected.csv`: one row per
fixture with what the extractor produced (total, currency, date, kind). It is
committed so a recognition change shows as a diff in review, and it is **never
the oracle** - `expected.csv` stays hand-written from the paper.

```
expenses/
  expected.csv     filename,category,total,currency,date - the ground truth
  recognised.csv   what the extractor produced - a review artefact, never the oracle
  *.txt            one OCR line per line, the input the vocabulary reads
  *.jpg            the photograph a .txt of the same name was dumped from
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
