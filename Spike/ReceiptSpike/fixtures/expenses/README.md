# Expense-kind OCR fixtures (RV.200)

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

**The first photograph arrived 2026-09-11**: `parking-tallinn-airport-et.jpg`,
a Tallinn Airport (Tallinna Lennujaam AS) car-park ticket, 10/09/2026, 20
minutes, `PARKIMISTEENUS 2.00 EUR`, KM 24%. Its `.txt` is the **Vision dump**
of that photo (the `--dump-text` shape, one line per recognised box), so the
sweep reads exactly what the app's OCR produced rather than what a human
would type. It is the corpus's first non-fuel receipt and the first one that
names its kind **only in Estonian** - `PARKIMISTEENUS` (parking service) and
`Lennujaam parkla` (airport car park). The vocabulary abstained on it until
the two Estonian stems (`PARKIMI`, `PARKLA`) were added in the same change,
which is the folder doing its job: a fixture that does not move the vocabulary
was not worth adding. Converted from HEIC to full-resolution JPEG with EXIF and
ICC stripped before commit.

Add the next real photograph the same way - the `.jpg` beside a `.txt` holding
its OCR dump, one `expected.csv` row for the `.txt` - and this folder becomes
the same kind of corpus as `receipts/`.

```
expenses/
  expected.csv     filename,category - the ground truth, from the file name
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

A `none` fixture is as load-bearing as the rest: a vocabulary that always
answers is a vocabulary that guesses.
