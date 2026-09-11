# RV.174 - the baseline gate can be green on code that does not compile into the app

**no-scenario: the gate itself.** Cross-cutting; before scenario 6. Every dispatch after it is safer.

## The escape

`swift build` and `swift test` exercise the **SwiftPM package** (`ios/Sources/TankbookCore`); every
screen lives in the **app target** (`ios/App/Sources`), which only `xcodebuild` compiles. Found
2026-09-10: build 0, lint 0, 1826 package tests green - and `xcodebuild` failed at
`FeedbackComposerView.swift:50`. Same escape as the Debug-vs-Release one hard rule 14 already
names, through a different door, and wider: any app-target-only change can take it.

## Build

Make the app-target compile part of the **baseline gate**, not a per-brief reminder:
1. A single script - `scripts/gate.sh` - that runs, in order, `swift build`, `swiftlint lint`
   (repo root), `xcodegen generate`, `xcodebuild ... build` for the app target, and `swift test`;
   stops at the first non-zero; prints one line per step with its exit code. `RELEASE=1` adds the
   Release build. It is what `agents/briefs/PREAMBLE.md` step 1-4 describe; make the preamble call
   the script instead of listing the steps.
2. `docs/TESTING.md` -> "the baseline gate" and CLAUDE.md hard rule 14: name the script and state
   plainly that package-green is not app-green.
3. **Prove the teeth**: introduce a deliberate app-target-only compile error in a scratch change,
   show `gate.sh` fails at the `xcodebuild` step with the package steps green, revert. That output
   verbatim is the deliverable.

## Tests

The gate script is the test. Also **L1** (shell, `scripts/tests/` has the pattern): the script
exits non-zero when any step does, and its step order is package -> lint -> app -> tests.

## Mutation - named

Remove the `xcodebuild` step from the script; the scratch compile error passes the gate. Restore.

## Vacuous trap

A script that runs `xcodebuild` and ignores its exit code.
