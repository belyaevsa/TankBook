# Pump window annotator

A local web page for `Spike/ReceiptSpike/fixtures/pump/windows.json` - the
quads that tell the locator ratchets where the number windows are and what
each display shows. It is the manual step of `.claude/skills/corpus-intake`
(step 3), which also carries the annotation conventions.

    ml/pump-reader/.venv/bin/python tools/pump-annotate/server.py
    # open http://127.0.0.1:8765/

The venv is needed for Pillow + pillow-heif (HEIC fixtures are served as
EXIF-oriented JPEG); the server itself is stdlib. No venv yet:
`python3 -m venv ml/pump-reader/.venv && ml/pump-reader/.venv/bin/pip install
pillow pillow-heif`. Under a Python without Pillow the server says so at
start and serves the original files, which only Safari renders (HEIC).

- Left: every fixture in `expected.csv` (grey = no windows yet). `J`/`K` walk it.
- Middle: drag a rectangle to add a window (the first three go to
  total / liters / unitPrice and pre-fill the text from `expected.csv`; the rest
  are `board`); click to select; drag a corner to adjust; drag inside to move;
  `1`-`4` set the field; `⌫` deletes.
- Right: the text as the display SHOWS it (zero padding, comma), `partial`
  legibility, `rotationCW` (rotates the view only - quads stay in image space),
  `notOnDisplay` and `csvDisagrees`.
- `Save` (`⌘S`) writes the entry back in the file's own formatting; `Check`
  runs `scripts/pump-windows-check.py --check` and shows the verdict.

Loopback only. Nothing is committed - stage the JSON by path when the batch
is done.
