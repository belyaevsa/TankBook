# PJ.23 - Edit entry can edit a service's line items

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## Read this first: HALF of this row already shipped, four hours ago

`PJ.23` is *"Edit entry edits service line items (title / category / cost) **and Expense
category**"*. The **Expense category half shipped on 2026-09-10 as [RV.195]** (`24f4acc`) - filed
from the product owner's report without anyone noticing this row had been open since **2026-08-31**,
marked PRIORITY.

**So your scope is the SERVICE half only**, and RV.195 is your worked example: read
`EditEntryNonFillView.categoryRow` and `EditEntryView.saveNonFill`'s `case var expense` arm to see
exactly the shape this row wants, one entry kind over.

## The defect

Open a service in Edit entry and you get **a Vendor field and nothing else**. A service's **line
items** - the actual work: *"Замена масла"*, its category, its cost - are invisible and
uneditable. `EditEntryNonFillForm` has no `items` at all
(`ios/App/Sources/EditEntry/EditEntryFormState.swift:96`), and `saveNonFill`'s `case var service`
arm writes only `service.vendor`, so **the items ride through every edit untouched and unshown**.

That matters more since [RV.187]: a service's Log row is now titled from its **first named line
item** when it has no vendor. So the row can read *"Замена масла"* while the screen that opens it
cannot show or change that text. An **imported** service gets its items from the Drivvo kind
column - the importer's guess - and hard rule 13 requires a derived value to be editable at the
moment it is offered **and afterwards**.

## What the row asks for, verbatim

> L1: `.other("x")` -> `.oil` keeps title, cost, attachments, links.

That sentence is the acceptance: **promoting a category must lose nothing**. `.other(String)` is the
escape hatch the schema gives an unknown category, and J7 promises it is *"promoted later without
data loss"*.

## What to build

`ServiceEntryFormState` already models this for the CREATE path -
`items: [ServiceEntryItemDraft]` with title, category and cost, summed into the header total
(`ServiceEntryFormState.swift:55,92-111`). **Reuse that draft type rather than inventing a second
one**, or the two paths will drift the way `pristineNonFillForm` and `loadNonFill` were deliberately
merged to avoid ([RV.31]).

1. `EditEntryNonFillForm` carries the items, loaded by `pristineNonFillForm` - **the same single
   source the discard baseline compares against**, so a changed item reads as an unsaved edit. Get
   this wrong and a swipe-back loses the user's work silently (hard rule 8); `RV.195` has an L1 for
   exactly this and you should have its twin.
2. The service branch of `typeCard` renders the items: title, category, cost per row.
3. `saveNonFill`'s `case var service` arm writes them back.
4. **Decide and state** whether this row adds or deletes items or only edits the ones that exist.
   Editing is what the row asks for; add/delete is a bigger surface. **Either is acceptable - saying
   which you chose, and why, is not optional.**

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one. In
particular **check what a service with NO items renders today** and what it should render - an empty
list, or nothing at all. And check whether `ServiceItem` has any field the edit path must preserve
untouched (`partNumber`, `lifetime`) - **it does**, and dropping one on save is data loss.

## Explicitly out of scope

- The Expense category (**shipped as `RV.195`** - do not redo it).
- `PJ.22` (the lifetime editor - km/months on an item) and `PJ.26`/`PJ.27` (tire sets, seasonal
  reminders). They touch the same items; they are separate rows. **Preserve `lifetime` on save;
  do not build an editor for it.**
- The CREATE path (`ServiceEntryView`). It already works.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> **ServiceRecord** and **ServiceItem** - every field you must round-trip.
2. `docs/JOURNEYS.md` -> J7, and the sentence about `.other` promoted without data loss.
3. `ios/App/Sources/EditEntry/EditEntryNonFillView.swift` + `EditEntryView+Discard.swift` -
   `RV.195`'s expense category, which is this row's pattern.
4. `CLAUDE.md` hard rules 8 and 13.

## Environment axes this crosses

**Locale**: a user-facing surface, so **EN and RU screenshots**, dark theme. RU runs 20-30% longer
and a category name plus a cost on one row is exactly where that bites - **check the row does not
truncate in RU**. Add capture lines: `RV.176` now fails CI on a committed frame no line produces.
The existing `PJ.28-expense` pose is the neighbouring pattern; a service pose may need a seed - say
which you used.

## If this adds a failure path, what makes it visible in production?

An item silently dropped on save is invisible to the user until they look. If your save path has a
branch that can lose one, add the shape-only event that answers *"did an edit drop a line item?"* -
**counts only**, never a title or a cost (hard rule 12).

## Tests you must add

- **L1, the row's own acceptance**: an item at `.other("x")` promoted to `.oil` keeps its **title,
  cost, partNumber, lifetime**, and the record keeps its attachments and links. Oracle: `SCHEMA.md`'s
  ServiceItem field list - assert every field, not the two you changed.
- **L1, and it FAILS TODAY**: an edited item title reaches the stored `ServiceRecord`. On today's
  code `saveNonFill` writes only `vendor`, so this is red before your change.
- **L1**: changing an item marks the form dirty (the `RV.195` twin - without it a swipe-back loses
  the edit).
- **L4 `EditEntryUITests`, EN and RU**: open a service, change an item's title, save, reopen, see it.
  And - the [RV.187] tie - the **Log row's title follows the edited item**.
- **L1**: a service with no items renders without crashing and saves unchanged.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Delete the `service.items = ...` line from `saveNonFill`'s service arm** - reproducing exactly
today's state - and show the "an edited item title reaches the stored record" L1 goes red. Then
restore byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Asserting the item row EXISTS** rather than that an edit round-trips. The row exists in a
  read-only form today; existence proves nothing.
- Writing `title` and `category` and silently dropping `partNumber` or `lifetime` - the row's own
  acceptance sentence says *keeps title, cost, attachments, links*, and `PJ.22`/`PJ.26` depend on
  those fields surviving.
- A second item-draft type beside `ServiceEntryItemDraft`, so the create and edit paths drift.
- Loading the items somewhere other than `pristineNonFillForm`, so the dirty check cannot see them.
- Re-implementing the Expense category. It shipped.

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
5. `xcodegen generate`, then `EditEntryUITests` **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.

Verify by **exit code** (`echo $?`).

## Report back

Whether you chose edit-only or add/delete and why; what a service with no items renders; every check
with its **exit code observed** and counts; **the mutation's red-then-green output verbatim**; what
you captured, in both locales; whether RU truncates; and **anything you found and did not fix**.
