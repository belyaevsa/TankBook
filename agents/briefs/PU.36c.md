# PU.36c - the Swift writer, the frames in the bucket, sync and the docs

**Parent journey:** J4. **Rows:** `docs/TASKS.md` → PU.36c (PU.36a `3dbda379`, PU.36b
`c4e14564` shipped). **Read first:** `scripts/corpus_db.py` (the API: `connect`, `save_labels`,
`save_tracked`, `dump`, `check`, the schema at the top - `frames` has `record, frame, still,
split, inliers, anchor, verified, keys, extra, ord`), `scripts/corpus-sync.py`,
`ios/Tests/TankbookCoreTests/PumpVideoReadTests.swift`, `Spike/ReceiptSpike/fixtures/pump-live/README.md`,
`.claude/skills/corpus-intake/SKILL.md`, `tools/pump-annotate/README.md`, `ml/pump-reader/CORRECTIONS.md`.

## The situation

Three things still bypass the database or are missing from it:

1. **`PumpVideoReadTests`** (`PUMP_VIDEO_READ=1`) writes `pump-live/video-labels.json` and
   `frames/<video>/readings.json` as files. The database does not see them, and the next `dump`
   overwrites them with the database's older rows - a label the reader wrote can be silently
   reverted. The annotator's `/api/rerun` read phase runs this test, so the loss is reachable
   from the UI.
2. **The frames are on this Mac only.** `frames/` is gitignored (4.4 GB, 23 080 JPEGs over 161
   records) and `corpus-sync.py` pushes only `live-*.mov/.heic`, `video-*.mp4` and the index
   files. The hand-placed anchors and the trained models were cut from these exact files;
   re-extraction is deterministic (`pump_reader.frames`) but not free, and the database has no
   link to them (`frames` has no key).
3. **The docs still describe the files as the store.**

## Where you may write

`ios/Tests/TankbookCoreTests/PumpVideoReadTests.swift`, `scripts/corpus_db.py` (an
`import-readings` command and an `s3_key` column on `frames` via a schema migration - bump
`schema_version`, add the column with `alter table` when absent; the dump does NOT include the
key, so the JSON files stay byte-identical), `scripts/corpus_db_test.py`, `scripts/corpus-sync.py`,
`Spike/ReceiptSpike/fixtures/pump-live/README.md` and `pump/README.md` (the "how the corpus is
stored" prose only - never a fixture row), `.claude/skills/corpus-intake/SKILL.md`,
`tools/pump-annotate/README.md`, `ml/pump-reader/CORRECTIONS.md` (§3's `--hard <path>` sketch →
`--hard-weight`, §8), `ml/pump-reader/README.md`. **Never write a corpus file by hand**; the
owner's annotator (8765) is running - do not start one there. Do not touch the bucket without
`DRY_RUN` first (below).

## Write code first, explore second

## What to build

1. **The Swift writer goes through the database.** `PumpVideoReadTests` writes its readings and
   arithmetic labels to a **staging file** (`ios/.build/pump-reader-out/video-read/<stem>.json`,
   the same shape as today's per-frame readings plus the labels it would write) and then invokes
   `python3 scripts/corpus_db.py import-readings <that file>` (via `Process`), which writes
   `readings` and `labels` (arithmetic rows only; an owner row is never overwritten - the rule
   `save_labels` already has) in one transaction and dumps the two files. The test's acceptance
   is unchanged (the summary lines it prints). If `python3` is unavailable the test fails loudly
   with the path it wanted to import - never a silent file write.
2. **The frames in the bucket.** `corpus-sync.py` gains a frames set: every JPEG under
   `frames/<record>/` for a record that is registered (a `media` row, i.e. its clip is in the
   README) goes to `pump-live/frames/<record>/<NNN>.jpg` (the `sheet.jpg` too). After a
   successful upload, `frames.s3_key` is set for that row. `pull` fetches a record's frames only
   on request (`--frames <record>` or `--frames all`) - a fresh machine can re-extract instead.
   Skip what is already there by size (as `push` does now). **Run with `DRY_RUN=1` first** and
   report the count and bytes it would send; then push for real (the credentials are in
   `~/.config/tankbook/corpus-s3.env` - `set -a; . ~/.config/tankbook/corpus-s3.env; set +a`;
   never print or copy them). 4.4 GB at whatever the uplink gives - report the wall time.
3. **The docs**: each README's storage paragraph says the database is the write store, the files
   its dump (`corpus_db.py dump`/`check`), the frames' bucket keys live on `frames.s3_key`; the
   intake skill's steps write through the annotator or `corpus_db`, never the files; the
   annotator README drops "in the file's own formatting" for "through the database, dumped";
   CORRECTIONS.md §3 names `--hard-weight` as built.

## Explicitly out of scope

The schema beyond the one column; the annotator's routes; the trainers; the models.

## Tests

- `scripts/corpus_db_test.py`: `import-readings` on a staging file adds readings and arithmetic
  labels, leaves an existing owner label untouched, and the dump of `video-labels.json` /
  `readings.json` matches what the old writer produced for the same input (byte-identical -
  take the old writer's output from git: `git show HEAD:...video-labels.json`); the migration
  adds `s3_key` to an older database without losing rows.
- `PumpVideoReadTests` with `PUMP_VIDEO_READ=1 PUMP_VIDEO_READ_ONLY=video-011` (60 frames, the
  shortest clip): `corpus_db.py check` → 0 afterwards and `git diff --stat Spike/` shows only
  that clip's label/readings changes (the owner's concurrent edits aside - name them if they
  are there).
- **Mutation named by this brief:** in `import-readings`, let an arithmetic row overwrite an
  owner row - the "owner label untouched" test goes red. Paste red and green verbatim.
- Vacuous traps: an import test with no owner row present; a sync dry run that counts zero.

## Checks (by exit code)

`ml/pump-reader/.venv/bin/pytest -q scripts/corpus_db_test.py` → 0 with the count; `swift build`
in `ios/` → 0 and `swift test --filter PumpVideoReadTests` with the env above → 0 (the only
Swift change is a test file; `scripts/gate.sh`'s package steps are enough - run `swift build`
and `swiftlint lint` from the root, report both exits; the app build is untouched); the sync
dry run's count; the real push's count and time; `corpus_db.py check` → 0.

## Report back

The staging-file shape; the import command's transaction; the sync counts (dry, then real) and
wall time, and how many `frames.s3_key` rows were set; the mutation red/green verbatim; the test
counts; each doc paragraph changed (file and heading); anything found and not fixed with the row
that owns it.
