# RV.199 - a service's total and its line items must agree, or say why they do not

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Scenario: J7 · Service visit.** Every task names its parent journey (`CLAUDE.md`, 2026-09-10), and
**a change to what the user is promised edits `docs/JOURNEYS.md` in the same change**.

## The defect, and why it is urgent now

`REVIEW-SERVICE`'s walk (`diagnostics/REVIEW-SERVICE-2026-09-10.md`) calls this a **precondition of
`RV.198`, not a follow-on**: *"shipping add/delete while the total stays stale IS the RV.199 bug."*

`RV.198` shipped hours ago. **A user can now add a line for 50.00 and the header Amount does not
move.** The create path derives the header from the items
(`ServiceEntryFormState.swift:169-171`, *"the sum of the items' exact costs"*); the EDIT path
(`EditEntryNonFillView`'s money card) leaves Amount at its stored value. **So the same service shows
two different totals depending on which door you came through.**

## The decision, made - confirm it, do not silently re-open it

**Amount stays independently editable, and the screen states the line sum beside it whenever the two
disagree.** It is NOT silently derived on the edit screen.

Three reasons, all already in this codebase:

- **An invoice's grand total legitimately differs from its lines** - tax, a discount, a line the user
  did not itemise. This is the same truth `hard rule 4` encodes for fuel: *"fuel amount ≠ receipt
  grand total"*. Deriving it would make an honest invoice unrecordable.
- **Hard rule 13**: a value the user set is theirs. Rewriting a stored total because the items now
  sum differently overwrites a fact with a derivation.
- **The create path stays as it is** - deriving the total for a NEW record is a *default*, a
  suggestion the user may type over, which is exactly what hard rule 13 permits.

**What must change is that the disagreement is VISIBLE.** Today it is silent, and silence is the
defect.

**If you find a reason this decision is wrong, say so in your report and stop** - do not implement
the opposite quietly. Four of the orchestrator's decisions were corrected by agents this session and
every correction was welcome.

## What to build

1. **The line sum, shown on the edit screen's money card**, and a stated mismatch when it differs
   from Amount. `docs/ERRORS.md` owns the vocabulary; this is **attention, not an error** - the user
   is not blocked and nothing is wrong with their data. **Amber is attention and never action**
   (hard rule 5), and this must not become a red state or a blocking gate.
2. **The sum is computed by ONE function shared with the create path.** `ServiceEntryFormState`
   already sums the items; extract it or call it. **A second summation is [RV.169]'s complaint**, and
   `RV.167`'s guard exists because a money total was re-implemented six times in this codebase.
3. **Cross-currency is a real case here**: an item cost carries its own `Money`. Decide what the sum
   says when items are in different currencies and **never print a summed cross-currency total**
   (hard rule 3, the `RV.145` rule) - say which currencies, or say it cannot be summed.

## This brief's reading is a hypothesis - confirm it before you change anything

Read `RV.198`'s shipped code (`8a4ba9d`) and `ServiceEntryFormState.swift:169-171` first. In
particular: **does the create path's derived total survive a user typing over it**, or does the next
item edit clobber the typed value? If it clobbers, that is a second instance of this defect on the
create side and it is **in scope** - say so and fix it in the same change.

## Explicitly out of scope

- `RV.200` / `RV.201` / `RV.202` (expense category, late recognition, attachments).
- `PJ.22`, `PJ.26`, `PJ.27` - the reminder and tire halves of this loop.
- The `Money` rate snapshot itself. An item's stored `rateDate` is immutable (hard rule 3); you are
  summing what is there, not re-resolving it.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> **ServiceRecord & ServiceItem**, and **CHECK 3** - the fill-up cross-check
   that is this row's closest precedent.
2. `docs/ERRORS.md` -> the attention vocabulary and the 3-question audit rule. **Extend it with this
   state in the same change.**
3. `docs/JOURNEYS.md` -> **J7**, which `RV.198` already amended. **Amend it again**: what the user is
   promised about the total is changing.
4. `CLAUDE.md` hard rules 3, 4, 5 and 13.

## Environment axes this crosses

**Locale**: new copy, so **EN and RU screenshots**, dark theme, capture lines added ([RV.176] fails
CI on a frame no line produces). The `RV.198-service-items` pose already exists - extend or add
beside it. RU runs 20-30% longer and a sum plus a mismatch sentence on one card is where that bites.
**Currency**: exercise a same-currency and a mixed-currency service.

## If this adds a failure path, what makes it visible in production?

None expected - this shows a figure that already exists. If your implementation can silently fail to
compute a sum (a nil cost, an unresolvable currency), say what the user sees then, and make sure it
is never a blank where a number was (hard rule 7).

## Tests you must add

- **L1, and it FAILS TODAY**: after adding an item, the screen's line sum reflects it. Oracle: the
  items' own exact `Decimal` costs, summed - never a `Double`.
- **L1**: the stored Amount is **unchanged** by any item edit. This is hard rule 13 and it is the
  half a careless implementation gets wrong.
- **L1**: the mismatch state appears when they differ and is absent when they agree - both
  directions, or half of it is untested.
- **L1**: a mixed-currency item set produces **no summed total**, per hard rule 3.
- **L1**: create and edit produce the same sum for the same items - **asserted from both paths**, so
  the two cannot drift.
- **L4 `EditEntryUITests`, EN and RU**: add a line, see the sum move and the mismatch stated; type
  the Amount to match, see it clear.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count. Note that
`RV.198`'s and `PJ.23`'s UI tests are **extensions of `EditEntryUITests`** - filter by that suite
name and **check the count**; a filter on a file name matches zero and prints `TEST SUCCEEDED`.

## The mutation you must run - I am naming it, do not choose your own

**Make the line sum ignore the newest item** (sum `items.dropLast()`) and show the "sum reflects an
added item" L1 goes red. Then restore byte-identical and re-run. Report both outputs verbatim.

That is the mutation because a sum that is merely *present* proves nothing - `PJ.55` and `RV.170` are
this project's monuments to asserting presence.

## Vacuous traps, named

- **Deriving the Amount** and calling the row done. That makes an honest invoice unrecordable and
  overwrites a user's value.
- A second summation beside `ServiceEntryFormState`'s.
- Summing `Double`s. Costs are `Decimal` (`docs/SCHEMA.md` -> Money).
- Printing a cross-currency total.
- Asserting the sum *exists* rather than that it *moved* when an item changed.
- Making the mismatch a blocking gate or a red state - it is attention, and the entry is always
  saveable.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Concurrent work in this checkout

Another `opencode` run has been growing the receipts corpus since 2026-09-10 19:57 and holds
uncommitted changes in `Spike/ReceiptSpike/fixtures/`,
`ios/Sources/TankbookCore/Config/PumpPhotoGate.swift` and `ios/Tests/TankbookCoreTests/Corpus*`.
**Do not touch, revert or `git checkout` any of them.** Also pre-existing and **not yours**: four
`ReminderNotificationActionTests` failures (the simulator's notification daemon drops `add` from a
test-hosted process, documented in that suite's own support file), and `SyncWriteTriggerTests`, which
fails **under machine load** and passes alone - re-run it alone before reporting it.

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

Whether the create path's derived total survives a typed override; every check with its **exit code
observed** and counts; **the mutation's red-then-green output verbatim**; what the mixed-currency
case renders; what you captured in both locales; how you amended `JOURNEYS.md`; and **anything you
found and did not fix**.
