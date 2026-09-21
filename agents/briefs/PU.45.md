# PU.45 - Annotator: keyframes, interpolation and per-frame confidence for video labels

Row: `docs/TASKS.md` -> PU.45. Source: `agents/reviews/PU.42-REVIEW-ANNOTATOR-UX.md` items B6, A3.

## Where you may write

`tools/pump-annotate/index.html`, `tools/pump-annotate/server.py`, `tools/pump-annotate/README.md`,
`tools/pump-annotate/test_server.py` (add, never rewrite - PU.43/PU.44 may be creating it),
`scripts/corpus_db.py` (labels/corrections write paths only), `ios/Tests/TankbookCoreTests/
PumpVideoReadTests.swift`, `Spike/ReceiptSpike/fixtures/pump-live/README.md` (one paragraph on the
new label sources). Dumped corpus files only through `corpus_db.py import`/`dump`. Scratch:
`ml/pump-reader/.out/pu45/`. **Two other agents edit `index.html`/`server.py` now** - keep to the
video-label functions, re-read before each edit, never reformat or move code; stop and report if a
merge is impossible.

## What exists (read first, in order)

1. `tools/pump-annotate/README.md` -> Videos, frame label, runs, anchors, `⟳ retrack + read all`.
2. `index.html`: `showVideoLabel`, `saveVideoLabel`, `frameStates`, `runOf`, `stepRun`,
   `copyPrevious`, `nextUnlabelled`, the `#frameStrip` classes; `server.py`: the
   `PUT /api/video-label/` handler (sources `arithmetic` / `owner`, `via` `copied` / `run`, the
   corrections ledger it writes), `video_labels()`.
3. `scripts/corpus_db.py`: the `labels`, `readings` and `corrections` tables and their write
   functions; the dump of `video-labels.json` and `corrections.jsonl`.
4. `ios/Tests/TankbookCoreTests/PumpVideoReadTests.swift` - the regeneration: which frames it skips
   (`owner`, anchored, reviewed video) and what it writes (`arithmetic`, and `readings`).
5. `Spike/ReceiptSpike/fixtures/pump-live/README.md` Batch 5 - the arithmetic rule the clips exist
   for: `total == round(liters x price, 2)`, both monotone non-decreasing within a fill.

This brief's diagnosis is a hypothesis - confirm before changing.

## What to build

**(a) Keyframes + interpolation.** In the frame label row, `⌥⏎` = "keyframe": saves this frame's
label as `owner` AND, if the nearest earlier owner-labelled frame in the same run exists, fills every
frame between them that has no `owner` label with the arithmetic closure: liters and total
interpolated linearly by frame index, then snapped to the nearest pair `(l, t)` with
`t == round(l x price, 2)` (price = the clip's constant), monotone non-decreasing in both, and written
with `source: "interpolated"` (never `owner`, never `arithmetic`). A frame where no such pair exists
within 0.02 L of the interpolation is left unlabelled and flagged attention. The strip gets an
`interpolated` colour; `frameStates` treats `interpolated` as labelled-but-not-confirmed.

**(b) Propagation with a glance.** `whole run` (`#vlRun`) no longer writes the run in one go. After
`⇧⏎` with it checked, the page enters a confirm loop: it shows the next frame of the run with the
typed label overlaid, `→` or `⏎` confirms it (`owner`, `via: run`), `⌥⏎` confirms all remaining
frames of the run ONLY if the arithmetic closes on each of their existing `arithmetic` readings
(else it stops on the first that does not and says why), `Esc` leaves the loop with the rest
unlabelled. The corrections ledger entry for a run write records `confirmed: N` and
`interpolated: M`.

**(c) Confidence.** Beside the frame label show the reader's margin for that frame from `readings`
(the lowest cell margin of the window that produced the label, or `–`); `frameStates` marks an
`arithmetic` frame with margin below the classifier's verify threshold (find it in
`PumpReadingVerifier` or its config - name the constant, do not copy the number) as attention.

**(d) Regeneration.** `PumpVideoReadTests` skips `interpolated` frames ONLY when both bounding
keyframes are `owner`; otherwise it regenerates them as `arithmetic` (an interpolation whose
keyframe was later changed is stale).

Out of scope: PU.43, PU.44, the live slicer, any change to the tracker.

## Tests you must add

pytest (copy of the DB in scratch; the env var PU.43 introduces or your own if none exists yet):
1. `interpolation between two keyframes yields only closing pairs`: price `1.729`, keyframes
   `001` = 3.18/1.84 and `005` = 5.19/3.00 (oracle: Batch 5's rule in `pump-live/README.md`; 1.84 x
   1.729 = 3.18, 3.00 x 1.729 = 5.19) -> frames 002-004 carry pairs with `round(l x 1.729, 2) == t`,
   monotone, `source: interpolated`. **Mutation (named): make the fill write `source: owner` - must go red.**
2. `a confirmed run writes owner per frame and interpolated nowhere`: confirm 3 frames one by one
   via the API -> three `owner` labels with `via: run`, ledger `confirmed: 3`.
3. `keyframe change invalidates`: after test 1, change keyframe `005` -> the frames between are no
   longer `interpolated` (or are marked stale) - state which you implemented and why.
Swift: `PumpVideoReadTests` - a fixture clip with two owner keyframes and interpolated frames between
is left alone; with one keyframe reverted to `arithmetic`, the interpolated frames are regenerated.
Run it with `PUMP_VIDEO_READ=1 PUMP_VIDEO_READ_ONLY=<stem>` on a scratch COPY of the labels (never
the real `video-labels.json`; say how you pointed the test at the copy).
Headless (playwright, paste output): (4) the confirm loop advances one frame per `→` and stops on
`Esc` with the remaining frames unlabelled.

## Checks

pytest exit 0 with count; `swift test --filter PumpVideoReadTests` exit 0 with count (it may skip
without the env var - say so); `corpus_db.py import`/`dump`/`check` exit 0; `scripts/pump-windows-check.py --check`
exit 0; `swiftlint lint` from the repo root exit 0.

## Vacuous traps

Interpolation that copies the keyframe's label to every frame (that is `whole run` again). A confirm
loop the owner can skip with one key without the arithmetic gate. Confidence read from the label
instead of the reading. A Swift test that runs against the real labels file. A `--filter` that
matches nothing ("0 tests passed").

## Report back

Exit codes, counts, run-or-only-written, the red-then-green for test 1 under the named mutation,
playwright output verbatim, and anything you found and did not fix.
