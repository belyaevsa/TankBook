# RV.259 - the wrong-provider question loops when both providers are empty

**Scenarios: F7 · restore fails or comes back empty ("truly nothing found"), J11a · the
wrong-provider handoff.** The one hole that held F7's review at NOT IMPLEMENTED
(`diagnostics/REVIEW-SCENARIO-F7-2026-09-12.md`).

`SignInFlow.performRestore`'s `.empty` arm (`SignInFlow.swift:312-324`) routes to
`.wrongProvider` whenever `arrivedViaRestore && SignInView.offersGoogle`. `switchProvider`
(`:183-186`) signs out and starts the other provider with no memory of having switched, so when the
second account is also empty the reverse question is asked, and neither question offers F7's
recovery screen (import a file you exported yourself / Start fresh). Latent in Release today
(`GoogleClientID` empty, `offersGoogle` false); real the moment Google is provisioned (SH.4).

## Build

One decision, in the flow: a `didSwitchProvider` flag set by `switchProvider`, read by the
`.empty` arm - once set, `.empty` resolves to `.emptyRestore` (the F7 recovery screen), never to
`.wrongProvider` again. It is cleared where the flow's other per-attempt state is cleared (read
`signOutLocally` and the flow's init to pick the one place). Do not add a third destination; the
recovery screen already carries both doors (RV.239).

**Sibling check (`docs/DEFECT-PATTERNS.md`)**: the `.unreachable` arm after a switch - does it
also need to remember the switch? Say what it does today and whether that is right; do not change
it silently.

## Tests

- **L1, FAILS TODAY** (`SignInFlowTests` or the file that owns `performRestore`'s decisions;
  `SignInRouterTests` exists but the live decision is inline - `RV.129`): with the flag set, an
  `.empty` outcome resolves to `.emptyRestore`; without it, to `.wrongProvider`.
- **L4 `SignInUITests`, EN + RU**: under a seed that offers Google (find how `offersGoogle` is
  driven in DEBUG - `SignInTestSeed.swift`; add a launch argument if none exists, say which),
  arrive via the restore door, first account empty -> wrong-provider question -> switch -> second
  account empty -> the empty-restore screen with `emptyRestoreImportRow` and
  `emptyRestoreStartFreshButton`, never a second wrong-provider question.

Run `SignInUITests` in its own invocation and report the count. `testEmptyRestoreShowsRecovery-
BeforeAddCarIsUsable` is nondeterministic today (`RV.257`) - re-run it alone before reporting it.
Screenshots EN + RU of the screen after the second empty account, `design/screenshots/RV.259-empty-
restore-after-switch.png` / `-ru.png`, dark.

## Mutation - named

Never set the flag; the L1 goes red and the L4 sees the second question. Verbatim.

## Docs

`docs/JOURNEYS.md` F7: the "truly nothing found" line names what happens after a provider switch.
`docs/ERRORS.md` if the wrong-provider row states its exits.
