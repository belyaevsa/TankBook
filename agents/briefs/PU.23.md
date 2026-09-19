# PU.23 - row assignment and boards, on the annotated quads

**Parent journey:** J4. **Row:** `docs/TASKS.md` → PU.23. **Design:** `agents/reviews/PU.14-REVIEW-DECODE-DESIGN.md`
§3 - "measured layout facts", "the assignment rule (proposed)", "the three hard cases" - read it whole.

## Where you may write

New files only: `ios/Sources/TankbookCore/Extraction/PumpReader/PumpRowAssignment.swift` and
`ios/Tests/TankbookCoreTests/PumpRowAssignmentTests.swift`. Nothing else. **Three other agents are
working in this checkout** (the law, the locator, the Python model) - never move or revert a file
you did not create; if you need a type PU.21 is defining (`PumpLocatedWindow`, `PumpRowAssignment`),
define a minimal `PumpRowAssignment` of your own in your file and say so in the report - the
orchestrator reconciles. No `/tmp`.

## Write code first, explore second

## What to build

`PumpRowAssignment.assign(windows: [(quad: [CGPoint], glyphCount: Int, hasDecimal: Bool)],
imageSize:, rotationCW:) -> PumpRowAssignment` giving each window a role: `.total`, `.liters`,
`.unitPrice`, `.board`, or `.unassigned`, from geometry alone (no strings, no classifier):
orientation (rotate the quads into reading order first - `PumpQuadWarp.readingOrder` exists),
column clustering by x-centre, y-order within the transaction column (total above volume above
price on Gilbarco/Wayne/Tokheim; Scheidt heads and Russian labels put price at the bottom in a
separate window), the digit-count audit (a price has 4-5 cells, a total 6-7 on Gilbarco, a
board cell 4-5 in a row of 3-4 equal windows at the same baseline), and the board rule: a row of
≥ 3 windows of near-equal width at one baseline below the transaction column is a board, and
the transaction price is the board cell whose digit count and x-position match the head's
convention only when no separate price window exists (the review's `pump-013` / `pump-051`
cases: assign `.board` to all and leave `.unitPrice` unassigned when none is singled out).

## Tests

- Harness over `windows.json` (gated like the other PU harnesses): feed each fixture's annotated
  quads with the STRING's glyph count (a stand-in for the slicer's count) and score the assigned
  role against the annotation's `field`. Print per-fixture misses and the totals; assert the
  ratchet at what you measure (the review's layout prior alone gives 93/95 on three-window
  fixtures).
- Named cases: `pump-009` (board of four to the left, transaction column at right) never
  assigns a board price as `.unitPrice`; `pump-019` (rotated 90) assigns all three;
  `pump-051` (four-price board, no separate price) leaves `.unitPrice` unassigned; `pump-016`
  (idle, two windows + board) assigns total/liters only.
- **Mutation named by this brief:** drop the rotation step → `pump-019`/`pump-069` misassign,
  red; treat the board cluster as the transaction column → `pump-009` assigns a board price, red.

## Checks

`cd ios && swift build` → 0; `swiftlint lint` from the repo ROOT → 0; `cd ios && swift test --filter
PumpRowAssignment` → 0 with a non-zero count. No app-target change → say so.

## Standing fences

Never stash / checkout / move; never commit; `pgrep -x` only; not alone in the checkout; no `/tmp`.

## Report back

Exit codes, counts, the assignment table, both red mutations verbatim, anything found and not fixed.
