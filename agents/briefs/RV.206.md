# RV.206 - a scan that read everything still cannot be saved

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J7b · Parts, tires, consumables** - the shop receipt. A change to what the user is
promised edits `docs/JOURNEYS.md` **in the same change** (`CLAUDE.md`, 2026-09-10).

## The defect, and how it was found

It was **visible in [RV.200]'s own screenshot the moment that row landed**: an Expense-mode scan
resolves the **category**, the **amount** and the **date**, and *Save* stays disabled. The user must
type a title before a complete scan can be saved.

**The gate**: `ExpenseEntryFormState.canSave` is `hasTitle && amountDecimal != nil`
(`ExpenseEntryView.swift:43`).

**The gate predates the two rows that made it wrong.** [RV.187] now titles the Log row from the
CATEGORY when the title is empty, and [RV.195] made that category a visible, editable field. So the
gate demands a field whose absence **the app already has an answer for**, and turns a complete scan
into a dead end - hard rule 7 in the letter (a next step exists) and not in the spirit (it is typing
something redundant).

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one.

**Find the gate's ORIGINAL reason before you change it.** `git log -S "hasTitle" --oneline` on that
file will show when it was written and against which row. If the title was the only thing naming an
expense at the time, the gate was right then and is stale now - **say so, with the commit**. If it
turns out to have a live reason you have not seen, **stop and report rather than removing it.**

## What to build, and the shape is a judgement call you must state

**An expense with a category and an amount is saveable.** The title stops being required when the
category can name the row.

**But do not simply delete the gate.** Decide and record which of these is right:

- `canSave` becomes `amountDecimal != nil` alone - the category always has a value
  (the code comment says so), so it always names the row; **or**
- `canSave` becomes `(hasTitle || categoryNamesIt) && amountDecimal != nil`, if some category - say a
  bare `.other("")` - genuinely cannot name a row.

**Check `.other("")` specifically.** `L10n.expenseCategoryLabel(.other(""))` renders as *"Other"* -
is an expense called *"Other · 12.40 €"* an acceptable Log row, or the thing the gate was protecting
against? **That question is the row.**

## The sibling, and whether it moves with you

`ServiceEntryView` gates on `form.hasTitledItem` (`:210`, `:478`) - **a service needs a titled line
item.** That is the same shape one entry kind over, and [RV.187] gives a service the same fallback
chain (vendor, then item, then category). **Look at it and say whether it has the same defect.** Do
not change it in this row unless it is genuinely the same line of code - **file it if it is not.**
Three times this session a fix landed on one entry kind and its sibling waited a row ([RV.211]
records the pattern).

## Explicitly out of scope

- [RV.200]'s vocabulary and [RV.205]'s corpus gap.
- The Log row's title chain ([RV.187]) - it already works and is what makes this safe.
- The service gate, unless it is literally the same code.

## Docs to read before writing (in order)

1. `ios/App/Sources/ServiceEntry/ExpenseEntryView.swift:38-49` - the gate and `hasEdits`.
2. `ios/App/Sources/Shared/EntryTitle.swift` - [RV.187]'s chain, the reason this is safe.
3. `docs/ERRORS.md` -> the Expense entry rows. **If the disabled-save hint changes, change it here
   too** - the caption under a disabled button is an error surface (hard rule 7).
4. `docs/JOURNEYS.md` -> **J7b**. Amend what the user is promised about saving a scanned expense.

## Environment axes this crosses

**Locale**: if the disabled-save hint or any copy changes, **EN and RU screenshots**, dark theme,
with capture lines added ([RV.176] fails CI on a frame no line produces). The
`RV.200-expense-category` pose already exists and is the natural one to extend - it is literally the
screenshot this defect was found in. **If no copy changes, say so and re-shoot that pose anyway**,
because the button's enabled state is what changed and that pose shows it.

## If this adds a failure path, what makes it visible in production?

None expected - a gate becomes less strict. Say so. If you add a branch where a save is refused for a
new reason, that reason needs a message naming its next step (hard rule 7).

## Tests you must add

- **L1, and it FAILS TODAY**: an expense with a category and an amount and **no title** is saveable.
  Oracle: [RV.187]'s chain - the Log row names it from the category.
- **L1**: it actually SAVES and the stored row round-trips - not merely that the button is enabled.
- **L1**: the Log row for that entry **reads the category**, so the user can find what they saved.
- **L1**: an expense with **no amount** is still refused. The gate exists for a reason and must not
  simply be deleted.
- **L1**: whatever you decided about `.other("")` is asserted directly.
- **L4 `ExpenseCaptureUITests`**: a scan that reads category and amount can be saved **without
  typing**, and the entry appears in the Log.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count.

## The mutation you must run - I am naming it, do not choose your own

**Restore `hasTitle &&` in `canSave`** and show the "saveable without a title" L1 goes red. Then
restore byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Asserting the button is enabled** rather than that the entry saved and the Log row names it.
  `PJ.55` and `RV.170` are this project's monuments to asserting an affordance.
- Deleting the gate entirely, so an expense with no amount saves as a blank row.
- Changing the service gate as a drive-by without checking it is the same defect.
- Removing the disabled-state hint copy and leaving the button silently inert.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08. **`git log -S`
and `git show` are fine** - they write nothing.

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
`SyncWriteTriggerTests` ([RV.203]) which fails under machine load and passes alone - six times now;
re-run it alone before reporting it.

## Standing checks

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone.**
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0.

Verify by **exit code** (`echo $?`).

## Report back

**The gate's original reason and the commit that introduced it**; which shape you chose and why; what
you decided about `.other("")`; **whether the service gate has the same defect** - a finding either
way; every check with its **exit code observed** and counts; **the mutation's red-then-green output
verbatim**; what you captured; and **anything you found and did not fix**.
