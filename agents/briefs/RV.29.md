# RV.29 – a foreign price rendered with the home currency symbol

Reported by the product owner with a screenshot: a **RUB-home** car shows **`1.919 ₽`** for a fill
that was **1.919 EUR**. The number is the original, the symbol is the home currency, and the pair is
a lie — a direct **hard rule 3** violation (*money is a pair: original + home with a rate snapshot*).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`. **Do not run `git add` or `git commit`.**
**Do not touch `docs/TASKS.md`.** Touch no `backend/` file — another agent is working there.

## The cause, verified — and the asymmetry is the clue

`ios/Sources/TankbookCore/Consumption/HomeStats.swift`:

- **`monthSpend` converts.** It sums `entry.money?.homeAmount`, so a fill with no rate contributes
  nothing and the tile correctly reads `0 ₽` beside the `1 entry pending rates` note (F9). Right.
- **`lastUnitPrice` does not.** It returns `fill.unitPrice` raw — **no conversion, no currency
  attached** — and `HomeVitals` then renders it through
  `HomeFormat.unitPrice(_:symbol:)` with the **home** `symbol`.

Two neighbouring tiles, one correct and one not, both stamped `₽`.

The broken `cis` feed only made it *visible* (the rate was pending, so the mismatch was obvious).
**The defect is present whenever a fill is foreign**, rate or no rate.

## What to build

`lastUnitPrice` must carry its currency rather than being a bare `Decimal`. Then the tile has a real
choice, and **you must make it explicitly and write it down**:

- show the **converted home** price — but then the pending case needs its own treatment, exactly as
  `monthSpend` has one, because there is nothing to show yet; or
- show the **original with the original's symbol** (`1.919 €`) — honest, and it needs no rate.

**Showing a converted value while the rate is pending is not an option** — there is no such number.
Pick one, say why in your report, and record it in the code where the next reader will find it.

## Audit the neighbours in the same change

This is a shape, not one line: **any surface rendering an entry figure with a home `symbol`** has
it. Check at least `Trends` and the entry detail. The Log row on the reported screen escapes only
because it prints `26.9 L · 92 · 78 000 km` and no money at all.

**Say in your report which surfaces you audited, which were affected, and which you fixed** — and
leave alone anything that is genuinely a different problem, naming it rather than silently widening.

## Explicitly out of scope

- The rate feeds and the backfill (RV.15/19/20/32/36 — landed or in flight elsewhere today).
- `monthSpend`, which is correct.
- Rewriting any stored `money` value. **Hard rule 3: snapshots are immutable** — an entry converted
  at some rate keeps it. This task changes *display*, never stored data.
- Any `backend/` file.

## Read before writing

1. **`CLAUDE.md`** — hard rule 3 above all (money is a pair, `rateDate` is the entry date, snapshots
   immutable), plus 6 (numbers in DIN, units subordinate), 10 and 14.
2. `docs/SCHEMA.md` → **Money**, and the consumption/stat definitions.
3. `docs/ERRORS.md` → the rate-pending rows (F9) — if the pending case gains a treatment, it is a row
   there.
4. `ios/Sources/TankbookCore/Consumption/HomeStats.swift`,
   `ios/App/Sources/Home/HomeSections.swift` (`HomeFormat.unitPrice`, `HomeVitals`).

## Tests

- `cd ios && swift test` — **1165 today; must not fall.**
- **L1 on `HomeStats`, which is where this belongs**: a foreign fill with **no** rate must not
  produce a home-currency price. That single test is the whole defect.
- L4 only if a screen's copy or layout changed.

**Vacuous-assertion traps, named:**
- Asserting `lastUnitPrice` is non-nil. It was non-nil throughout the bug.
- Asserting a formatted string contains `€`. Build the case from a **foreign fill on a home-currency
  car** and assert the whole rendered value — a substring check passes on `1.919 € ₽`.
- Testing only a same-currency fill. That is the case that already worked.

**Mutation-check and report it**: return the bare original again and confirm the L1 test goes red.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' build ; echo "APPBUILD=$?"

**Judge by the exit code you echoed.** Zero lint **errors**.

Match the process NAME (`pgrep -x xcodebuild`). **Never `pgrep -f` or `pkill -f`** on a build/test
pattern — an agent's brief is part of its command line.

## Screenshots

Only if a tile's rendering changed — it probably did, so
`design/screenshots/RV.29-home-vitals.png` and `-ru.png`, dark, outside any test run, **seeded with a
foreign fill on a home-currency car** so the shot actually shows the case. A screenshot of a
same-currency car proves nothing. Install the newest `DerivedData/Tankbook-*` (`ls -dt`).

## Report back

- Exit codes, test counts before/after, suites RUN, the mutation result.
- **Which display you chose** (converted home, or original with its own symbol) and why.
- **Which surfaces you audited**, which were affected, which you fixed, and what you left.
- Confirmation that no stored `money` value is written by your change.
- Files changed, docs extended, anything unfinished — named plainly.
