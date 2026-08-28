# Validation: P6.7 + W8, P6.18a/b, P6.8b (the iOS work of 2026-08-28)

Repo: **`/Users/sbelyaev/repos/fuel-counter-ios`**, branch `main`, at `015ea5c`.

**You are validating, not building.** Fix nothing. **Write exactly one file:**
`/private/tmp/claude-501/-Users-sbelyaev-repos-fuel-counter-ios/ios-validate-report.md`.
Do not commit. Do not modify `ios/`, `docs/`, `site/`, `Spike/` or `deploy/`.

**Do not run `xcodebuild` or `simctl`.** Two other processes are using the simulators right now. Use
`swift build`, `swift test` and source reading. If a claim can only be settled by a UI run, say so
in the report rather than running one.

Your value is finding what the orchestrator missed. A report that says "all good" without having
tried to break something is worth nothing. **Every prior validation on this project found real
defects, including seven checks that could not fail.**

## What landed, and the claim each makes

1. **P6.7 + W8** - added a `Palette.action` token, re-pointed ~66 non-electric uses of
   `headlight`, and moved light `headlight` to clear WCAG AA. Claim: cyan now means **electric
   only**, enforced by a source-scanning escape guard, and both tokens clear **4.5:1 on both
   grounds in both themes**.
2. **P6.18a/b** - `appUpdate` in the signed config, `AppVersion`, and a surface. Claim: the
   requirement **fails open** on anything unparseable, and under `.required` **everything local
   still works** (hard rule 1).
3. **P6.8b** - Low Power Mode wiring. Claim: **opportunistic work defers, user-initiated work never
   does**.

## Attack these, in priority order

**1. Is the escape guard honest?** `PaletteAccentGuardTests` compares `Palette.headlight`
occurrences against an allowlist of four electric uses. Ask: can a non-electric cyan reach a screen
**without** touching that guard? Consider `Color(...)` literals, `.tint`, `.accentColor`, asset
catalogue colours, values passed through a variable, and any spelling of the token the source scan
does not match. **The guard scans text - find what text it cannot see.**

**2. Do the contrast numbers hold for the pairs nobody tested?** The claim is AA on both grounds in
both themes. Compute every token pair that actually renders together - including `warn`, `taillight`
on `dash`, and any text drawn on an accent fill - from `design/tokens.json`. Report ratios as
numbers. A pair that fails and has no test is exactly the W8 defect repeating.

**3. Is fail-open real, or only tested where it is easy?** `AppConfig.updateRequirement` returns
`.none` for anything unparseable. Try to find an input that resolves `.required` or `.recommended`
when it should not: a version with extra components, leading zeros, whitespace, a negative or huge
number, an empty string, a non-ASCII digit. **Note: `CFBundleShortVersionString` is now `1.0.0`** -
check what that means for a build whose version is BELOW `minSupportedVersion`.

**4. Does hard rule 1 hold everywhere, not just where the test looks?** Under `.required`, find any
local path that stops working - saving, editing, recompute, export, viewing, undo. The UI test
covers a manual fill-up save. **Look for the paths it does not cover.**

**5. Low Power: is the background/user-initiated split complete?** Enumerate every call site that
starts work and classify it. Find one that is user-initiated but passes `.background`, or
opportunistic but passes `.foreground`. Also: the orchestrator noted the launch/foreground sync now
reaches the real network in UI tests - assess whether that makes any test order-dependent or
non-deterministic.

**6. Vacuous tests.** Read the new tests in `PaletteAccentGuardTests`, `AppUpdateRequirementTests`,
`ConfigUpdateSurfaceTests`, `LowPowerModeTests` and `SyncCoordinatorTests`, and for each ask: *if
the code were wrong, would this fail?* Name every one that would not, with the mutation proving it.

## Already known - do not re-report

- Screenshots are outstanding for all three tasks; the orchestrator is capturing now.
- Two ConfirmManual UI tests fail on `iPhone 17 Pro` and pass on `iPhone 17` - device-specific.
- Two SYNC.md triggers (debounced write, silent-APNs nudge) are unimplemented, out of scope.
- `ProcessInfoPowerState` was already constructed transitively before P6.8b - the TASKS row's old
  wording overstated it, and is corrected.

## Report

Write the file with: the exit codes you actually saw; **vacuous tests found, each with its
mutation**; defects ordered by severity with file and line; contrast ratios as numbers; claims that
outrun their evidence; and what you could NOT verify and why. A named gap beats a confident guess.

If you think part of this brief is wrong, say so - on this project agents who pushed back on a brief
have been right every time, including twice today.

En-dashes only, never em-dashes.
