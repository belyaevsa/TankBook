# RV.82 - `RemindersDeepLinkUITests` only passes in company

## The defect, and I have pinned the mechanism to a line

Found by the [RV.78] agent: run the suite **alone**, on a device with no Keychain session, and
`waitForCar` fails because Home renders the **guest** layout, which has no `carSwitcherButton`
(`ios/App/UITests/RemindersDeepLinkUITests.swift:124-131`). It passes when a session is planted or
when a sign-in suite ran earlier **in the same simulator session** - the Keychain survives between
runs, and `simctl uninstall` does NOT clear it (measured 2026-08-31).

**Why, exactly.** `WelcomeGate.shouldShowWelcome`
(`ios/App/Sources/Welcome/WelcomeGate.swift:38-52`) plants a stub session for exactly one harness
flag:

```swift
if !arguments.contains("-presentWelcome"),
   arguments.contains("-seedVehicleForUITests") {
    let store = KeychainSessionStore()
    try? store.clear()
    try? store.save(SettingsTestSeed.stubSession())
}
```

and its own doc comment (`:17-25`) already explains why: the seed targets the **signed-in** Home,
"without the session the tabbed app would still render the guest Home and the entry tests would find
no `typeItButton`". `-homeResetDatabase` gets the tabbed app but **no session**.

`RemindersDeepLinkUITests.launch` (`:23-30`) passes `-homeResetDatabase`, `-seedRemindersDeepLink`
and `-replayNotificationResponse` - **none of which plants a session**. So the suite depends on
whatever an earlier suite left in the Keychain. It is deterministic in both directions: green in a
full run, red alone - so the full suite certifies it and a focused re-run "fails", which is worse
than a flake.

## What to build

**Extend the gate's session-planting condition to `-seedRemindersDeepLink`.** That seed is a
signed-in-Home seed by nature - a reminder deep link lands on the merged list inside the tabbed app -
so it earns the session for exactly the reason the comment already gives for `-seedVehicleForUITests`.
Doing it there fixes every test using that seed rather than one call site, and it keeps the reason
next to the other one instead of scattering session setup across suites.

**The acceptable alternative**, if the gate change turns out wrong: add the existing
`-seedSettingsSynced` to the suite's own `launchArguments`. Either way **the suite must state its own
preconditions** and must not inherit a session from whichever suite ran before it. Take the smallest
correct option, say which you took and why.

**Do NOT** make the test tolerate the guest layout - that asserts the bug. **Do NOT** plant the
session in a shared `setUp` that other suites also mutate: that moves the coupling rather than
removing it, which is the trap the row names.

## Prove it BOTH ways - this is the deliverable

1. **Alone, on a device whose Keychain was deliberately cleared.** Erase the simulator
   (`xcrun simctl erase <device>`, which does clear the Keychain - an uninstall does not) and run
   only `-only-testing:TankbookUITests/RemindersDeepLinkUITests`. Green.
2. **Immediately after another suite in the same run** - e.g. `SignInUITests` then this one. Green.

**State the exact command for each in your report, with its exit code.** A single green full-suite
run proves nothing here: that is the state that hides the bug today.

## Audit the siblings, and REPORT rather than fix

`RemindersNotificationActionUITests`, `SettingsUITests` and `AccountDevicesUITests` all touch session
state. For each, say whether it plants its own session or inherits one, and how you determined it.
**Do not fix them all silently** - a list of which are self-sufficient is the useful output; fixing
four suites in one row makes the change unreviewable.

## Tests

Read the current `swift test` count yourself before you start and report before -> after (this row
may not change it at all - if the change is app-target-only, say so rather than inventing an L1).

- **L4**: the two runs above.
- Suites to run: `RemindersDeepLinkUITests` (both ways), plus `RemindersNotificationActionUITests`
  if your audit changes anything about it. Report the observed count - a filter matching nothing
  prints "0 tests ... passed".

### Vacuous traps, named

- **Running only the full suite**, which passes today.
- **Planting the session in a shared `setUp`** other suites also mutate.
- **Asserting the deep-link route** rather than the screen it lands on.
- Running "alone" on a simulator that already holds a session from an earlier run - that is the same
  false green in a smaller box. Erase first, and say that you did.

### Mutations (run each, report, restore byte-for-byte)

1. Remove the session-planting you added -> the alone-run must fail with the guest layout (this is
   the reproduction, so run it FIRST and report it as the "before").
2. Point the suite's assertion at the car switcher's mere existence rather than the car's name ->
   whichever test covers the two-car selection must still fail under a wrong-car bug. If it does
   not, the suite is weaker than it looks and that is a finding.

## Explicitly out of scope

- Changing what the deep link does, or the merged list it lands on ([RV.79], correct).
- Fixing the sibling suites (audit and report only).
- Making `simctl uninstall` clear the Keychain, or any change to how the app stores its session.

## Docs to reconcile

`docs/TESTING.md` - the order-dependence family has now bitten this suite three times (2026-08-30
suites that only pass in company, 2026-08-31 the Keychain surviving an uninstall, and this row). If
there is a place that says how a UI suite must state its preconditions, add the rule there: **a
suite plants the session it needs; a suite that reads Home's signed-in chrome may never inherit
one.**

## Hard rules that decide things in this area

**14** (it builds and it lints before anything else counts) - and the standing rule that a brief
NAMES the suites it expects to run, which this one does.

## Where you may write

Only inside `/Users/sbelyaev/repos/fuel-counter-ios`, and within it only:
`ios/Sources/TankbookCore/**`, `ios/App/Sources/**`, `ios/Tests/**`, `ios/App/UITests/**`,
`backend/src/**`, `backend/tests/**`, and the docs named in this brief. **If your row's "out of
scope" says not to touch a tier, that fence wins over this list.**

**Never move, rename or delete a file you did not create.** Another session may be working in this
checkout. Expect files, and even a red test, that are not yours: **report them and carry on** - never
"clean the baseline".
Do NOT tick anything in `docs/TASKS.md` - the orchestrator ticks at merge. Do NOT commit.
No `git add -A`, `git checkout`, `git stash`, `git clean`.

## Write code first, explore second

The dominant failure mode is a run that reads everything and writes nothing. The cause is pinned to
lines above. Where this brief leaves a genuinely open choice, **take the smallest correct option and
keep going**, then say which you took and what you rejected. Do not stop and wait on it.

**My diagnosis can be wrong** - it has been four times this month, and the agent was right every
time. If the reproduction does not match what this brief claims, **say so and report what you
measured**; that is a better outcome than a fix built on a wrong premise.

## The baseline gate (CLAUDE.md rule 14)

From the **repo ROOT**, judged by exit code (`echo $?`), never by skimming output:
- `cd ios && swift build` -> 0; `cd ios && swift test` -> 0, count reported (before -> after).
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

## Report back

1. Exit code of every gate, and observed test counts (before -> after), per tier you touched.
2. The reproduction: what you measured BEFORE changing anything, in numbers.
3. Each mutation: what you broke, which named test failed, that you restored it byte-for-byte.
   **A mutation that PASSES is a finding** - say so rather than moving on.
4. What is now true that was not before. If the honest answer for some case is "nothing changed",
   say so.
5. Anything in this brief that was wrong, as a Residual.
6. Whether the tests were actually **run**, not only written.
