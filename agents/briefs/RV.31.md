# RV.31 – re-tapping the active tab must return to its root

Reported by the product owner: with an entry open for editing, tapping **Log** (the tab already
selected) does nothing. It should close the entry and return to the Log root. That is the standard
iOS convention and the natural escape hatch when the back affordance is not where the thumb is.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.**

## The cause, verified

`AppTabBar`'s button body is `selection = tab` and nothing else — re-tapping the already-selected
tab is a no-op. Edit entry is a **pushed route** (`Route.editEntry`, rendered by `Destinations`) on
that tab's own `NavigationStack` path, so **popping the path is the correct mechanic — not a
dismiss**. This applies to all three tabs (Log, Trends, Garage), not just the one in the report.

## The fence that matters

**This must never silently discard unsaved work.** Edit entry already tracks `hasUnsavedChanges`
and the app already has a discard-confirmation guard (the same one the Close button uses) — a tab
tap that throws away a half-typed entry would be a **worse bug than the one being fixed** (hard
rule 8: nothing lost silently).

- **No changes**: re-tapping the active tab pops immediately, no confirmation.
- **Unsaved changes**: re-tapping goes through the **same discard-confirmation** the close button
  already uses. **Cancel leaves the entry open and unchanged** — nothing is popped, nothing is
  lost.

Reuse the existing guard; do not write a second one.

## What to build

Detect a tap on the *already-selected* tab (the `AppTabBar` button body currently just sets
`selection = tab`, so you need the "was this already the selection" comparison before that
assignment) and, when it fires, pop that tab's `NavigationStack` path to root — through the same
discard guard a pushed Edit entry already exercises when there are unsaved changes, and
immediately when there are none. A tap that would otherwise change tabs (different tab selected)
behaves exactly as it does today — this only changes the same-tab case.

## Explicitly out of scope

- The discard-confirmation dialog's own copy/behaviour — reuse it, don't rewrite it.
- Any tab-bar visual change.
- Any `backend/` file.

## Read before writing

1. **`CLAUDE.md`** — hard rule 8 (nothing lost silently) above all, and 14.
2. `docs/SCREENMAP.md` → back-path conventions.
3. `ios/App/Sources/Navigation/AppTabBar.swift` (or wherever the tab bar button lives — confirm the
   exact file), `ios/App/Sources/Navigation/TabRoots.swift`, `ios/App/Sources/Navigation/
   Destinations.swift`, and wherever Edit entry's existing discard guard is defined (`EditEntryView`
   / `EditEntryView+Attachment.swift`).

## Tests

- `cd ios && swift build ; swift test` — must not fall from today's count.
- **L4, and assert values, not that a dialog appeared**:
  - Pushed Edit entry, **no edits made**, tap the active tab → the Log root is showing (entry gone),
    immediately, no dialog.
  - Pushed Edit entry, **an edit made** (type into a field), tap the active tab → the discard
    dialog appears; tapping **Cancel** leaves the entry open and the typed field's value is still
    there — assert the field's value, not just that the sheet/dialog exists. A version that
    discards anyway would still pass an existence-only check.
  - Tapping a **different** tab while an entry is open still behaves as today (no regression to the
    ordinary tab-switch path).
- Cover all three tabs if the mechanism is shared; if it genuinely only applies to Log (no pushed
  edit route on Trends/Garage today), say so rather than fabricating tests for routes that don't
  exist yet.

**Vacuous-assertion traps:**
- Asserting the discard dialog `.exists` without checking Cancel actually preserves the typed
  value.
- Testing only the no-edits path, which was never the risky one.

**Mutation-check and report it**: make the same-tab tap always pop without the discard guard, and
confirm the "edit made → Cancel preserves the value" test goes red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build ; echo "APPBUILD=$?"

**Use the `iPhone 17 Pro` simulator for every xcodebuild/xcrun step in this task** — another agent
is using `iPhone 17` concurrently, and `simctl`/`xcodebuild` fight over a shared device.

**Judge by the exit code you echoed.** Zero lint **errors**.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern.

## No screenshots unless a surface visibly changed

The tab bar itself does not change; say none applies rather than fabricating one.

## Report back

- Exit codes, test counts before/after, suites RUN, the mutation result.
- Which tabs the fix covers and why the others were in or out of scope.
- Files changed, anything unfinished.
