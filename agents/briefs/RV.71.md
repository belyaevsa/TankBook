# RV.71 - warn when a scanned receipt's fuel kind is not the car's

## The requirement and the pieces that already exist

Product owner, 2026-09-05: *"if a scanned receipt and its fuel type differ from the main one (diesel
vs petrol, petrol vs diesel, gas vs diesel, or gas vs an unsupported type for a car) it should be
highlighted as a warning for the user at scan moment"*.

Everything needed is already in the codebase and **nothing compares the two**:

- `Vehicle.fuelKinds: [FuelKind]` (`ios/Sources/TankbookCore/Domain/Entities.swift:43`) - what the
  car takes.
- `FuelKind` covers `diesel/petrol92/95/98/100/lpg/cng/e85/electricity`
  (`ios/Sources/TankbookCore/Domain/Enums.swift:4-14`).
- `FuelExtractor` already resolves a `fuelKind` from the receipt
  (`ios/Sources/TankbookCore/Extraction/FuelExtractor.swift:36`, `FuelKindNormalizer`).
- The confirm screen already renders the kind as chips (`ManualFillUpFuelCard.swift:45-140`).

So a diesel receipt logged against a petrol car saves without a word. **Why it is worse than a
typo**: fuel kind feeds the consumption maths, which treats litres and kWh differently, and stats are
derived (hard rule 2) - a bad kind propagates on every recompute. **The mis-scan is real, not
hypothetical**: the corpus has `АИ-96` read at **confidence 1.00** on a 95 receipt, and
`receipt-032`'s `AM-95` smear.

## The comparison is DECIDED - implement this rule exactly

**Warn when the extracted kind is not in `FuelKind.offeredKinds(for: Set(vehicle.fuelKinds))`**, with
two carve-outs. `offeredKinds` (`Enums.swift:49-55`) already encodes the grade logic this row turns
on: a car declaring any petrol grade is offered **all** petrol grades, because they share a tank and
choosing between them is a driver's choice, not a fuel switch. Reusing it means the rule cannot drift
from the chips the same screen already shows.

The two carve-outs, both decided:

1. **An empty `fuelKinds` never warns.** A car that has declared nothing cannot disagree with
   anything, and that is the state most cars start in - a rule that fires on every scan for a fresh
   car is noise, and noise is how a warning stops being read.
2. **`electricity` never warns, in either direction.** A charge session is a different entry path,
   and warning here would fire on every hybrid.

Worked cases, which are also the tests:

| Receipt | Car declares | Warns? |
|---|---|---|
| diesel | petrol95 only | **yes** |
| petrol95 | diesel only | **yes** |
| **petrol95** | **petrol92 + petrol95** | **NO - the grade case** |
| petrol92 | petrol95 only | **NO** - `offeredKinds` opens all grades to a petrol car |
| lpg | petrol95 (no lpg/cng) | **yes** |
| anything | `[]` (empty) | **NO** |
| electricity | anything | **NO** |

Put the comparison in **TankbookCore as a pure function** so it is L1-testable without a simulator -
that is where the whole point of this row lives.

## What to build

1. The pure comparison above.
2. **The warning on the confirm screen, at the moment of the scan. It never blocks.** The extracted
   kind stays a default input the user edits (hard rule 13); the warning says the two disagree and
   **names its next step** (hard rule 7). It does not refuse the save and does not silently rewrite
   either value.
3. **Amber, and never colour alone** (hard rule 5: amber is attention; the words carry the meaning
   for VoiceOver exactly as the Garage attention strip does).
4. **Decide whether accepting a warned kind offers to add it to the car's declared kinds**, and say
   what you decided and why. Rule 13 says a value the user chooses becomes theirs permanently, which
   argues for offering it; a modal question mid-capture argues against. **Take the smallest correct
   option and keep going** - do not stop on this.

## Explicitly out of scope

- Changing what the extractor reads, or the normalizer's vocabulary.
- Warning on electricity vs liquid (see the carve-out).
- Blocking, refusing or auto-correcting a save.
- The manual entry path's own validation, beyond where the same warning naturally applies.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1, the whole point of the row**: every row of the table above, asserted individually. The
  **must-NOT-warn** cases are as load-bearing as the must-warn ones.
