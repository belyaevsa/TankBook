# RV.277 - a second Tallinn Airport parking ticket reads neither its total nor its currency

**Scenarios: J7b · the shop receipt (Expense mode), F1 · scan recognized nothing.** Reported by the
product owner 2026-09-13 with the photograph; the TestFlight build opened the expense form with no
amount and no currency. Owner's question: *can the same pattern as fill-up recognition be
applied?* - answer it in code.

**The fixture is already in place**: `Spike/ReceiptSpike/fixtures/expenses/parking-tallinn-airport-et-2.jpg`
(HEIC converted, auto-oriented, EXIF/ICC stripped). Ground truth, read from the paper by the
orchestrator: Tallinna Lennujaam AS, `SISSE 13.09.26 08:22`, `MAKSE 13.09.26 08:45`,
`Parkimistasu`, `TASU: 4.00 EUR`, `MAKSTUD: 4.00 EUR`, `NETO 3.23 EUR`, `KM 24% 0.77 EUR`.
Total **4.00**, currency **EUR**, date **2026-09-13**, kind **parking**. Do not derive the truth
from the extractor (`fixtures/README.md`'s oracle rule).

## Build

1. **Register** the folder's way: dump the Vision text with the harness (`--dump-text`, one line
   per box) to `parking-tallinn-airport-et-2.txt`, add its `expected.csv` row.
2. **Extend the expense ground truth**: `expected.csv` gains `total,currency,date` columns
   (blank where a hand-authored `.txt` has none; fill the ones whose lines carry an amount). The
   folder scores the kind only today - that is why this could not be measured. `README.md` says
   so.
3. **One finder, per-kind vocabulary**: route the expense read (`ExpensePrefill` /
   `ExpenseRecognition`, RV.62/RV.200/RV.246) through the FUEL path's total finder and
   `CurrencyDetection` rather than a second implementation; add the expense total words the corpus
   shows - Estonian `TASU`, `MAKSTUD`, `SUMMA`, `KOKKU`, and whatever the RU/EN hand fixtures print
   (`ИТОГО`, `К ОПЛАТЕ`, `TOTAL`, `PAID`) - and say which marker wins when two amounts agree
   (`TASU` = `MAKSTUD` here) and when they differ (`NETO` is never the total). Check why the
   currency did not reach the form: `EUR` after the amount is exactly `CurrencyDetection`'s
   explicit-marker tier, so the miss is either the total's (no amount → no currency) or the
   pre-fill boundary's rule (RV.200: the amount is offered only when the currency is nil or the
   car's home) - find which and say.
4. `docs/EXTRACTION.md`: the expense read's fields and the shared finder; `HIGH-WATER.md`: a
   ratchet line for the expense folder (cells asserted / resolved).

## Tests

- **L1 over the new dump, FAILS TODAY**: total 4.00, currency EUR, date 2026-09-13, kind parking.
- **L1**: the first Tallinn ticket still reads 2.00 EUR and parking; the hand-authored fixtures
  with totals pass their new columns.
- The whole-class check: no expense fixture resolves a total its `expected.csv` contradicts.
- `swift test` in full (package); the fuel corpus ratchet (255/300) must not move down.

## Mutation - named

Drop `TASU` from the vocabulary; the new fixture's total L1 goes red (and, if `MAKSTUD` alone
still resolves it, say so - that is the agreement rule at work). Verbatim, with the expense
folder's before/after numbers.
