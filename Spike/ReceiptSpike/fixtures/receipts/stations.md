# The `station` column (RV.179)

The cell is the run of normalised tokens (`StationBrandMatcher.normalisedTokens`) the extracted
station line must contain; `|` separates the spellings a receipt may print (`lukoil|lukoyl` for
Latin and Cyrillic). **The oracle is the fixture filename**, which the product owner wrote from the
paper before any station extractor existed, cross-checked against the OCR text (the extractor's
INPUT, never its output). Where the two cannot agree the cell is empty and the reason is here - a
blank for any other reason is a miss hiding, which is the RV.161 trap.

Asserted: 82 of 97 receipts (the 2026-09-21/22 eleven all assert; of the 2026-09-22 French batch, seven assert). Blank, with the reason:

| fixture | why the cell is blank |
|---|---|
| `receipt-001.heic` | the filename carries no name at all |
| `receipt-008-kemerovo-95-2022-ru.png` | the filename names the city; the print names `ООО "Кузбасский деловой союз"` - rename the fixture to assert it |
| `receipt-009-mkad-mixed-fuel-water-ru.png` | the filename names the road; the print's company line is a fragment (`"ПИТАЛ`) |
| `receipt-011-samara-diesel-ru.png` | the filename names the city; the print names `АО "САМАРАНЕФТЕПРОДУКТ"` - rename the fixture to assert it |
| `receipt-013-rn-moscow-95-ru.png` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-015-kedr-simferopol-95-ru.jpg` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-019-web-2018-ru.jpg` | a web-sourced image with no chain in its name; the read carries none |
| `receipt-020-web-2020-ru.jpg` | a web-sourced image with no chain in its name; the print reads `Газпромнефть-Центр` - rename the fixture to assert it |
| `receipt-021-web-2018-ru.jpg` | a web-sourced image with no chain in its name; the print reads `АО "ННК-КАМЧАТНЕФТЕПРОДУКТ"` - rename the fixture to assert it |
| `receipt-024-krymoil-sevastopol-diesel-newpower-ru.png` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-036-tatneft-azs172-98-terminal-slip-ru.jpeg` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-041-zolotaya-seredina-tver-95-fuelcard-ru.jpg` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-053-gpn-tver-95-ru.jpg` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-057-gpn-valday-95-occluded-ru.jpg` | brand not legible in the OCR text (the filename names it, the read does not carry it on any line) |
| `receipt-096-unknown-gazole-3463l-1843-no-total-cropped-fr.jpg` | the photo is cropped above the header: no station name is on the paper that was photographed, only `TICKET CLIENT A CONSERVER` |

`receipt-006` (`ИП Гридяева А.В.`) and `receipt-043` (`ООО "Артемовск-Газсервис"`) are single
stations, not chains, and the filename names them - asserted as `gridyaeva` and
`artemovsk gazservis|gazservis` (the OCR garbles the first word). `receipt-035` (`gdrive95` in the filename) is asserted as `gazpromneft`: G-Drive is Gazpromneft's own
grade, sold nowhere else, so the filename names the chain through its product. `receipt-031`
(`ГАЗПРОМ СЕТЬ АЗС`) is `gazprom`, the parent's own network, not `gazpromneft`.

Cross-checked 2026-09-19 against Vision on macOS 27 (`swift run ReceiptSpike fixtures/receipts
--dump-text`); the seven not-legible blanks are that runtime's reads and may be legible on the
measured one - re-check them there before asserting.
