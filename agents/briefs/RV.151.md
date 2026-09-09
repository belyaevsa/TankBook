# RV.151 - a rate lookup cannot cross the EUR base

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect, and what is NOT the defect

Product owner, 2026-09-09, on an imported USD car carrying RUB and PLN entries: *"the problem is
that they haven't been resolved during the import, but must be."* 381 rows are rate-pending.

**The ask is not what is missing.** [RV.88]'s `drainAfterImport`
(`ManualFillUpCurrencySupport.swift:220-250`, scheduled from `ImportFlowModel+Wizard.swift:337`)
already computes the imported span and chunk-fetches it through `RateStore.fetchSpan`
(`RateStore.swift:247-274`), which pages under the server's 400-day cap. **Do not rebuild that, and
do not change what is fetched.**

**The lookup is what is missing.** `RateStore.snapshot(original:home:on:)` (`RateStore.swift:75-93`)
resolves a pair only two ways:

```swift
// 1. direct:  base == home && quote == original
// 2. inverse: base == original && quote == home   -> 1 / rate
return nil
```

Every fetch asks `base: .eur` (`fetchSpan`'s default, `drainAfterImport`, `fetchAndMerge`), so the
cache holds `(EUR -> X)` rows. Therefore:

| The car's home | The entry's currency | Needs | Today |
|---|---|---|---|
| EUR | anything | `(EUR, original)` | direct hit |
| anything | EUR | `(home, EUR)` | inverse hit |
| **USD** | **RUB** | `(USD, RUB)` | **nil - neither present nor invertible** |

The cache holds `(EUR,USD)` **and** `(EUR,RUB)` for that same day, and the lookup still returns nil,
so the row stays rate-pending permanently. That is the owner's exact configuration and why 381 rows
survived every drain.

**This is independent of [RV.139].** RV.139 is that no `/v1/rates/pack` request leaves the device at
all; fixing it would still leave these rows pending. Do not touch RV.139's territory.

## What to build

**Derive the cross rate through the pack's base, on the device:**

```
home -> original  =  (base -> original) / (base -> home)
```

with **both legs read from the same day** - which the pack already contains. No new request, no new
endpoint, nothing added to the wire (hard rules 1 and 9). Work out the direction from
`docs/SCHEMA.md`'s conversion semantics and the existing `converted(using:)` arithmetic
(`Money.swift:126-131` computes `homeAmount = amount / rate`) rather than trusting the formula
above - **the direction is the thing worth being certain about**, and an inverted rate is a wrong
number that looks plausible.

**Keep the existing paths first.** Direct, then inverse, then derived. A derived rate is the
fallback, never the primary, so a pack that carries the pair outright is still used as-is.

**Decide what `RateSource` a derived snapshot records** and say why. Both legs are `.ecb`, but a
snapshot the app *computed* rather than received is a different provenance, and hard rule 3 makes it
immutable once written - so it must be right the first time, not corrected later. Record the
decision in `docs/SCHEMA.md` -> Exchange rates.

**Do not** fall back to a nearby day, and **do not** convert at today's rate: a day missing either
leg stays rate-pending and counted (F9, hard rule 3, and [RV.88]'s defect). A miss is a non-event.

**Precision**: `Decimal` throughout, no `Double`. The rate is stored as computed; only the converted
amount rounds, to the home currency's minor units, exactly as `Money.converted(using:)` already does.

## Explicitly out of scope

- [RV.139] (no rate request leaves the device) and [RV.135]'s feed.
- Changing what `fetchSpan`/`drainAfterImport` ask for, or adding a second request.
- [RV.144]/[RV.143]'s re-homing, and [RV.145]'s rendering.
- Any server change. A base-conversion endpoint would be hard rule 9.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money and Exchange rates - **the authority for conversion direction, and
   extend it** with the derived-rate rule and its source decision.
2. `docs/SYNC.md` -> S8 (the backfill is silent).
3. `docs/ERRORS.md` -> Home, F9 (a miss is a non-event).
4. `CLAUDE.md` hard rules 1, 3, 9.

## Checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1776 tests / 203
suites**, **808** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it reports thousands of phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count.
4. UI suites: **none expected** - this is core. If you touch `ios/App/Sources`, name the suite you
   ran and its observed, non-zero count.
5. Localization gate - exit 0; report keys and RU percentage. No new user-facing strings expected.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

### Tests you must add

- **L1, the row's whole point and it FAILS TODAY**: a USD-home car with a RUB entry resolves from a
  pack holding `(EUR,USD)` and `(EUR,RUB)` for that day. Assert the resulting **rate value** against
  the two legs, and the converted **amount**, not merely that a snapshot exists.
- **L1**: the direct and inverse paths are unchanged, **to the cent**.
- **L1**: a day missing either leg stays pending; a day missing only the cross pair still resolves.
- **L1**: the derivation round-trips - deriving `USD->RUB` and `RUB->USD` from the same pack gives
  reciprocal rates.
- **L3**: importing a multi-currency file onto a non-EUR car leaves **zero** rows pending when the
  packs cover the span. This is the owner's scenario end to end.

### Vacuous traps, named

- **A fixture whose home currency is EUR** - it passes today and proves nothing.
- Asserting the snapshot is non-nil without asserting its **value**. An inverted cross rate is
  non-nil, plausible, and wrong.
- Deriving the two legs from **different days**.
- Falling back to a nearby day, or to today's rate, to close a gap ([RV.88]'s defect).
- Changing what is **fetched** instead of what is **looked up** - the pack already holds the data.
- Doing the arithmetic in `Double`.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change - or mutate one line to
prove the test's teeth. **Do not** `git stash`, `git checkout`, or move files out of the tree: an
agent did that on 2026-09-08 and a bad `mv` loop destroyed three of its own new files. Here the
headline test genuinely fails on the current code, so run it first and show that output.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## Report back

Every check with the **exit code you observed** and the observed count; whether each test was **run
or only written**; the failing-then-passing output for the headline test; **how you established the
conversion direction** and against what; what `RateSource` a derived snapshot records and why; and
anything you found and did not fix.
