# PU.1 - the synthetic seven-segment renderer (`ml/pump-reader/`)

**Parent journey:** J4 (no receipt - pump display photo). **Row:** `docs/TASKS.md` → PU.1.
**Authority:** `docs/EXTRACTION.md` → "The pump reader" - read it first, it is the design.

## Where you may write

Only inside this checkout: `/Users/sbelyaev/repos/fuel-counter-ios-pump-reader`. Everything for this
row goes under **`ml/pump-reader/`** (new directory) plus one line in `.gitignore`. Nothing in
`ios/`, `backend/`, `Spike/`, `docs/` - the docs for this row are already written. Never write to
`/tmp` or the filesystem root. **Do not read or open the real pump fixtures** under
`Spike/ReceiptSpike/fixtures/pump/` for anything but the make names in their filenames: the corpus
is held-out by design and this renderer must not be tuned against it.

## Write code first, explore second

The dominant failure mode of a dispatched run is reading everything and writing nothing. Create the
package skeleton and the first passing test in your first ten minutes, then iterate.

## What this is

Pump displays are seven-segment. Vision OCR reads them as text and misreads a `9` with one dim
segment as a `4` at confidence 1.00 (`pump-004`), and drops the decimal point. The fix is a
**segment-level** classifier (8 outputs: segments a–g plus the decimal point) trained on
**synthetic** glyphs, so every real photo stays a held-out test set. This row is the data source:
a deterministic renderer that produces labelled glyph crops and labelled number rows. No model is
trained here (PU.3), no Swift is written here (PU.4/PU.5).

## Toolchain - fixed, do not shop around

- **Python 3.12** (`/opt/homebrew/bin/python3.12`). Not 3.14 - the ML packages the next row needs do
  not run on it yet. Create `ml/pump-reader/.venv` with `python3.12 -m venv .venv`; the venv is
  gitignored (add `ml/pump-reader/.venv/` to the root `.gitignore`).
- Dependencies in `ml/pump-reader/pyproject.toml`: `numpy`, `pillow`, `pytest`. **Nothing else** -
  no OpenCV, no torch, no coremltools in this row. Install with `.venv/bin/pip install -e '.[dev]'`.
- Package name `pump_reader`, layout `ml/pump-reader/src/pump_reader/…`, tests in
  `ml/pump-reader/tests/`. Type hints throughout; `from __future__ import annotations`.

## What to build

### 1. Make profiles (`pump_reader/profiles.py`)

A `MakeProfile` dataclass and a registry of at least **five** profiles named for the makes the
corpus holds: `gilbarco`, `wayne`, `dresser`, `scheidt`, `tokheim`. Fields, each a range the
renderer samples from:

- segment length / thickness ratio, segment gap, slant (degrees), glyph pitch (advance as a
  multiple of glyph width), decimal-point diameter and offset
- display technology: `lcd` (dark segments on a pale, greenish or grey ground, faint **ghost
  segments** for the off state), `led` (lit segments on a dark ground, red/amber/green, bloom), `vfd`
  (cyan-green on near-black, soft bloom)
- on/off colour ranges per technology

You do not know the true geometry of each make and **must not look at the corpus to learn it**.
Choose plausible, clearly distinct ranges and document each choice in the profile's docstring as a
guess to be revisited by PU.6 from measured failures. The point of five profiles is variety, not
fidelity.

### 2. The glyph renderer (`pump_reader/glyph.py`)

- `SEGMENTS = "abcdefg"` in the conventional order (a top, b upper-right, c lower-right, d bottom, e
  lower-left, f upper-left, g middle). `DIGIT_SEGMENTS: dict[str, str]` maps `"0"…"9"` to their
  segment sets. `BLANK` renders nothing. The decimal point is a separate bit.
- `render_glyph(label: SegmentLabel, profile: MakeProfile, rng) -> PIL.Image` draws the segments as
  hexagonal or rectangular bars with the profile's geometry into a fixed **32×48** grayscale-or-RGB
  canvas, then applies augmentation.
- `SegmentLabel` is an 8-bit value: bit 0 = a … bit 6 = g, bit 7 = dp. `label.digit` decodes to
  `"0"…"9"`, `"blank"`, or `None` for a pattern that is no digit. `SegmentLabel.from_digit("9",
  dp=True)` builds one.

### 3. Augmentation (`pump_reader/augment.py`)

Each applied with a sampled probability and strength, all seeded from the passed `rng`:

