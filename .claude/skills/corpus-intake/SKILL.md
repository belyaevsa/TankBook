---
name: corpus-intake
description: Register new captures (pump display photos, receipts, Live Photo records, videos) in the recognition corpus - naming, EXIF stripping, truth rows, window annotations, pairing, the S3 media store, and the ratchet re-measure that every corpus change requires. Use whenever files land in Spike/ReceiptSpike/fixtures/ or the owner says "add these to the corpus".
---

# Corpus intake

The corpus is the recognition pipeline's only honest measurement, and it is **held-out**: nothing
trains on it. A new capture therefore changes what the ratchets measure, and every step below
exists because skipping it once produced a wrong number. Do them in order.

## 0. Sort what arrived

For each file decide which of the four it is; the owner usually drops a mixed batch:

| Kind | Goes to | Tracked in git? |
|---|---|---|
| Pump display still (`.HEIC`/`.jpg`) | `Spike/ReceiptSpike/fixtures/pump/pump-NNN-<make>-<station>-<detail>-<country>.jpg` | yes |
| Receipt still | `Spike/ReceiptSpike/fixtures/receipts/receipt-NNN-<station>-<detail>-<country>.jpg` | yes |
| Live Photo record (`.mov` beside a HEIC) | `Spike/ReceiptSpike/fixtures/pump-live/live-<IMGnumber>.mov` | **no** - the `tankbook-corpus` bucket |
| A plain video (not from the owner's camera roll) | `pump-live/video-NNN-<make>-<station>-<detail>-<country>.mp4`, **cut to the seconds that show the display** and re-encoded without audio or metadata (`ffmpeg -ss … -t … -an -map_metadata -1 -c:v libx264 -crf 18`); a person in the rest of the clip never enters the corpus | **no** - the bucket |
| A HEIC that is a copy of a still already in the corpus | delete it | - |

Match copies by perceptual hash first (`dhash` at 16 px, distance 0 = identical) and by reading
the digits second; a still shot again at another angle is "the same fill", not a copy. Next ids:
`ls fixtures/pump | grep -c ^pump-` and the same for receipts.

## 1. Convert and strip (product owner, 2026-09-19)

Every still enters as **JPEG with the orientation baked in and every EXIF field removed** - no
GPS, device or timestamp in the corpus:

```python
im = ImageOps.exif_transpose(Image.open(src)).convert("RGB"); im.save(dst, "JPEG", quality=92)
```
Check: `len(Image.open(dst).info.get("exif", b"")) == 0`. Movies keep their container; they are
not in git.

## 2. Truth

Append a row to the class's `expected.csv` (`filename,liters,unitPrice,total,fuelKind,currency`)
and import it (`scripts/corpus_db.py import`); the database is the write store and the file is
its dump. A pump row never asserts `fuelKind`; a receipt row does. **The receipt is the truth for a fill**
(decision 6): a display that rounds a total gets the receipt's value in the CSV and a
`csvDisagrees` note in `windows.json`. A cell you cannot read stays blank (unscored), never a
guess. Where a pump and a receipt show one fill, name both files `…-pair-…` and register the pair
in `ios/Tests/TankbookCoreTests/CorpusPairTests.swift`.

## 2b. The split (decision 9, product owner 2026-09-19; `heldout2` 2026-09-23)

Every still gets a row in `pump/split.csv`. Three values, and which one is the owner's call when
they name it - otherwise the rule below:

| Split | What it is | A new still joins it when |
|---|---|---|
| `train` | the classifier's real glyphs and the detector's boxes | **the default** - everything not named below |
| `heldout2` | the second frozen draw: no model trains on it and **no constant is tuned against it** - measured only when a change is judged | the capture shows a condition the heldout sets under-represent (rain, night, a new make or country) **and** no model has trained on it yet. Pick **whole fills** - every angle of one transaction together (`pump-322`/`323`) - so no display content is shared with a train still. A few per batch, not all: the rest are train so the classifier sees the condition too |
| `heldout` | the first frozen draw, 68 stills, what the model-scored ratchets measure | **never** - frozen; a new row would move a mark for no reason |

A Live record follows its still (`paired_records` carries the still's split to its frames).
**Video frames never go to a heldout one by one**: adjacent frames are near-copies, so a frame
held out of a train video is measured on what the model saw a few frames away. A video could only
join whole, and none does yet - `videos` has no split column and `pump_reader.track` writes every
video frame as `train`. A still that a model has trained on never moves to a heldout set, and a
heldout still never moves back (`docs/EXTRACTION.md` → decision 9 and its amendments).

Every trainer reads `split = 'train'` (or `isTrain`), `corpus_db.heldout_names` returns every
non-train still for the exports' disjointness guards, and `detdata` writes a `heldout2` still to
neither the detector's train nor its validation directory. Count: `scripts/corpus_db.py sql
"select split, count(*) from fixtures where kind='pump' group by 1"`.

## 3. Window annotations (pump stills only; orchestrator's own work - agents cannot see)

`windows.json` gets one entry per still: `field` (`total` / `liters` / `unitPrice` / `board`),
`text` exactly as the display shows it (zero padding and the comma kept, empty when unreadable),
`quad` TL/TR/BR/BL normalised over the oriented image, `rotationCW` when the text reads upright
only after a clockwise turn. **Draw them in the annotator** - `ml/pump-reader/.venv/bin/python
tools/pump-annotate/server.py`, then open the URL it prints (`tools/pump-annotate/README.md`):
drag a rectangle per window, drag corners to tighten, type what the display shows, `Save`. It
writes the entry through the database and dumps the JSON, so the diff is only your windows. The product
owner can annotate too - the page needs no reader knowledge, only the conventions below.
Conventions and the declared-exception keys are in the file's `_about`. Then (also the page's
`Check` button):

```
scripts/pump-windows-check.py --check      # strings vs expected.csv, arithmetic, quads in [0,1]
```

## 4. The media store

```
scripts/corpus-sync.py push                # the movies to the bucket; size+MD5 skip what is there
                                           # - also rebuilds corpus.sqlite and uploads it with the
                                           #   annotation files under index/
scripts/corpus_db.py sql "select name, present, in_bucket, paired_fixture from media where paired_fixture is null"
                                           # what is still unpaired, straight from the database
```
**The database (`corpus.sqlite`) is the write store and the CSV / JSON are its dump** - write
through the annotator or `corpus_db`, never by hand; `scripts/corpus_db.py dump` writes the files
and `check` fails a stale one, and `import` is the one direction back from the files. The
database is committed beside the files it dumps.
Access (a static key for `tankbook-corpus-rw`, kept in `~/.config/tankbook/corpus-s3.env`) is
described in `fixtures/pump-live/README.md` → Access. Extract frames locally with the `ffmpeg`
line there; `frames/` is gitignored, and `push` uploads them with their key on `frames.s3_key`.

## 5. READMEs

Each class README gets a dated "Added" section saying what the images are, what is special
(glare, rotation, a truncated total, a pair), and the measured numbers before → after (step 6).
`pump-live/README.md` gets a row per movie with its frame count and the still it pairs with.

Every new image in `receipts/`, `pump/`, `fiscal/` or `screenshots/` is also added to
`ios/Tests/TankbookCoreTests/PostSweepCorpusAdditions.swift` under its class, with a dated comment:
the LLM arm's A/B sweep is frozen, and `CorpusABTests` fails on any image that is neither swept nor
declared - a skipped declaration turned `swift test` red for 57 images across batches 8-10 (PU.80).
The PaddleOCR arm is retired and needs nothing.

## 6. Re-measure - the step that is not optional, and the runtime that gates it

Adding a fixture moves the corpus score, and two places assert the live score by constant. **The
marks are measurements of one Vision runtime, macOS 26** (`docs/TESTING.md` → "runtime-specific";
`VisionMeasuredRuntime.measuredMajorVersion`). On any other macOS the four measured suites skip
with the reason printed, and you may **bump the totals only** (they are corpus facts: pump cells
= liters + unitPrice + total asserted; receipts = 5 cells per row) and leave hits, committed and
committed-correct where they are, saying so in `high-water.json`'s dated `_note`. The next run on
macOS 26 records the hits. Never write a 27-measured hit into a 26 mark.

- `Spike/ReceiptSpike/fixtures/high-water.json` (per class hits/total) - the ratchet
  `AccuracyRatchetTests` compares against it; raise `total`, and `hits` only if the parser
  actually reads the new cells (run the suite on the measured runtime to find out).
- `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` (`measuredNumericTotal`, `measuredCommitted`,
  `measuredCommittedCorrect`, `measuredNumericHits`) - the gate; its test asserts they equal the
  live pump score.

Then the reader's own ratchets, which print their numbers: `swift test --filter
"PumpReaderHarnessTests|PumpReadingLawTests|PumpReaderPipelineTests|PumpRowAssignmentTests"`
(count agreement, the law's oracle ceiling, the real-cells gate-mirror, row assignment). A floor
that is now exceeded moves **up** to the measured value; a floor that a new hard fixture drops
below is a finding to record, never a floor to lower silently.

## 7. Commit

One commit, `git add` by explicit path (never `-A` - the movies must stay out), message naming
the batch and the before → after numbers. `scripts/tasks-index.py --check` if a task row was
ticked.

## What goes wrong

- A movie committed to git (235 MB once); the `.gitignore` covers `pump-live/*.mov|*.heic`.
- A rotated fixture annotated 270 where 90 is right - the warped strips show it upside down;
  look at them (`ios/.build/pump-reader-out/strips/`).
- A truth row typed from the receipt while the display shows something else (`pump-003`) -
  declare it, do not average it.
- The ratchet constants left where they were: the next `swift test` on the measured runtime
  fails, or worse, passes on a stale total.
