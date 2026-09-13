# The accuracy ratchet, and the one number in it that went down

`high-water.json` is the floor each corpus class must not fall below
(`docs/TESTING.md` → "L5 accuracy not below the recorded high-water mark"). CI runs it; a
regression fails the build.

The table below is the shape of the ratchet and the reasoning behind each class;
**`high-water.json` holds the current numbers** and is the only place they are
recorded, so this table names the class and its rule rather than a figure that
would go stale the next time the corpus grows.

| class | what it means |
|---|---|
| `receipts` | the working number; raise it as the parser improves |
| `pump` | pump mode stays behind its flag until it clears the B1 gate (`PumpPhotoGate`: 0.99 precision, 0.60 coverage) |
| `fiscal` | only the rows that are OCR-scorable images are scored |
| `screenshots` | **was re-baselined downward once - read below before "fixing" it** |
| `expenses` | the expense read's four cells (kind, total, currency, date); the photograph is OCR'd at test time where one exists, else the `.txt` is the input; first recorded 29/29 on 2026-09-13 |

## The expense class (RV.277, photo input RV.278)

`expenses/` joined the ratchet on 2026-09-13. It is the corpus's only non-fuel
class. Ten fixtures are hand-authored OCR dumps with no photograph - there the
`.txt` IS the input by construction - and two are real tickets. Since RV.278 a
fixture with a `.jpg` is OCR'd through the same `VisionTextRecognizer` the fuel
classes use, and the `.txt` beside it is a debugging dump compared with the fresh
OCR: a difference is reported as **drift** and never scored, so a Vision change
(new runtime, new rendition) can move the expense number exactly as it moves the
fuel classes'. The four cells are the KIND (the `category` column the
folder scored alone before RV.277), `total`, `currency` and `date`; `none` in the
category column is a deliberate assertion that the vocabulary abstains, not a
blank. The first score is **29/29** - every asserted cell resolved. A
`recognised.csv` beside `expected.csv` records what the extractor produced on the
last `swift run ReceiptSpike fixtures/expenses`; it is a review artefact and
never the oracle.

## Why `screenshots` was re-baselined from 3/3 to 1/3

It scored **3/3 before P2.2 and 1/3 after**, and that is a deliberate correctness change, not a
regression to be reverted.

The single fixture is `25,52 X 70.92` - **unmarked**: no `л`, no `руб`, no labelled column, so
nothing in the document says which operand is the volume and which is the price. The old
`bestTriple` broke the tie by decimal-digit count, both operands have two decimals, so the
score was **0 - a tie** - and the "right" answer won only because litres were iterated in
ascending order and `25.52 < 70.92`. It was luck, not resolution.

The proof that it was luck: **the same code path swapped `receipt-007`**, returning
`99.400 L at 43.610` when the truth is `43.61 L at 99.40` - and the arithmetic cross-check
reported PASS on it, because `a x b == b x a`. A parser that is right by coincidence on one
fixture and confidently wrong on another is not 100% accurate; it is untrustworthy at 100%.

The new ladder returns **nil** for an unmarked pair when no price band or user history is
available. That is hard rule 13 behaviour - a value the app cannot know is left for the user,
not invented - and it is why the class now scores 1/3.

**So 3/3 and 1/3 are not measurements of the same thing.** The old number counted lucky
guesses; the new one counts resolved assignments. Comparing them directly is the mistake this
file exists to prevent.

## What raises it back

The resolution ladder's steps 3 and 4 (`docs/SCHEMA.md` → Reference data → Fuel price bands):
the user's own price history, and the curated per-country band pack that lands in **P5**. With
a band injected, `70.92` is recognisable as the price and `25.52` as the volume, and this
fixture resolves for a real reason. **Do not raise this number by restoring a tie-break
heuristic.**

## The unmarked pair, and the band's lower edge

`receipt-061` (2026-09-10) is the corpus's clearest statement of what the price band can and
cannot settle. Its money line is `71.18 x 42.000`, read at confidence **1.00** and **unmarked** -
no `л`, no `руб`, no labelled column. The RU 2024+ petrol band is `40..500`, so **both** operands
are plausible prices, nothing pins which is which, and the parser abstains on `liters` and
`unitPrice` while still resolving the total, fuel kind and currency.

Its sibling `receipt-060`, from the same brand and card, resolves every cell - because `21.000`
falls **below** the band floor and is therefore not a candidate price. The two differ in nothing
but the size of the fill. The band resolves small fills and abstains on ordinary ones.

The paired `pump-084` is what makes the truth provable rather than argued: the display states the
three values separately and labelled (`СУММА` / `ЛИТРЫ` / `ЦЕНА ЗА ЛИТР`), so `42` is the volume
beyond dispute. That is the case for shooting both (`README.md` -> matched pairs).

**Do not close this gap with a decimal-count tie-break.** Two decimals against three looks like a
free signal here and is the same heuristic the `screenshots` re-baseline above exists to keep
out; `receipt-036`/`receipt-037` already show the same till printing the operands in both orders
one minute apart. What closes it is step 3 of the ladder - the user's own price history.

## A fuel kind read from boilerplate

