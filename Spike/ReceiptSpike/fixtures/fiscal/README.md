# Fiscal receipts (Russian ФНС / OFD)

**A different input class from `../receipts/`, and a different pipeline.** These
are the documents an OFD serves for a fiscal receipt - what the app gets after
scanning the fiscal QR (`docs/JOURNEYS.md` J5, `docs/TASKS.md` P2.6), not a photo
of paper. They carry a **text layer**, so `pdftotext` reads them exactly and no
Vision OCR is involved.

Keeping them here rather than in `../receipts/` matters: mixing them in would
inflate the image-OCR accuracy number with documents OCR never had to read.

## What is here

| File | Source |
|---|---|
| `fiscal-001-gpn-ru.pdf` | Газпромнефть, Moscow, 22.08.26 - petrol, RUB |
| `fiscal-001-gpn-ru.txt` | `pdftotext` output, committed so a parser test needs no PDF toolchain |

Ground truth in `expected.csv`, verified arithmetically rather than eyeballed:
`25.52 x 70.92 = 1809.8784 -> 1809.88`, and VAT 22% of the gross is 326.37,
matching the printed figure.

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
