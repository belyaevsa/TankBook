# PU.43 - Annotator: live arithmetic on stills, keyboard nudge, heldout badge with reviewed-clearing

Row: `docs/TASKS.md` -> PU.43. Source: `agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md` items B3, A4, B5.

## Where you may write

`tools/pump-annotate/index.html`, `tools/pump-annotate/server.py`, `tools/pump-annotate/README.md`,
a new `tools/pump-annotate/test_server.py`, `scripts/corpus_db.py` ONLY if the fixtures route needs a
query helper it lacks. Nothing under `Spike/`, `ios/`, `ml/` or `docs/` except the README named.
Scratch: `ml/pump-reader/.out/pu43/` (a headless browser goes there: `npm i playwright` in that
folder, `npx playwright install chromium`).

## What exists (read these first, in this order)

1. `tools/pump-annotate/README.md` - every control and key.
2. `tools/pump-annotate/index.html` - `frameStates()` (the video arithmetic test), the `keydown`
   handler (near the end; `[`/`]` turn keys, `+`/`-` zoom), `hitCorner`/`drag` (corner and move
   drags), `renderList()` and `#counts`, `save()`.
3. `tools/pump-annotate/server.py` - `/api/fixtures` (what the list gets), the `PUT /api/entry/`
   handler, `clean_entry` in `scripts/corpus_db.py`.
4. `docs/EXTRACTION.md` -> Decision 9 and its 2026-09-21 amendment; `ios/Tests/TankbookCoreTests/
   PumpReaderTestSupport.swift` `isHeldout` (heldout AND reviewed) - the reason (c) exists.
5. `scripts/corpus_db.py` - the corpus is SQLite-first; `fixtures.split` is the column. Run
   `ml/pump-reader/.venv/bin/python scripts/corpus_db.py sql "select name, split from fixtures where kind='pump' limit 3"`.

This brief's diagnosis is a hypothesis - confirm the line numbers before changing anything.

## What to build

**(a) Live arithmetic mark on stills.** When the open still's windows for `total`, `liters` and
`unitPrice` all carry non-empty text, compute `liters x unitPrice` (parse `,` as `.`; ignore
leading zeros/blanks) and compare with `total` to the cent (|diff| <= 0.005 + half a cent of
rounding slack, exactly as `frameStates` does it - reuse that function's arithmetic, do not write a
second one). Show `✓ closes` / `✗ 15.20 x 2.099 = 31.90, shown 31.91` beside the `#csv` line,
updated on every text input. The mark reads the WINDOW texts, never the CSV row. It is
informational: it never blocks Save (the corpus has legitimate off-by-a-cent displays, `pump-256`).

**(b) Keyboard nudge.** With a window selected and nothing typing (`typing` in the handler):
`←↑→↓` move the whole quad by ONE SCREEN PIXEL at the current zoom (i.e. `1/zoom` unscaled display
px, then through `toImg`); `⇧`+arrow = 10 px; `⌥`+arrow moves only the active corner (the last
corner dragged or, if none, corner 0; show which with a filled dot). Mark the entry dirty (`touch()`);
on a video frame it is a quad edit (`frameQuadsEdited = true`). Arrow keys in frames view currently
step frames - keep that when NO window is selected, and nudge when one is; `Esc` deselects.

**(c) Heldout badge + reviewed-clearing.** `/api/fixtures` adds `split` per still (query
`fixtures.split`; absent = `train`). The list shows a small `H` badge (title "heldout - measured
once reviewed") and `#counts` adds `heldout N (M reviewed)`. On `PUT /api/entry/<still>`: if the
stored entry is `reviewed` and the still is heldout and the incoming windows' quads OR texts differ
from the stored ones, store `reviewed: false` regardless of the checkbox, and return
`{"reviewedCleared": true}`; the page shows "heldout still changed - review again before it
measures" and unticks the box. A save with identical windows keeps `reviewed`.

Out of scope: PU.44 (cell counter, provenance), PU.45 (video keyframes), the same-head template,
the live slicer (PU.46, orchestrator).

## Tests you must add

`tools/pump-annotate/test_server.py` (pytest, run with `ml/pump-reader/.venv/bin/python -m pytest
tools/pump-annotate -q`; add pytest to the venv if missing - `pip install pytest`), against a COPY
of the corpus database in the scratch folder (point the server at it via an env var you add, e.g.
`PUMP_ANNOTATE_DB`; never write to the real `corpus.sqlite`):

1. `fixtures route carries split`: at least one `heldout` and one `train` in the response, matching
   `select name, split from fixtures`. Oracle: `pump/split.csv`.
2. `reviewed heldout entry with a moved quad stores reviewed false`: take a reviewed heldout entry
   (e.g. `pump-186-tatsuno-amber-led-night-third-party-ru.jpg`), PUT it with one corner moved by
   0.01 and `reviewed: true` in the body -> stored `reviewed` is false, response says
   `reviewedCleared`. **Mutation (named): remove the clearing branch - this test must go red.**
3. `identical windows keep reviewed`: the same PUT with unchanged windows -> `reviewed` stays true.

Headless page tests (playwright, node script in the scratch folder, run against the server on a
spare port with the copied DB; paste the script's output into the report): (4) select window 0 of
`pump-023-wayne-circlek-glare-ee.jpg`, press `→` once, assert every x of the quad moved by exactly
`1/zoom/img.naturalWidth` (rotation 90 on that still: check the axis the move lands on and say
which); (5) type a wrong total into the total window's text on a still whose three windows exist
and assert the mark reads `✗`; restore it and assert `✓`.

## Checks

- `ml/pump-reader/.venv/bin/python -m pytest tools/pump-annotate -q` exit 0, count > 0.
- `node --check` is not enough for the page: `node -e "...new Function(script)"` parses it, and the
  playwright runs above exercise it.
- `scripts/pump-windows-check.py --check` and `ml/pump-reader/.venv/bin/python scripts/corpus_db.py check`
  both exit 0 afterwards (you changed no corpus file - prove it).
- `swiftlint lint` from the repo root exit 0 (you touched no Swift; run it anyway, it is the gate).

## Vacuous traps

A badge with no reviewed-clearing. Nudging in normalised units (the step would depend on image
size). The arithmetic mark reading the CSV instead of the typed window texts. A test that PUTs to
the real corpus database. A nudge that also fires while typing in an input.

## Report back

Exit codes observed (`echo $?`), test COUNTS, run-or-only-written per test, the red-then-green output
for test 2 under the named mutation, the playwright output verbatim, and anything you found and did
not fix.
