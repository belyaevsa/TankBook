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
- `Save` (`⌘S`) writes the entry back in the file's own formatting and rebuilds
  `fixtures/corpus.sqlite` (also rebuilt at startup) (`scripts/corpus_db.py`), which is committed with it; `Check`
  runs `scripts/pump-windows-check.py --check` and shows the verdict.

Loopback only. Nothing is committed - stage the JSON by path when the batch
is done.
