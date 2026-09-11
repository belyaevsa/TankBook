# PJ.22 - a line item's lifetime, and the reminder it proposes

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J7 · Service visit** - *"app proposes the next reminder"*. A change to what the user is
promised edits `docs/JOURNEYS.md` **in the same change** (`CLAUDE.md`, 2026-09-10).

**PRIORITY (product owner, 2026-08-31)**, unbriefed for eleven days, and it was **blocked** until
`PJ.62` was decided last night.

## The decision that unblocked it - implement it, do not re-open it

`PJ.62`, decided 2026-09-11 from the greps rather than from memory:

> **`Reminder.sourceEntryId` is the single link. `ServiceRecord.proposedReminderId` is DROPPED.**

The evidence: `sourceEntryId` is **written non-nil in production** (`ReminderLifecycle.swift:223`)
and **read** (`ReminderOfferSession.swift:64` keys the offer by it). `proposedReminderId` has **no
writer and no reader anywhere** - `RV.196`'s guard reports it and `PJ.63` confirmed it. They encode
the same fact in opposite directions, and the reverse direction is a local query the app can always
make. **Two pointers for one relationship is two sources of truth**, which is what
`RV.169`/`RV.170`/`RV.171` exist to prevent.

**So this row's text is out of date where it says "write `proposedReminderId`". Do the opposite:
delete the field, its migration column and its schema line**, and cite `sourceEntryId` in
`docs/SCHEMA.md` where `proposedReminderId` was described.

**`RV.196`'s guard currently reports `ServiceItem.lifetime` behind an exception naming THIS ROW as
its writer.** When you ship the editor, **delete that exception** - the stale-exception check fails
until you do. That is the mechanism working; `PJ.45` and `PJ.26` both did exactly this.

## What to build

1. **A lifetime editor (km / months) on a service line item.** `ServiceItem.Lifetime` already exists
   with `km` and `months`. [PJ.23] built the item editor and [RV.198] gave it add and delete; this is
   one more field on that row.
2. **On save, propose the next reminder**, anchored at **the record's own date and odometer**, not at
   today. J7's promise is *"Oil change in 15,000 km or 12 months?"*, and `PJ.27` shipped the same
   shape hours ago for the tire swap - *"Отсчёт от этой записи, а не от сегодняшнего дня"*.
3. **Accept / decline on the sheet.** The proposal is a **suggestion** (hard rule 13): declining
   leaves no reminder, and the interval is editable before accepting **and afterwards**.

## The seam - and a second reminder path is the one forbidden outcome

**`ReminderOffer` is the seam. Use it.** `PJ.27` used it for the tire swap and the row before it
said so explicitly. `RV.169`/`RV.170`/`RV.171` are three shipped guards against exactly the shape
where a second minting path is written and nothing fails, and `RV.171`'s own guard now fails a second
receipt-binding site. **Adding a second reminder-minting path here would be writing the defect three
guards exist to catch.**

Read `ReminderOffer.swift`, `ReminderDraft.swift` and `ReminderLifecycle.swift` before writing
anything, and say which entry point you used.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one - two of
them last night. In particular:

