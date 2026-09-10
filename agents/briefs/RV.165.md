# RV.165 - a journey starts at a cold launch and reaches everything by tapping

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## The defect, and it is a defect in the TESTS

Product owner, 2026-09-09: *"a test scenario must be covered from an imitation of common user
behavior - click, click, choose, select, but not just open a screen."*

**The existing UI suite bypasses exactly what the reachability class lives in.** `-presentScreen
editEntry`, `-seedStationSettings`, `-openFirstFlaggedEdit`, `-selectTrendsTab` and the whole
`-seedHome*` family teleport into a screen with its state pre-made. A test that STARTS inside Edit
entry can never discover that Edit entry is unreachable.

That is not hypothetical. **`PJ.4` shipped a Reminders screen whose only route was `#if DEBUG`** -
unreachable in Release, green suite, because the UI tests navigated through the debug door.
`RV.162`'s guard now catches that exact shape, and **states its own blind spot**: it proves a door
NAMES the screen, it does not walk the view graph. This row is what walks the graph.

## What to build

**Four journeys, each from a cold launch with an empty database, reaching everything by tapping.**

| Journey | The walk | Why this one |
|---|---|---|
| J1 -> J3b | add a car -> log a fill-up -> set its station | `RV.156` shipped three features onto a station set a typing user could never populate |
| J3 -> J8b | scan -> save -> reopen the entry -> see the receipt | `PJ.28`'s silent loss; `RV.149` was its unfenced half |
| J13 -> F10 | delete a car -> find it in Recently deleted | `RV.98` |
| feedback | send feedback -> see it confirmed | `RV.160`: the confirmation existed and sat below the fold |

**Each of those four failed, or would have failed, on a build that shipped.** Start from the
journeys `docs/JOURNEYS.md` already names rather than inventing a set.

### The rules that make these different from the existing suite

- **No `-presentScreen`. No navigation seed. No seeded state the journey exists to create.**
  The launch arguments a journey may pass are `-homeResetDatabase` and nothing else, unless the
  argument is data VOLUME (see below).
- **Seeds stay legitimate for data VOLUME** - 500 fill-ups cannot be typed - **never for
  navigation**. If a journey needs one car, it taps "Add your car" and types the name.
- **Assert the outcome the user came for**, not that a screen appeared. *The receipt is openable
  from the saved entry*, not *the attachment row exists*. A test that asserts a screen exists is
  the thing this row is replacing.

## This brief's reading is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one. In
particular: **check what the cold-launch state actually is.** If the app opens on Welcome for an
empty database, the walk starts there; if it opens on a guest Home, it starts there. Say which you
found. If a journey turns out to be impossible to walk without a seed, **that is a FINDING, not an
obstacle** - report it as an unreachable path rather than reaching for `-presentScreen`.

## The guard, and it is half the row

**A journey test that passes a navigation argument must fail the build.** Add an L1 source scan
over the journey suite's own file(s): any `launchArguments` entry matching `-presentScreen`,
`-openFirst*`, `-select*Tab`, or a `-seed*` flag not on a small documented data-volume allowlist,
is a failure naming `file:line`. Without this the suite quietly regresses to the shape it replaced
the first time a journey is awkward to walk.

Mirror `RV.162`/`RV.163`'s mechanism: a **pure function over source text**, masking comments and
strings first, with a **reasoned exception list** where a bare entry fails the guard's own check.

## Explicitly out of scope

- Rewriting the EXISTING UI suites. They keep their seeds; this is a new suite beside them, not a
  migration. Say so in the file's header.
- `RV.162`/`RV.163`'s guards themselves.
- `RV.194` (the screenshot manifest's own blind spot) - a different row, a different seam.

## Docs to read before writing (in order)

1. `docs/JOURNEYS.md` -> J1, J3, J3b, J8b, J13, F10 - the authority on what each journey promises.
2. `docs/TESTING.md` -> "Which gates for which change" and the verification levels. **Extend it in
   the same change** to say where this suite runs.
3. `docs/SCREENMAP.md` -> the navigation graph you are walking.
4. `CLAUDE.md` -> the UI-suite convention (full suites at a PHASE gate, not per task).

## Where these run, and say so in the docs

**They are slow** - five full UI runs measured ~2h15m (`docs/TESTING.md`) - so they belong at a
**phase gate, not per task**. Record that in `docs/TESTING.md` -> which gates for which change,
next to the existing rule. A row that adds two hours to every task's gate will be turned off.

## Environment axes this crosses

**Release vs Debug is the whole point** - the class this catches is invisible in Debug. State
whether the journeys pass in a **Release** build; if the harness cannot run UI tests against
Release, say so plainly rather than implying coverage you do not have. **Locale**: the journeys type
and read text, so at least one must run in RU. **Clean install**: every journey starts there by
construction, which is the row's argument.

## If this adds a failure path, what makes it visible in production?

None - this is test code and a source guard; nothing in the shipping app changes. Say so.

## Tests you must add

- **The four journeys**, each from a cold launch with no navigation seed, each asserting the user's
  outcome.
- **Prove the teeth**: re-gate ONE production route behind `#if DEBUG` and show the journey that
  needs it goes red. Then restore it byte-identical. **This is the mutation - I am naming it, do
  not choose your own.** Report both outputs verbatim and name the route you gated.
- **The guard**, both directions: a planted `-presentScreen` in a journey test fails it; the clean
  suite passes.
- **The guard's exception check**: a documented exception with a blank reason fails.

Report each suite's observed, **non-zero** count, and **filter by suite name, not the file's** - on
2026-09-10 a class-name filter matched nothing and printed `TEST SUCCEEDED` on zero tests.

## Vacuous traps, named

- **A journey that passes a navigation argument "just for setup"** - that is the defect, wearing the
  row's own name.
- Asserting a screen exists rather than the outcome the user came for.
- A guard that scans for `-presentScreen` only, so `-openFirstFlaggedEdit` walks past it.
- Writing four journeys that all walk the same two screens - check they reach four different places.
- **Deleting or weakening an existing test** to make a journey pass. If an existing suite conflicts,
  report it; do not edit it.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1879 tests / 225 suites**, **831** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then the new journey suite **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. **Release build** if you touch any `#if DEBUG` seam.

Verify by **exit code** (`echo $?`).

## Report back

Every check with the **exit code observed** and the counts; run or only written; **the mutation's
red-then-green output and which route you gated**; what the cold-launch state actually is; any
journey you could NOT walk without a seed, named as a finding; and **anything you found and did not
fix**.
