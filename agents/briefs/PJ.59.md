# PJ.59 - Recently deleted's "Overwritten by sync" section is a fixture

**Scenario: F10 · sync conflicts surface after the fact.** The only v1 row holding F10 open.

`RecentlyDeletedView.swift:21-25,52-54,161-173` renders the section from `-forceSyncOverwritten`,
a DEBUG launch argument, under a comment calling it *"a fixture until P4"* - P4 shipped. `PR.14` is
ticked and its own deliverable (the Edit-entry row and its toast) is real; the sibling surface is
fake and no row tracked it. `PJ.4`'s shape on a section rather than a screen - the blind spot
`RV.162`'s guard states for itself.

## Decide, then build

**Does S8's overwrite record exist in the data?** Read `docs/SYNC.md` S8 and find what `PR.14`
writes when an entry is overwritten. If a record exists, render the section from it and delete the
launch argument's production reach (it may stay as a seed for the UI test). If nothing writes it,
either write it here (it is `PR.14`'s missing half, on the same seam) or delete the section and
correct `SYNC.md` - **say which, with the citation**. A section that exists only behind a debug
flag is neither.

## Tests

- **L1, FAILS TODAY**: an entry overwritten by sync (through the real S8 path, not the flag)
  appears in Recently deleted's overwritten section.
- **L4 `RecentlyDeletedUITests` EN + RU**: the section from a seeded S8 record, not from
  `-forceSyncOverwritten`; screenshots, capture lines.
- **Guard**: extend `ScreenRouteScanner` or add a small one - a view section gated ONLY on a
  DEBUG launch argument is reported. Calibrate on this instance; prove red before the fix.

## Mutation - named

Re-gate the section on the launch argument; the L1 goes red. Verbatim.
