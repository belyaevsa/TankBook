# RV.192 + PJ.45 - the pace bound: make it right, then make it the user's

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

**Two rows, one dispatch.** `RV.192` fixes when the pace bound fires; `PJ.45` puts its limit in the
user's hands. They are the same seam - `paceLimitKmPerDay` and `TimelineValidator`'s CHECK 2 - and
shipping the fix without the tunable leaves the product owner's own case answerable only by an
agent. `PJ.45` has been marked **PRIORITY since 2026-08-31** and has waited ten days.

## RV.192 - the defect, pinned

Product owner, their **second** report of the same shape: *"one more problem with odo and fill ups
at the same day. it's marked as Needs a look."* `RV.186` settled the ORDER check (a service may
share its fill-up's reading) and **deliberately did not touch the pace check**. This is the half it
left.

**The line**: `TimelineValidator.swift:198` and `:209` guard CHECK 2 with `days > 0`, where
`dayDiff` (`:423-425`) is `abs(a.timeIntervalSince(b)) / 86400` - **a fraction of a day, measured
between instants**. Two entries nine hours apart on one calendar day give `days = 0.375`, so a
300 km delta reads as **800 km/day** and trips a 1 500 km/day limit at 3 000 km.

**`docs/SCHEMA.md` already says the opposite of the code**: *"a same-day neighbour contributes no
pace bound."* The prose is right and the guard does not implement it. That doc line is the
authority; you are making the code match it, not inventing a rule.

## The decision, made - confirm it, do not re-open it

**"Same day" means the same calendar day, in an INJECTED calendar defaulting to `.current`.**

Two reasons, both already in the tree:
- **`Vehicle` carries no timezone** (check `Entities.swift` - there is no such field), so "the
  vehicle's own timezone" is not available to implement and inventing a field is out of scope.
- **`LogStream` already sets the precedent**: `public init(vehicle:entries:calendar: Calendar = .current, ...)`
  (`LogStream.swift:291`). The engine takes a calendar; the caller supplies it. `TimelineValidator`
  should do the same, so a test can pin a timezone without touching a global.

## The named tension - check it before you assume it

`RV.192`'s row warns that `dateIntervalEndpointsAreExactInBothDirections`
(`ios/Tests/TankbookCoreTests/TimelineValidRangeTests.swift:338`) deliberately pins sub-day
precision and may conflict.

**Read it first.** Its fixture spans **day 0 -> day 60** with the answer `[day 25, day 35]` - whole
days, far apart. It may not conflict at all. **Say which you found.** If it does conflict, change it
**with its reason written in the test**, and say so loudly in your report - silently loosening a
deliberate test is the worst outcome available here.

## What the same-day rule must NOT do

A same-day pair contributes **no pace bound**. It must still contribute its **order** bound - a
reading that FALLS between two same-day entries is still wrong, and `RV.186`'s work must keep
holding. Two travel entries at one reading are still flagged. Prove all of that stayed green.

Watch the second consumer: `validRange`'s `odometerRange` / `dateRange` mirror the same `days > 0`
guard. **Both directions must agree**, or the panel will suggest a range the validator then flags.

## PJ.45 - what to build

`paceLimitKmPerDay` is created at **1 500** by `TargetCar.newCar` and the add-car path and **edited
nowhere today**. Put it on **Vehicle detail**, beside the car's other per-car settings.

- **It is a suggestion, not a fact** (hard rule 13): pre-filled with the current value, editable,
  and once the user changes it the value is theirs - no later default may overwrite it.
- **State the consequence in the caption**, the way `PJ.55`'s favourite row does: this number is what
  decides whether an entry lands in "Needs a look".
- **Editing it re-derives the flags.** The flags are computed from the entries and the limit, so a
  raised limit must clear a flag that only existed because of the old one, with no re-save of every
  entry. Say how you verified that.

## This brief's diagnosis is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one.
**Reproduce the owner's case first**: two entries on one calendar day, hours apart, with a real
odometer delta, and show the pace flag firing BEFORE you change anything. If it does not reproduce,
say so and say what would - do not fix a break you could not observe.

## Explicitly out of scope

- `RV.186`'s order rule. It shipped; do not re-open it.
- `RV.188`'s conflict panel. It renders whatever the validator says.
- The 1 500 default itself. `PJ.45` makes it editable; it does not re-decide the number.
- `RV.143`/`RV.152` (currency re-homing on Vehicle detail) - a different row on the same screen.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Validation, and the sentence *"a same-day neighbour contributes no pace
   bound"* - the authority you are implementing. **Extend it in the same change** to say which
   calendar decides a day.
2. `docs/JOURNEYS.md` -> F9a, and `docs/ERRORS.md` -> Confirm -> F9a.
3. `docs/DESIGN.md` -> the per-car settings on Vehicle detail.
4. `CLAUDE.md` hard rule 13.

## Environment axes this crosses

**Timezone is the row's own subject** - a test must pin a calendar rather than inherit the machine's,
or it passes in Tallinn and fails in CI. **Locale**: PJ.45 adds a user-facing row and caption, so
**EN and RU screenshots**, dark theme, with capture lines added ([RV.176] now fails CI on a frame no
line produces). **Cross-border (J10)** is worth one sentence in your report: a car driven across a
timezone will have entries stamped in two zones, and `.current` is a device-local reading.

## If this adds a failure path, what makes it visible in production?

A flag that silently stops firing is indistinguishable from no conflicts. If your change has a
branch that suppresses a bound, add the shape-only event that answers *"did the same-day rule
suppress a pace check?"* - **counts only** (hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: two entries at 09:00 and 18:00 on one calendar day, 300 km apart,
  produce **no** pace flag. Oracle: `SCHEMA.md`'s own sentence.
- **L1**: the same pair on two ADJACENT calendar days, nine hours apart, still gets its pace bound -
  the rule is calendar day, not "less than 24 hours".
- **L1**: a same-day pair whose reading FALLS is still order-flagged ([RV.186] holds).
- **L1**: `validRange` and the flags agree for the same-day case - no suggested range the validator
  would flag.
- **L1 (PJ.45)**: an edited `paceLimitKmPerDay` persists, and raising it clears a flag that existed
  only under the old limit.
- **L4 `VehicleDetailUITests`**: the row is present, editable, and its value survives a reopen.

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Restore `days > 0` on the raw fractional `dayDiff`** for the previous-side check only, and show the
same-day L1 goes red with the pace it computes (the number in the failure message is the finding).
Then restore byte-identical and re-run. Report both outputs verbatim.

## Vacuous traps, named

- **Raising the limit to make the flag go away.** That hides every real pace conflict and is the
  trap the row names by name.
- `days >= 1` on the fractional value: 23 hours across midnight is a different calendar day and must
  still be bounded; 25 hours inside one long day does not exist.
- Testing with `Date()` and `.current`, so the test's result depends on the machine's timezone.
- Fixing the flag and leaving `validRange` on the old guard, so the panel suggests a range the
  validator rejects.
- Shipping PJ.45's row without proving an edit re-derives the flags - a setting that changes nothing
  visible is the `Station.favorite` shape ([PJ.55]).

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1887 tests / 226 suites**, **831** localization keys at 100% RU.

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

Whether the owner's case reproduced before your change and what pace it computed; whether
`dateIntervalEndpointsAreExactInBothDirections` actually conflicted; every check with its **exit code
observed** and counts; **the mutation's red-then-green output verbatim**; how you verified an edited
limit re-derives the flags; what you captured; and **anything you found and did not fix**.
