# RV.144 - editing an entry's currency converts it into the car's OLD home currency

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect, reproduced from production

Product owner, 2026-09-08, on an imported Volvo whose Garage home currency is now **USD**:
*"I changed a currency for existing entry from USD to RUB, and after some time... I saw that in the
Log entry became euro (hardcoded?) however, in the garage the currency is USD."*

Two screenshots a minute apart: `2101.75 RUB` and `1942.50 RUB` (dimmed, pending) become
**`28.78 €`** and **`26.59 €`** (converted) - euros, on a car the same screen labels `$`.

## The cause, pinned - and there are TWO copies of it

**Copy 1, the fill-up path the owner actually hit** -
`ManualFillUpFormState.updatedMoney` (`ios/App/Sources/EditEntry/EditEntryFormState.swift:88-96`):

```swift
guard let money = originalMoney else {
    return Money(amount: derivedTotal, currency: currency, homeCurrency: homeCurrency)
}
let withCurrency = currency == money.currency ? money : money.replacingCurrency(currency)
return withCurrency.replacingAmount(derivedTotal)
```

**Copy 2, the non-fill path** - `editedMoney` (`:127-131`), same shape:

```swift
let base = original ?? Money(amount: amount, currency: currency, homeCurrency: homeCurrency)
```

In both, when the entry **already carries money** the base is the ORIGINAL pair and the
`homeCurrency` argument the caller passed is **discarded**. The caller does supply the right value
(`buildUpdatedFill` passes `vehicle.homeCurrency`, `:66`; `EditEntryView.swift:306` the same), so
this is a stale value being preserved, not a missing one. The edit correctly clears the snapshot for
re-conversion (`Money.replacingCurrency` -> `resetSnapshotForEdit`, hard rule 3), but the pair keeps
`homeCurrency = EUR` - stamped when the import wrote the row while the car was still EUR - and the
S8 backfill then converts RUB -> **EUR** at the entry's own date (`MoneyBackfillService.outcome`
resolves `store.snapshot(original: money.currency, home: money.homeCurrency, ...)`).

`EditEntryView.swift:161,168` also carries a literal `?? .eur` fallback. It is **not** this path -
`vehicle` is non-nil there in practice - but it is the same assumption written down, and it is the
"hardcoded" the owner suspected. Fix it or justify it in your report.

**Related, do NOT fix here:** the three USD rows on that car are still *pending*, which proves
[RV.140]'s re-home never ran for it - had it run they would have snapshotted at rate 1. That is
[RV.143]'s territory (a home-currency change arriving by sync). Stay out of it.

## What to build

**1. An entry edit re-homes to the car's CURRENT home currency.**
Apply the caller's `homeCurrency` to the base pair in **both** copies. **Reuse
`Money.rehomed(to:)`** (`ios/Sources/TankbookCore/Money/Money.swift:182-194`) rather than writing a
second re-homing rule - it already encodes the invariants: a pair carrying a snapshot is returned
byte-identical (hard rule 3), a re-homed pair whose currency equals the new home snapshots at rate 1
with no fetch, and one that still differs stays pending asking for a rate into the NEW home.

**Mind the order of operations and say which you chose and why.** `rehomed` refuses to touch a
snapshotted pair, while `replacingCurrency`/`replacingAmount` deliberately clear the snapshot. An
edit that changes amount or currency must end up re-homed AND re-pending; an edit that touches
neither must leave a snapshotted pair byte-identical. Getting this wrong in either direction is the
defect: one way silently restates history (hard rule 3), the other leaves the bug in place.

**Consider extracting the shared shape.** The two copies are the same function with different
argument names. If one core-side helper can serve both, write it once; if they genuinely differ,
say why in your report rather than duplicating a third time.

**2. A currency edit that CAN resolve resolves at commit - the owner's "why not immediately?"**
Today the conversion waits for the next automatic pass's S8 backfill. [RV.88] already established
the precedent for the import commit: `MoneyBackfillService.backfill(_:limitedTo:)` +
`AppRates.drainAfterImport` resolve an import's own rows instead of waiting for the whole-garage
sweep. **An entry edit has the same claim and no equivalent.** Give it one, reusing the scoped
backfill - do not write a second drain.

Two cases, and they are different:
- **The edited currency equals the car's home currency**: `Money.rehomed`/`Money.init` snapshot it at
  rate 1. This needs **no network at all** and must be resolved before the sheet closes. This case
  must never depend on connectivity (hard rule 1).
