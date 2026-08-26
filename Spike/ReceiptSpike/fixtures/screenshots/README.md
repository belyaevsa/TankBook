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

## `screenshot-002` - a ЛУКОЙЛ e-receipt, six minutes from a paper one

Минеральные Воды, 28.06.26 13:48. `20 X 73.83 = 1476.60`, ИТОГ **1476.00** - the
ЛУКОЙЛ whole-rouble rounding again, this time by 0.60, with VAT 266.27 computed on
the pre-rounding 1476.60 exactly as on every other ЛУКОЙЛ receipt in the corpus.

It is rendered HTML, not a photo of paper, so it scores in this class rather than
`receipts/` - no glare, no perspective, no thermal fade. Note it carries **no
QR**: the fiscal ids are printed as text (ФД 131546, ФПД 49643412), so the anchor
that works on paper is unavailable here.

Its sibling is worth knowing about: `receipts/receipt-031` was bought in the same
town **six minutes later** at a Газпром station. Two brands, two receipt
technologies, two rounding behaviours, one afternoon.

## `screenshot-003` - a loyalty app's own transaction record

A third source class, after paper receipts and pump displays: the **payment app's
transaction screen**. Тольятти, АЗС №341, 16.08.26 12:47.

```
3429,65 ₽                    <- rendered with the kopecks in a LIGHTER GREY
Приобретено
  АИ-98 x 35.0 л.   3429,65 ₽
  Цена               97,99 ₽
  Цена с учетом скидки  97,99 ₽
```

`35.0 x 97.99 = 3429.65` closes exactly. Three things make it worth having:

- **The amount is styled in two weights.** "3429" is dark and ",65" is grey, so
  OCR may return them as separate tokens and a parser can lose the kopecks or read
  3429 and 65 as unrelated numbers. Paper never does this; app UIs do it often.
- **List and discounted price are BOTH shown, and here they are equal.** On
  `receipts/receipt-031` they differ (71.05 vs 69.98). So the presence of two price
  fields says nothing about whether a discount applied - only their values do.
- **Everything is labelled and unambiguous**: the quantity carries its unit
  (`35.0 л.`), the grade is explicit (`АИ-98`, the corpus's first), and the station
  is a structured address rather than a header line. This is the easiest input in
  the whole corpus, which is worth knowing: if an app screenshot is available it
  beats photographing the paper.

## `screenshot-004` .. `screenshot-008` - the Circle K app, and the discount that breaks the cross-check

Added 2026-08-26. Five Circle K "Transaction Details" screens from Estonia,
Latvia and Lithuania. Rendered light-mode UI, EUR, dot decimals, English chrome
over local station names. Four are fuel-only; `screenshot-008` is mixed.

### `screenshot-004` is a THIRD view of `receipt-001` / `pump-001`

Circle K Järvevana, Tallinn, 24/08/2026 07:28. The corpus already had this fill
twice - the paper receipt and the pump display. The app record is the third, and
it is the one that explains the other two:

```
D B0 miles          1.884 EUR x 67 L        125.22 EUR
Total                                       125.22 EUR
Discount                                      1.01 EUR
```

`67 x 1.884 = 126.23`, and `126.23 - 1.01 = 125.22`. So the **list** price is
1.884 and the **effective** price is 1.869 - which is the number
`receipts/receipt-001` prints and `pump/expected.csv` records for `pump-001`. Same
fill, two different truthful unit prices, depending on which document you read.

It also settles the fuel kind the receipt garbled. `receipt-001` OCRs to
`D BÓ miles` and the parser calls it **98**; the app renders it cleanly as
`D B0 miles` - diesel, B0, `miles` being the loyalty brand. The corpus README
recorded that as "confirmed by the owner of the receipt"; it is now confirmed by a
document.

### The cross-check closes on none of these five

`liters x unitPrice != total` on `screenshot-004`, `-005`, `-006`, `-007` and
`-008`, every time by exactly the discount:

| fixture | line | product | discount | total |
|---|---|---|---|---|
| 004 | 1.884 x 67 | 126.23 | 1.01 | 125.22 |
| 005 | 2.159 x 58.01 | 125.24 | 4.06 | 121.18 |
| 006 | 1.799 x 68 | 122.33 | 1.02 | 121.31 |
| 007 | 1.614 x 64 | 103.30 | 1.92 | 101.38 |
| 008 | 1.924 x 59.78 | 115.02 | 2.39 (fuel share) | 112.63 |

This is the single most useful thing in this batch. The confirm-screen lock in
`docs/JOURNEYS.md` J4 fires when the three numbers multiply out - and on a loyalty
receipt they systematically **do not**, while every field has been read correctly.
A cross-check that refuses to lock here is refusing a perfect scan.

So the rule needs a third outcome beyond lock and mismatch: **`product - total`
matches a discount line on the document** is a *reconciled* state, not an error.
Where no discount line is visible, the residual is still the honest thing to show
the user rather than a bare amber warning - "1.01 less than 67 x 1.884" names its
next step, a raw mismatch does not (hard rule 7).

`expected.csv` records the **printed** unit price (the list price) and the
**charged** total, because that is what the document says. A parser that returns
the effective price instead is not wrong about the fill - it is answering a
different question, and the app has to decide which one it stores.

### `screenshot-008` - the corpus's third mixed receipt, fully reconciled

Circle K Jugla, Rīga, 03/05/2026. Latvian item names, eight lines, one of them
fuel:

```
SOK.BAT.KNOPPE   1.39 x 1 Gab.     1.00
SOK.BAT.KNOPPE   1.39 x 1 Gab.     1.00
Dizeld. Miles    1.924 x 59.78 L  112.63
LIMO.COCA COLA   1.69 x 1 Gab.     1.69
DEPOZITA MAKSA   0.10 x 1 Gab.     0.10
PIENA BAT.KIND   0.99 x 1 Gab.     0.99
M KAFIJA         2.79 x 1 Gab.     2.79
M KAFIJA         2.79 x 1 Gab.     2.79
Total                            122.99
Discount                           3.17
```

Hard rule 4 in one image: the fuel amount is **112.63** and the grand total is
**122.99**, and a FillUp that stores 122.99 has silently charged chocolate,
coffee and a bottle deposit to the car's fuel consumption.

It reconciles completely, which is rare and makes it a strong test vector:
non-fuel charged `10.36`, `112.63 + 10.36 = 122.99` exactly; non-fuel at list
`11.14`, so the shop discount is `0.78`, and `2.39 + 0.78 = 3.17` - the printed
discount, split between the pump and the shop. Every number on the document is
accounted for.

Also note the fuel line is the **third** of eight, not the first and not the
largest by line count. A parser that takes the first priced line, or the line
nearest the total, gets a chocolate bar. The discriminator is the unit: `L`
against `Gab.` (Latvian *gabali*, pieces) - a vocabulary entry the corpus did not
have before.

### Why these are easy inputs, and what that is worth

Rendered UI, high contrast, no glare, labelled fields, explicit units. If a user
has the app record, it beats photographing the pump or the paper - which is the
same conclusion `screenshot-003` reached from the Russian side, now with a second
brand and three more countries behind it. The hard part of these documents is not
reading them; it is knowing which of the two unit prices to keep and which total
is the fuel.
