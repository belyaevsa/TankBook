# PU.36b - the Python trainers on the database

**Parent journey:** J4. **Rows:** `docs/TASKS.md` → PU.36b (this; PU.36a shipped as
`3dbda379`, PU.36c follows). **Read first:** `scripts/corpus_db.py` end to end - it is the
corpus's API now: `connect`, `import_corpus`, `render`/`dump`, `save_*`, `pin_frame`,
`import_frames`, `save_labels`, `add_corrections`; the schema at the top (tables `fixtures,
entries, windows, live_anchors, media, pairs, videos, video_windows, video_anchors, frames,
frame_windows, labels, readings, corrections, meta`). Then `ml/pump-reader/CORRECTIONS.md`
§3 (the two sampler changes this row implements) and `ml/pump-reader/REPORT.md` → "Round 10"
(why).

## The situation

The database is the write store and the files are its dump (PU.36a). The Python package still
reads the files and `track.py` still WRITES one - `frames/<stem>/windows.json` - which the
server then imports (`corpus_db.import_frames`, the one remaining file-to-database direction,
marked as this row's to remove). This row moves every Python reader and writer onto the
database, and while it is in the sampler it adds the two changes `CORRECTIONS.md` §3 asks for.

## Where you may write

`ml/pump-reader/src/pump_reader/{track,frames,realglyphs,detdata,score,calibrate}.py`,
`scripts/corrections-report.py`, `scripts/corpus_db.py` (new query/write helpers only - do not
change the schema or the dump), `ml/pump-reader/tests/` (pytest), `scripts/corpus_db_test.py`
(extend), `ml/pump-reader/README.md` and `REPORT.md` ("PU.36b"). **Never write a file under
`Spike/` except through `corpus_db`** - the owner is annotating in a running server (port 8765)
that writes the database; your writes go through the same module and its transactions. Do not
start a server on 8765. **Not** `tools/pump-annotate/`, the Swift tree, `corpus-sync.py`.

## Write code first, explore second

## What to build

1. **`track.py` writes `frames` / `frame_windows`** (and reads its inputs - the still's windows,
   `live_anchors`, `videos`/`video_windows`/`video_anchors`, `firstFrame`/`lastFrame` - from the
   database) through a `corpus_db.save_tracked(record, tracked_dict)` helper you add, in one
   transaction per record; then `corpus_db.dump` for that record's file so the Swift readers
   see it. Remove the server's `import_frames` call path's reason to exist: after this,
   `import_frames` is only for the one-time import of a folder tracked before this row (leave
   it, comment it so). The `sheet.jpg` contact sheet stays a file - it is a picture.
2. **`frames.py`** reads `firstFrame`/`lastFrame` from `videos`; writes `movie.json` as today
   (a derived artefact, not corpus state).
3. **`realglyphs.py`** reads windows, frames, frame windows and labels from the database (the
   Swift export `train-slices.json` / `train-videos.json` stays its input for the strips - the
   database tells it which windows and frames are TRAIN, labelled and not `tracking = bad`).
   Two sampler changes, each a command-line option with the default OFF so the export is
   reproducible first:
   - `--cap-fixture 0.02`: no single fixture (still or record or video) contributes more than
     this share of the real pool; cells beyond the cap are dropped by uniform subsampling with a
     fixed seed.
   - `--hard-weight 4`: a frame or still with a `corrections` row of kind `text` and
     `proposedBy = reader` (a pre-fill the operator corrected, `CORRECTIONS.md` §3) has its cells
     repeated this many times in the pool. The manifest records the weight per cell.
   Print the pool's composition per make and the top-10 fixtures by share, before and after.
4. **`detdata.py`** builds its records from `windows` / `frames` / `frame_windows` / `labels`
   (labelled or `verified` frames, as today) and the split from `fixtures.split`; the heldout
   assertion stays.
5. **`score.py`**, **`calibrate.py`**, **`scripts/corrections-report.py`** read from the database.
6. **Reproduce today's counts from the database** with the options off - the acceptance:
   `detdata` **926 images / 3 126 boxes** (`.out/det/counts.json`), `realglyphs` **40 755 cells**
   (`.out/real-r10/manifest.json` - compare per-fixture counts, not just the total).

## Explicitly out of scope

Retraining; the schema; the dump; the annotator; the Swift writer (PU.36c); sync (PU.36c).

## Tests

- `ml/pump-reader/.venv/bin/pytest -q` over `ml/pump-reader/tests` and `scripts/corpus_db_test.py`:
  `save_tracked` + `dump` reproduces a record's `windows.json` byte-identically (take a record
  already in the database, round-trip it); `realglyphs --cap-fixture` on a synthetic manifest
  with one fixture at 50 % caps it at the share; `--hard-weight 3` triples a corrected frame's
  cells and leaves the rest at 1; `detdata` from a temp database with one train still, one
  heldout still and one labelled video frame writes 2 train records and 1 heldout record and
  asserts the heldout is not in train.
- **Mutation named by this brief:** in `--hard-weight`, apply the weight to every frame instead
  of the corrected ones - the "leaves the rest at 1" assertion goes red. Paste red and green
  verbatim.
- Vacuous traps: a round-trip test on an empty record; a cap test where no fixture exceeds
  the cap.

## Checks (by exit code)

`pytest -q` → 0 with the count; `python -m pump_reader.detdata` → the counts above;
`python -m pump_reader.realglyphs --also ../../ios/.build/pump-reader-out/train/train-videos.json
--out .out/real-r11` → 40 755 (the Swift export already exists in `ios/.build/pump-reader-out`;
do not re-run the Swift export - it takes 15 min and the tree may be building); `python -m
pump_reader.track --only live-5860` then `python3 scripts/corpus_db.py check` → 0 and `git diff
--stat Spike/ReceiptSpike/fixtures/pump-live/frames/live-5860/` → empty (the record round-trips).
No iOS gate (nothing in `ios/` changes) - say so.

## Report back

Each reader/writer moved, with the query it now runs; the counts reproduced (per-fixture diff
for realglyphs if any); the sampler composition before/after with the options on; the
round-trip on live-5860; the mutation red/green verbatim; pytest count; anything found and
not fixed with the row that owns it.
