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

## Not yet extracted

The PDF embeds an image on page 1 (452x1567) which is the fiscal QR strip. P2.6
parses the QR *payload* (`t=...&s=...&fn=...&i=...&fp=...&n=1`), and that payload
is not recoverable from this PDF - it needs the original scan. Add the raw QR
string alongside as `fiscal-001-gpn-ru.qr.txt` when one is captured; until then
this fixture exercises the document parser, not the QR parser.
