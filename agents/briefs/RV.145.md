# RV.145 - the Log's month divider prints a sum of euros with a dollar sign

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect, from the owner's screenshot (2026-09-08)

The `AUGUST 2023` divider reads **`91 $`** directly above rows of `36.06 €`, `28.78 €`, `26.59 €`
and three still-pending USD rows. 36.06 + 28.78 + 26.59 = **91.43**. So the app summed **euros** and
printed the total with a **dollar sign**.

**Two independent mechanisms, both live.**

**1. The symbol and the figure are read from different objects.** The divider takes its symbol from
the VEHICLE (`HomeSections.swift:345-346`, `AddVehicleSupport.currencySymbol(for: vehicle.homeCurrency)`
-> `$`), while each row takes its own money pair's home currency
(`HomeSections+LogStream.swift:179` -> `€`). Same screen, two currencies, nothing said.

**2. The sum itself is currency-blind.** [RV.112] moved every month-spend derivation through one
accumulator (`LogStream.swift:498-524`), and its rule is:

```swift
public mutating func add(_ money: Money?) {
    if money?.isRatePending == true { pendingCount += 1 }
    else if let amount = money?.homeAmount { self.amount += amount }
}
```

It **never reads `money.homeCurrency`**. A garage holding entries homed in two currencies - which
[RV.144], [RV.143] and [RV.140] all produce legitimately - yields a number that is not a quantity of
anything. This is hard rule 2's defect in its purest form: a derived figure asserting a falsehood.
It survived [RV.106] and [RV.112] because both fixed the pending/known axis and neither questioned
the currency axis.

**The good news**: after RV.112 the accumulator is the single seam. Fix it there and every surface
inherits the fix.

## What to build

### 1. A total is only printable when its addends share one home currency

Extend `MonthTotal` (or the accumulator's result - your call, say why) so a month whose **known**
figures are homed in more than one currency **cannot be expressed as a bare number**. This is the
same move [RV.106] made for the pending axis, applied to the second way a sum can lie.

**Carry the home currency WITH the amount**, so a renderer physically cannot pair a figure with a
foreign symbol. A figure and a symbol read from two different objects is the bug; passing them
together is the fix.

**Decide and record what the mixed case DISPLAYS** - the dominant currency's subtotal, a
per-currency breakdown, or a marked "mixed" state. Write the decision into `docs/ERRORS.md` -> Home
with its reason. **Do not** convert between home currencies to force a single number ([RV.88]'s
defect, hard rule 3).

**All five surfaces** RV.112 touched inherit this: the Log month divider, the Home vitals tile
(`HomeSections.swift:242`), the guest strip (`HomeGuestLayout.swift:102`), `VehicleVitals`
(`VehicleVitals.swift:20`) and the Trends spend tile and series (`TrendsView.swift:146`,
`TrendsStats`).

### 2. Symbols everywhere (product owner, 2026-09-08 - DECIDED, do not relitigate)

Every money figure renders with its currency's **symbol**, converted or not: `2416.00 $`, never
`2416.00 USD`.

This **reverses** `LogEntryAmount`'s current rule (`HomeSections+LogStream.swift`, the
`homeEntryAmountPending` branch passes `money.currency.rawValue` as the symbol). That rule existed so
an unconverted figure could not be read as a home-currency one; that job now belongs to the dimming,
the row's footnote and the divider's pending phrase - and **this row's own fix is what makes it
safe**, by ending the two-currencies-on-one-screen state that made the code necessary.
**Rewrite `LogEntryAmount`'s doc comment in the same change** - a comment still asserting the old
contract is part of the defect (`CLAUDE.md` -> Code comments).

**The trap, and it is not hypothetical.** `AddVehicleSupport.currencySymbol(for:)`
(`AddVehicleForm.swift:163-170`) returns **the empty string** when the symbol equals the code:

```swift
return symbol.caseInsensitiveCompare(code.rawValue) == .orderedSame ? "" : symbol
```

So CHF - which the currency chips actually offer - renders as `2416.00 ` with **no currency marker
at all**. "Symbols everywhere" must go through a resolver that **falls back to the code**;
`currencyLabel` (`:173-176`) already does exactly that fallback and is the model. Make the fallback
a named, tested path, not an accident.

## Explicitly out of scope

