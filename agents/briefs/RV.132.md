# RV.132 - "Check for rates" tells the user nothing

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The report, from a production device

Product owner, 2026-09-07 (device `787c4f6f`, `1.0.0+841`): *"Check for rates button doesn't work,
or the user doesn't understand if something is happening. Server logs doesn't show anything."*
The logs confirm it: across 20:24-20:30 the device pushes, pulls, refreshes its token and posts
feedback, and there is **no `/rates` line at all**.

## Half of this is ALREADY FIXED. Do not re-fix it.

The shipped build called `AppRates.refresh()`, which takes `RateStore.refresh()`'s **default
`trigger: .background`**, and `PowerState.swift:83-84` defers `.ratePackRefresh` whenever Low Power
Mode is on **and** the trigger is `.background`. So the tap opened no connection at all.

**[RV.111] already replaced that call with `drainPendingRows()`, which passes `.userInitiated`.**
That is in the tree. Confirm it and move on - your row is the second half.

## Your half: five different outcomes are indistinguishable

`AppRates.drainPendingRows()` (`ManualFillUpCurrencySupport.swift:127-142`) is silent by design -
`onBackfilled` posts no toast, deliberately, because `docs/SYNC.md` S8 makes the **automatic** pass
silent. So a tap that filled rows, one that reached the provider and found nothing, one deferred by
Low Power Mode, one with nothing pending, and one that hit a dead network **all look the same:
nothing moves.**

**The outcome data mostly exists but is thrown away.** `MoneyBackfillService.DemandDrainResult`
carries four facts - `filledCount`, `stillPendingCount`, `reachedProvider`, `hasUnresolvableRows` -
and `drainPendingRows` collapses them to a two-field `MoneyBackfillService.Result`, **losing
`reachedProvider`**, which is exactly what separates "asked and the provider has none" from
"never asked". It also returns `nil` for **both** "no repository" and "nothing pending", which are
not the same outcome. Widening that return is part of this row.

## Design questions ALREADY CLOSED

1. **The automatic path stays silent.** S8's "nothing was wrong" rule is about the background pass.
   A launch must not raise a toast. The distinction you are writing down is **user-initiated vs
   automatic**, not "rates are noisy now".
2. **The acknowledgement is immediate, before the network resolves.** A spinner that appears only
   when the response lands still reads as a dead button on a slow link - that is the reported
   symptom, so getting this backwards fails the row.
3. **Low Power Mode is named explicitly** when it defers, because it is the one outcome the user can
   act on. Do not fold it into a generic "try again later".
4. **Never blocking, never a modal.** `docs/ERRORS.md` severity vocabulary: this is a notice.

## What to build

- Widen what `drainPendingRows` returns so the caller can tell the outcomes apart, including
  "nothing was pending" and "the provider was never reached". Keep `DemandDrainResult`'s four facts
  rather than inventing a parallel type.
- A visible outcome per case. `ToastCenter.show(_:)` exists (`ios/App/Sources/Navigation/ToastCenter.swift:19`)
  and `HomeView` already holds an `AppToastCenter` (`:19`); the footnote itself is also a live
  region. **Decide which surface carries which outcome and say why** - a toast for a transient
  result and the footnote for a standing state is a defensible split, but make the choice
  deliberately.
- Copy: **one full localised phrase per language**, EN + RU in `Localizable.xcstrings`, never
  concatenation, with **RU plural forms** for any count (three forms: строка/строки/строк). The
  dead-end wording [RV.111] added already exists - reuse it, do not write a second one.
- **Write the outcomes into `docs/ERRORS.md`** as part of the change: this is a user-facing surface
  and that doc is its authority.

## Explicitly out of scope

- `LowPowerPolicy`, `PowerState`, and the deferral rules themselves.
- The automatic launch pass (`TabRoots.runAutomaticPass`).
- [RV.112] (rate-pending rows read as zero in the vitals tile and Trends).
- Changing what `fetchSpan` asks for, or the 400-day chunking.

## Docs to read before writing (in order)

1. `docs/ERRORS.md` -> the Home surface and the severity vocabulary (**the authority**).
2. `docs/SYNC.md` -> S8 (**why the automatic path is silent** - read this before touching anything).
3. `CLAUDE.md` - hard rules 1, 3, 7, 10, 13.
4. `docs/SCHEMA.md` -> Exchange rates.

## Checks

Baseline: **iOS 1639 tests / 182 suites**, `swift build` 0, `swiftlint` 0 errors **from the repo
ROOT**, localization gate 0 (773 keys, 100% RU). Rows are landing around you; **re-measure the
baseline yourself** and report what you found, including any failure that is not yours.

1. `cd ios && swift build` - 0.
2. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
3. `cd ios && swift test` - full, never subsetted; report the number.
4. `xcodegen generate` + the Home/Trends UI suites you touched **by name**; report a non-zero
   observed count - a filter matching nothing prints "0 tests ... passed".
5. Localization gate - 0, 100% RU, report the key count.
6. Release build - required if you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1**: a user-initiated drain is **NOT deferred in Low Power Mode**. Assert against
  `LowPowerPolicy.defers(work:trigger:lowPowerMode:)` - the rule - not against a captured trigger
  value, and run it with `lowPowerMode: true`, where the deferral is observable.
- **L1**: the drain reports "nothing pending" **distinguishably** from "asked and nothing came back".
- **L4**: each outcome renders a different, identifiable state - filled, provider had none, nothing
  pending, Low Power deferral.
- **L4**: the **automatic** launch pass still shows nothing.
- **L4**: the acknowledgement is present **before** the network call resolves.

### Vacuous traps, named

- Asserting a toast appeared without asserting **which outcome** it names.
- Making the automatic pass noisy, which breaks S8.
- A spinner that only appears after the request returns - the reported symptom.
- Testing with Low Power Mode **off**, where the deferral cannot be observed.
- Asserting the trigger enum is passed, rather than that the work is not deferred.
- Writing a second dead-end string instead of reusing [RV.111]'s.

## Screenshots

Home showing the outcome after a tap, dark, EN and RU:
`design/screenshots/RV.132-home-rates-outcome.png` and `-ru.png`. Pass the reset flag with the seed;
take them **outside** a test run; **OCR your own capture and read the text back** - a committed
screenshot has twice shown the opposite of its row's claim.

## Never `pgrep -f` for a build process

Your brief is part of your command line. Use `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**,
which surface you chose for which outcome and why, and confirmation that [RV.111]'s
`.userInitiated` trigger is in place. Name any closed decision you think is wrong and stop there.
