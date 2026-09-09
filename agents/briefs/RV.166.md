# RV.166 - a purchase group's total sums a rate-pending member as zero

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. If a file is in your way or a test is red that is not yours, report it and carry on.

## The defect

`LogStream.group(id:members:)` (`ios/Sources/TankbookCore/Consumption/LogStream.swift:367-378`):

```swift
/// A purchase group's display figure (RV.145): the sum of the members'
/// KNOWN home amounts (never a rate-pending line summed as zero), paired
/// with the ONE home currency they share …
let grandTotal = members.reduce(Decimal.zero) { partial, member in
    partial + (member.money?.homeAmount ?? Decimal.zero)      // ← it does exactly that
}
let knownHome = Set(members.compactMap { … money.homeAmount != nil … })
…
grandTotalCurrency: knownHome.count == 1 ? knownHome.first : nil,
```

**The comment describes the opposite of the code.** `knownHome` goes nil only when the known lines
span currencies or none is known - so a group with **two known EUR members and one rate-pending
member** has `knownHome == {EUR}`, count 1, and `HomeSections.swift:614-615` renders a **bare total
that silently omits the pending line**.

This is the **sixth** instance of the shape [RV.106], [RV.112], [RV.145] and [RV.147] each fixed on
their own surface - and it is in the file that fixed it everywhere else. It is also the **third**
time a comment has asserted the absence of the bug it sits on (`recordsEqual`'s *"non-`Vehicle`"*,
the station row's `PJ.19` citation).

## Sibling inventory - I ran this, do not repeat it

Every `Decimal.zero` accumulation in `ios/Sources/TankbookCore` and `ios/App/Sources`:

| Site | Verdict |
|---|---|
| `LogStream.swift:369` | **This row.** Sums a pending `homeAmount` as zero and presents it as complete |
| `MonthlySummaryNotification.swift:178` | Same shape - already filed as **[RV.148]** and **deferred by the product owner**. Do not touch it |
| `ImportConversion.swift:483` | **Check and report.** Sums `fill.money?.amount` - the ORIGINAL amount, not `homeAmount` - into an `ImportSummary` spend figure. An original amount is always known, so this may be honest; **say which** |
| `ServiceEntryDraft.swift:94` | **Different semantic, leave alone.** `item.cost?.amount ?? .zero` on a draft form: a cost not yet typed is genuinely zero-so-far, not an unknown rate |
| `InvoiceSplitter.swift:113`, `MixedReceipt.swift:93,288` | **Different semantic, leave alone.** OCR line amounts during extraction, not `Money` pairs with a home currency |

**Report if you disagree with any verdict** - the distinction between these classes is what
[RV.167]'s guard will have to encode, so a correction here is worth more than the fix.

## What to build

**Route the group's figure through `LogStream.MonthTotal.Accumulator`**, the same seam every other
surface now uses ([RV.112], [RV.145], [RV.147]). It is in the same file - there is no reach problem.

**Do not invent a second vocabulary.** Whatever [RV.145] settled for the divider - a marked partial,
or no bare figure - is what a partial group reports. `LogGroup` currently exposes
`grandTotal: Decimal` and `grandTotalCurrency: CurrencyCode?`; if the honest answer needs a richer
type, change it and update `HomeSections.swift:614` with it.

**Rewrite the doc comment in the same change** - it currently describes behaviour the code does not
have (`CLAUDE.md` -> Code comments: current truth only).

**Hard rule 4 still holds**: a purchase group is counted once by its grand total, and the S2
single-count invariant must survive.

## Explicitly out of scope

- [RV.148] (the monthly-summary push) - **deferred by the product owner**, do not fix it here.
- [RV.167]'s architecture test - the next row, built against this one.
- The four "different semantic" sites above.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money, and Recalculation on edit (hard rule 2).
2. `docs/ERRORS.md` -> Home, F9 - what a partial figure is allowed to say.
3. `CLAUDE.md` hard rules 2, 4.

Extend the docs only if this adds behaviour they do not describe; [RV.145] likely covered it.

## Environment axes this crosses

Core logic plus one render site. **If the group header's copy changes at all, it needs EN and RU
screenshots**; if the figure's shape changes but not its words, say so and skip them. No Release-only
seam, no locale-dependent logic, no new failure path - so **no new log line is needed** (say if you
disagree).

## Tests you must add

- **L1, and it FAILS TODAY**: a group of **two known members and one rate-pending member** does not
  report a bare total. **Oracle**: the two known members' own `homeAmount`s - `10.00 + 20.00 = 30.00
  EUR`, with the third contributing nothing because it has no home amount. The honest figure is
  `30.00 EUR` **marked partial with `pendingCount: 1`**, never `30.00` presented as the group's total.
- **L1**: an all-known group is unchanged, **to the cent**.
- **L1**: a group whose known members span two currencies still reports no bare figure (today's
  `knownHome.count == 1` behaviour, preserved).
- **L1**: the group's classification **agrees with the accumulator** for the same members - assert
  through the shared seam, never a parallel sum written in the test.
- **L4** if the header's rendering changes: the group header in the partial state.

## The mutation you must run - I am naming it, do not choose your own

**Restore `?? Decimal.zero` in the group's accumulation** (or bypass the accumulator and sum
directly). The two-known-plus-one-pending test **must go red**. Then restore and re-run. Report both
outputs. A mutation you pick yourself proves sensitivity to that edit; this one is the row's headline
claim.

## Vacuous traps, named

- A fixture with **no pending member** - it passes today and proves nothing.
- Asserting the total **changed** without asserting it is **marked partial or withheld**.
- Fixing the sum and leaving the comment that says it was never broken.
- Writing a seventh summation instead of using the accumulator.
- "Fixing" it by making `grandTotalCurrency` nil whenever anything is pending - that hides a figure
  the app legitimately knows, which is the mirror of the defect ([RV.106] already proved partial is
  printable).

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left, and another agent (`RV.141`) may have moved things.
**Verify the partial-group case actually renders a bare total before you fix it** - if
`grandTotalCurrency` turns out nil in that case for a reason I missed, report that and stop.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1808 tests / 209
suites, all green**, **811** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then any UI suite you touch by name with an observed, **non-zero** count -
   a filter matching nothing prints "0 tests … passed" and still exits 0.
5. Localization gate - exit 0; report keys and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output**; your verdict on
`ImportConversion.swift:483`; whether you disagree with any sibling verdict above; and anything you
found and did not fix.
