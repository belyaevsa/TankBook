# Screenshots of electronic receipts

The `.screenshot` provenance in `docs/SCHEMA.md`: a user forwards or screenshots
an e-receipt instead of photographing paper. Common for online fuel payment and
for fiscal receipts mailed by the OFD.

A **third input class**, distinct from both siblings: it goes through Vision OCR
like `../receipts/`, but the source is rendered text rather than a photographed
surface - so there is no glare, no perspective, no crumpling, and the failure
modes are entirely different.

## What is here

`screenshot-001-gpn-email.png` - the **same transaction** as
`../fiscal/fiscal-001-gpn-ru.pdf`, viewed in an email client. Truth:
`25.52 L x 70.92 RUB/L = 1809.88 RUB`.

## What makes this class its own problem

- **App chrome is in the frame and looks like content.** A status bar (`12:26`),
  a truncated mail subject (`Кассовый чек + (1) подарок. Общество с...`), a reply
  bar and a tab bar (`Email · Calendar · Apps`). None of it belongs to the
  receipt. The pump fixture already showed what happens when surrounding text is
  treated as data - the parser returned a sandwich advert as the litre count.
- **Dark mode inverts the document.** Light text on dark ground, where paper
  receipts are the opposite. Worth having at least one of each polarity, since a
  binarisation step tuned on paper can fail badly here.
- **It is cropped.** The visible portion starts mid-document: the station name,
  address and date are all above the fold. A parser must not assume the header
  exists, and must not mistake the first visible line for the top of the receipt.
- **The fiscal QR is in the frame**, which is what makes this fixture especially
  valuable - see below.

## Current parser result: 1/3 (total), litres and price undecided

The total-finder reads **1809.88** (the modal of `=1809.88`, `ИТОГ` and
`Безналичными`). Litres and price are **nil**: `25,52 Х 70.92` has no unit marker
on either operand, so the ladder (`docs/SCHEMA.md` -> Fuel price bands) refuses to
guess - the old "25.520 x 70.920" was `bestTriple` guessing a commutative product,
which the swap failure (`receipts/README.md` item 1) shows cannot be trusted. The
correct reading (25.52 L at 70.92) is what a price band resolves; the band pack is
P5, so until then the user fills the two fields. One honest gap remains: **currency
reads `–`**. There is no `₽` or `RUB` anywhere in the visible crop - the amounts
are bare numbers - so the parser is right not to invent one. The app resolves this
from the vehicle's home currency, and `docs/ERRORS.md` -> Confirm covers the
low-confidence case with a chip row rather than a silent guess.

## The QR it yielded

Decoding the QR in this screenshot produced the payload that the PDF could not
give up, now saved as `../fiscal/fiscal-001-gpn-ru.qr.txt`:

```
t=20260822T1702&s=1809.88&fn=7380440903722095&i=95516&fp=4235874914&n=1
```

Every identifier cross-checks against the PDF of the same receipt (`fn`, `i`,
`fp`, `s` all appear in it verbatim).

**Note what the QR does not carry: liters, unit price, or fuel kind.** It has the
total, the timestamp and the fiscal identifiers, nothing more - which is exactly
why `docs/JOURNEYS.md` J5 says the QR pre-fills total and date instantly and
leaves litres and price "for the user or a later fetch". This fixture is the
evidence for that design, not just an assertion of it.
