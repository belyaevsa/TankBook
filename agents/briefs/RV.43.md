# RV.43 – a UI test that fails on the 1st–6th of every month

`TrendsUITests.testSingleFillShowsOnlyTheTilesThatHaveHonestData` fails today and will fail again on
**1 October**, whatever anyone changes between now and then.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios` — `ios/` and `docs/` only.
**Do not run `git add` or `git commit`. Do not touch `docs/TASKS.md`.** Touch no `backend/` file.

**Never move, rename or delete a file you did not create.** Other sessions work in this checkout.
There is a git worktree at `.claude/worktrees/rv48` that is **not yours** — `swiftlint` reports
errors from inside it; those are not your gate. If something else is broken and is not yours,
**report it and carry on**.

## The cause, verified — confirmed failing on a clean tree

- `-seedHomeSingleFill` writes its fill at **`FillSpec(daysAgo: 6, …)`**
  (`ios/App/Sources/Home/HomeTestSeed.swift:87`).
- `HomeStats.monthSpend` filters entries to the **calendar month of `asOf`**
  (`ios/Sources/TankbookCore/Consumption/HomeStats.swift:151-152`).
- The test's first assertion is `anyElement(app, "trendsSpendTile").waitForExistence(…)`
  (`TrendsUITests.swift:129`).

On 3 September, `daysAgo: 6` lands on 28 August — a different month — so `monthSpend` returns nil,
the spend tile is absent, and the assertion fails. **The orchestrator confirmed it failing on a clean
tree** (`EXIT=65`), and it is unrelated to any change in flight.

**It passes for roughly 24 days a month, which is exactly what makes it expensive**: on the 1st it
will be blamed on whatever landed that morning.

## The fix, and the thing not to do

**The test is right and the seed is wrong.** The test's claim — *"a single fill shows spend and
price, but not consumption or cost/km"* — is a true statement about the product. The seed just picks
a date whose meaning changes with the calendar.

Pin the seed to a date that is **always inside the current month** — the 1st of the current month, or
a `daysAgo` clamped so it cannot cross the boundary. Whatever you choose, the entry must still be in
the past (an entry dated in the future is its own bug).

**Do NOT fix it by relaxing the assertion.** "Assert the tile exists or does not" makes the test
vacuous, and the tile's presence is precisely the product claim under test.

**Do NOT change `monthSpend`.** Filtering spend to the calendar month is correct and is what the
"SEPTEMBER SPEND" tile means.

## Audit the same shape while you are here — this is half the value

Any seed with a `daysAgo` large enough to cross a month boundary, feeding a month-filtered stat, has
this bug latent. **`grep -rn "daysAgo" ios/App/Sources/` is the whole audit.** Report what you found:
which seeds are date-sensitive, which are safe, and which you changed. A seed that is only used by
tests that never touch `monthSpend` is safe — say so rather than changing it.

## Read before writing

1. **`CLAUDE.md`** — hard rule 14, and the standing note that a green suite is not evidence a thing
   is correct.
2. `ios/App/Sources/Home/HomeTestSeed.swift` (`seedSingleFill`, `FillSpec`, `makeFill`),
   `ios/Sources/TankbookCore/Consumption/HomeStats.swift` (`monthSpend`),
   `ios/App/UITests/TrendsUITests.swift:126-135`.

## Tests

- `cd ios && swift build ; swift test` — **1243 today; must not fall.** (Note:
  `CaptureOrientationTests` is `.disabled` on purpose — RV.52. Leave it disabled.)
- **`TrendsUITests` must pass — and you must show it passes on a date where it fails today.** The
  proof is the whole task:
  - state the date you ran it on, and
  - **demonstrate the boundary case**: run it with the simulator's clock set to the 1st of a month
    (`xcrun simctl status_bar` does not move the clock — set the device date in Settings, or reason
    it through by seeding and asserting the computed date). If you cannot move the clock, **say so
    plainly** and instead prove it at the unit level: an L1 that pins the seeded fill's date is
    inside `monthSpend`'s window for a given `asOf` on the 1st.
  - **Running it on the 20th proves nothing** and must not be reported as proof.

**Vacuous-assertion traps, named:**
- Reporting "TrendsUITests passed" without saying what date it ran on.
- Loosening the assertion instead of fixing the seed.
- Fixing only this one seed and not reporting the audit.

**Mutation-check and report it**: restore `daysAgo: 6` and show the failure returns under the
boundary condition you used to prove the fix. Restore your change, confirm green.

## The baseline gate (CLAUDE.md rule 14)

    cd ios && swift build ; echo "BUILD=$?"
    cd ios && swift test ; echo "IOSTEST=$?"
    swiftlint lint ; echo "LINT=$?"          # from the repo ROOT; ignore .claude/worktrees/*
    xcodegen generate && xcodebuild -project Tankbook.xcodeproj -scheme Tankbook \
      -destination 'platform=iOS Simulator,name=iPhone 17' test \
      -only-testing:TankbookUITests/TrendsUITests ; echo "UITEST=$?"

**Echo the exit code from the COMMAND, never through a pipe** (`cmd | tail -2 ; echo $?` reports
`tail`'s status); redirect to a file instead. Match the process NAME (`pgrep -x xcodebuild`);
**never `pgrep -f`/`pkill -f`**.

## Screenshots

None applies — no user-visible surface changes. Say so rather than fabricating one.

## Report back

- Exit codes (captured, not piped), test counts, the mutation result.
- **The date you ran on, and how you demonstrated the 1st-of-month case** — or a plain statement
  that you could not move the clock, with the unit-level proof instead.
- **The `daysAgo` audit**: every seed found, and for each, date-sensitive or safe, changed or left.
- Files changed, anything unfinished.
