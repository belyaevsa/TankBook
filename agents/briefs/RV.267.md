# RV.267 - a cancelled expense scan stays in memory

**Scenario: J7b · the shop receipt (a cancelled expense scan).** Small; the sibling `RV.245`
found and the seam it built.

`ExpenseEntrySession` keeps `pendingCapture` / `pendingPrefill` / `pendingPreset` set and its
deferred read running when `ExpenseEntryView` is dismissed without a save, so
`ExpenseEntryView.load` (`:393-417`, re-find) pre-fills the NEXT expense from the scan the user
abandoned. No disk orphan (expenses stage no page files) - memory, not files, a different decision
from RV.245, the same seam.

## Build

`ExpenseEntrySession.discard()` clears the three pending fields and cancels the read through
`DeferredRecognition.cancel()` (RV.245 added it); `ExpenseEntryView` calls it on
dismissal-without-save exactly the way `ServiceEntryView+DiscardPages.swift` does (`onDisappear`
unless `didSave`; X, swipe-down and any discard prompt funnel through one path). Say whether a
read landing AFTER the cancel can still repopulate the session, and pin it.

## Tests

- **L1, FAILS TODAY**: cancel after a staged expense scan leaves the session empty and the read
  cancelled; the next `load` pre-fills nothing.
- **L1**: a saved expense keeps nothing pending either.
- `ExpenseEntryUITests` in its own invocation, count reported. No UI change, no screenshots.

## Mutation - named

Drop the `discard()` call; the cancel L1 goes red. Verbatim.
