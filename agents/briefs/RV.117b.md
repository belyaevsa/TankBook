# RV.117b - the conflict neighbourhood, drawn

**[v1.1]**, the presentation half of [RV.117]. [RV.117a] shipped the substance on 2026-09-09
(`e249a13`); this row makes it visible. The row's own trap list is why the order was that way:
*"shipping the chart without the intervals, which is decoration"*.

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## What already exists - this row consumes it, it does not recompute it

`TimelineValidator.EntryValidation.validRange` (`TimelineValidator.swift:62`) is a
`TimelineValidRange?` - nil only when the entry has no odometer - carrying two intervals
(`ios/Sources/TankbookCore/Validation/TimelineValidRange.swift`):

```swift
public enum ValidRange<Bound: Comparable & Equatable & Sendable>: Equatable, Sendable {
    case none                                  // the neighbourhood itself is inconsistent
    case bounded(lower: Bound?, upper: Bound?) // inclusive; a nil end is genuinely OPEN
}

public struct TimelineValidRange {
    public let odometer: ValidRange<Int>   // readings valid for the entry's DATE
    public let dates: ValidRange<Date>     // dates valid for the entry's ODOMETER
}
```

**Recomputing any of this in the view is the row's named trap.** Read it from the validation.

The flag's neighbour values are already on `Flag.Detail.order(previousOdometer:previousDate:
nextOdometer:nextDate:)` (`:20-21`), so the surrounding points need no new query either.

## What to build

**The neighbourhood, and the two sentences that make it actionable.**

1. **A chart of the surrounding entries** with the offending point plotted off the trend through the
   valid ones. The competitor screen this came from shows five points
   (489 590 / 490 500 / **490 200** / 491 206 / 491 791); match that shape, not that data.
2. **The bracketing rows** - the previous entry and this one - and the consumption from the previous.
3. **The bidirectional statement**, which is the whole point: *"on 13/07 the odometer must be between
   490 500 and 490 983 km"* and *"if 490 200 is correct, the date must be ..."*. Render each from its
   `ValidRange`, and **handle all three cases in copy**:
   - `.bounded(lower:upper:)` with both ends - the between sentence;
   - a **`nil` end** - open, so the sentence is "at least X" / "at most X", never a sentinel number;
   - **`.none`** - and read the next paragraph before writing this one.

**`.none` on the DATE side is information, not an empty state.** [RV.117a]'s agent established this
and it is the most useful thing in the row: when the odometer sits at or below its previous reading
(or at or above its next), **no date between those two neighbours works**, so the date interval is
`.none` - and that is precisely the evidence that **the odometer is the field to question**. Say that
to the user. Answering the competitor's full second clause would need an alternative-neighbourhood
search - moving the entry before the earlier row - which is **out of scope**; do not build it, and do
not let its absence turn into a blank panel.

Also from RV.117a, so you do not misread a bound: the odometer interval's upper end is open only when
the newest entry's previous neighbour is same-day or absent. The cleanly open ends of a normal
newest/oldest entry are on the **date** side.

**It must work from the FLAGGED LIST, not only at save time.** This is the product owner's second
point and the reason the row is more than cosmetics: an entry flagged during an import is one the
user cannot reason about from memory, and the neighbourhood is the only evidence they have. Reach it
from `FlaggedEntriesView` **and** from Edit entry.

**The app suggests, the user decides** (hard rule 13). Nothing auto-corrects, nothing pre-fills a
"should be" value as fact, and the existing ranked fixes stay as they are. **Coordinate with
[RV.104]**: accepting a flag is the honest last resort, and this row is what makes it a last resort
rather than the only option.

**Palette and type**: amber is attention (hard rule 5) - the offending point is amber, red stays
inside system dialogs. Numbers in DIN with `tabular-nums` (hard rule 6). The offending point must be
**distinguishable by more than colour** (hard rule 5's accessibility floor).

## Explicitly out of scope

- Changing `TimelineValidator`, `ValidRange`, or when an entry flags. If you find the interval wrong,
  **report it** - do not work around it in the view.
- The alternative-neighbourhood search described above.
- [RV.104]'s acceptance behaviour and the ranked-fix ordering.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Validation -> Valid range (RV.117a wrote it) and PRIORITY.
2. `docs/ERRORS.md` -> Confirm -> F9a: the existing amber row, its quoted neighbour and its ranked
   fixes. **Extend it** with what the neighbourhood panel says, including the `.none` case.
3. `docs/DESIGN.md` -> chart and card patterns; **extend it** with this chart.
4. `docs/SCREENMAP.md` if you add a route from the flagged list.
5. `CLAUDE.md` hard rules 5, 6, 7, 13.

## UI suites to run

`TankbookUITests/EditEntryUITests`, `TankbookUITests/FlaggedEntriesUITests`,
`TankbookUITests/ConfirmManualUITests`. Report each observed, **non-zero** count.

## Tests you must add

- **L4, both doors**: the chart renders from Edit entry **and** from the flagged list.
- **L4**: the offending point is distinguishable by more than colour.
- **L1/L4, the copy**: the between-sentence, the open-ended sentence, and the `.none` sentence are
  each produced for the interval that yields them - assert **what it says**, not that a panel exists.
- **L1**: the view reads `validRange` and derives no bound of its own. A source-scan gate is
  acceptable here if a behavioural test cannot express it; say which you used.
- **L4**: an entry with no odometer (`validRange == nil`) renders no panel and no empty box.

## Vacuous traps, named

- **Recomputing the interval in the view**, so the panel and the flag can disagree.
- **Asserting the chart appears** rather than what it says - the row calls this out by name.
- Rendering a `nil` bound as a number, or `.none` as a blank panel.
- Testing only a middle entry, where both neighbours exist and the open-ended cases never arise.
- Auto-applying the suggested value, or pre-filling it as fact (hard rule 13).
- Colour as the only signal for the offending point.

## Screenshots

**EN and RU**, **dark**, outside any running test: the neighbourhood panel from Edit entry, and from
the flagged list. Commit as `design/screenshots/RV.117b-neighbourhood.png`, `-ru.png`,
`RV.117b-flagged.png`, `-ru.png`. A `.none`-date-side pair is worth a fifth and sixth shot, because
that is the case the row exists to make legible.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
**`simctl launch` on an already-running app silently ignores new arguments** - `terminate` first and
wait for the relaunch, or the "RU" shot is the EN one with a different clock. RU runs 20-30% longer
and these sentences are long. **You cannot see your own screenshots**; state what you captured.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1761 tests / 199
suites**, **779** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then the UI suites above by name with observed, non-zero counts.
5. Localization gate - exit 0; report keys and RU percentage. **Every new string is EN and RU.**
6. Release build if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the exit code you observed and the observed counts; whether each test was **run or
only written**; the exact copy for all three interval cases; how the offending point is marked beyond
colour; how the flagged-list door reaches the panel; and anything you found and did not fix.
