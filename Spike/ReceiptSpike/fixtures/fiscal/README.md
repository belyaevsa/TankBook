# Fiscal receipts (Russian ФНС / OFD)

**A different input class from `../receipts/`, and a different pipeline.** These
are the documents an OFD serves for a fiscal receipt - what the app gets after
scanning the fiscal QR (`docs/JOURNEYS.md` J5, `docs/TASKS.md` P2.6), not a photo
of paper.

**They do not all carry a text layer.** `fiscal-001` (ofd.ru) does, and
`pdftotext` reads it exactly. `fiscal-002` (ofd-ya.ru / ООО "Ярус") is
**image-only** - `pdftotext` returns 2 bytes - so it must be rendered and OCR'd
like a photo. Any enrichment path that assumes "OFD document -> text layer ->
exact fields" is wrong for at least one major OFD, and which one you get is not
knowable before fetching.

Keeping them here rather than in `../receipts/` matters: mixing them in would
inflate the image-OCR accuracy number with documents OCR never had to read.

## What is here

| File | Source |
|---|---|
| `fiscal-001-gpn-ru.pdf` | Газпромнефть, Moscow, 22.08.26 - petrol, RUB. **Has a text layer** |
| `fiscal-001-gpn-ru.txt` | `pdftotext` output, committed so a parser test needs no PDF toolchain |
| `fiscal-002-lukoil-ru.pdf` | ЛУКОЙЛ, Тверская обл, М-11 313км, 18.08.26 - petrol 95, RUB. **No text layer** |
| `fiscal-002-lukoil-ru.png` | Page 1 rendered at 200dpi - the only way to read 002, since OCR is required |
| `fiscal-002-lukoil-ru.qr.txt` | QR payload, decoded from the document's own QR with Vision |

Ground truth in `expected.csv`, verified arithmetically rather than eyeballed:
`25.52 x 70.92 = 1809.8784 -> 1809.88`, and VAT 22% of the gross is 326.37,
matching the printed figure. For `fiscal-002` the arithmetic does **not** close,
and that is the point - see "The receipt that breaks the cross-check" below.

## What makes this fixture worth having

- **Mixed decimal separators inside one line.** The item line reads
  `25,52 X 70.92` - comma for quantity, period for price. A parser that picks one
  convention per document gets this wrong, and the failure is silent: 2552 litres
  or 70.92 as a total both parse as plausible numbers.
- **Fuel kind is spelled in the product name, not a code**: `Бензин G-Drive
  95(АИ-95-К5)` - petrol95 with grade `G-Drive`. The `АИ-95-К5` suffix is the
  Russian octane/class standard, not a separate grade.
- **RUB**, so the currency path is exercised in a non-EUR, non-Latin document.
- **VAT is stated inclusive** (`в т.ч. СУММА НДС 22%`), which is a place a naive
  total-finder can grab the wrong number.

## The receipt that breaks the cross-check (`fiscal-002`)

This is the most valuable thing in the corpus so far, because it invalidates a
rule the parser and the Confirm screen both lean on.

The document is a **single-item fuel receipt** - no car wash, no snacks - and its
own numbers still do not reconcile:

```
ТРК №1 Бензин автомобильный ЭКТО Plus (АИ-95-К5)
                                23 x 73.06 = 1680.38
НДС 22%
ИТОГО                                        1680.00
НДС 22%                                       303.02
Безналичными                                 1680.00
```

`23 x 73.06 = 1680.38`, but ИТОГО is **1680.00** - and the QR agrees with ИТОГО
(`s=1680.00`), so 1680.00 is the fiscally binding number.

The mechanism is **ЛУКОЙЛ rounding the grand total down to the whole rouble**. A
second ЛУКОЙЛ receipt (СПб, АЗС 78154, 22.08.26, АИ-100) prints the same thing
and names it outright:

```
ТРК №3 БЕНЗИН АВТОМОБИЛЬНЫЙ ЭКТО-100 (АИ-100-К5), Л
                              43.61 X 99.40
                              ≡4334.83_НДС 22%
В ТОМ ЧИСЛЕ ВАША СКИДКА = 0.83
ИТОГ                             4334.00
ОКРУГЛЕНИЕ                          0.83
СУММА НДС 22%                    ≡781.69
```

`43.61 x 99.40 = 4334.83`, ИТОГ `4334.00`, and the 0.83 difference gets its own
**ОКРУГЛЕНИЕ** line while simultaneously being called "your discount". Both
receipts round *down*, both gaps are under 1 ₽, and in both the VAT is computed
on the **pre-rounding** sum: 781.69 is 22/122 of 4334.83, and 303.02 is 22/122 of
1680.38 (not of 1680.00, which would be 302.95).

So the quantity is exact - 23.00 L really was dispensed - and it is the *total*
that moves. An earlier reading of this fixture guessed a preset-amount fill with
a rounded-off quantity; the СПб receipt disproves that by printing the rounding
line explicitly.

