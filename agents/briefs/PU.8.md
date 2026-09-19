# PU.8 - the slicer on faint and glare-washed displays

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.8. **Builds on:** PU.4's
`ios/Sources/TankbookCore/Extraction/PumpReader/PumpGlyphSlicer.swift` and its harness
`ios/Tests/TankbookCoreTests/PumpReaderHarnessTests.swift`. Read both, and PU.4's per-make table
in the git log of commit `500937c3` (`git show 500937c3 -- docs/TASKS.md`).

## Where you may write

Only `ios/Sources/TankbookCore/Extraction/PumpReader/` and
`ios/Tests/TankbookCoreTests/PumpReader*.swift`. **Another agent is working in `ml/pump-reader/` at
the same time - do not touch anything there**, and do not regenerate `ios/.build/pump-reader-out/`
files that agent reads except `slices.json` at the very END of your run (it is the deliverable).
No `/tmp`; scratch is `ios/.build/pump-reader-out/`.

## Write code first, explore second

## The measured state

Count agreement 173/433 (0.40). Two failure shapes on `ml/pump-reader/runs/2026-09-19/held-out-cells-pu4.png`:
faint LCD where the ink profile never clears the threshold (blank cells where digits are:
`pump-004`, `pump-062` board, Scheidt reflections), and glare that splits a glyph into two runs the
snap does not re-merge. The locator is out of scope here.

## What to change

1. **Adaptive threshold**: Otsu (or a two-cluster split) on the column-profile histogram instead
   of a fixed fraction of max; on a faint display the two clusters are close but present.
2. **Local contrast normalisation on the strip** before projection (CLAHE-like, or divide by a
   large-box blur).
3. **Short-count retry**: if the snapped count is below what the pitch grid allows for the strip
   width, run a second pass at half the threshold and take the pass whose cells have the more
   uniform ink mass.
4. **Split-glyph merge**: two runs closer than 0.35 × pitch whose combined width ≤ 1.1 × a
   digit's width are one glyph.
5. Never use the annotated string length inside the slicer - it is an oracle for the test, not an
   input. (The brief for PU.8 in TASKS mentions it as an upper bound during measurement; ignore
   that - it would make the ratchet vacuous.)

## Tests

- The existing `PumpGlyphSlicerTests` and the named PU.4 mutation stay red-under-mutation and
  green otherwise.
- Raise the harness ratchet constant `count ≥ 0.39` to what you measure; it moves only up.
- Add a synthetic faint-display test: a PU.1 render with its contrast collapsed to 15 % (do it in
  Swift on the loaded PNG - scale pixel values toward the mean) still slices to the right count.
  Oracle: the row's box count. **Mutation named by this brief:** replace the adaptive threshold
  with the old fixed fraction - this test must go red; paste it.
- Re-run the harness at the end and write `slices.json` (the ml agent scores against it).

## Out of scope

The classifier, the locator, `windows.json`, anything in `ml/`.

## Checks (by exit code)

`cd ios && swift build` → 0; `swiftlint lint` from the repo ROOT → 0; `cd ios && swift test` → 0
with the harness count non-zero and the totals above 2123/261. No app-target change → no
`xcodebuild`; say so.

## Standing fences

Never stash / checkout / move; never commit. `pgrep -x` only. Not alone in the checkout.

## Report back

Exit codes, counts, run-or-only-written, the red mutation output, the per-make table before and
after, the new ratchet constant, and anything found and not fixed.
