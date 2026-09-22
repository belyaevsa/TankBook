# PU.50 - The annotator's compare view: two models on one photo

Row: `docs/TASKS.md` -> PU.50. Product owner, 2026-09-22, after PU.48 spent a day judging a
candidate by its committed count: *"a new view where we will compare work of different models on a
sample picture. Two screens, one model against another. Visually - what was expected, what a model
saw, annotated. I need logs and steps on the view of each model."*

## Where you may write

`tools/pump-annotate/index.html`, `server.py`, `README.md`, `test_server.py` (ADD tests, never
rewrite - other rows have written it). Scratch: `ml/pump-reader/.out/pu50/` (playwright goes
there). **Nothing under `ios/`, `Spike/` or `ml/pump-reader/src`** - PU.51 is editing the reader
core at the same time and the corpus is another session's live work.

## What exists (read first, in order)

1. `tools/pump-annotate/README.md` - the whole tool; `?` in the page opens the key table.
2. `server.py`: `detectors()` (PU.46 - every model with a **version**: folder tag, write date, the
   corpus generation from `counts.json`, sha8), `/api/detectors`, `/api/read` (runs `pump-read`
   with a chosen, validated detector), `/api/slice` and `slicer.py` (the resident slicer pattern -
   reuse it for the compare sweep rather than launching a process per still).
3. `index.html`: `runReader(live)` and what it does with the reply (`readRows`, `readCells`, the
   overlay in `draw()`), the rail modes, `toggleHelp`.
4. `ios/Sources/PumpReadTool/main.swift` - **what a live reply actually carries**: `rows`
   (quad, cells, field, detected), `rowTexts` (digits + per-cell margins), `committed`,
   `cellsPerRow`, `timingsMs` (detectorOnly, candidates, verify, read, law, appDecide,
   appClassifyAndRead, textLines, readPhoto), `appDecision`. PU.51 is adding `abstainReason` -
   render it when present, never require it.
5. `ml/pump-reader/REPORT.md` -> the PU.47/PU.48 sections and "PU.48's candidate re-scored": the
   comparison this view exists to make by eye.

## What to build

A **compare mode** (rail icon `⚖`, or a button on a still - your call, say which). One still (or a
video frame) rendered in two columns, A and B, each with:

1. **Its own detector picker** (reuse `/api/detectors`; the version string is already built) and,
   if `pump-read` accepts one, a classifier picker the same way - if it does not, say so and leave
   the classifier fixed.
2. **The image with layered overlays**, each toggleable, drawn from what the MODEL returned, never
   from the annotation: the CSV truth as text; the hand windows (dashed, the oracle); the detector's
   boxes; the rows the verifier kept; the assigned field per row (the existing field colours); the
   slicer's cells inside each kept row, **tinted by the cell's margin** so an uncertain digit is
   visible.
3. **The funnel as steps with counts and timings**: `detector N boxes -> verified M kept -> roles
   assigned K -> cells sliced -> read -> law`, each with its `timingsMs` entry. A step that loses
   rows says how many it lost.
4. **The verdict table**: per field, `expected.csv` / A / B with ✓ ✗ –, plus the law's
   `abstainReason` when the reply carries one, and the raw JSON of each reply behind a disclosure.

Then the three things that make it worth its cost:

- **Blink** (a key): swap A and B in place without moving the eye - the only reliable way to see a
  box shift.
- **The disagreement sweep**: run both models over the current list filter (or the heldout split)
  and show a table of the stills where the committed triples differ, each row opening the compare
  view on that still. This is how the interesting photo is FOUND; 68 stills at ~2.4 s each is ~3
  minutes per model, so run it in the background with progress, cache per (still, model sha), and
  never re-run a pair that is already cached.
- **Save**: write both JSON replies and a PNG of the two panes under
  `ml/pump-reader/runs/<date>/compare/<still>/` so `REPORT.md` can carry the evidence instead of a
  typed number.

Out of scope: changing the reader, the law or the corpus; a third pane; training anything.

## Tests you must add

pytest in `test_server.py` (a COPY of the corpus db in scratch, the existing `PUMP_ANNOTATE_DB`
env):
1. `/api/compare` with two model paths returns both replies and a per-field verdict against
   `expected.csv` (oracle: the CSV row for a still whose values you name in the test).
2. An unknown model path is refused (PU.46's validation, 400).
3. The disagreement route returns only the stills whose committed triples differ - build it from
   two stubbed replies, not by running the models.
**Named mutation**: drop the path validation in the compare route - test 2 must go red. Paste
red-then-green.
Headless (playwright, node, in the scratch folder; paste the output): both panes render for one
still; the blink key swaps the pane contents; a layer toggle hides its overlay; the save writes a
PNG that exists on disk.

## Checks

`ml/pump-reader/.venv/bin/python -m pytest tools/pump-annotate -q` exit 0 with count; the page
parses (`node -e "...new Function(script)"`); `scripts/pump-windows-check.py --check` and
`corpus_db.py check` exit 0 (you changed no corpus file - prove it); `swiftlint lint` from the repo
ROOT exit 0 (no Swift touched; it is the gate).

## Vacuous traps

A view that shows two committed numbers and no funnel - that is the table the report already has.
Overlays drawn from `windows.json` rather than from the model's reply. A sweep with no cache that
runs 136 reads on every click. A blink that re-renders and moves the layout. Claiming the PNG was
saved without asserting the file exists.

## Report back

Exit codes, counts, run-or-only-written, the mutation red-then-green, the playwright output
verbatim, a description of what the two panes show for ONE named still (you cannot see it - say
what the DOM contains), and anything found and not fixed.