- **L4 `ConfirmManualUITests`**: the warning renders on the confirm screen after a scan, **Save stays
  reachable with it on screen**, and dismissing it changes neither value.
- Suites: `ConfirmManualUITests`. Report the observed count.

### Vacuous traps, named

- **Asserting the warning exists without a case that must NOT warn.** A rule that fires on everything
  is not a rule - and the grade case is the one that would annoy every user daily.
- **Asserting a string rather than that Save still works.**
- **Testing only diesel-vs-petrol** and missing the grade case and the empty-`fuelKinds` case.
- Asserting the warning's colour instead of its text - colour is never the only channel, and a test
  cannot see colour anyway (that is what the screenshots are for).

### Mutations (run each, report, restore byte-for-byte)

1. Compare against `vehicle.fuelKinds` directly instead of `offeredKinds` -> the **grade** test must
   fail (a 92 receipt on a 95 car would start warning).
2. Drop the empty-`fuelKinds` carve-out -> its test must fail.
3. Make the warning block the save -> the Save-stays-reachable test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Screenshots

EN **and** RU, **dark**, into `design/screenshots/`, as `RV.71-confirm-fuel-mismatch.png` and
`-ru.png`, **with the warning showing**.
- Capture **outside** a test run; pass `-homeResetDatabase` alongside any seed (seeds are idempotent
  and silently do nothing on a populated database).
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- **Verify the pair differs with `md5 -q`** and report both hashes.
- RU runs 20-30% longer and short strings expand worst - a warning line that wraps or truncates
  breaks hard rule 7. Read the rendered Russian for grammar and word order, and use a **full
  localised phrase per language, never concatenation**.
- You cannot see your own screenshots; the orchestrator opens every one.

## Docs to reconcile

`docs/ERRORS.md` (the new warning, its severity and its next step - this is the authority and the
3-question audit rule applies), `docs/EXTRACTION.md` if the cross-check outcomes change,
`docs/JOURNEYS.md` if the confirm journey gains a step.

## Hard rules that decide things in this area

**2** (stats are derived - the reason a wrong kind matters) · **5** (amber is attention; never colour
alone) · **7** (the warning names its next step and survives being ignored; **no monetization and no
blocking mid-capture**) · **10** (EN + RU, full localised phrase) · **13** (the extracted kind is a
default input, editable now and later) · **15** (typing is a peer path - the warning must not make
the scan feel like the only correct door) · **14** (it builds and it lints).

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, `Spike/ImportFixtures/**`, `design/screens/**`,
`design/screenshots/**`, and the docs named in this brief. **If your row's "out of scope" says not to
touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above and is confirmed - do not spend the run re-deriving it. Where this brief leaves a
genuinely open choice, **take the smallest correct option and keep going**, then say in the report
which you took and what you rejected. Do not stop and wait on it. (`RV.74`'s first dispatch ran two
hours and wrote nothing, stuck on a question its brief left open.)

If a fence in this brief turns out to be wrong, **report it as a Residual rather than obeying
quietly** - a fence can be wrong the same way a diagnosis can. Two of my diagnoses have been wrong
this month and the agent was right both times.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0
- `cd ios && swift test` -> 0, count reported (before -> after). Never subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `cd backend && dotnet build` -> 0 and `dotnet test` -> 0 (count
  before -> after), plus `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  `swift build` does NOT compile `ios/App`; only `xcodebuild` does. Run `xcodegen generate` first if
  you added a file. **Check the observed count is non-zero.** Do NOT run the whole UI suite - that
  belongs to phase completion (2026-08-29 rule).
- **`$?` after a pipe is the pipe's exit code.** `dotnet test | tail` once reported 0 while the run
  aborted and "66 passed" of ~396 nearly read as green. Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Simulator contention produces false reds** with a *different* failing set each run, and a suite
  reporting "Executed 0 tests" beside its failures is kills, not assertions. Shut the simulators down
  and re-run once on a quiet machine before believing a red.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. Each mutation: what you broke, which named test failed, and that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on. Four passed on 2026-09-06
   and each meant the test did not cover the claim its row was written for.
3. Screenshot paths and md5s, if this brief asked for screenshots.
4. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