`receipt-062` and `receipt-063` (2026-09-11) are the corpus's cleanest **OCR-not-parser** pair: one
RN-Tver till, one slip layout, two minutes apart. `063` sweeps 5/5. On `062` Vision reads the
product line as `МИ95ФИРМ` at confidence **1.00** (`АИ` -> `МИ`), the `95` marker is gone, and the
parser then commits **`fuelKind = lpg`** from `/СУГ` in the footnote `1 ед.=1 литр для
нефтепродуктов/СУГ` - a line **every** RN-Tver slip prints, `063` included. The receipt says АИ95
and its paired pump (`pump-085`) was dispensing it, so this is a confident-wrong kind read from
boilerplate, not a ground-truth question. It is the receipt-side twin of the pump rule ("a visible
grade is evidence the station sells it, never that this fill used it"): a kind word in a footnote
that lists what the till can sell is not the kind of this fill. The fix belongs in the fuel-kind
vocabulary (where a marker is allowed to come from), not in the ratchet; do not raise the number
by teaching the parser `МИ95`.

**Fixed 2026-09-12 (`RV.270`).** A kind may now come only from the product / line-item block:
`FuelKindNormalizer.isBoilerplate` rejects a unit-convention legend (`для нефтепродуктов` /
`для КПГ` in either script, the `1 ед.=` shape) and a fuel token in a slash-list (`.../СУГ`)
*before* a marker is read, so the legend's `/СУГ` can no longer set `fuelKind`. On `receipt-062`
the parser now **abstains** (`nil`) instead of committing `lpg`; `receipt-063` still resolves
`petrol95`. The ratchet is **unchanged at 255/300**: a confident-wrong kind and an abstention both
miss the same expected cell, which is exactly why the score alone could not catch this. The
whole-class check `AccuracyRatchetTests.noReceiptCommitsAFuelKindItsExpectedContradicts` now fails
on any committed kind its `expected.csv` contradicts, so the next boilerplate read fails the suite
rather than merely lowering a count.

The same batch's eleven pump displays sharpen the other standing asymmetry: both Circle K Gilbarco
reads (`pump-094`/`095`, `€` / `L` / `€/L` beside the digits) sweep 3/3 and the nine Cyrillic-
labelled displays behind glass (two Tokheim, seven Scheidt & Bachmann) commit nothing - so the
same `30.00 x 71.30` fill is resolved from the paper (`receipt-063`) and not from the pump
(`pump-086`). Precision moved 0.940 -> 0.946 and coverage 0.216 -> 0.212; the mode stays off on
both.

## `receipt-065` - the 062/063 question answered, and the pump asymmetry repeats

`receipt-065` (RN-Tver, АЗК Тверь-2 ТС252, 2026-09-13) is the same non-fiscal PetrolPlus till family
and the same `1 ед.=1 литр для нефтепродуктов/СУГ` legend as `receipt-062`/`063`, one station over.
It **sweeps 5/5**: Vision reads the product line as `АИ95фирм` cleanly, so the `95` marker survives
and `fuelKind = petrol95` resolves, and after `RV.270` the legend can no longer set a kind. That is
the proof `062`'s `МИ95ФИРМ` was an OCR glyph problem and its `lpg` commit a vocabulary problem, not
ground-truth ambiguity. Receipts **255/300 -> 260/305**.

Its paired `pump-096` (Tokheim LCD, Cyrillic labels) commits nothing on any of its three numeric
cells, so the pump numeric total grows 264 -> 267 while committed stays 56 and committed-correct 53:
coverage 0.212 -> 0.210, precision 0.946. The same `20.00 x 71.30` fill is resolved from the paper
and not from the display - the asymmetry the 2026-09-11 batch recorded, now repeated at a third
RN-Tver station. The mode stays off.

## The Circle K Dresser Wayne set - a receipt that commits the discount as the unit price

The 2026-09-13b set is four Circle K Estonia Dresser Wayne displays (`pump-097`..`100`, all the
same `SUMMA`/`LIITRIT`/`HIND-1L` face, the grade never named) and the paper half of `pump-100`,
`receipt-066` (Circle K Jarvevana, pump 4, `D B0 miles 64,04L 129,62`, 13/09/2026 15:32).

**Receipts 260/305 -> 263/310.** `receipt-066` resolves litres, total and currency; it misses
`fuelKind` (`D B0 miles`, the loyalty product string that has never normalised to diesel) and
`unitPrice`. The unit-price miss is **not** an abstention: the parser commits **`unitPrice = 0.96`**,
which is the `EXTRA SOODUS -0,96 EUR` discount line, not the `2,024` the receipt prints and its
paired pump displays. The footnote `Kütuse liitrihind kviitungil sisaldab allahindlust` says the
printed per-litre price already includes the discount, so `64.04 x 2.024 = 129.62` closes exactly
and the `-0,96` is informational. A confident-wrong unit price is hard rule 13's exact concern, and
the ratchet scores it as a plain miss - the same asymmetry `RV.270` fixed for `fuelKind`. Recorded,
not tuned.

**Pump 53/267 -> 53/279.** The four displays assert twelve numeric cells and the parser commits
nothing on any of them, so committed stays 56 and committed-correct stays 53: coverage
0.210 -> 0.201, precision 0.946. The `D`/`95`/`98+` windows are recognised as text but the
transaction price is never selected from them. The mode stays off.

## Known trap

`swift run ReceiptSpike fixtures/receipts` - the CLI a human runs when adding a fixture by
hand - still uses the **Spike's own** parser and prints the old `18/47`, while this file
records the ported parser's `29/47`. The two are different implementations. Score against
`TankbookCore`'s extractor (the ratchet test) when you care about the committed number.
