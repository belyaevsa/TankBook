# PJ.26 + PJ.27 - a tire purchase becomes a set, and the set asks to be swapped

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Two rows, one dispatch.** Both are J7b's tire loop and both write through `TireSet`: `PJ.26` links
a set to the expense that bought it, `PJ.27` creates the reminder that swaps it. Splitting them
means touching `TireSet` and the reminder writer twice. Both are **PRIORITY (product owner,
2026-08-31)** and have waited ten days.

## PJ.26 - the defect, and it is a dead field

`docs/JOURNEYS.md` J7b: *"a tire purchase becomes a TireSet."* Today it cannot.

`TireSet.purchaseExpenseId` exists as a **column** (`Migrations.swift:348`) and is written **only as
`nil`** (`TireSetDraft.swift:35`). Nothing in the app can set it, and `TireSetDraft`'s own comment
one line down already says a rename *"must never overwrite it"* - **a promise about a value nothing
can create.**

**That is `PJ.55`'s shape exactly**: a column, a decoder, a comment protecting it, and no writer.
`PJ.55` shipped three features onto `Station.favorite` before anyone noticed the flag could never be
set, and `RV.163`'s guard exists because of it. **Read `PJ.55`'s row before you start** - it is the
worked example for "give a dead field a writer, in the place the user already is".

**What to build**: *"Make this a tire set"* from a `.parts` Expense, writing `purchaseExpenseId`, and
the set shows its purchase. The link is the deliverable, not the button.

## PJ.27 - the defect

J7b: *"swap reminder each season."* A mount record (category `.tires`) should create a **seasonal
swap reminder**, recurring by months, anchored at the mount date. Today mounting a set proposes
nothing, so the loop the journey describes never closes.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one. In
particular:

1. **Confirm `purchaseExpenseId` really has no writer** - `rg -n "purchaseExpenseId" ios/` and read
   every hit. If one exists, say so and this half becomes smaller.
2. **Find out what a "mount record" IS in this tree** before building on the phrase. `PJ.27` says
   *"category `.tires`"*; check whether that is a `ServiceRecord` with a `.tires` item, a
   `TireSet.mountedAt`, or something not built yet. **If the state PJ.27 fires from does not exist,
   that is the finding** - report it rather than inventing the entity, because a feature built on an
   entity nothing creates is the exact shape `docs/DEFECT-PATTERNS.md` Part 2 catalogues.
3. **Read how reminders are created today** (`P3.4`, the reminder writer) and reuse it. A second
   reminder-minting path is `RV.169`/`RV.170`/`RV.171`'s whole complaint.

## Explicitly out of scope

- `PJ.22` (the lifetime editor and `proposedReminderId`). **It is the same dead-field shape on
  `ServiceRecord` and it is sequenced after `PJ.23`** - do not do it here, and do not write
  `proposedReminderId` as a side effect.
- `PJ.23` (editing service line items) - briefed separately, in flight or queued.
- The tire-set list's own screens beyond what these two rows need.

## Docs to read before writing (in order)

1. `docs/JOURNEYS.md` -> **J7b** end to end - the authority on this loop, and the source of both
   rows' sentences.
2. `docs/SCHEMA.md` -> **TireSet**, **Expense**, **Reminder** - every field you write.
3. `docs/NOTIFICATIONS.md` -> the reminder scenario catalogue and fire timing, before you create a
   recurring one.
4. `docs/DEFECT-PATTERNS.md` -> Part 2, the dead-field and unreachable-state shapes. Both rows are
   instances.
5. `CLAUDE.md` hard rule 13 - a proposed reminder is a **suggestion**, never a fact: the user
   accepts or declines it, and once they change it the value is theirs.

## Environment axes this crosses

**Locale**: both rows add user-facing surfaces, so **EN and RU screenshots**, dark theme, with
capture lines added ([RV.176] now fails CI on a frame no line produces). RU runs 20-30% longer -
*"Make this a tire set"* is exactly the button-label length that overflows. **Notifications**: a
recurring reminder is scheduled locally; say whether you exercised the permission-denied path
(`docs/ERRORS.md`).

## If this adds a failure path, what makes it visible in production?

A reminder that silently fails to schedule is indistinguishable from one nobody accepted. Add the
shape-only event that answers *"was a swap reminder proposed, and was it accepted?"* - **counts and
outcomes only**, never a date, a set name or a car (hard rule 12).

## Tests you must add

- **PJ.26, L1 and it FAILS TODAY**: making a set from a `.parts` Expense writes `purchaseExpenseId`,
  and the set still carries it after the expense is EDITED. Oracle: `SCHEMA.md`'s TireSet field.
- **PJ.26, L1**: the link is written **once** - a second "make this a tire set" on the same expense
  does not mint a second set. (Name what it does instead: no-op, or navigate to the existing set.)
- **PJ.27, L1**: a mount creates a reminder **anchored at the mount date**, recurring by months.
  Oracle: J7b's sentence and `NOTIFICATIONS.md`'s timing.
- **PJ.27, L1**: the proposal is declinable, and declining leaves no reminder (hard rule 13).
- **L4** `TireSetsUITests` and `RemindersUITests`: the door exists, the link is visible on the set,
  and the reminder appears in the reminders list. EN and RU.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Set `purchaseExpenseId` back to `nil` at your new write site** - reproducing today's state exactly -
and show the PJ.26 L1 goes red. Then restore byte-identical and re-run. Report both outputs verbatim.

That is the mutation because it recreates the defect as it actually is: the field is written, just
always with nothing in it.

## Vacuous traps, named

- **Shipping the button and asserting the button.** The link is the deliverable; a test that finds
  *"Make this a tire set"* and stops proves nothing that `PJ.55` did not already prove is provable
  while the field stays dead.
- **A second reminder-minting path** beside the existing one.
- Building `PJ.27` on a "mount record" you invented because the real one does not exist. Report
  instead.
- Writing `proposedReminderId` as a convenient side effect - that is `PJ.22`'s row and its own
  acceptance.
- A recurring reminder with no way to stop it. Say how the user cancels the season.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1887 tests / 226 suites**, **831** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone** - on 2026-09-10 four
   `SyncWriteTriggerTests` failed purely from contention with a parallel build.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.
8. **Release build** if you touch a `#if DEBUG` seam.

Verify by **exit code** (`echo $?`).

## Report back

**What a "mount record" turned out to be** - that is the finding even if PJ.27 ships whole; whether
`purchaseExpenseId` really had no writer; every check with its **exit code observed** and counts;
**the mutation's red-then-green output verbatim**; what you captured in both locales; how a user
cancels a seasonal reminder; and **anything you found and did not fix**.
