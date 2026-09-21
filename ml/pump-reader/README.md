# pump-reader (PU.1) – the synthetic seven-segment renderer

Renders labelled seven-segment glyphs and number rows for the pump-display
reader (`docs/EXTRACTION.md` → "The pump reader"). This row is only the data
source: no model is trained here (PU.3) and no Swift is written here (PU.4/PU.5).

## What it renders

- A **glyph crop** (32×48) per draw, labelled with an **8-bit segment label**
  (bit 0 = a … bit 6 = g, bit 7 = decimal point).
- With `--rows`, a **number row** (e.g. `12.38`, ` 40.00`, zero-padded variants)
  plus one axis-aligned box per glyph, transformed by the same perspective
  homography as the image so the boxes are true.

Five make profiles (`gilbarco`, `wayne`, `dresser`, `scheidt`, `tokheim`) carry
segment geometry (length/thickness ratio, gap, slant, pitch, decimal-point size
and offset) and a display technology (`lcd` / `led` / `vfd` with on/off colour
ranges and bloom). Each profile's docstring records the geometry as a **guess**
to be revisited by PU.6 from measured failures – the true geometry is unknown.

Augmentations (each with a sampled probability and strength): specular glare,
gaussian + motion blur, perspective tilt, LCD ghosting, canopy reflection,
sensor noise and exposure, partial occlusion. All sampling is seeded from the
passed rng, so `--seed` makes a whole run reproducible.

The real corpus under `Spike/ReceiptSpike/fixtures/pump/` is held-out; nothing
here is fitted to it.

## Setup

Python 3.12 only (the ML packages the next row needs do not run on 3.14 yet):

```
cd ml/pump-reader
/opt/homebrew/bin/python3.12 -m venv .venv
.venv/bin/pip install -e '.[dev]'
```

## Run

```
.venv/bin/python -m pump_reader.render --count N --seed S --out DIR [--make NAME] [--rows]
```

Writes `DIR/glyphs/NNNNNN.png` and `DIR/labels.csv`
(`file,label,digit,make,technology`); with `--rows` also `DIR/rows/NNNNNN.png`
and `DIR/rows.json`.

## The corpus database

The corpus is SQLite-first (`scripts/corpus_db.py`, `Spike/ReceiptSpike/fixtures/corpus.sqlite`);
the text files are a deterministic dump of it. Every trainer reads and writes through
`corpus_db`, the Swift reader writes its readings and arithmetic labels through
`corpus_db.py import-readings`, and the frames' bucket keys live on `frames.s3_key`:

```
.venv/bin/python -m pump_reader.track --only live-5860        # writes frames/frame_windows, dumps the file
.venv/bin/python -m pump_reader.frames                        # firstFrame/lastFrame from videos
.venv/bin/python -m pump_reader.detdata                       # detector boxes from windows/frames/labels
.venv/bin/python -m pump_reader.realglyphs \
    --also ../../ios/.build/pump-reader-out/train/train-videos.json
```

`realglyphs` has two sampler levers, both off by default so the export is reproducible first
(`CORRECTIONS.md` section 3): `--cap-fixture` caps any one still, record or video's share of the
pool by uniform subsampling, and `--hard-weight` repeats the cells of a frame or still the
operator corrected a reader pre-fill on. The manifest records each cell's weight.

## Test

```
cd ml/pump-reader && .venv/bin/pytest -q
```
