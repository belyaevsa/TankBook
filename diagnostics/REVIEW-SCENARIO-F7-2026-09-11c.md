# REVIEW-SCENARIO run: F7 - 2026-09-11c

## Verdict

**NOT IMPLEMENTED.** One v1 promise (F7's source 3, "import a file you exported yourself") names a next step that does not work: the import rows on both the empty-restore and backend-down screens are `NavigationLink(value: Route.importWizard)` rendered inside a sheet that has no `navigationDestination(for: Route.self)`, so tapping them navigates nowhere.

## Ticked rows found untrue

| Row | Claim | What the code actually does |
|---|---|---|
| `P4.7` (`[x]`, TASKS-DONE.md:178) | L4: "backend down -> `.unreachable` (F7 copy + **import path reachable**)" | The import row renders and is hittable, but it is not *reachable*: `RestoreFailureViews.swift:194` is a `NavigationLink(value: Route.importWizard)` with no matching `navigationDestination` in any presenting context (see sequence trace). The existing UI test only asserts `.exists`/`.isHittable`, never that a tap navigates (`SignInUITests.swift:261-262`). |

## Promise-to-code map

| F7 promise | Verdict | Evidence |
|---|---|---|
| Source 1: sync pull from zero (normal path) | MET | `Restore.swift:116-137` (`RestoreEngine.restore` = `SyncEngine.synchronize(.userInitiated)`); fresh cursor 0 in `SignInFlow.swift:427-450` (`InMemorySyncCursorStore`), final cursor persisted at `SignInFlow.swift:446-448`. |
| Source 2: server backup snapshot | N/A | `[v2]` per `PJ.46` (TASKS.md:788); `RestoreOutcome` has no snapshot case. |
| Source 3: "import a file you exported yourself" | **PARTIAL → broken** | The door exists (both failure screens) but is dead: `RestoreFailureViews.swift:72` (empty-restore) and `:194` (unreachable). No `navigationDestination(for: Route.self)` in the presenting sheet (only at `TabRoots.swift:577`, inside a different stack). |
| Backend down says exactly that, never generic | MET | `RestoreFailureViews.swift:183` (copy verbatim; asserted `SignInUITests.swift:256-258`). `.unreachable` is produced honestly by `Restore.swift:126-131`. |
| Truly nothing found: said *before* the user logs anything new, with a recovery entry point | MET | `EmptyRestoreView` "Expecting your data?" card (`RestoreFailureViews.swift:66-89`); `emptyRestore` phase reached before add-a-car is usable (`SignInFlow.swift:323`), asserted `SignInUITests.swift:213-242`. The recovery card's import row is the dead link above. |
| Post-restore: verification stats (entries, date range, last odometer) | MET | `RestoreStats.compute` (`Restore.swift:40-76`); rendered in `RestoringView.swift:83-101` (cars, entries with start/end month-year, last odometer). Asserted `SignInUITests.swift:187-204`. |
| Metric (≥99.5% / 100% recovery reach) | N/A | Metric, not a code promise. |

Noted, not blocking: the entries "date range" is month-year granularity only (`RestoringView.swift:108-113`), coarser than J2's preview; and "last odometer ... from your Android phone" source-device attribution is a v2 field, nil in production (`SignInFlow.swift:24-27`).

## Sequence trace

New phone → Welcome → "Already use Tankbook? Restore your garage" → `SignInFlowHost(arrivedViaRestore: true)` → provider sign-in → session saved → `RestoreEngine` pulls from cursor 0. Three exits:

- `.restored` → `RestoringView` (stats) → "Open my garage". Carried end to end. ✓
- `.empty` (returning user, Google offered) → wrong-provider question → switch/sign out. ✓ (J11a, not F7)
- `.empty` (peer sign-in / single provider) → `EmptyRestoreView` → recovery card lists "Import a file you exported yourself". **Fact lost here**: the `NavigationLink` has no destination.
- `.unreachable` → `RestoreUnreachableView` → "Import a file". **Same dead link.**

The fact that stops being carried is the *import next step*. The copy promises it, the row renders it, and it is unreachable for one structural reason that applies to every real presenting context:

- Welcome presents the flow in a bare sheet, no `NavigationStack` (`WelcomeRootView.swift:47-53`).
- Settings presents it the same way (`SettingsView.swift:79`).
- Home/Trends/Garage present it via `SheetDestinationView` → `DiscardAwareSheet`, whose `NavigationStack` (`DiscardAwareSheet.swift:30`) registers no `navigationDestination(for: Route.self)`; the only registration is `TabRoots.swift:577`, in the *tab* stack, not the sheet.

So a user whose restore fails or is empty is offered an import door that does nothing - on the app's most critical error screen (hard rule 7: the next step must exist *and* work).

## Proposed rows

| # | Deliverable (one line) | Closes | User-facing consequence today | Severity | Check (L1/L4) | Scenario |
|---|---|---|---|---|---|---|
| 1 | Make the import rows on `EmptyRestoreView` and `RestoreUnreachableView` open `ImportWizardView` (sheet presentation, or a `navigationDestination(for: Route.self)` on the sheets that present `SignInFlowHost`, or a host `onNavigate` callback). | F7 source 3 + backend-down "you can import an export file" | A user whose restore fails or is empty taps "Import a file you exported yourself" / "Import a file" and nothing happens - a dead next step on the error screen that exists to prevent data loss. | **bug** | L4 `SignInUITests`: tap `restoreUnreachableImportRow` and `emptyRestoreImportRow` and assert `ImportWizardView` appears (the existing test asserts only `.isHittable`, `SignInUITests.swift:261-262`). EN + RU. | F7 |

## Unsettled

- Whether "or it will all arrive when the service is back" (`RestoreFailureViews.swift:183`) is honoured without the user tapping "Try again": the automatic resume-on-reconnect is `PJ.39` `[v1.1]`. In v1 a user who swipe-dismisses (session stays saved) would be picked up by regular sync, but a user who taps "Sign out" (the only explicit non-import exit) clears the session and the data would not arrive. This is the `PJ.39` fence, not a new gap; left as N/A. A `PJ.39` implementation should confirm the copy's auto-arrival claim becomes true for every exit path.