- [RV.147] (`ConsumptionEngine.costPerKm` still sums pending rows as zero). It is the next row and
  will reuse whatever you build here. Do not fix it.
- [RV.143] / [RV.140] (re-homing entries). This row makes a mixed history **display honestly**; it
  does not eliminate it, and must not try to.
- The currency chip row ([RV.146]) and the rate feed ([RV.135], [RV.139]).
- Converting between currencies anywhere, for any reason.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money, and Recalculation on edit (hard rule 2).
2. `docs/ERRORS.md` -> Home, F9 - and **extend it** with the mixed-currency decision.
3. `docs/DESIGN.md` -> the vitals tile, Trends, and the money type rules - **extend it** with the
   symbols-everywhere rule and the code fallback.
4. `CLAUDE.md` hard rules 2, 3, 5, 6, 7, 10.

## Checks

Re-measure the baseline yourself and report what you observe; do not copy numbers from this brief.
As left, `main` was **1694 tests / 190 suites**, **777** localization keys at 100% RU, `swift build`
0, `swiftlint lint` 0 errors **from the repo ROOT**.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. (Run it from the root, not from `ios/`: the
   `excluded:` paths are root-relative and it reports thousands of phantom errors from elsewhere.)
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then these UI suites **by name**, each with its **observed, non-zero** count:
   `TankbookUITests/HomeUITests`, `TankbookUITests/TrendsUITests`, `TankbookUITests/GarageUITests`.
   A filter matching nothing prints "0 tests ... passed" and still exits 0 - and several RV suites
   here are `extension HomeUITests`, so a class-name filter for them matches nothing.
5. Localization gate - exit 0; report the key count and RU percentage. Any new string is EN **and**
   RU (hard rule 10).
6. Release build only if you touch a `#if DEBUG` seam (a test seed is one). Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1**: a month whose known figures are homed in two currencies is **not** reported as a bare
  number by any of the five surfaces.
- **L1**: the symbol rendered beside a figure always belongs to that figure - assert it for a car
  whose `vehicle.homeCurrency` differs from an entry's `money.homeCurrency`. This is the one that
  fails today.
- **L1**: a single-currency month is unchanged, **to the cent**, on all five surfaces.
- **L1**: every money figure renders a symbol, and the ISO code appears **only** for a currency whose
  symbol resolves empty. Assert CHF explicitly - it is the live case.
- **L4**: the owner's exact scene - a USD car with EUR-homed rows - renders no `$` on a euro sum.
- **L4**: a rate-pending row is still visibly distinct from a converted one once both carry symbols.
  This is the risk the code-not-symbol rule was protecting against, so it is **asserted, not
  assumed**.

### Vacuous traps, named

- Changing the symbol lookup without fixing the **sum** - a wrong number, correctly labelled.
- A fixture where the vehicle's home currency equals every entry's: it passes today.
- Asserting the divider changed without asserting the vitals tile, the guest strip, `VehicleVitals`
  and Trends did too - that split is exactly how this survived [RV.106] and [RV.112].
- Rendering an empty symbol for CHF and calling it "symbols everywhere".
- Converting between home currencies to produce a single figure (hard rule 3).
- Leaving `LogEntryAmount`'s doc comment asserting the code-not-symbol contract.

## Screenshots

Two screens, **EN and RU**, **dark** theme, captured **outside** any running test (`simctl` and
`xcodebuild test` fight over the device): the Log with a mixed-currency month, and the Trends spend
tile in the same state. Commit as `design/screenshots/RV.145-log.png`, `RV.145-log-ru.png`,
`RV.145-trends.png`, `RV.145-trends-ru.png`.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Pass `-homeResetDatabase` alongside any seed - seeds are idempotent and silently do nothing on a
populated database. **You cannot see your own screenshots**; state what you captured and how, and do
not assert they look right.

## This brief's reading of the code is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. If the accumulator turns out not to be the single seam,
report that with evidence rather than forcing the change through it.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; the fail-then-pass (or mutation) evidence for the two headline tests; what you
decided the mixed case displays and why; how the empty-symbol fallback is expressed; and anything you
found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line.

**Do not** `git stash`, `git checkout`, or move files out of the tree to get a clean baseline. On
2026-09-08 an agent did exactly that and a bad `mv` loop destroyed three of its own new files; the
same loop would have taken a concurrent session's uncommitted work. Assume you are not alone in this
checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**
