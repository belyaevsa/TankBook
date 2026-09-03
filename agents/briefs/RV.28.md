# RV.28 – fuel chips must pack, not distribute

Reported by the product owner with a screenshot: `92 95 98` strung out with large gaps, then
`100 +` wrapped onto a second row, while all five chips would fit on one line at their natural
size.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.**

## The cause, verified in `ManualFillUpFuelCard.chooser`

The chips sit in `LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment:
.trailing)`. `.adaptive` **distributes**: it computes how many columns fit and then stretches them
to fill the width, so the gaps grow with the container and the last chips are pushed to a new row
even when space remains. `alignment: .trailing` aligns content *inside* each cell, not the grid
within its row, and the `.frame(maxWidth: .infinity, alignment: .trailing)` below it is a no-op on
a grid that already fills the width.

**The grid was chosen for the right reason and must keep doing it**: its comment says *"The grid
must wrap chips onto the next row instead of compressing them"* after `minimum: 44` squeezed "100"
and "LPG" until their labels broke inside the capsule. Any fix must keep chips at their intrinsic
width and still wrap — never compress a label again.

## What to build

**Pack, don't distribute, and align the block to the trailing edge** so the chips line up with
`Not set`, the Full-tank toggle, and the other right-hand values on the card — the card is a grid
and the chips currently break it. A wrapping flow (a small custom `Layout`, or a
`ViewThatFits`/HStack composition that falls back to wrapping) sizes each chip to its label's
intrinsic width, packs left-to-right, wraps only when a chip genuinely does not fit, and the whole
block is trailing-aligned within the card.

`EditEntryView` uses the same component (`ManualFillUpFuelFullCard` / the chooser it hosts) — the
fix must land on both screens, not just the one in the screenshot.

## Explicitly out of scope

- The offer-set logic (`offeredKinds`, `visibleKinds`, the "+" correction menu) — untouched, still
  correct.
- Any other card on this screen.
- Any `backend/` file.

## Read before writing

1. **`CLAUDE.md`** — hard rule 5 (palette tokens, no ad-hoc hex), 6 (numbers in DIN, tabular-nums),
   14.
2. `docs/DESIGN.md` → layout & IA rules, the card grid convention.
3. `ios/App/Sources/ConfirmManual/ManualFillUpFuelCard.swift` (the chooser and its grid),
   `ios/App/Sources/EditEntry/EditEntryRows.swift` or wherever `EditEntryView` hosts the same
   chooser — confirm the exact call site before assuming.

## Tests

- `cd ios && swift build ; swift test` — must not fall from today's count.
- **L4 asserts frames, not existence** (this bug's whole signature is layout, not presence):
  - With a four-grade car (or the widest realistic set), every chip sits on **one row** — compare
    each chip's `minY`.
  - The trailing edge of the **last** chip aligns with the Full-tank toggle's trailing edge, ±2 pt.
  - The widest chip's label is **not truncated** — "100" and "LPG" breaking inside the capsule is
    the regression this code already carries a comment about, and it was caught by a screenshot
    last time, not a test. Assert it this time.
- Apply the same three assertions on `EditEntryView`'s chooser if it is a distinct call site.

**Vacuous-assertion traps:**
- Asserting the chips `.exists` — they existed throughout the bug.
- Testing with only 2–3 kinds, where `.adaptive` distributing is not visually wrong even though the
  mechanism is. Use a car with enough kinds to force the distribute-vs-pack difference to matter.

**Mutation-check and report it**: revert the layout to the original `LazyVGrid(.adaptive(...))` and
confirm the new frame assertions go red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "APPBUILD=$?"

**Use the `iPhone 17 Pro` simulator for every xcodebuild/xcrun step in this task** — another agent
is using `iPhone 17` concurrently, and `simctl`/`xcodebuild` fight over a shared device.

**Judge by the exit code you echoed.** Zero lint **errors**.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line.

## Screenshots

`design/screenshots/RV.28-fuel-chips.png` and `-ru.png` — dark, RU has the longest kind names so it
is the real stress case for packing. Outside any test run. Install the newest
`DerivedData/Tankbook-*` for the `iPhone 17 Pro` device (`ls -dt`), matching the destination above.

## Report back

- Exit codes, test counts before/after, suites RUN, the mutation result.
- Confirm both call sites (`ManualFillUpFuelCard` and `EditEntryView`'s chooser) were fixed, or
  name the reason if only one applies.
- Files changed, docs extended if the layout convention belongs in `DESIGN.md`, anything
  unfinished.
