# Pump window annotator

A local web page for `Spike/ReceiptSpike/fixtures/pump/windows.json` - the
quads that tell the locator ratchets where the number windows are and what
each display shows. It is the manual step of `.claude/skills/corpus-intake`
(step 3), which also carries the annotation conventions.

    python3 tools/pump-annotate/server.py
    # open http://127.0.0.1:8765/

Stdlib only. HEIC fixtures are converted with macOS `sips` (or Pillow when
the ml venv runs it); the converted images are cached under
`~/Library/Caches/tankbook-pump-annotate/` by content hash.

- Left: every fixture in `expected.csv` (grey = no windows yet). `J`/`K` walk it.
- Middle: drag a rectangle to add a window (the first three go to
  total / liters / unitPrice and pre-fill the text from `expected.csv`; the rest
  are `board`); click to select; drag a corner to adjust; drag inside to move;
  `1`-`4` set the field; `⌫` deletes.
- Right: the text as the display SHOWS it (zero padding, comma), `partial`
  legibility, `rotationCW` (rotates the view only - quads stay in image space),
  `notOnDisplay` and `csvDisagrees`.
- `processed` (`P`) marks the entry as checked by a human - `reviewed: true` in
  the JSON - and `✓ Save & next` (`⏎`) sets it, saves and opens the next one in
  the filtered list; the list filter separates empty / not processed / processed.
- A `▶` in the list marks a still with a Live record (blue = tracking unreviewed,
  green = ok, red = bad; `▶?` = not tracked yet); the filter has *with Live record* and
  *Live, tracking unreviewed*.
- **Live record / View frames** (shown when the still has a Live record and
  `pump_reader.frames` + `pump_reader.track` have run): steps through the
  record's tracked frames with the carried quads drawn (`←`/`→`, slider,
  `Esc` back). Mark **tracking ok / bad** on the still; `bad` makes the glyph
  extractor skip that record. Frames are read-only - a wrong quad is fixed on
  the still and the record re-tracked.
- **Videos** (`🎞`, filter *videos*): the running-display clips from
  `pump-live/videos.json`. Their "still" is the hand-annotated reference frame;
  *View frames* steps the tracked frames, and a **frame label** row shows the
  frame's total / liters / price - filled by the reader where the arithmetic
  closed (`arithmetic`), empty otherwise. Correct or fill it and **Save label**
  (`⇧⏎`; `⌥←`/`⌥→` step frames from the input); owner labels are kept by every
  re-run of the reader. Stored in `pump-live/video-labels.json`.
- `Save` (`⌘S`) writes the entry back in the file's own formatting and rebuilds
  `fixtures/corpus.sqlite` (also rebuilt at startup) (`scripts/corpus_db.py`), which is committed with it; `Check`
  runs `scripts/pump-windows-check.py --check` and shows the verdict.

Loopback only. Nothing is committed - stage the JSON by path when the batch
is done.
