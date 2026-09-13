# RV.282 - a discount line is committed as the unit price (receipt-066)

**Scenarios: J3 · the 5-second fill-up (the pre-fill is a default input), F2 · scan recognised
WRONG data.** `[!]`. Found 2026-09-13 by registering the owner's Circle K Järvevana receipt
(`CORPUS-2026-09-13b`): `receipt-066` commits **`unitPrice = 0.96`** - the `EXTRA SOODUS -0,96 EUR`
discount - where the paper prints `Hind 2,024 EUR/L` and its paired display (`pump-100`) shows
`2.024`. `64.04 x 2.024 = 129.62` closes exactly; `64.04 x 0.96` does not. A confident-wrong
unit price is hard rule 13's exact concern (a wrong fact is worse than none), and the ratchet
scores it as a plain miss - the asymmetry `RV.270` closed for `fuelKind`, open again for money.

## The cause, pinned

Vision splits the fuel block into one-token lines (the dump, `swift run ReceiptSpike --dump-text`):

```
4 Hind
2,024
EXTRA SOODUS
EUR/L
-0,96 EUR
KOKKU
```

- `FuelExtractorLabelValue.pricePerUnitValue(forLabelAt:in:)`
  (`ios/Sources/TankbookCore/Extraction/FuelExtractorLabelValue.swift:14-40`): the label is the
  bare `EUR/L` fragment; the inline form finds no value on it; the fallback "pump form" takes
  the **nearest value line below** (`distance > 0, distance < 0.02`) - `-0,96 EUR` - and
  `NumberScanner.value` **silently drops the sign** (by design, for the discount-magnitude path),
  so `0.96` is returned as the price. The true value `2,024` sits **above** the label, which
  that branch excludes by construction ("never above it, where the row's sum lives").
- `FuelExtractorTotalFinder.isSubtractionLine(_:)` (`FuelExtractorTotalFinder.swift:79-86`)
  already names the rule - a `-`-prefixed value line is a subtraction, never a candidate - and
  the total finder consults it; the unit-price path does not. **Sibling shape**
  (`docs/DEFECT-PATTERNS.md`): one predicate, consulted by one of two callers.
- Nothing downstream rejects the price: `FuelExtractor` (`:57-75`) assigns it, and the
  cross-check (`ExtractionCrossCheck.evaluate`, `CrossCheck.swift:43`) reports the product
  mismatch but does not clear a unit price that contradicts a known litres x total.

**This brief's diagnosis is a hypothesis - confirm it on the dump before you change anything.**
`receipt-038` (Circle K Sikupilli, `Hind 1,754 EUR/L` on ONE line) resolves through the inline
form and must keep doing so; `receipt-001` (the "pump form" the below-rule exists for) must keep
resolving too.

## Build

1. The pump-form branch of `pricePerUnitValue` skips a subtraction line - reuse
   `isSubtractionLine` (move it to a shared home, e.g. `NumberScanner`, so both callers use ONE
   predicate; leave a one-line doc on why the sign check lives outside `value(in:)`).
2. With the discount line skipped, `receipt-066`'s label has no value below within the window.
   Add the honest next step: when litres and total are both resolved and the label-value price
   is nil, **derive** the unit price only if a printed value on the document equals
   `total / liters` within the cross-check tolerance (here `2,024`, two lines above) - the
   document said it, the arithmetic confirms it. No printed match → `nil`, never a computed
   price (hard rule 13; `docs/EXTRACTION.md` "a wrong value is worse than a nil").
3. Belt and braces, the money sibling of RV.270: a resolved unit price that contradicts a
   resolved litres x total by more than the tolerance **and** is the magnitude of a printed
   discount line is dropped to nil before assembly. Say in `EXTRACTION.md` which of steps 2/3
   caught `receipt-066`.
4. `HIGH-WATER.md` / `receipts/README.md`: rewrite the `receipt-066` note from "recorded, not
   tuned" to what ships; `high-water.json` receipts hits rise by what the sweep says (263 → 264
   or 265 if the derived price lands); `CorpusCompressionTests.recordedReceipts` follows.

Out of scope: `fuelKind` on `D B0 miles` (the loyalty string, `receipt-001`/`064`/`066` - a
separate vocabulary decision, file it if you touch it); the spike CLI's own parser (the "Known
trap" in `HIGH-WATER.md`).

## Tests

- **L1, fails today**: `ios/Tests/TankbookCoreTests/RV282DiscountLineUnitPriceTests.swift` over
  the six-line dump above as `OCRLine`s with the real geometry (label below the price, discount
  below the label): the unit price is `2.024` (or nil - never `0.96`); a `receipt-038`-shaped
  inline line still returns `1.754`; a `receipt-001`-shaped pump form still returns the value
  below. **Oracle**: `receipt-066`'s paper and `pump-100`'s display both print `2,024`.
- The ratchet (`AccuracyRatchetTests`) green with the new mark; `receipt-038`, `-001`, `-064`
  unchanged in the sweep (name their rows in the report).

## Checks - by exit code

`scripts/gate.sh` from the repo ROOT (0; `swift test` count, app-target count); `cd
Spike/ReceiptSpike && swift test` 0; the receipts sweep line before → after.

## Mutation - named

Remove the subtraction-line skip from the pump-form branch; the L1's `receipt-066` case goes red
with `0.96`. Verbatim, then restore.

## Vacuous trap

Asserting the price is "not 0.96" while it is nil AND the derive step never ran; matching
`total / liters` against any number on the page without the printed-value requirement (that is
a computed price wearing a printed one's clothes).
