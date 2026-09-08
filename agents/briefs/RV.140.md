# RV.140 - a home-currency change never reaches the entries, and the Log hides money it knows

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The report, from a real car

Product owner, 2026-09-08, on a car whose imported entries are USD: *"Previously, the home currency
for that car was Eur, but all imported entries are USD. I changed home currency in the garage to USD
and expected to see prices in a log journal. But didn't see. Also, worth to display sum even in
currency filled up tank anyway."*

The screenshot shows **381 entries pending rates** and Log rows reading
`40.0 L · Diesel · 426 220 km · 18 Aug 23` - with **no amount at all**.

## Two independent causes, both pinned

### 1. The change touches the vehicle and nothing else

`VehicleDetailFormState.swift:133` sets `vehicle.homeCurrency = homeCurrency`. That is the whole
change. Each entry's `Money` carries its **own** `homeCurrency`, stamped when the entry was written
(`Money.swift:105-109`), so 381 rows still say "my home is EUR" and still need a USD->EUR rate that
[RV.135]/[RV.139] cannot yet supply. The setting looks like it should fix them and does nothing.

### 2. A pending row renders no money at all

`HomeSections.swift:522`:

```swift
guard let money = entry.money, let homeAmount = money.homeAmount else { return nil }
```

`money.amount` and `money.currency` are both known - the app has "45.00 USD" and shows nothing.

## Design questions ALREADY CLOSED

1. **Re-home the PENDING entries only.** Hard rule 3 protects **snapshots**; a rate-pending entry
   has none, so there is nothing immutable to preserve. An entry carrying a snapshot keeps its
   `homeCurrency` untouched - rewriting one would silently restate history that was true when it was
   recorded.
2. **The owner's case must need no network.** After re-homing, those 381 rows have
   `currency == homeCurrency`, and `Money.init` (`:103-109`) already snapshots that pair at **rate
   1** immediately. The pending count should go to zero with **no fetch at all** - assert that.
3. **A mixed history is legitimate and must survive.** A car with some snapshotted EUR rows and some
   pending USD rows is a real state. Decide what it does, say so, and make the snapshotted rows
   provably untouched.
4. **Never convert at today's rate** to fill a gap. Hard rule 3, and [RV.88]'s defect.
5. **The unconverted amount is MARKED as such.** Showing `45.00` bare, where every other row shows a
   home-currency figure, invites reading a USD number as EUR. It must be visibly the original.

## What to build

- The re-homing pass. **`MoneyBackfillService.outcome(for:)` (`:217-223`) is the shape to mirror**:
  it already walks entries, guards on `money.isRatePending`, and rewrites the money. Put the new
  work beside it rather than inventing a second traversal, and drive it from the point where the
  vehicle's currency actually changes.
- The Log row showing the original amount when no home amount exists.
- **Write both into `docs/SCHEMA.md` -> Money** in the same change: what a home-currency change does
  to existing entries, and that a pending row displays its original.

## Explicitly out of scope

- [RV.135] and [RV.139] - the rate supply. This row must work without them.
- [RV.142] (the Log row's title, station and consumption). **It edits the same file
  (`HomeSections.swift`) and is dispatched separately** - touch only the money rendering.
- The vitals tile and Trends ([RV.112]).

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 3 and 13.
2. `docs/SCHEMA.md` -> Money (**the authority**: `rateDate` is the entry date, snapshots immutable,
   backfill fill-blanks-only).
3. `docs/SYNC.md` -> S8.
4. `docs/ERRORS.md` -> the Home F9 row (pending rates).

## Checks

Baseline: `main` green at **1657 tests / 184 suites**, **777** localization keys, `swift build` 0,
`swiftlint` 0 errors **from the repo ROOT**. **Re-measure yourself** and report what you observe.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + the UI suites you touched **by name**; report a **non-zero** count - a
   filter matching nothing prints "0 tests ... passed" and still exits 0, which cost a whole
   verification round on [RV.132].
5. Localization gate - 0, report the key count.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1, the row's point**: changing a car's home currency re-homes its pending entries **and leaves
  every snapshotted entry byte-identical**. Assert both halves in one test, so a fix that rewrites
  history fails.
- **L1**: after the change, an entry whose currency now equals home is snapshotted at **rate 1 with
  no fetch** - assert against a fetcher that would fail if called.
- **L1**: a mixed history keeps its snapshotted rows in their original home currency.
- **L4**: a rate-pending row displays its original amount and currency, and is **visibly distinct**
  from a converted row.

### Vacuous traps, named

- Rewriting snapshotted entries - breaks hard rule 3 and silently restates history.
- Converting at today's rate.
- Asserting the pending **count** fell without asserting a specific entry's money.
- Showing the original amount unmarked, so a USD figure reads as home currency.
- Testing with a car whose entries are all pending, where the "leave snapshots alone" half cannot
  fail.

## Screenshots

The Log with pending rows showing their original amounts, dark, EN and RU:
`design/screenshots/RV.140-log-original-amount.png` and `-ru.png`. Pass the reset flag with the
seed, take them **outside** a test run, and **OCR your own capture** before reporting it.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, what
you decided for the mixed-history case, and how you marked an unconverted amount. Name any closed
decision you think is wrong and stop there rather than absorbing it.
