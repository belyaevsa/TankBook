# RV.301 - the expense total finder reads Russian invoice totals

## Where you may write
Only inside `/Users/sbelyaev/repos/fuel-counter-ios-wt-rv301` (a git worktree on branch `wt/rv301`).
Write code first, explore second. Do not commit.

## The defect (cause pinned; confirm before you change anything - this diagnosis is a hypothesis)
`FuelExtractor().extract(lines:)` resolves the TOTAL of three Russian invoices wrongly or not at all:
- `Spike/ReceiptSpike/fixtures/expenses/accessory-gorunov-roof-rack-invoice-ru.txt`: prints
  `На сумму : 11 850.00 руб.` (line 42) and `11 850.00 руб.` (line 40); `expected.csv` says 11850.00.
- `parts-akhmadullin-kumho-tires-invoice-ru.txt`: `87 600,00` (lines 13, 42) and
  `Всего наименований 7, на сумму 87600 руб` (line 44); expected 87600.00.
- `parts-vag-invoice-page-two-screenshot-ru.txt`: `Итого:` (line 108) is followed by three column
  values `4 152,00` / `108 173,00` / `159 373,00` and then `Сумма документа:` (line 112); expected
  159373.00. Since RV.305 this fixture ABSTAINS on its total (the two labels tie and the most-printed
  fallback is guarded) - that abstention must stay unless the new rule reads 159 373.00.
The label vocabulary is `TotalLabel` in `ios/Sources/TankbookCore/Extraction/FuelExtractor.swift:656-700`
(`primary`: ИТОГ, ВСЕГО, К ОПЛАТЕ, TOTAL, KOKKU, SUMMA, СУММА, AMOUNT, TASU, MAKSTUD, PAID, ШТРАФ). The
pairing is `FuelExtractorTotalFinder.pairedValue(forLabelAt:in:)` and the resolution
`grandTotalRead` (`ios/Sources/TankbookCore/Extraction/FuelExtractorTotalFinder.swift`). Known
suspects: `На сумму` is not a label (`СУММА` needs the Cyrillic word as a substring - check the
case/spacing of `сумму`); `Всего наименований 7, на сумму 87600 руб` carries the value ON the label
line in a no-decimal form; `Сумма документа` should outrank a column-laid `Итого` (a document total
over a column sum) - that ranking is the decision this row records.

## What to build
Teach the total finder these invoice totals with the narrowest rule that reads all three, and record
the label-ranking decision (`Сумма документа` / `На сумму` over a column `Итого`) in a code comment and
in `docs/EXTRACTION.md` (the expense-total section). **Out of scope:** expense categories (RV.304 did
them), fuel receipts' totals beyond keeping them unchanged, PU.* pump rows.

## Docs to read
`docs/EXTRACTION.md` (the expense total finder, RV.277/RV.305 notes), `docs/TASKS.md` rows RV.301,
RV.305 and RV.277, `Spike/ReceiptSpike/fixtures/expenses/README.md`.

## Checks - by exit code, from the worktree root
1. `cd ios && swift build --build-tests` - 0.
2. `swiftlint lint --quiet` from the worktree ROOT - 0 errors.
3. `cd ios && swift test --filter "RV277|RV56|Expense|TotalFinder|FuelExtractor|Corpus"` - report the
   count; `RV277ExpenseTotalTests` must pass with no contradiction, and every receipt/fuel ratchet in
   that filter must stay green (a fuel total that moves is a regression).
4. The full `cd ios && swift test` - report the count and every failure; the only acceptable failures
   are ones you can show also fail on `HEAD` without your change (run them there to prove it).

## Tests you must add
- Each of the three fixtures resolves its expected total (oracle: `expected.csv` and the printed line
  quoted above).
- The mutation that must go red: remove your new label (or ranking) rule - the test for the fixture it
  serves must fail. Run it, paste the red output, restore.

## Vacuous traps
A label so broad it catches line-item columns (`Сумма` as a column header on the VAG page reads 650 -
RV.305's case); a rule that fixes the VAG page by picking the largest number on the page; moving a
fuel receipt's total.

## Report back
Exit codes and counts of every check; the mutation's red output verbatim; the diff summary; anything
you found and did not fix.
