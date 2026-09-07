# RV.102 - the localization gate cannot see a key that never reaches a view

## The defect the gate missed, already fixed - this row is the GATE

Found 2026-09-07 by the orchestrator **opening the RU screenshot** while verifying [RV.100] - by no
test and no gate. `HomeEmptyStates.quickAction` took `_ title: String` and handed it to
`Label(title, systemImage:)`. `Label` has **two** initialisers - one taking `LocalizedStringKey`, one
taking a `String` - and the `String` one renders the literal. So **"Select car" and "Type it"
rendered in ENGLISH on a Russian device**, while "Edit entry", written as a literal in the body and
therefore taking the `LocalizedStringKey` overload, was correctly Russian: two English rows and one
Russian row in one card, on the first screen a new user sees, in the build now on TestFlight.

Both translations existed in `Localizable.xcstrings` («Выбрать автомобиль», «Ввести вручную») and
simply never reached the screen.

**The one-line fix already shipped** in [RV.100]'s commit (`bfad97c`): the parameter is now
`LocalizedStringKey`. **This row is the part that is NOT fixed** - the localization gate reported
**0 violations** throughout, because it checks that keys exist and are translated, never that a key
**reaches a view**.

## What to build

1. **Teach the gate the shape it missed.** A `String`-typed parameter or variable reaching a SwiftUI
   text-rendering initialiser - `Label`, `Text`, `Button`, and any other with a
   `LocalizedStringKey`/`String` overload pair - is the defect class, and it is detectable
   statically. The gate lives in `ios/Sources/LocalizationGate/` with its own tests
   (`ios/Tests/LocalizationGateTests/`); extend it there.
2. **Sweep the app for other instances FIRST and report the count before fixing them.** Any helper
   that takes `_ title: String` (or `text:`, `label:`, `message:`) and renders it. **The count is the
   useful number**: one more instance is a lint rule, twenty is a convention that needs stating in
   `docs/DESIGN.md`. Report before you fix.
3. **Do not fix the call sites without teaching the gate** - the next one lands the same way
   tomorrow, and this row exists because that is exactly what happened.

**Watch the false-positive rate.** A `String` reaching `Text` is legitimate when the value is
genuinely dynamic user data - a car name, a station, a note. The gate must distinguish "a literal or
catalogue key passed as `String`" from "a runtime value that must not be localised", and a gate that
cries wolf gets disabled. If you cannot separate them cleanly, say so and propose the narrower rule
you can enforce - a precise partial gate beats a noisy complete one.

## Explicitly out of scope

- Re-fixing `HomeEmptyStates.quickAction` (done in `bfad97c`).
- Translating anything, or touching the catalogue's contents.
- The RU copy of any screen.

## Tests

Read the current `swift test` count yourself before you start and report before -> after.

- **L1 over the gate**: a fixture view passing a `String` **variable** to `Label`/`Text` is
  **FLAGGED**, and the same view passing a `LocalizedStringKey` is **not**.
- **L1**: a `String` holding genuinely dynamic data (a car name from the model) is **not** flagged -
  whatever rule you land on, this is the false-positive guard.
- **L1**: the exact `quickAction` shape this row came from would have been caught - reconstruct it as
  a fixture and assert the gate flags it. That is the regression oracle.
- **L4 in RU** on whatever screens the sweep touches, if it touches any.

### Vacuous traps, named

- **Fixing the call sites without teaching the gate** - the whole point of the row.
- **Asserting the catalogue has the key**: it did, for both strings, all along.
- **Asserting a screenshot exists** rather than reading the rendered Russian.
- A gate test whose fixture is the fixed code, so it passes without ever having failed - run it
  against the pre-fix shape and show it goes red.

### Mutations (run each, report, restore byte-for-byte)

1. Revert `quickAction` to `_ title: String` -> the gate must flag it (this is the reproduction; run
   it FIRST and report it as the "before").
2. Broaden the rule to flag every `String` reaching `Text` -> the dynamic-data test must fail.

**A mutation that PASSES is a finding** - say so and grow the test until it fails.

## Docs to reconcile

`docs/DESIGN.md` or `docs/TESTING.md` - wherever the localization gate's contract is stated, record
what it now catches and, honestly, **what it still cannot**: a gate whose limits are written down is
trustworthy, one whose limits are assumed is how this defect shipped.

## Hard rules that decide things in this area

**10** (all user-facing strings through the String Catalog, EN + RU - the rule this defect broke in
the shipped build) · **14**.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`, `backend/src/**`,
`backend/tests/**`, `design/screenshots/**`, and the docs named in this brief. **If your row's "out
of scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been several times this month, and the agent was right every
time. If what you measure does not match what this brief claims, **say so and report the
measurement**; that beats a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after). Never
  subset it.
- `swiftlint lint` **from the repo root** -> 0 errors. From `ios/` it prints thousands of phantom
  violations; that false red has cost two sessions.
- `swift run --package-path ios localization-gate` from the root -> 0.
- **If you touched `backend/`**: `dotnet build` -> 0, `dotnet test` -> 0 (count before -> after),
  `dotnet format --verify-no-changes` -> 0.
- **If you touched `ios/App/`**: `xcodebuild -project Tankbook.xcodeproj -scheme Tankbook -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:<the suites this brief names> test` -> 0.
  Run `xcodegen generate` first if you added a file. **Check the observed count is non-zero.**
- **A change touching a `#if DEBUG` seam also builds RELEASE**
  (`xcodebuild -configuration Release ... build`).
- **`$?` after a pipe is the pipe's exit code.** Never judge a run by `... | tail`.
- **Never `pgrep -f` for a build** - your own brief is in your command line and you will match, and
  could kill, a sibling agent. Use `pgrep -x xcodebuild`.
- **Watch the file-length ceiling**: several files sit at 699-700 lines and the lint error is a hard
  700. If your change pushes one over, split it the way the codebase already does (`+Wizard`,
  `+Cars`, `L10n+…`), never by deleting comments.

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The measurement this row asked for, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. Screenshot paths and md5s, if this brief asked for screenshots.
5. What the user can now do that they could not before. If the honest answer for some case is
   "nothing changed", say so.
6. Anything in this brief that was wrong, as a Residual.
7. Whether the tests were actually **run**, not only written.
