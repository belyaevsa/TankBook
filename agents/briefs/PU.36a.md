# PU.36a - the corpus goes SQLite-first: schema, import, dump, check, and the annotator on it

**Parent journey:** J4 (the corpus is the pump reader's). **Rows:** `docs/TASKS.md` → PU.36a
(this), PU.36b (the Python trainers on the database), PU.36c (the Swift writer, sync, docs).
**Decided by the product owner 2026-09-21:** *"make this sqlite-first approach and dump to
json data"* - the database is the canonical write store; the JSON/CSV files are a
deterministic dump of it, committed beside it so diffs stay readable and the Swift ratchets
keep reading files unchanged. **Read first:** `scripts/corpus_db.py` (the derived database
today - it becomes the canonical one), `tools/pump-annotate/server.py` (every write route),
`tools/pump-annotate/README.md`, `Spike/ReceiptSpike/fixtures/pump-live/README.md` (records,
videos, frames), `ml/pump-reader/CORRECTIONS.md`.

## The situation

Seven text formats hold the corpus's mutable state, written by three tools with whole-file
rewrites: `pump/windows.json` (entries, windows, `liveAnchors`, tracking), `pump/expected.csv`
(truth rows), `pump-live/videos.json` (reference frame, quads, anchors, `firstFrame`/`lastFrame`,
reviewed), `pump-live/video-labels.json`, `pump-live/frames/<stem>/windows.json` (tracked frames,
per-frame windows, `verified`, `_anchors`, `_split`), `pump-live/frames/<stem>/readings.json`,
`pump-live/corrections.jsonl`. `corpus.sqlite` is rebuilt from them (`corpus_db.py build`) and
holds a subset. This slice inverts the direction for the annotator: **the database is written,
the files are dumped from it.** The trainers (PU.36b) and the Swift label writer (PU.36c) come
after, so until they land the dump must reproduce today's files byte-for-byte - that is the
regression test for this slice.

## Where you may write

`scripts/corpus_db.py`, `tools/pump-annotate/server.py`, `tools/pump-annotate/index.html` (only
if a route's shape changes), `tools/pump-annotate/README.md`, `scripts/pump-windows-check.py`
(only to read from the dump, which it already does - probably nothing), a new
`scripts/corpus_db_test.py` (pytest, run with `ml/pump-reader/.venv/bin/pytest`), `docs/TASKS.md`
nothing (the orchestrator ticks). **Never write the corpus files under `Spike/` by hand** - the
owner is annotating in a running server (port 8765) while you work; do not start a server on
8765; use another port for your own checks. Do not touch `ml/pump-reader/src/` (PU.36b), the
Swift tests (PU.36c), `scripts/corpus-sync.py` (PU.36c).

## Write code first, explore second

## What to build

1. **The schema, versioned.** Extend `corpus_db.py`'s schema (keep the existing tables and
   columns - the report and the annotator read them) with: `schema_version` in `meta`;
   `windows` gains nothing; `entries` gains `tracking text`; a new `live_anchors (fixture,
   record, frame, ord, field, quad)`; `videos (stem primary key, reference, unitPrice, currency,
   reviewed, firstFrame, lastFrame, note)`, `video_windows (stem, ord, field, quad)`,
   `video_anchors (stem, frame, ord, field, quad)`; `frames (record primary key-ish: record,
   frame; still, split, inliers, anchor, verified)` with `frame_windows (record, frame, ord,
   field, text, quad, legibility)`; `labels (video, frame, field, text, source)`; `readings
   (record, frame, field, text, closes)`; `corrections (at, build, kind, still, record, video,
   frame, field, proposedBy, proposed, final, iou, inliers)`. Every JSON-carried value that has
   no column goes into a `extra text` (JSON) column on its table, so the dump loses nothing -
   that is how byte-identity is achieved, not by inventing columns for every key.
2. **`corpus_db.py import`** (the old `build`, renamed; keep `build` as an alias for a
   release): reads every file above into the database. Idempotent.
3. **`corpus_db.py dump`**: writes every file above FROM the database, in exactly the formatting
   the writers use today (`json.dumps(indent=1)`, sort keys where the writer sorts,
   `ensure_ascii` as the writer does, trailing newline where the file has one - read
   `save_windows`, the video routes and `track.py`'s writer for each). **`import` followed by
   `dump` on the committed corpus must produce no diff** (`git diff --stat Spike/` empty). That
   is the first check and the one that proves the schema carries everything.
4. **`corpus_db.py check`**: fails (exit 1, names the file) when a dumped file differs from what
   the database would dump - the staleness gate, run by `scripts/gate.sh`? **No** - the iOS gate
   is not the corpus gate; add it to `scripts/pump-windows-check.py --check`'s exit instead
   (that script is what the annotator's Check button and the corpus intake skill run).
5. **The annotator writes the database.** Every `PUT`/`POST` route in `server.py` that writes a
   file (`/api/entry/<still>`, `/api/entry/<video>`, `/api/video-anchor/...`, `/api/video-label/...`,
   `/api/retrack-now`, the corrections ledger) writes rows through `corpus_db.py`'s functions
   (import it as a module: `corpus_db.save_entry(...)`, `corpus_db.pin_frame(...)`, ...) and then
   calls `dump` for the files that changed (a whole dump is fine if it is under a second; measure
   it). Reads may stay on the files until the dump is proven, but the write path is the database.
   `track.py` still writes `frames/<stem>/windows.json` in this slice (PU.36b moves it); so after a
   retrack the server **imports** that record's file into `frames`/`frame_windows` - the one
   file-to-database direction that remains, named in a comment as PU.36b's to remove.
6. **Concurrency**: `sqlite3` with `PRAGMA journal_mode=WAL` and `busy_timeout=5000`; the
   server's writes in one transaction per request.

## Explicitly out of scope

The Python trainers (`track.py`, `frames.py`, `realglyphs.py`, `detdata.py`, `score.py`,
`calibrate.py` keep reading files - PU.36b), `PumpVideoReadTests` (writes labels/readings as
files - PU.36c imports them), `corpus-sync.py` (PU.36c), the Swift readers (never: they read the
dump), README prose.

## Tests

- `scripts/corpus_db_test.py` (pytest): import → dump round trip on a **copy** of the corpus
  in a temp directory produces byte-identical files (assert per file; name the first mismatch
  with a unified diff of the first 20 lines); a `save_entry` + `dump` changes only the one still's
  block; `pin_frame` writes a `frames` row with `verified = 1` and a `corrections` row when the
  quad moved; `check` exits 1 after a file is edited by hand and 0 after `dump`.
- **Mutation named by this brief:** in `dump`, change `indent=1` to `indent=2` for
  `windows.json` - the round-trip test goes red with the diff. Paste red and green verbatim.
- `python3 scripts/pump-windows-check.py --check` → 0 on the committed corpus after import + dump.
- Vacuous traps: a round-trip test that dumps only the tables it imported (it must dump every
  file); a check that compares the database to itself.

## Checks (by exit code)

`ml/pump-reader/.venv/bin/pytest scripts/corpus_db_test.py -q` → 0 with the count;
`python3 scripts/corpus_db.py import && python3 scripts/corpus_db.py dump && git diff --stat
Spike/` → **empty**; `python3 scripts/pump-windows-check.py --check` → 0; the annotator started
on port 8799 answers `GET /api/fixtures` and a `PUT /api/entry/<still>` with an unchanged body
leaves `git diff Spike/` empty. No iOS gate (nothing in `ios/` changes) - say so.

## Report back

The schema (tables and columns) as built; the round-trip result (files compared, identical or
the diff); dump time; every route moved to the database and the one remaining
file-to-database import; the mutation red/green verbatim; the pytest count; anything found
and not fixed with the row that owns it (PU.36b/c or new).