This is **not universal**. A 2022 Кемерово receipt (ООО "Кузбасский деловой
союз", АИ-95, `48.89 X 48.80`) totals `2385.83` with no rounding line at all, and
`48.89 x 48.80 = 2385.83` closes exactly. So "extension == total" holds at some
chains and not others, and a parser cannot learn the rule from one brand.

Two consequences, both spec-level:

- **`liters x unitPrice == total` is not an invariant of real receipts.** It is a
  *heuristic*, and here it is off by 0.38 ₽ on a document that is perfectly valid.
  `docs/SCHEMA.md` CHECK 3 already anticipates this: its tolerance is
  `max(0.02, amount x 0.005)` = 8.40 ₽ at this total, which absorbs 0.38
  comfortably. **So the invariant is fine and this fixture confirms the tolerance
  was the right design** - worth stating, because the tempting "fix" after seeing
  this receipt is to tighten the check, and that would break it.
  What the receipt *does* break is **derivation**: a parser that computes the
  third value from the other two writes 1680.38 where the customer paid 1680.00
  and the QR says 1680.00. Two known values must not silently overwrite a third
  the document states.
- **The pump display and the receipt disagree, and both are right.** The pump
  photo taken at that СПб fill reads `РУБЛИ 4334.83 / ЛИТРЫ 43.61 / ЦЕНА/ЛИТР
  99.40` - the **pre-rounding** amount. The receipt for the same fill says ИТОГ
  4334.00. "Photograph the pump" and "scan the receipt" therefore return totals
  differing by up to 1 ₽ **for the same purchase**. Duplicate detection must not
  read that as two fills, and a later scan must not "correct" one into the other.
- **`CLAUDE.md` hard rule 4 is narrower than reality.** It says fuel amount ≠
  grand total *on mixed receipts*. This receipt is not mixed and they still
  differ. The rule should say the two are independently sourced, full stop.

### What the parser does with it today: 1/3 (total, fixed by P2.2)

The total-finder now returns **1680.00** (the modal of ИТОГО and Безналичными,
paired by baseline, not the 303.02 VAT the naive finder grabbed). Litres and price
are **nil** for the unmarked `23 x 73.06` - no unit marker on either operand, so
the ladder (`docs/SCHEMA.md` -> Fuel price bands) refuses to guess, and a band pack
is P5. OCR is not the problem. Vision reads every relevant line at confidence 1.00 -
`23 x 73.06 = 1680.38`, `1680.00`, `ИТОГО`, `303.02`. The original 0/3 was two parser
defects:

- **The total-finder grabbed the VAT amount.** In Vision's reading order a
  right-aligned two-column layout emits *value before label* (`1680.00` then
  `ИТОГО`, `303.02` then `НДС 22%`). A finder that looks for a number *after* its
  label lands on the next row's value. This is the second independent sighting of
  "naive total-finder grabs НДС" in a two-fixture corpus.
- **The quantity has no decimal point.** `23`, not `23,00`. `fiscal-001` reads
  `25,52 X 70.92` - comma decimals and an uppercase `X`; this one is `23 x 73.06`
  - integer quantity and a lowercase `x`. A line-item pattern tuned on 001 misses
  002 entirely.
- Fuel kind was the one hit: `95`, correctly read out of `АИ-95-К5`. Note this is
  a *product name* on a receipt, which is the case where fuel kind IS reliable -
  unlike a pump display, where the grade labels are every nozzle's, not the fill's.

## The QR payload

`fiscal-001-gpn-ru.qr.txt`, recovered by decoding the QR visible in
`../screenshots/screenshot-001-gpn-email.png`:

```
t=20260822T1702&s=1809.88&fn=7380440903722095&i=95516&fp=4235874914&n=1
```

`fn`, `i`, `fp` and `s` all appear verbatim in the PDF of the same receipt.

**The QR carries the total, the timestamp and the fiscal identifiers - nothing
else.** No litres, no unit price, no fuel kind. That is why `docs/JOURNEYS.md`
J5 pre-fills total and date from the QR instantly and leaves litres and price
"for the user or a later fetch": the enrichment step is not polish, it is the
only route those fields can arrive by.

## Open: how enrichment actually fetches the line items

The OFD serves this receipt's PDF at

```
https://ofd.ru/Document/RenderDoc?RawId=0854958e-d3df-6d7d-c983-7b9cde818da4&format=pdf
```

**`RawId` is an opaque GUID and is not derivable from the QR.** Nothing in
`t/s/fn/i/fp/n` produces it, so "scan the QR, build the document URL, fetch the
line items" does not work - the link only exists because the OFD mailed it to
this buyer. Verified against this receipt, not assumed.

**Confirmed a second time, against a different OFD.** `fiscal-002` came from
ofd-ya.ru (ООО "Ярус") with the link

```
https://ofd-ya.ru/k?fPTk5JmenBpr_gH2hJ4x
```

a short opaque token, and its QR decodes to the plain ФНС payload

```
t=20260818T193700&s=1680.00&fn=7380440902835516&i=16299&fp=4135886385&n=1
```

with no trace of that token. So the blocker is not one OFD's URL scheme: **the
QR does not address the document at any OFD we have seen.** Two OFDs, two
unrelated opaque link formats, the same standard six-field payload in both QRs.
That makes the third option below - or the ФНС API keyed on `fn`/`i`/`fp` - the
only routes that can exist, and it is worth deciding before P2.6 promises J5.

So J5's "all fields land exact" depends on a lookup this project has not chosen
yet. The realistic options, each with a cost worth deciding deliberately:

| Route | Cost |
|---|---|
| Official ФНС API (`irkkt-mobile.nalog.ru`), keyed on `fn`/`i`/`fp` | Needs a registered ФНС account per user - phone-verified. Free, authoritative, and a real onboarding step |
| Third-party aggregator | Usually paid, unofficial, and means sending a user's fiscal identifiers to a third party - a privacy decision, not a technical one |
| No lookup: QR fills total + date, user types litres | Zero dependencies and always works. Weakens J5's "100% correct, free" claim to "total and date exact, two fields typed" |

`docs/API.md` currently describes no fiscal endpoint at all, so nothing is
committed to yet. **This is a product decision, not an implementation detail**,
and P2.6 cannot honestly claim "instant fill, all fields exact" until it is
made. Whatever is chosen, F5 already covers the failure path: parse what the QR
carries, never block save, enrich in the background, fill blanks only.
