# PJ.41 - "Add expense from this receipt" on Edit entry

Journey: J3 mixed fallback (one receipt, several things bought). Product owner, 2026-10-01: build it.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`: `ios/App/Sources/EditEntry/`,
`ios/App/Sources/ExpenseEntry/` (or wherever the expense form and `ExpenseEntrySession` live),
`ios/Sources/TankbookCore/` (only if a core helper is needed), `ios/App/Sources/Localizable.xcstrings`,
the matching tests, `docs/JOURNEYS.md` J3, `docs/SCREENMAP.md` (the new edge), `docs/ERRORS.md` (if a
failure path is added). Nothing under `ios/Sources/TankbookCore/Extraction/PumpReader/` - another
session has uncommitted work there.

## Write code first, explore second

## What exists (confirm before you change anything - this is a hypothesis)

- `purchaseGroupId` is on every entry kind (`ios/Sources/TankbookCore/Persistence/Records.swift`, the
  v1 JSON schemas `fillUp`, `expense`, `serviceRecord`, `chargeSession`), migrated
  (`Migrations.swift`), and the Log already groups entries that share it into one purchase moment
  (`ios/Sources/TankbookCore/Consumption/LogStream.swift:20, 350, 366`). The capture path already
  creates groups for a mixed receipt (`Extraction/MixedReceipt.swift`). So the data model needs no
  change - this row is a door, not a schema.
- Edit entry (`ios/App/Sources/EditEntry/`) shows an entry's receipt attachment (`EditEntryView+Attachment`,
  `AttachmentPhotoChip`, `heldPages`).
- The expense form opens from the capture path with a pre-fill through `ExpenseEntrySession`.

## What to build

On Edit entry, for an entry that has a receipt attachment, an action **"Add expense from this
receipt"** (RU a full phrase, e.g. "Добавить расход из этого чека"). It opens the expense form
pre-filled with the entry's date and car, the same attachment, and the shared `purchaseGroupId`:

- If the source entry already has a `purchaseGroupId`, the expense takes it.
- If it has none, create one and write it to **both** the source entry and the new expense, in one
  write, only when the expense is saved. Cancelling the expense leaves the source entry untouched -
  no orphan group id.
- The attachment is shared, not copied: the expense references the same stored receipt (find how
  attachments are referenced - by `sha256`/blob id - and reuse it; never a second copy of the image).
- After saving, the Log shows the source entry and the expense as one grouped purchase.
- The action is absent when the entry has no attachment.
- Sync: both writes go through the normal entry-write path so they sync like any edit (hard rule 1:
  works offline).

**Out of scope:** PJ.16, PJ.42, PJ.43 (separate rows). Splitting a receipt's lines automatically -
that is the capture path's job and exists.

## Docs to read, in order

1. `docs/SCHEMA.md` -> `purchaseGroupId` (line ~89) and the mixed-receipt section (~647) - authority
   for what the group means.
2. `docs/JOURNEYS.md` J3 mixed fallback.
3. `docs/DESIGN.md` - action placement on Edit entry; `docs/SCREENMAP.md` - add the edge
   Edit entry -> Expense form.
4. `docs/SYNC.md` - only to confirm an edit of the source entry syncs normally.

## Checks (exit codes; report each)

- `scripts/gate.sh` exit 0. If you add a `#if DEBUG` seed for the UI test, also `RELEASE=1
  scripts/gate.sh` exit 0.
- The UI suite covering Edit entry (`EditEntryUITests` or the file that tests `EditEntryView`), its own
  `-only-testing:` run; read the COUNT.

## Tests you must add

- **L1/L2:** saving the expense from an entry without a group writes the same new `purchaseGroupId` to
  both; from an entry with one, reuses it; cancelling writes nothing. Oracle: the group id read back
  from the database for both rows. **Mutation:** skip the write of the group id to the source entry -
  the "both share it" test must go red.
- **L2:** the expense references the same attachment as the source (same blob id), and no new blob is
  stored.
- **L2 Log:** `LogStream` over the two rows yields one purchase group.
- **L4 UI:** the action is visible on an entry with an attachment and absent on one without; tapping it
  opens the expense form with the date filled.

## Vacuous traps

- A group id written to the expense only - the Log then shows two separate moments.
- A copied attachment (a second blob) instead of a shared reference.
- A group id written at the moment the action is tapped, leaving an orphan when the user cancels.

## Screenshots

EN and RU, dark, outside a test run: Edit entry with the action, and the expense form it opens.
`design/screenshots/PJ.41-edit-entry-action.png` / `-ru.png`, `PJ.41-expense-prefilled.png` / `-ru.png`.
`terminate` before re-launching with new arguments. You cannot see screenshots: state what you captured.

## Standing fences

- `swiftlint lint` from the repo ROOT. Check test COUNTS, not only exit codes.
- Never stash, move or `git checkout` for a baseline; mutate one line to prove a test, then restore.
- Never `pgrep -f` / `pkill -f`. Never move, rename or revert a file you did not create.
- Assert frames against the window, not `isHittable` alone. Git is read-only for you.

## Report back

Exit codes; test counts before/after; run-or-written per test; the mutation's red-then-green output;
how attachments are referenced and how you shared it; **anything you found and did not fix**.
