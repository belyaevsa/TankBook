# PU.44 - Annotator: derived text conventions and per-window provenance

Row: `docs/TASKS.md` -> PU.44. Source: `agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md` items B2, B4.

## Where you may write

`tools/pump-annotate/index.html`, `tools/pump-annotate/server.py`, `tools/pump-annotate/README.md`,
`tools/pump-annotate/test_server.py` (PU.43 may be creating it in parallel - if it exists, ADD tests,
never rewrite it; if it does not, create it), `scripts/corpus_db.py`, `scripts/pump-windows-check.py`,
`Spike/ReceiptSpike/fixtures/pump/windows.json` `_about` string ONLY (document the two new keys),
and the dumped files ONLY through `corpus_db.py import` / `dump` (never by hand). Scratch:
`ml/pump-reader/.out/pu44/`.

**Another agent (PU.43) edits `index.html` and `server.py` at the same time.** Keep your edits to
the functions you need, re-read the file before each edit, never reformat, never move a function.
If a merge is impossible, stop and report.

## What exists (read first, in order)

1. `tools/pump-annotate/README.md`; `index.html`: `renderWins()` (the window cards and the
   `data-t` text inputs), `runReader()` and `readCells` (the slicer's cells from the last read,
   with `dp` and `blank` per cell), `addWindow`, the corner/move/turn drags, `autoAnnotate`.
2. `scripts/corpus_db.py`: `clean_entry`, the `windows` table DDL, `import`/`dump`, `check`.
   The corpus is SQLite-first: **a new key must survive import -> dump byte-for-byte**.
3. `ios/Tests/TankbookCoreTests/PumpReaderTestSupport.swift` `glyphCount` (digits + leading
   spaces; separators are not glyphs) - port it exactly to JS for (a).
4. `agents/reviews/PU.13-REVIEW-ANNOTATIONS.md` items 1-3 - the padding inconsistencies (a) exists
   to stop; `agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md` B2/B4.
5. `ml/pump-reader/src/pump_reader/detdata.py` and `REPORT.md` PU.36b (the sampler) - the consumer
   of (b); you do not change it, you make the column exist for it.

This brief's diagnosis is a hypothesis - confirm before changing.

## What to build

**(a) Derived text conventions.**
- Beside each window's text input: `cells N` from the last read's slicer cells for that window
  (`readCells` keyed by field; empty until a read ran), against `glyphCount(text)`; the badge is red
  when they differ, green when equal, grey with no read.
- A warning icon when the typed separator's cell index (the digit index before `.`/`,`) differs from
  the index of the slicer cell whose `dp` is true.
- Key `Z` (not typing): pad the three transaction texts to the head's convention. The convention is
  DERIVED: from the reviewed entries of the same make (make = the filename token after `pump-NNN-`,
  the way `scripts/corrections-report.py` attributes it), take the modal digit count and separator
  per field; pad with leading zeros to that count and swap the separator. Never a hard-coded table.
  Show what it did in `#msg` (`padded total 34.36 -> 0034,36 (gilbarco: 6 digits, comma)`).
- Board strings: `pump-windows-check.py` gains a check that a `board` text is a price-shaped number
  (digits with one separator) or empty - today boards have no validator at all.

**(b) Provenance.** Each window gets `placedBy` in {`hand`, `auto`, `reader`, `tracker`, `template`}
and `zoom` (float, the canvas zoom at the last edit). Written by the PAGE: a drag-drawn or
corner/move/turn-edited window -> `hand` + current zoom; `autoAnnotate` -> `auto`; a `▶ read` prefill
that changed only text leaves `placedBy` alone. `clean_entry` passes both through; the `windows`
table gets the two columns (migration: add if missing); `dump` writes them after `legibility` so
entries without them dump unchanged. On import, a window with no `placedBy` gets `hand`, EXCEPT
windows of entries that carry `pendingWindows` or whose still is `pump-244`..`pump-281`, which get
`auto` (they were placed by the reader on 2026-09-21) - write this rule once, in `corpus_db.py`,
with a comment naming the batch. The card shows `hand @1.4x` style.

Out of scope: the sampler using the column (a PU row of its own), PU.43's items, PU.45.

## Tests you must add

pytest in `tools/pump-annotate/test_server.py` (copy of the DB in scratch, `PUMP_ANNOTATE_DB` or
whatever env var PU.43 introduces - coordinate by reading the file):
1. `placedBy and zoom round-trip`: import a windows.json fragment with both keys -> dump -> identical
   text. **Mutation (named): remove the passthrough in `clean_entry` - must go red.**
2. `import defaults`: an entry without `placedBy` gets `hand`; `pump-250-...` gets `auto`.
3. `board text validator`: a `board` window with text `abc` makes the checker report a problem;
   `1.969` and `` do not. Oracle: `_about`'s board convention.
Headless (playwright, node, paste output): (4) drag a corner on a still -> the saved window carries
`placedBy: hand` and `zoom` equal to the page's `zoom` at the drag; (5) with a read done, typing a
5-digit text against 6 slicer cells turns the badge red; (6) `Z` on a Gilbarco still pads
`34.36` to `0034,36` (oracle: the reviewed Gilbarco entries' modal convention - print the derivation).

## Checks

pytest exit 0 with count; `scripts/pump-windows-check.py --check` exit 0; `corpus_db.py import`
then `dump` then `check` exit 0 and `git diff --stat Spike/` shows only the `_about` line and the
new keys; `swiftlint lint` from the repo root exit 0 (no Swift touched; it is the gate).

## Vacuous traps

A pad key with a hard-coded six. A cell counter reading `text` instead of the slicer's cells.
Provenance written by the server at save time (it cannot know the zoom). A round-trip test that
compares parsed JSON instead of text (dump order matters). Editing the dumped files by hand.

## Report back

Exit codes, counts, run-or-only-written, red-then-green for test 1 under the mutation, playwright
output verbatim, the derived per-make convention table you observed, anything found and not fixed.
