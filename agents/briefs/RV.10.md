# RV.10 – the date picker cannot be dismissed without changing the date

Reported by the product owner; **screen named by them**: *edit or add an entry from the Log screen*.
That narrows it to `ManualFillUpDateRow` as used by `EditEntryView` and `EditEntryNonFillView`.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**

## What is actually wrong (verified - do not "fix" the wrong thing)

`ios/App/Sources/ConfirmManual/ManualFillUpSections.swift` → `ManualFillUpDateRow` (~line 545):

```swift
Button { withAnimation(.easeInOut(duration: 0.2)) { showDatePicker.toggle() } } label: {
    HStack { Text(date.formatted(...)); Image(systemName: "chevron.down") }
}
...
if showDatePicker { DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date) }
```

**A dismiss path exists** - the header button toggles it shut. So this is an **affordance bug, not a
missing feature**, and a fix that adds a second way to close it while leaving the first undiscoverable
has missed the point. Three things make it unfindable:

1. The **chevron never flips.** It is `chevron.down` whether the picker is open or closed, so the one
   visual cue that a thing collapses says "expand me" while it is already expanded.
2. The tap target is the **date text at the far end of the header row** - the opposite side from
   where the eye is once a calendar is on screen.
3. Nothing else on the expanded picker suggests a way out. A user who does not already know the row
   is a toggle will tap a date, because tapping a date visibly does something.

## What to build

Make the exit discoverable, without adding a modal or a second concept:

- **Flip the chevron** to `chevron.up` while the picker is open. This alone is most of the fix.
- Consider whether the whole header row (not just the date text) should be the toggle target, and
  whether the expanded picker deserves a "Done"-style affordance. Use your judgement, and **say in
  your report what you added and what you deliberately did not** - the risk here is over-building a
  one-line problem.

**The invariant that defines success: opening the picker and closing it again must leave the date
byte-identical.** Not "approximately the same day" - the same `Date`.


## Do not touch `docs/TASKS.md`

The orchestrator marks the row after verifying your work. Editing it from an agent is the conflict
class that forces iOS dispatch to be sequential: resolving a `TASKS.md` conflict by side silently
un-ticks a task (`HANDOVER.md`), and it cost a scattered commit on 2026-09-03. Report what you did;
the row is not yours to tick.

## Explicitly out of scope

- The picker's own behaviour, its `in: ...Date()` past-only range, or the date format.
- `ConfirmManual`'s use of the same row - it shares the component, so your change lands there too,
  which is fine and expected; just do not restructure that screen.
- `ServiceEntrySections`' separate date card - it has the same `toggle()` shape but is a different
  component. **Note in your report whether it has the same defect**; do not fix it here.
- Any backend file.

## Read before writing

1. **`CLAUDE.md`** - hard rules 5, 10, 13 (the app suggests, the user decides - a date the user did
   not choose must never be written), 14.
2. `docs/ERRORS.md` → **Edit entry**, and `docs/DESIGN.md` for motion (the row already animates with
   a 0.2 s `easeInOut`; nothing else animates beyond system defaults).
3. `ios/App/Sources/ConfirmManual/ManualFillUpSections.swift`,
   `ios/App/Sources/EditEntry/EditEntryView.swift`, `EditEntryNonFillView.swift`.

## Tests

- `cd ios && swift test` - **1154 today; must not fall.**
- L4 in `EditEntryUITests`: open the picker on Edit entry, dismiss it **without touching the
  calendar**, and assert the date field's value is unchanged. Then assert the dismiss affordance is
  hittable while the picker is open.

**Vacuous-assertion traps, named:**
- **A test that changes the date first proves nothing.** The bug is specifically the *no-change* exit.
- Asserting the picker element disappears, without asserting the date survived. Both halves or it
  is not a test of this bug.
- Asserting the chevron's `systemName` - XCUITest cannot read it. Assert behaviour and hittability;
  verify the glyph by screenshot and say so.

**Mutation-check**: revert your change, re-run, and report whether the new test went red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** swiftlint from the repo root; zero **errors**;
`file_length` at 700 is an error and `EditEntryView.swift` is already ~670 lines.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`**.

"Failed to load the test bundle" is contention, not a red - re-run once.

## Screenshots

`design/screenshots/RV.10-date-picker-open.png` and `-ru.png`, dark, outside any test run - the
point of the shot is the **flipped chevron and the dismiss affordance**, so frame the header row.

## Report back

- Exit codes, test counts, suites RUN, mutation result.
- What you added and what you deliberately did not.
- Whether `ServiceEntrySections` has the same defect.
- Files changed, docs extended, anything unfinished.