- **`ReminderOffer.defaultInterval(for:)` deliberately returns nil for `.tires`** (`PJ.27`'s note).
  Find out what it returns for the service categories you are proposing from, and whether an
  item-level lifetime should override it. **Say what you found.**
- **The row claims it "unlocks the km-lifetime odometer rule."** Check whether that rule exists and
  what it needs; if it does not, that is a finding, not a thing to build.

## Explicitly out of scope

- `PJ.61` / `RV.207` - `ServiceItem.partNumber`. It has no editor and, per `RV.207`, the guard cannot
  even see it. **Preserve it on save; do not build its editor.**
- `PJ.27`'s tire swap. Shipped.
- `RV.211` - the service F9a's single Fix. Different row, different screen.

## Docs to read before writing (in order)

1. `docs/JOURNEYS.md` -> **J7** (*"app proposes the next reminder"*) and **J7d** (*a reminder is
   born*). **Amend them** - what the user is promised is changing.
2. `docs/SCHEMA.md` -> **ServiceItem.Lifetime**, **Reminder**, and the `proposedReminderId` line you
   are deleting.
3. `docs/NOTIFICATIONS.md` -> the scenario catalogue and fire timing, before creating a reminder.
4. `ios/App/Sources/Reminders/ServiceReminderOfferSheet.swift` - `PJ.27`'s accept path, including
   `requestPermissionIfFirstReminder`.
5. `CLAUDE.md` hard rule 13.

## Environment axes this crosses

**Locale**: a new editor and a new proposal, so **EN and RU screenshots**, dark theme, capture lines
added ([RV.176] fails CI on a frame no line produces). RU runs 20-30% longer and *"15 000 км или 12
мес"* on one row is where that bites. **Notifications**: the accept path arms a local notification -
reuse `PJ.27`'s, which already covers the denied case; say so rather than adding a second.

## If this adds a failure path, what makes it visible in production?

`PJ.27` added a shape-only swap event. If your proposal can silently fail to arm, add the equivalent
that answers *"was a service reminder proposed, and was it accepted?"* - **counts and outcomes
only**, never a title, an interval or a vehicle (hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: a draft with an item lifetime produces **one** `Reminder`, linked by
  `sourceEntryId`, anchored at the record's date and odometer. Oracle: J7's sentence and the
  record's own values - not today's date.
- **L1**: declining leaves **no** reminder at all (hard rule 13).
- **L1**: the interval is editable before accepting, and editing it afterwards is not overwritten by
  any later default.
- **L1**: exactly **one** reminder per accepted proposal - saving twice does not mint two.
- **L1**: `proposedReminderId` is gone from the type, the migration and the schema, and nothing
  references it.
- **L1**: `RV.196`'s guard **no longer reports `ServiceItem.lifetime`**, and its exception is deleted.
- **L4 `EditEntryUITests` / `RemindersUITests`, EN and RU**: set a lifetime, save, see the proposal,
  accept it, find the reminder. `PJ.23`'s and `RV.198`'s tests are **extensions of
  `EditEntryUITests`** - filter by that suite name and **check the count**.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Anchor the proposal at `Date()` instead of the record's date** and show the anchoring L1 goes red.
Then restore byte-identical and re-run. Report both outputs verbatim.

That is the mutation because anchoring at today is the plausible wrong implementation - it looks
right on a record saved the same day and is wrong for every back-dated one, which is exactly the
case an imported or late-entered service is.

## Vacuous traps, named

- **A second reminder-minting path.** Three guards exist for this.
- Asserting a reminder *exists* rather than that it is anchored where the row promises.
- A proposal that cannot be declined, or an interval that is not editable afterwards (hard rule 13).
- Writing `proposedReminderId` because the row's own text says to - `PJ.62` overrode it.
- Dropping `partNumber` or the item's other fields while adding `lifetime` to the editor.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 and holds uncommitted
changes under `Spike/ReceiptSpike/fixtures/`, `PumpPhotoGate.swift` and
`ios/Tests/TankbookCoreTests/Corpus*`. **Do not touch, revert or `git checkout` any of them.** Also
pre-existing and **not yours**: four `ReminderNotificationActionTests` failures, and
`SyncWriteTriggerTests` ([RV.203]) which fails under machine load and passes alone - it has done so
six times; re-run it alone before reporting it.

## Standing checks

As left, `main` is **1968 tests / 238 suites**, **841** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.
8. **Release build** if you touch a `#if DEBUG` seam.

Verify by **exit code** (`echo $?`).

## Report back

What `defaultInterval(for:)` returns for the service categories and whether an item lifetime should
override it; **whether the "km-lifetime odometer rule" actually exists**; which `ReminderOffer` entry
point you used; every check with its **exit code observed** and counts; **the mutation's
red-then-green output verbatim**; that the guard exception is deleted; what you captured in both
locales; how you amended `JOURNEYS.md`; and **anything you found and did not fix**.