- specular **glare**: a soft white ellipse or diagonal band, partially occluding segments
- **blur**: gaussian and slight motion blur
- **perspective**: a random homography within ±12° tilt, then crop back to canvas size
- **LCD ghosting**: the off segments drawn faintly (lcd only)
- **canopy reflection**: a low-frequency brightness gradient plus a faint rectangular highlight
- **sensor noise** and **exposure**: gaussian noise, gamma, contrast
- **partial occlusion**: a random thin bar (a pump nozzle hose, a finger edge)

### 4. The row renderer (`pump_reader/row.py`)

`render_row(text: str, profile, rng) -> (PIL.Image, list[GlyphBox])` renders a whole number such
as `"12.38"` or `" 40.00"` as a sequence of glyphs on the profile's pitch, with the decimal point
either as its own dp bit on the preceding glyph (the common case) or as a separate narrow cell
(some makes) - a profile flag chooses. Returns the row image and one axis-aligned box per glyph
with its `SegmentLabel`, **after** perspective so the boxes are true. Leading blanks are rendered as
blank glyphs and labelled as such; zero-padding (`"0040.00"`) is a sampled variant.

### 5. The CLI (`python -m pump_reader.render`)

`--count N --seed S --out DIR [--make NAME] [--rows]`. Writes `DIR/glyphs/NNNNNN.png` plus a single
`DIR/labels.csv` (`file,label,digit,make,technology`), and with `--rows` also `DIR/rows/…png` with a
`rows.json` of boxes. `--seed` makes the whole run reproducible.

## Tests (`ml/pump-reader/tests/`) - each names its oracle

1. **Determinism**: two runs with `--seed 7 --count 50` into two directories produce byte-identical
   PNGs and CSVs. Oracle: the seed contract.
2. **Coverage**: a 1 000-glyph draw contains every one of the 12 classes (0–9, blank, dp-only) and
   every registered make. Oracle: the class list in `glyph.py`.
3. **Round trip**: for every digit, `SegmentLabel.from_digit(d).digit == d`; for every non-digit
   pattern in a sampled set, `.digit is None`. Oracle: `DIGIT_SEGMENTS`.
4. **Profiles differ**: render `"8"` with no augmentation in each make; every pair differs by more
   than a pixel-diff floor you compute once from the profile constants and assert against. **Mutation
   named by this brief**: set `scheidt`'s slant range to `gilbarco`'s and the other geometry fields
   equal - this test must go red. Run it, paste the red output in the report, then restore.
5. **Boxes are true**: for a rendered row with perspective, every box's centre lands on a lit pixel
   for a non-blank glyph (threshold against the ground colour). Oracle: the row's own labels.
6. **Row labels**: `render_row("12.38")` yields five boxes whose digits read `1,2,3,8` with the dp
   bit on the `2` (or a sixth dp cell when the profile flag is set). Oracle: the input string.

## Vacuous traps, named

- A determinism test that compares file *counts* rather than bytes.
- A profiles-differ test with a floor of zero.
- A coverage test on a draw so large that any renderer passes - keep it at 1 000 and sample the
  classes uniformly, do not stratify to force the pass.
- Asserting only that `render_glyph` returned an image of the right size.

## Out of scope - do not start these

Training (PU.3), Core ML export (PU.3), the annotations (PU.2, orchestrator-only), any Swift
(PU.4/PU.5), OpenCV, a real-photo comparison of any kind. Do not "improve" the corpus, `expected.csv`
or `PumpPhotoGate`.

## Checks (judged by exit code)

- `cd ml/pump-reader && .venv/bin/pytest -q` → exit 0, and report the **count** (must be ≥ 6).
- `python -m pump_reader.render --count 200 --seed 1 --out /Users/sbelyaev/repos/fuel-counter-ios-pump-reader/ml/pump-reader/.out --rows` → exit 0; `.out/` is gitignored (add it).
- The iOS and backend gates are untouched by this row - do not run `scripts/gate.sh`; report that you did not.
- `ml/pump-reader/README.md`: what it renders, how to run it, and the sentence *"The real corpus under `Spike/ReceiptSpike/fixtures/pump/` is held-out; nothing here is fitted to it."*

## Standing fences

- Never stash, move or `git checkout` for a clean baseline. Never `git add`, never commit.
- Never `pgrep -f` / `pkill -f`; `pgrep -x` only.
- Assume you are not alone in the checkout: never move, rename or revert a file you did not create.
- No `/tmp`; the only scratch is `ml/pump-reader/.out/`.

## Report back

Exit codes observed (`echo $?`), the pytest count, each test run-or-only-written, the red-then-green
output of the profiles-differ mutation, ten sample glyph filenames the orchestrator should open
(one per make, lcd and led), and **anything you found and did not fix**.
