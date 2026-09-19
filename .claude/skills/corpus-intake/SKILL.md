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

Append a row to the class's `expected.csv` (`filename,liters,unitPrice,total,fuelKind,currency`).
A pump row never asserts `fuelKind`; a receipt row does. **The receipt is the truth for a fill**
(decision 6): a display that rounds a total gets the receipt's value in the CSV and a
`csvDisagrees` note in `windows.json`. A cell you cannot read stays blank (unscored), never a
guess. Where a pump and a receipt show one fill, name both files `…-pair-…` and register the pair
in `ios/Tests/TankbookCoreTests/CorpusPairTests.swift`.

## 2b. The split (decision 9, product owner 2026-09-19)

`pump/split.csv` names the **frozen heldout set** - 64 of the 211 stills, drawn once with a seed
and never redrawn - and every still added after it is **train**: append `<filename>,train` to
the file (a still absent from it is read as train anyway; the row keeps the list complete). Never
add a heldout row: the model-scored ratchets (`PumpReaderHarnessTests`, `PumpReaderPipelineTests`,
`PumpDisplayCaptureTests`) run on the heldout set only, so a fresh still joining it would move a
measurement for no reason, and a train still is what the classifier's real glyphs come from.
`scripts/corpus_db.py sql "select split, count(*) from fixtures where kind='pump' group by 1"`.

## 3. Window annotations (pump stills only; orchestrator's own work - agents cannot see)

`windows.json` gets one entry per still: `field` (`total` / `liters` / `unitPrice` / `board`),
`text` exactly as the display shows it (zero padding and the comma kept, empty when unreadable),
`quad` TL/TR/BR/BL normalised over the oriented image, `rotationCW` when the text reads upright
only after a clockwise turn. **Draw them in the annotator** - `ml/pump-reader/.venv/bin/python
tools/pump-annotate/server.py`, then open the URL it prints (`tools/pump-annotate/README.md`):
drag a rectangle per window, drag corners to tighten, type what the display shows, `Save`. It
writes the JSON in the committed formatting, so the diff is only your windows. The product
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
`corpus.sqlite` is derived from the git files and committed beside them - never edit it; edit the CSV / JSON /
README and rebuild (`scripts/corpus_db.py build`; the annotator does it on save).
Access (a static key for `tankbook-corpus-rw`, kept in `~/.config/tankbook/corpus-s3.env`) is
described in `fixtures/pump-live/README.md` → Access. Extract frames locally with the `ffmpeg`
line there; `frames/` is gitignored.

## 5. READMEs

Each class README gets a dated "Added" section saying what the images are, what is special
(glare, rotation, a truncated total, a pair), and the measured numbers before → after (step 6).
`pump-live/README.md` gets a row per movie with its frame count and the still it pairs with.

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
