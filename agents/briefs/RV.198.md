# RV.198 - a service line can be added and removed, not only corrected

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## The defect

Product owner, 2026-09-10, on the [PJ.23] build that shipped an hour ago: *"I don't see an option to
add or delete additional service line in the entry. Neither add, nor delete."*

`PJ.23`'s brief left the choice open - *"decide and state whether this row adds or deletes items or
only edits the ones that exist"* - and its agent chose **edit-only** and said so. That answered the
brief and does not answer the product. **A workshop invoice gains a line as often as it corrects
one**, and the CREATE path (`ServiceEntryView`) already offers both, so the two paths now disagree
about what a service is.

## What to build

Add and delete on the card `PJ.23` built (`EditEntryNonFillView`'s service branch).

**The mechanics already exist.** `PJ.23` deliberately reused `ServiceEntryItemDraft` rather than
inventing a second type, and `ServiceEntryFormState` already models an item collection for the
create path. **Reuse it**; a second add/remove implementation beside the create path's is
[RV.169]'s complaint in a new place.

## The decision you must make and record

**Is an empty item list legal?** A service with no items renders and saves today (`PJ.23` has an L1
for it), so deleting the last row is not obviously forbidden - but a service with no lines and no
vendor titles itself with the bare word *Service* ([RV.187]'s last resort). Decide, and write the
reason where the code enforces it. **Either answer is acceptable; not choosing is not.**

## The trap that will cost you data if you skip it

`ServiceRecord` carries **`usedParts`** and **`tireSetId`** alongside `items`. **Before you delete an
item, find out whether either links to items by POSITION or by id** - `rg -n "usedParts|tireSetId"
ios/Sources ios/App/Sources` and read the writers. If anything indexes by position, a delete
silently re-points a link at the wrong line, which is worse than the missing feature.

Say what you found even if the answer is "nothing links to items".

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one. Read
`PJ.23`'s shipped code (`fd57e7b`) first: the loader, the save arm in
`EditEntryView+NonFillSave.swift`, and how `pristineNonFillForm` builds the baseline. **Your add and
delete must go through that same baseline**, or the dirty check will not see them.

## Explicitly out of scope

- **[RV.199]** - the header total not following item costs. It is filed, it is a DECISION about
  whether Amount is derived, and it is not this row. **Do not derive the total as a side effect.**
- `PJ.22` (the lifetime editor). Preserve `lifetime` on every item you keep; do not build an editor.
- The create path. It already works.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> **ServiceRecord** and **ServiceItem**, including `usedParts` and `tireSetId`.
2. `docs/JOURNEYS.md` -> **J7** and **J7b** - the invoice the user is holding, and the parts shelf.
3. `ios/App/Sources/ServiceEntry/ServiceEntryFormState.swift` - the collection to reuse.
4. `CLAUDE.md` hard rules 8 (nothing lost silently) and 13.

## Environment axes this crosses

**Locale**: new controls and probably new copy, so **EN and RU screenshots**, dark theme, with
capture lines added ([RV.176] fails CI on a frame no line produces). The `PJ.23-service-items` pose
already exists - extend or add beside it. RU runs 20-30% longer; a delete affordance plus a cost on
one row is where that bites.

## If this adds a failure path, what makes it visible in production?

A delete is destructive and a mis-linked `usedParts` would be silent. If your delete has a branch
that can orphan a link, add the shape-only event that answers *"did a service edit drop a link?"* -
**counts only**, never a part name or a cost (hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: adding an item and saving stores it with every field; the record's
  existing items are untouched.
- **L1**: deleting an item removes exactly that one and preserves the rest **including `partNumber`
  and `lifetime` on its neighbours**. Oracle: `SCHEMA.md`'s ServiceItem field list.
- **L1**: the dirty check sees an add **and** a delete - a swipe-back must not lose either (hard
  rule 8). `PJ.23` has the twin for an edit; yours is beside it.
- **L1**: whatever you decided about the last item is asserted directly.
- **L1**: `usedParts` / `tireSetId` survive a delete of an unrelated item - or, if they link by
  position, that the link is re-pointed correctly.
- **L4 `EditEntryUITests`, EN and RU**: add a line, save, reopen, see it; delete a line, save,
  reopen, it is gone. Note `PJ.23`'s tests live as an **extension of `EditEntryUITests`**, so filter
  by that suite name and **check the count** - a filter on the file name matches zero and prints
  `TEST SUCCEEDED`.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Make the delete a no-op** - drop the removal from the form's item collection while leaving the
button - and show the delete L1 goes red. Then restore byte-identical and re-run. Report both
outputs verbatim.

That is the mutation because "the button exists and nothing happens" is exactly the shape this row
exists to remove, one level down.

## Vacuous traps, named

- **Asserting the button exists** rather than that the stored record changed. `PJ.55` and `RV.170`
  are this project's monuments to that mistake.
- An add that writes a blank item the user then cannot remove.
- Renumbering that silently reorders the remaining items.
- A second add/remove implementation beside `ServiceEntryFormState`'s.
- Deriving the header total while you are in there - that is `RV.199` and it is a decision, not a
  cleanup.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Concurrent work in this checkout, 2026-09-10

Another `opencode` run has been growing the receipts corpus since 19:57 and holds uncommitted
changes in `Spike/ReceiptSpike/fixtures/`, `ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and
`ios/Tests/TankbookCoreTests/Corpus*`. **Do not touch, revert or `git checkout` any of them.**

Also pre-existing and **not yours**: four `ReminderNotificationActionTests` failures in the app unit
target - the simulator's notification daemon drops `add` from a test-hosted process, documented in
that suite's own support file. And `SyncWriteTriggerTests` fails **under machine load** and passes
alone; if you see it, re-run it alone before reporting it.

## Standing checks

As left, `main` is **1926 tests / 232 suites**, **835** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then `EditEntryUITests` **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.

Verify by **exit code** (`echo $?`).

## Report back

**What links to items and how** - position or id - and what that meant for delete; **what you decided
about the last item and why**; every check with its **exit code observed** and counts; **the
mutation's red-then-green output verbatim**; what you captured in both locales; and **anything you
found and did not fix**.
