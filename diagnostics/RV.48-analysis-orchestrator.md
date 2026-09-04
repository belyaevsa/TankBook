# RV.48 - my own reading of the receipt corpus, written before the agents reported

Baseline, measured live this morning on the 46-receipt corpus (`diagnostics/receipt-field-report.txt`):

    receipts 101/210
    misses: unitPrice=34  liters=30  currency=28  fuelKind=10  total=7

## 1. The abstentions dominate, and they are one code path

**26 of the 30 litre misses are `got nil`** - the ladder reached step 5. All 26 have a printed
operand pair in the OCR dump. They die in `FuelExtractor.resolveUnmarked`, whose first line is

    guard let provider = bandProvider else { return (nil, nil) }

and **nothing in the app or the corpus scorer ever injects a provider**. `FuelPriceBandProvider`
is a declared seam with no implementation (P5 work). So steps 3 (user price history) and 4 (curated
band) of the documented ladder are dead code today, and `HIGH-WATER.md` already says these two
steps are the sanctioned way to raise this number.

Two further defects in the same path:

- `extract()` computes `result.date` and then calls `resolveVolumeAndPrice(..., date: nil)`, so the
  band could not be era-keyed even if one existed. The corpus spans 2018-2026 with RUB prices from
  43.38 to 450.00 per litre - era is not a detail here.
- The corpus scorer builds a bare `FuelExtractor()`, so whatever the app injects, the measured
  number would still be the unfed parser. Scoring must follow the app (the same argument the
  `source: .pump` comment already makes).

## 2. What a band can and cannot do - simulated on the real pairs

Taking the widest RUB band the corpus forces (it must contain every real RU price, 43.38 to 450.00,
so roughly `[43, 500]`) and applying the existing "exactly one operand in band" rule:

- **resolves correctly**: 003, 004, 005, 014, 015, 017, 024, 026, 027, 028, 030, 031, 032, 035,
  037, 043, 044 - the fills whose volume is under 43 L, so only the price is in band.
- **still abstains** (both operands in band): 002, 007, 008, 018, 040, 041 - e.g. `43.61 X 99.40`
  and `48.89 X 48.80`, which is correct behaviour, not a failure.
- **would be WRONG with a currency-only band**: `receipt-012`, `52.15 X 23.99` - LPG at 23.99
  RUB/L is *below* a petrol band, so the band picks 52.15 as the price. The fix is that the band
  must be keyed by **fuel kind** as well (the LPG band contains both operands -> abstain), which is
  what `FuelPriceBandProvider.band(currency:fuelKind:date:)` already promises.

So a fuel-kind- and era-keyed band is worth roughly **+17 litres and +17 prices**, and its failure
mode is an abstention rather than a swap - provided the LPG case is honoured. A currency-only band
is not safe.

## 3. Currency - 28 misses, all RUB, and the evidence is unambiguous

`CurrencyDetection` has exactly two tiers: an explicit marker, then a **Kazakhstan** document
evidence gate (P2.10). There is no Russian one, and most Russian receipts never print a currency
word Vision reads.

Token sweep over the dump, by expected currency:

- `ККТ` (the cash-register acronym) appears on **28 RUB fixtures and on zero EUR or KZT ones**.
- `ИНН` appears on 33 RUB fixtures and no EUR one; `receipt-033` (the Kazakh receipt) carries
  `КГД`, `ККС`, `ЖИЫНЫ`, `KOFD` and no `ИНН`/`ККТ`, so the existing KZ gate keeps winning if it
  stays ordered first.
- The five Estonian receipts carry none of these tokens at all.

A Russian fiscal cash-register receipt is denominated in roubles as a matter of law, so this is
document evidence in exactly the sense the KZT gate already uses - not a guess from magnitude.
Only `receipt-035` (`ИТОГ` alone) and `receipt-041` (no fiscal tokens at all) stay unresolved.

Expected: **+26 currency cells**, and it is also the precondition for the band, which is keyed by
currency.

## 4. Fuel kind - 10 misses, 4 of them one vocabulary entry

- `D B0 miles` on the four Estonian Circle K receipts (001, 042, 045, 046) is a loyalty grade name
  the normaliser does not map to diesel. The corpus README has been saying this for three fixtures.
- `receipt-044` returns **`lpg` for an AI-95 fill**, and the reason is boilerplate: the slip prints
  `1 ед.=1 литр для нефтепродуктов/суг`, and `суг` is matched as LPG. Its actual product line reads
  `AM-95` - Vision read `АИ` as Latin `AM`. Both halves are the cleaning problem: a fuel kind must
  come from the product line, never from a legal footnote.

## 5. The cleaning stage, and the two numbers that prove it is needed

    receipt-023  liters: want 20.000  got 32986034.000
    receipt-046  liters: want 55.800  got 10180925.000

`10180925` is `Reg.kood 10180925` on the Estonian receipt. The parser turned a merchant
registration number into a volume in litres. That is the product owner's complaint stated as a
defect: unfiltered id lines are not just noise in the viewer, they are candidate operands.

## 6. Order of work implied by the above

1. Cleaning/classification of lines (kills the two confident-wrong volumes and the `суг` fuel kind).
2. RUB document-evidence gate (+26, and unlocks the band, which is currency-keyed).
3. Feed the ladder: a curated fuel-kind- and era-keyed band pack plus the user's own price history,
   injected in the app **and** in the corpus scorer; pass the parsed date through (+~34).
4. Fuel-kind vocabulary (`D B0`, `AM-95`) (+5).
5. RV.48 proper: persist the assignment on `Attachment`, show meaning in the viewer, decide the
   raw-text trim question.