- **The edited currency is foreign**: attempt the scoped resolve from the cache, and if the rate is
  not there the row stays rate-pending and counted. A miss is a silent non-event (F9), never an
  error, never a blocked save, and **never** a conversion at today's rate (hard rule 3, [RV.88]'s
  defect).

## Explicitly out of scope

- [RV.143] (a home-currency change arriving by sync) and [RV.140]'s Garage-side pass.
- [RV.145] (the divider's mixed-currency sum and the symbol-everywhere change) - you will see the
  `$`-over-euros defect on the same screen. **Do not fix it here**; it has its own row and another
  agent takes it next. Do not change `LogEntryAmount` or any divider/tile rendering.
- The rate feed itself ([RV.135], [RV.139]). Assume rates may never arrive.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money, and the conversion semantics.
2. `docs/SYNC.md` -> S8 (the backfill is silent).
3. `docs/ERRORS.md` -> Edit entry, and F9.
4. `CLAUDE.md` hard rules 1, 3, 8, 13.

**Extend the docs in the same change** where this adds behaviour they do not describe - that an edit
re-homes, and that a resolvable edit resolves at commit, both belong in `docs/SCHEMA.md` -> Money.

## Checks

Baseline on `main` as left: **1675 tests / 187 suites**, **777** localization keys at 100% RU,
`swift build` 0, `swiftlint lint` 0 errors **from the repo ROOT**. **Re-measure yourself and report
what you observe** - do not copy these numbers into your report.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then these UI suites **by name**:
   `-only-testing:TankbookUITests/EditEntryUITests` and
   `-only-testing:TankbookUITests/HomeUITests`.
   **Report the observed count for each and check it is non-zero** - a filter matching nothing
   prints "0 tests ... passed" and still exits 0. Note that several RV suites in this repo are
   `extension HomeUITests`, so a class-name filter for them matches nothing; that is why
   `HomeUITests` is named here rather than a sub-suite.
5. Localization gate - exit 0; report the key count and RU percentage.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1, the row's whole point**: an entry written with `homeCurrency: EUR` on a vehicle whose
  `homeCurrency` is now USD, edited to currency RUB, ends up with `money.homeCurrency == .usd`.
  Assert the **home currency**, not that the edit saved.
- **L1**: the same edit where the new currency equals the car's home currency is snapshotted at
  **rate 1** with **no fetch** - assert the stub fetcher's request count is 0.
- **L1**: an edit that changes neither amount nor currency leaves a **snapshotted** pair
  byte-identical (hard rule 3).
- **L1**: a foreign edit with no rate in the cache stays rate-pending, is counted, and asks for a
  rate into the **new** home currency.
- **L1**: both paths - the fill-up (`updatedMoney`) and the non-fill (`editedMoney`) - are covered.
  A test for only one leaves half the defect shipped.
- **L4**: edit an entry's currency and see the row resolve without leaving the screen, for the
  same-currency case.

### Vacuous traps, named

- Asserting the entry's `currency` changed without asserting its `homeCurrency` - the row is
  entirely about the second field.
- Fixing `updatedMoney` and leaving `editedMoney`, or the reverse.
- Rewriting a **snapshotted** pair to the new home currency - that breaks hard rule 3 and silently
  restates history. `rehomed` already refuses; do not work around it.
- Converting at today's rate to make the commit-time resolve produce a number ([RV.88]'s defect).
- A fixture where the vehicle's home currency already equals the entry's - it passes today.
- Making the save await a network call, or fail/block when offline (hard rule 1).

## Screenshots

One screen, **EN and RU**, **dark** theme, captured **outside** any running test (`simctl` and
`xcodebuild test` fight over the device): the Edit-entry sheet after a currency edit that resolved.
Commit to `design/screenshots/` as `RV.144-edit-entry.png` and `RV.144-edit-entry-ru.png`.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Pass `-homeResetDatabase` alongside any seed - seeds are idempotent and silently do nothing on a
populated database.
**You cannot see your own screenshots** - the orchestrator opens every one. State what you captured
and how; do not assert they look right.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## This brief's diagnosis is a hypothesis - confirm it before you change anything

The line numbers were read on the tree as left; verify them. Four of the orchestrator's diagnoses in
recent sessions were wrong and an agent caught every one. If the two copies turn out not to be the
cause, **report that with evidence** rather than making the tests match the brief.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each new test was
**run or only written**; your new tests run against the CURRENT code first (they must fail) and then
against your fix; which order of operations you chose for re-home vs snapshot-clearing and why;
whether you extracted a shared helper or kept two; what you did about the `?? .eur` fallback; and
any defect you found and did not fix.
