# The accuracy ratchet, and the one number in it that went down

`high-water.json` is the floor each corpus class must not fall below
(`docs/TESTING.md` → "L5 accuracy not below the recorded high-water mark"). CI runs it; a
regression fails the build.

| class | recorded | what it means |
|---|---|---|
| `receipts` | 29/47 | the working number; raise it as the parser improves |
| `pump` | 0/12 | pump mode stays behind its flag until it clears >=95% |
| `fiscal` | 1/3 | only one of the three rows is an OCR-scorable image |
| `screenshots` | 1/3 | **re-baselined downward - read below before "fixing" it** |

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

## Known trap

`swift run ReceiptSpike fixtures/receipts` - the CLI a human runs when adding a fixture by
hand - still uses the **Spike's own** parser and prints the old `18/47`, while this file
records the ported parser's `29/47`. The two are different implementations. Score against
`TankbookCore`'s extractor (the ratchet test) when you care about the committed number.
