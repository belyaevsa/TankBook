# PJ.7f – the tagline gate's positive control is pinned to copy that shipped out from under it

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and only:

- `ios/Tests/LocalizationGateTests/LocalizationGatePJ3bTests.swift`

Do **NOT** touch `docs/TASKS.md` (the orchestrator ticks it at merge; editing it conflicts with
other lanes), any file under `ios/App/`, `design/screens/`, or `ios/App/Sources/Localizable.xcstrings`.
Two sibling lanes are running; `ios/App/UITests/` and `ios/App/Sources/Welcome/` belong to them.

This task needs **no simulator** – unit tests only. Never `pgrep -f` / `pkill -f` for a build (a
brief is part of the process command line, so an `-f` pattern matches a sibling agent and has
killed one). Use `pgrep -x xcodebuild`.

Write the fix first, explore second. It is a small, fully diagnosed task.

## The defect, already diagnosed – do not re-bisect it

`cd ios && swift test` is **red on `main`**: 1062 tests, 1 failing –
`OverPromiseGateTests.honestTaglineIsPresent` (`LocalizationGatePJ3bTests.swift:129-137`).

It is the gate's **positive control**: it asserts the tagline literal is present in
`WelcomeView.swift`, `Localizable.xcstrings`, `Welcome.dc.html` and `LightWelcome.dc.html`, so that
a path typo or an unread file cannot make the negative scan pass on empty input. The literal it
pins is `"A head start, not an answer"`.

The Welcome hero tagline has since changed **three times in one day**:

1. `4968590` -> `Scan the receipt – or type the numbers`
2. `ac4c08c` -> `Fuel, charging and service – one log` (product owner's pick)
3. `43e50c6` reworded the second feature row

All four scanned files now carry `Fuel, charging and service – one log` (verified). The gate is the
only thing still pinned to the old wording, so it fails.

## What to build

Make the test green **without giving up what it protects**. The straightforward fix is to update
the literal. The better fix, and the one to prefer if you can do it cleanly, is to stop hardcoding
the sentence at all:

- Derive the tagline from **one** source of truth – the `Text("…")` in `WelcomeView.swift` – and
  assert the other three scanned files carry **that same string**.
- Then the control still fails loudly on an unread file or a path typo, and a fourth copy change
  no longer reds the suite for the wrong reason.

**If you take the derived route, these two properties are mandatory** and each must be proved by a
mutation below:

1. If the tagline cannot be extracted (file missing, path typo, pattern not found, empty scan), the
   test **fails** – it must never silently derive `""` and then find `""` in every file, which
   passes vacuously. That vacuum is exactly the failure mode this control exists to prevent.
2. A file that does **not** carry the tagline still fails the test.

Keep the doc comment honest about what the control is for, and update it – it currently describes
the old literal.

## Explicitly out of scope

- Changing the tagline anywhere in the app, the artboards or the catalogue. The shipped copy is the
  product owner's and is correct.
- The negative scan above it (the over-promise patterns at lines ~96 and ~119) – it is passing.
- The three UI-suite failures other lanes are fixing.

## Named vacuous traps for this task

- Deriving the expected string from a file and then asserting it against **that same file** only.
- An extraction that yields `""` on failure and an assertion that `text.contains("")` – always true.
- `#expect(true)`, or asserting only that the scan did not throw.
- Deleting the control, or reducing it to a substring so short it matches anything.

## Checks

- `cd ios && swift build` exit 0; `swiftlint lint` exit **0 run from the repo root**.
- `cd ios && swift test` – **all 1062 unit tests, never subsetted**. Report the observed count and
  the failure count. Expect 1062 passing; if anything else is red, say so rather than fixing it.
- Mutation checks, both required:
  - Point the scanner at a **nonexistent path** (or otherwise make the extraction fail) and confirm
    the test goes **red**, not green. This is the property-1 proof.
  - Change the tagline literal in your **local backup copy** of one scanned file – or, simpler,
    temporarily edit `design/screens/LightWelcome.dc.html`'s tagline – and confirm the test goes
    **red**. This is the property-2 proof.
  - Restore each file by **copying back a backup you made first and verifying with `md5`**. Never
    use `git checkout` – it has destroyed uncommitted work in this repo three times, and two
    sibling agents hold uncommitted work in this tree **right now**.

## Report back

The observed unit-test count and failure count, both exit codes, which fix shape you chose and why,
the result of each mutation (did it actually go red?) and the `md5` match after each restore. Say
whether you **ran** the tests or only wrote them. Do not commit – the orchestrator verifies and
commits.
