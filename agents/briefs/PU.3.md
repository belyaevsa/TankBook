# PU.3 - the segment classifier (train, export to Core ML, score on the held-out windows)

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.3. **Authority:** `docs/EXTRACTION.md` → "The pump
reader". **Builds on:** PU.1 (`ml/pump-reader/`, commit `366691da`) - read its README and
`src/pump_reader/{glyph,profiles,row,render}.py` before writing anything.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios-pump-reader`, and only under **`ml/pump-reader/`**
plus the new resource file `ios/App/Resources/PumpSegments.mlpackage` (a directory) and, if you need
it, one line in the root `.gitignore`. No other Swift, no `project.yml` change, no `Spike/` change.
Never write to `/tmp` or the filesystem root; scratch is `ml/pump-reader/.out/`.

**The real corpus is held-out.** You may read `Spike/ReceiptSpike/fixtures/pump/windows.json` (the
annotation file, if it exists yet - it is being written by the orchestrator in parallel and may be
partial) and the fixture images **only through the `score` command you build**. Never train, tune,
or pick hyperparameters by looking at real-photo results; never open a fixture image by hand. The
synthetic validation split is your only tuning signal.

## Write code first, explore second

Skeleton `train.py` + `export.py` + `score.py` with a smoke test in your first ten minutes.

## Toolchain

`ml/pump-reader/.venv` exists (Python 3.12). Add to `pyproject.toml` an optional extra `train`:
`torch`, `torchvision` is NOT needed, `coremltools`, `numpy`, `pillow`. Install with
`.venv/bin/pip install -e '.[dev,train]'`. Pin nothing beyond a lower bound. If `coremltools` refuses
the installed torch, pin torch to the newest version coremltools supports and say so in the report.
CPU training is fine; the model is tiny.

## What to build

### 1. Data generation config (`pump_reader/dataset.py`)

- A `SyntheticDataset` that renders on the fly from PU.1's `render_glyph` with a seeded rng per
  index, returning `(tensor 3x48x32 float in [0,1], target 8 floats)` where the target is the 8
  segment bits (a–g, dp) of the `SegmentLabel`.
- **Technology sampled independently of make**, with an LCD-heavy prior (LCD 0.6, LED 0.3, VFD
  0.1): PU.1 binds technology to make by guess, and technology is a palette, not a geometry. Do this
  by resolving the profile and overriding its colour fields with another technology's palette - a
  small helper in `dataset.py`, no change to PU.1's profile constants.
- **Blank and dp-only classes are sampled at ≥ 8 % each**; the digits uniformly over the rest.
- **Crop jitter**: shift the glyph by up to ±20 % of the cell width and ±10 % of the height, and
  scale by 0.8–1.2, so a slicer that cuts a cell slightly off still classifies. PU.1's perspective
  already pushes glyphs off-canvas; keep that but make sure at least 70 % of a glyph stays inside.
- Validation split: a fixed seed range disjoint from training, 5 000 samples.

### 2. The model (`pump_reader/model.py`)

A small CNN: 3 conv blocks (16/32/64 channels, 3×3, BN, ReLU, 2×2 max-pool), global average pool,
a linear layer to **8 logits**. Sigmoid + BCE. Target ≤ 500 KB exported. Name it `SegmentNet`.

### 3. Training (`python -m pump_reader.train --steps N --seed S --out DIR`)

AdamW, cosine schedule, batch 128, augmentation on by construction. Logs every 200 steps: loss,
per-segment accuracy, **per-digit accuracy** (all 8 bits right, decoded via `SegmentLabel.digit`),
on the validation split. Saves `DIR/segmentnet.pt` and `DIR/metrics.json`. Default 6 000 steps;
report how long it took on this machine. A `--smoke` flag runs 20 steps for the test.

### 4. Export (`python -m pump_reader.export --checkpoint … --out ios/App/Resources/PumpSegments.mlpackage`)

`coremltools.convert` from a traced module, `ML Program`, input name `glyph` (image, 32×48 RGB,
scale 1/255), output name `segments` (8 sigmoid probabilities, so put the sigmoid IN the exported
graph), `minimum_deployment_target = iOS18`. Write the model's metadata: `author = "Tankbook"`,
`short_description` naming the segment order `abcdefg.`, `version` = git short sha.

### 5. Scoring on the real windows (`python -m pump_reader.score --model DIR/segmentnet.pt --windows Spike/ReceiptSpike/fixtures/pump/windows.json --fixtures Spike/ReceiptSpike/fixtures/pump`)

This is the one place the corpus is touched, and it is measurement only.

The annotation format (normalized coordinates over the EXIF-oriented image, `[[x,y]…]`):

```json
{ "pump-020-….jpg": { "rotationCW": 90,
    "windows": [ { "field": "total", "text": "0020,00",
                   "quad": [[x,y],[x,y],[x,y],[x,y]] } ] } }
