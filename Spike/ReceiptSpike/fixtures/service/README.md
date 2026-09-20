# Service documents (unscored)

The first photographs of the documents J7's `InvoiceSplitter` and the invoice kind of `/extract`
(`docs/EXTRACTION.md` → "The invoice kind") are meant to read. Three arrived from the product owner
on 2026-09-21; **no scorer covers this folder yet** - `expected.csv` is the hand-written truth
(vendor, grand total, currency, date, the number of costed line items) so a scorer can be built
against it later without re-reading the paper. Ground truth is written from the paper, never from
an extractor's output (`../README.md`, the oracle rule).

| file | what it is | total | lines |
|---|---|---|---|
| `service-001-lrwest-order-with-fiscal-slip-ru.jpg` | LR-West (ИП Седельников, Moscow) `заказ-наряд Р-0000000016611` of 09.09.2026 for a Land Rover (VIN, plate and mileage printed): diagnostics 1 600, front bumper off/on 8 000, electrical work 5 000 = **14 600,00**, НДС 2 632,78; the fiscal slip (`ИТОГ ≡14600.00`) stapled at the top-left corner over the header; a recommendations paragraph and a stamp below | 14600.00 RUB | 3 |
| `service-002-maslotex-oil-change-fiscal-ru.jpg` | МаслоТех (ИП Французова, Раменское) fiscal receipt of 09.09.2026 17:40 for an oil change: two oil lines (4 L + 2 x 1 L), a flush, 5 L of bulk oil, and the labour line at **0.01** (a promotion), then a second block `1 Замена масла в автомобиле 14160.01*1` - the sum re-printed as one item - ИТОГ **14160.01**, cash; a portrait strip photographed over a printed checklist | 14160.01 RUB | 5 |
| `service-003-hyundai-order-works-materials-fiscal-slip-ru.jpg` | An `акт выполненных работ № 0000055002` of 09.09.2026 for a Hyundai ix35 (VIN, plate, 228 499 km) with TWO tables - works (inspection 1 000 priced but not totalled, oil change as a promotion with no price, skid-plate off/on 750 → Итого 750,00) and materials (consumables 300, 4 x Motul 5W40 1 480, filter 590, drain-plug gasket 120 → Итого 6 930,00) - `К оплате 7 680,00`; the fiscal slip (`≡7680.00`) stapled top-left, a post-it hiding the vendor's name | 7680.00 RUB | 7 |

`lineCount` is the number of rows a correct split produces, including zero- and blank-priced ones
the paper prints as rows; a row the paper prices but does not total (the ix35 inspection) is still
a row. JPEG, orientation baked in, EXIF stripped. Photos include a plate and VIN - they are the
owner's own documents and stay in this repository like the receipts do.
