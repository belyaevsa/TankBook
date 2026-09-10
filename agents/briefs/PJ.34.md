# PJ.34 - the F9a sheet renders the suggestions the validator already computes

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**PRIORITY (product owner, 2026-08-31)** and unbriefed for ten days. It was **blocked until
2026-09-10**: `RV.192` changed what CHECK 2 produces, and rendering suggestions computed by the rule
being fixed is the wrong order. That row shipped, so this one is unblocked.

## The defect - and it is bigger than the row says

`TimelineValidator.EntryValidation.suggestions` is an **ordered resolution list**
(`TimelineValidator.swift:41-44, 56-57`): `.fixOdometer` and `.fixDate(requiresExplicitConfirmation:)`,
ranked so that **when a receipt or QR carries a printed date, that date is ground truth** - "fix
odometer" ranks FIRST and changing the date is marked as needing explicit confirmation.

The orchestrator checked two things before writing this brief. Confirm both:

1. **No caller passes `attachments:`.** Every one of the six `TimelineValidator.validate(...)` call
   sites omits it (`ManualFillUpFormState.swift:268`, `ManualFillUpView.swift:656`,
   `EditEntryView.swift:330`, `EditEntryFormState.swift:78`, `TimelineNeighbourhood.swift:77`,
   `ServiceEntryFormState.swift:176`), so `receiptDateIsGroundTruth` is **always false** and the
   receipt-priority ranking never happens in production at all.
2. **Nothing renders `suggestions`.** `rg -n "\.suggestions" ios/App/Sources` finds only
   `ReceiptAttachMerge`'s blank-fields-only suggestions and the vehicle catalogue's - different
   things entirely.

So the ranking is **computed on every validation, pinned by `TimelineValidationTests` (lines
239-282 assert the exact order), and consumed by nothing.** That is `RV.129`'s shape - *"tested
decisions that production does not use"* - and a cousin of `RV.196`'s dead fields: a dead OUTPUT
rather than a dead field. The tests are green and protect a decision no user ever sees.

## What to build

1. **Pass `attachments:` at the call sites that have them.** The confirm and edit paths know the
   entry's attachments; the receipt-priority ranking is worthless until they do. **A call site that
   genuinely has no attachments passes none and that is correct** - say which are which.
2. **The F9a sheet renders the suggestions in the validator's order**, rather than the fixed layout
   it uses today. Order comes from the model, never from the view.
3. **Preselect "Fix odometer"** when it ranks first.
4. **"Fix date" requires an explicit confirmation** when
   `requiresExplicitConfirmation` is true, and the confirmation **names the evidence**: *"the receipt
   says <date>"*. A user overriding a printed receipt should be told what they are overriding.
5. **Add "Move entry"** as the row lists.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one. Here,
specifically:

- **Find the F9a sheet before assuming its shape.** `docs/ERRORS.md` -> Confirm -> F9a and
  `docs/JOURNEYS.md` -> F9a are the authority; the sheet may be `OdometerConflict`'s rendering in
  `ManualFillUpFormState`/`ConfirmManual` rather than a separate view. **Say what you found.**
- **"Move entry" may not exist as a concept.** If nothing can move an entry between cars or dates in
  the sense the row means, that is a FINDING - report it rather than inventing the operation. A
  feature built on an action nothing implements is `docs/DEFECT-PATTERNS.md` Part 2's shape.
- `RV.192` just landed: re-read `suggestions(flags:receiptDateIsGroundTruth:)` as it is **now**, not
  as an older row described it.

## Explicitly out of scope

- `RV.129` itself - this row removes ONE instance of that shape; do not go after the other four.
- The validator's ranking RULE. It is decided and tested; you are consuming it, not re-deciding it.
- `RV.188`'s neighbourhood panel. It renders the pair, not the suggestions.
- `PJ.45`'s pace limit row, which shipped hours ago.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> **Confirm -> F9a** - the authority on this surface's copy and its next steps.
   **Extend it in the same change** if the confirmation sentence is new.
2. `docs/JOURNEYS.md` -> **F9a**.
3. `docs/SCHEMA.md` -> Validation, and the PRIORITY note the row cites for receipt-date priority.
4. `CLAUDE.md` hard rules 7 (every error names its next step) and 13 (the app suggests, the user
   decides - a ranked suggestion is still a suggestion).

## Environment axes this crosses

**Locale**: new user-facing copy, so **EN and RU screenshots**, dark theme, capture lines added
([RV.176] fails CI on a frame no line produces). RU runs 20-30% longer and *"the receipt says
<date>"* is a composed sentence - **a full localised phrase per language, never a date spliced onto
a shared stem** (hard rule 10; the P1.4 RU pass proved this). **Scanned vs typed** is the row's own
axis: the ranking differs, so exercise both.

## If this adds a failure path, what makes it visible in production?

None expected - this renders a value that already exists. If your change can silently fall back to
the old fixed order (an empty `suggestions`, say), say what the user sees then, and make sure it is
never a blank sheet (hard rule 7).

## Tests you must add

- **L1, and it FAILS TODAY**: the confirm path passes `attachments:`, so an entry with a
  receipt-dated attachment gets `.fixOdometer` FIRST. Oracle: `TimelineValidator`'s own documented
  rule, and `TimelineValidationTests:239-254`, which already pin both orders.
- **L1: rendered order == model order.** Not "both suggestions appear" - the ORDER, because the
  ranking is the row's whole content.
- **L4 `ConfirmManualUITests`, EN and RU**: a scanned prefill carrying a timestamp preselects "Fix
  odometer", and choosing "Fix date" requires an explicit confirmation naming the receipt's date.
- **L4**: a TYPED entry with no attachment gets the other order and no extra confirmation.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Drop the `attachments:` argument at the confirm call site** - restoring today's state exactly - and
show the "fix odometer ranks first" L1 goes red. Then restore byte-identical and re-run. Report both
outputs verbatim.

That is the mutation because the missing argument, not the missing UI, is why the ranking has never
run in production.

## Vacuous traps, named

- **Asserting both suggestions are present.** They are both computed today; presence proves nothing.
  Assert the ORDER and the preselection.
- Hardcoding the order in the view "to match" the model - then the model is still unconsumed and the
  test passes on a coincidence.
- A confirmation dialog that does not name the date it is overriding: *"Are you sure?"* fails hard
  rule 7 and defeats the row's point.
- Passing `attachments:` at a call site that has none, just to make a signature uniform.
- Inventing "Move entry" if nothing implements moving.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1907 tests / 229 suites**, **835** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone** - on 2026-09-10 four
   `SyncWriteTriggerTests` failed purely from contention with a parallel build.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.

Verify by **exit code** (`echo $?`).

## Report back

Where the F9a sheet actually lives; which call sites now pass `attachments:` and which correctly do
not; **whether "Move entry" exists as an operation** - a finding either way; every check with its
**exit code observed** and counts; **the mutation's red-then-green output verbatim**; what you
captured in both locales; and **anything you found and did not fix**.