```

- `quad` corners are TL, TR, BR, BL **in image space**; `rotationCW` (absent = 0) is how far to
  rotate the image clockwise for the text to read upright. Apply EXIF transpose (pillow-heif is
  installed for `.heic`), rotate, then rotate the quad with it.
- Warp the quad to a `48 × (48/… )` strip with a perspective transform, then slice it into **N
  equal cells** where N = the number of glyph cells in `text`: each digit is a cell; a `.` or `,`
  belongs to the preceding cell as its dp bit; a leading space is a blank cell. Resize each cell to
  32×48. This is deliberately naive - PU.4 builds the real slicer - and it is good enough to
  measure the classifier.
- `field` values: `total`, `liters`, `unitPrice`, `board`. Score **every** window whose `text` is
  non-empty; an empty `text` means the window is unreadable in the photo and is skipped.
- Report: per-segment accuracy, per-glyph accuracy (all 8 bits), per-window string accuracy
  (every cell right), and per-make (make = second dash-token of the filename, `pump-013-dresser…`
  → `dresser`; `pump-001.heic` → `unknown`). Then, **by name**: `pump-004` (Vision's confident
  misread), `pump-009` (zero-padded), `pump-013` and `pump-015` (the 9-as-4 pair), each with the
  string the model read next to the truth. Print, and write `ml/pump-reader/REPORT.md`.
- Also: `--dump DIR` writes every sliced cell as `DIR/<fixture>-<field>-<i>-<truth>-<read>.png`, so
  the orchestrator can open a sheet of them and see what the naive slicer fed the model.

### 6. Swift side - one test only

`ios/Tests/TankbookCoreTests/PumpSegmentsModelTests.swift`: **do not write this** - the package
cannot see app resources and PU.4 owns the Swift. Instead put in the report the exact
`MLModel(contentsOf:)` + `MLFeatureValue` snippet PU.4 should use, and the output shape you exported.

## Tests (`tests/`)

1. `test_dataset.py`: 1 000 samples contain every technology and every make; blank and dp-only
   each ≥ 5 % (oracle: the sampling priors); every tensor is in [0,1] and shaped 3×48×32.
2. `test_model.py`: `SegmentNet` forward on a batch of 4 gives shape (4, 8); parameter count
   < 130 000 (oracle: the ≤ 500 KB target at float32).
3. `test_train_smoke.py`: `--smoke` runs 20 steps, writes the checkpoint and `metrics.json`, and
   the final loss is below the initial (oracle: a learning model on a learnable task).
4. `test_export_roundtrip.py`: export the smoke checkpoint to a temp `.mlpackage` under `.out/`,
   load it with `coremltools.models.MLModel`, run one PU.1 render of `8` through both torch and
   Core ML; the 8 probabilities agree within 1e-3 (oracle: the torch model). Skip cleanly with a
   named reason if Core ML prediction is unavailable on this host - but it is macOS, so it should run.
5. `test_score_slicer.py`: build a fake `windows.json` around a PU.1 **row render** (you know its
   boxes), run the scorer's slicing on it, and assert cell count == glyph count and each cell's
   centre is inside the corresponding rendered box (oracle: PU.1's `render_row` boxes).

**Mutation named by this brief**: in `dataset.py`, drop the dp bit from the target (7 bits padded
with a constant 0). `test_export_roundtrip` must stay green (it is a round trip) and the trained
model's per-digit accuracy on the validation split must fall on every dp-carrying class -
demonstrate with `--smoke` numbers that `metrics.json` reports dp accuracy at chance. Paste both.

## Vacuous traps, named

- A smoke test that only asserts the files exist.
- Scoring the real windows with the slicer's cell count taken from the model rather than from
  the annotation - the count comes from `text`, always.
- A "per-make" table that silently drops fixtures whose make token is unknown.
- Reporting synthetic validation accuracy as if it were the held-out number.

## Out of scope

The locator, the slicer in Swift, row assignment, decimal recovery, `PumpPhotoGate`, any change to
`expected.csv` or `windows.json`, any change to PU.1's profile constants.

## Checks (by exit code)

- `cd ml/pump-reader && .venv/bin/pytest -q` → 0, count ≥ 14 (PU.1's 9 plus yours).
- A real training run (`--steps 6000`) → 0, with `metrics.json` committed-able under
  `ml/pump-reader/runs/<date>/` (small: metrics only, not the checkpoint - checkpoints go in
  `.out/`; the `.mlpackage` under `ios/App/Resources/` IS committed).
- `python -m pump_reader.score …` → 0 on whatever `windows.json` holds when you run it; if the
  file is absent, say so and run the scorer on the synthetic fake from test 5 instead.
- No iOS or backend gate: nothing compiled changed. Report that you did not run `scripts/gate.sh`.

## Standing fences

Never stash / `git checkout` / move files; never `git add` or commit. `pgrep -x` only, never `-f`.
You are not alone in the checkout: `Spike/ReceiptSpike/fixtures/pump/windows.json` may change under
you - read it fresh each run, never write it. No `/tmp`.

## Report back

Exit codes (`echo $?`), pytest count, run-or-only-written per test, training wall time and final
validation per-segment / per-digit accuracy, the held-out numbers from `score` (or the statement that
`windows.json` was absent/partial and how many fixtures it held), the dp-mutation numbers, the
exported model's size in KB, the Swift snippet, and **anything you found and did not fix**.
