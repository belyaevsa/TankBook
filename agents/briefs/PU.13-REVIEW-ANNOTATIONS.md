# PU.13-REVIEW-ANNOTATIONS - a second pass over the number-window oracle

**Read-only.** You write exactly ONE file: `agents/reviews/PU.13-REVIEW-ANNOTATIONS.md`. No edits
to `windows.json` - name what you would change and why. No `/tmp`; scratch is
`ml/pump-reader/.out/review-ann/`.

## What this is

`Spike/ReceiptSpike/fixtures/pump/windows.json` is the oracle for every number in the pump-reader
tranche (`docs/EXTRACTION.md` → "The pump reader"; `ml/pump-reader/REPORT.md`): 114 real photos ×
hand-drawn number windows (456), one annotator, from grid overlays at ±1 % of the image edge. Its
`_about` key documents the format; `scripts/pump-windows-check.py --check` cross-checks strings
against `expected.csv`. Nobody has checked the quads or the strings a second time.

You cannot see images. You CAN measure them: with `ml/pump-reader/.venv/bin/python` (pillow,
pillow-heif, numpy) load each fixture (EXIF-transposed, then `rotationCW`), warp each quad to a
strip, and compute what a good annotation implies.

## What to check, and how

1. **Quad tightness and bias.** For each window: the ink band (rows with dark/light ink after
   polarity) as a fraction of the strip height, and the left/right margin between the strip
   edge and the first/last ink column as fractions of the estimated pitch. Report the
   distributions per make and per field. A systematic left margin larger than the right one
   (or the reverse) is a bias that the slicer's leading-blank logic pays for - say if it is there.
2. **Strings.** For every window, count ink runs along the strip (a crude glyph count) and
   compare to `glyphCount(text)` (digits + leading spaces; separators are not glyphs). List
   every window where they disagree by ≥ 2 - each is either a bad string, a bad quad, or a
   hard image; classify by the evidence you have (is the ink band clean? is contrast low?).
3. **Zero padding and leading blanks.** The strings encode leading zeros (`0020,15`) and
   leading spaces (` 40.00`). Check consistency: do all Gilbarco windows carry the same digit
   count per field? Do the Scheidt ones? Flag the outliers.
4. **The declared exceptions** (`pump-031` csvDisagrees, `pump-072` notOnDisplay, `pump-067`
   partial): are they the only ones? Search `expected.csv` vs strings for any other cell where a
   display could not show what the CSV asserts (e.g. a 3-decimal price on a 2-decimal display).
5. **The `board` windows.** They are the grade-price board cells, not the transaction; are they
   consistently labelled, and does every four-price Wayne head have all four?
6. **Rotation.** `rotationCW` is set on three fixtures; check every strip's aspect ratio - a
   window taller than wide is a missed rotation.

## Report

`agents/reviews/PU.13-REVIEW-ANNOTATIONS.md`: the distributions (tables), every specific
window you would re-draw or re-type with the reason, the biases you found, and a verdict: is the
oracle good enough to measure a 0.99 gate, and if not, what exactly must change. Then **"What I
would need to know or have"** - ranked asks to the product owner (a second human annotator?
glyph-level boxes on a subset? which fixtures?).
