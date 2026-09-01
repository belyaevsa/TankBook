# PJ.2b – the guarantee PJ.2 is named for is asserted nowhere

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`:

- `ios/Sources/TankbookCore/Domain/ScannedSavePlan.swift` (and neighbours in core if the plan needs
  to grow)
- `ios/App/Sources/ConfirmManual/ManualFillUpView.swift` (the save loop at ~lines 555-575)
- `ios/Tests/TankbookCoreTests/` (the L1 that must reach it)

No sibling lane is running. Do **NOT** touch `docs/TASKS.md`. **Never `git checkout`** to undo
anything – copy a backup back and verify with `md5`.

Write code first, explore second.

## Use this simulator

`iPhone 17` for the UI runs. **Never** `pgrep -f`/`pkill -f` for a build – a brief is part of the
process command line and that pattern once killed a sibling agent 48 minutes in. Use
`pgrep -x xcodebuild`.

## The gap, and it was found by a mutation that PASSED

PJ.2's headline guarantee is that **one attachment is shared** by the fill-up and every expense a
mixed receipt produces. Giving each accepted `Expense` its **own** attachment id instead passes
`ScannedSavePlanTests` **and** 28 L4 tests across EditEntry and ConfirmManual. The behaviour is
right; **nothing pins it**, so a regression ships silently.

The cause is structural, not sloppy:

- The L1 covers the core `ScannedSavePlan`, which carries a single `attachmentID` (line 47).
- The loop that actually **copies that id onto each expense** lives in `ManualFillUpView.swift`
  (~line 562-571, `attachments: attachmentIDs`), inside `ios/App` - which **no unit test target can
  import**.
- No L4 case drives a **mixed-receipt scanned** save, so nothing exercises the loop either.

## What to build

Follow the **P3.7 lesson**, which is the point of this row: `AppTabBar`'s padding arithmetic lived
in the app target where package tests could not reach it, so a double-counted inset survived two
phases "verified by looking at one device". P3.7 moved the arithmetic into core and the tests caught
both mutations immediately.

So: **move the Expense construction into the core plan** so the existing L1 reaches it, rather than
adding an app-side test that cannot exist. The app should apply what the plan decided, not decide
it. If you find a reason that cannot work, say so with the evidence rather than falling back to an
app-side assertion.

## The assertion that matters

**Assert the SAME id**, not that each row has one. The row says this explicitly, and it is the whole
difference between a test that pins the guarantee and one that passes under the defect:

- the plan emits **one** attachment id;
- the fill-up references it;
- **every** expense references **that same id**.

## Named vacuous traps

- **Asserting `attachments` is non-empty**, or that each expense has *an* attachment. Per-row ids
  pass both - that is precisely the mutation this row exists to catch.
- Asserting the count of attachments rather than their identity.
- A test that constructs the plan and the expenses separately in the test body, so it asserts its
  own arrangement rather than the production path.
- Leaving the copying loop in `ios/App` and adding an app-side test: `ios/App` has no unit-test
  target, and an L4 that drives a mixed-receipt scanned save is the expensive, fragile way to pin
  an invariant that belongs in core.

## The mutation that MUST fail

Give each expense its own freshly minted id. Your new L1 must go red. If it stays green, the test
is the vacuous version and the row is not done - that is the exact state this task starts from.

## Checks

- `swift build --package-path ios` exit 0; `swiftlint lint` exit **0 from the repo root**.
  **`swift build` does not compile `ios/App`** – also `xcodebuild ... build` → `BUILD SUCCEEDED`.
  Keep files under **700 lines** (`file_length` is an error here; `ConfirmManualUITests` is at the
  ceiling, and the precedent for a new suite is `ConfirmOdometerPrefillUITests`).
- `swift test --package-path ios` – whole suite, never subsetted; it stood at **1122**. Report the
  observed count and your delta.
- `xcodebuild ... -only-testing:TankbookUITests/ConfirmManualUITests
  -only-testing:TankbookUITests/EditEntryUITests test` on `iPhone 17` – the 28 L4 tests that
  currently pass under the defect must still pass after the move. Then
  `scripts/check-ui-test-count.sh` on the log.
- **Mutation**: per-row ids, as above. Restore by copying a backup back and verifying `md5`.

## Report back

Whether the Expense construction moved into core and, if not, the evidence for why; the exact L1
assertion (quote it) and why it cannot pass under per-row ids; observed counts and exit codes; the
mutation result; the `md5` match. Say whether you **ran** the tests or only wrote them. Do not
commit.
