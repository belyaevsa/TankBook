# RV.270 - a fuel kind committed from till boilerplate

**Scenarios: J3 · the 5-second fill-up (the pre-fill is a default input), F2 · scan recognized
WRONG data.** A confident-wrong kind pre-filled on Confirm looking exactly like a right one - the
F2 shape. Renumbered from a duplicate `RV.243` on 2026-09-12; F2's and J3's status lines are
cleared until this ships.

`receipt-062` (RN-Tver PetrolPlus, 2026-09-11) reads `fuelKind = lpg` off the footnote
`1 ед.=1 литр для нефтепродуктов/СУГ` that EVERY slip from that till prints: Vision reads the
product line as `МИ95ФИРМ` at confidence 1.00, the `95` marker is lost, and `FuelKindNormalizer`
takes `/СУГ` from the legend. The paired `pump-085` and `receipt-063` (same till, two minutes
apart) both say АИ95 - the corpus's cleanest OCR-not-parser pair (`fixtures/HIGH-WATER.md:74`).

## Build

Restrict where a fuel-kind marker may come from: the product / line-item block
(`FuelKindNormalizer.isProductLine`, `FuelKindNormalizer.swift:55`), never a line that is a unit
legend or boilerplate - `1 ед.=`, `для нефтепродуктов`, a slash-list such as `/СУГ`. Prefer
abstaining (`nil`) over a kind read from a line that also names another kind: a nil kind is an
empty field the user fills, a wrong kind is a fact they must notice (hard rule 13). The receipt
rule is the twin of the pump rule already written down: *a visible grade is evidence the station
sells it, never that this fill used it* (`fixtures/pump/README.md`). **Do NOT fix it by teaching the
normalizer `МИ95`** - that is Vision's glyph, not the parser's vocabulary; the next slip will
misread differently.

## Tests (`Spike/ReceiptSpike`, then the package)

- **L1 over `receipt-062`'s dump, FAILS TODAY**: `fuelKind` is nil or `.petrol95`, never `.lpg`.
- **L1**: `receipt-063` still resolves `.petrol95`.
- **Whole-class check**: no receipt in the corpus commits a `fuelKind` its `expected.csv`
  contradicts, so the next boilerplate read fails the suite too.
- The accuracy gate: run the harness per `Spike/ReceiptSpike/README.md`; the ratchet must not
  fall below **255/300** asserted cells and `fixtures/HIGH-WATER.md` gains the entry *"A fuel kind
  read from boilerplate"* with the before/after numbers. `docs/EXTRACTION.md` names the failure
  mode with its fixture.

`swift test` in full for the package (the normalizer is shared); no UI, no screenshots.

## Mutation - named

Let the legend line through again; the `receipt-062` L1 goes red on `.lpg`. Verbatim, with the
harness numbers before and after.
