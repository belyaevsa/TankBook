# RV.248 - option (a): a reminder history surface

**Scenario: J7c · reminder lifecycle ("Delete", and the history the copy promises).** Owner
decision 2026-09-12: **(a)** - done and dismissed rows get a surface with their reasons, and the
copy stands.

Today `RemindersView.swift:195-207` collects the dismissal reason, `ReminderLifecycle.dismiss`
persists it (synced), no code reads it back, and `RemindersAllRows.swift:13` excludes `.done` /
`.dismissed` rows before grouping. `JOURNEYS.md:456` and `SCHEMA.md:294,301` promise *"stays in
your history - a reason helps the app learn"*.

## Build

A **History** section (or screen - decide by the artboard; if none exists, a section at the foot
of the merged reminders list is the smaller change, say which) listing terminal rows: done rows
with the entry they were completed by (`.done(entryId)`, tappable to the entry) and the count
line J7c promises (*oil changed 3× on time* is the aspiration - ship the honest version the data
supports and say what it is), dismissed rows with their reason as the row's caption. Rows are
per car in the merged list, the way live rows are. Hard rule 8: nothing here is deletable
without the 30-day undo the rest of the app has.

`docs/SCREENMAP.md` gains the node; `docs/JOURNEYS.md` J7c "Delete"/history text says what
ships; `docs/ERRORS.md` if the empty history state needs copy. `RV.196`/`RV.162`-family guards:
the new surface must be reachable from a live door.

## Tests

- **L1, FAILS TODAY**: the stored reason renders on a dismissed row; a done row names its entry.
- **L4 `RemindersUITests` EN + RU**: dismiss with a reason, open History, the reason is on the
  row; complete one, it appears as done. Screenshots `RV.248-reminder-history` EN + RU, dark.

## Mutation - named

Exclude terminal rows from the history query; the L1 goes red. Verbatim.
