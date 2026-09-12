# REVIEW-SCENARIO run: F7 - 2026-09-12 (first walk)

- **Scenario:** `F7` - Restore fails or comes back empty (J11's nightmare) (`docs/JOURNEYS.md:697-705`)
- **Run id:** REVIEW-SCENARIO-F7-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-F7-2026-09-12.md`
- **Context:** Rows closed today naming F7: `RV.239` (the dead import `NavigationLink`s on `EmptyRestoreView`/`RestoreUnreachableView`; `2f10dad1`). Earlier: `PJ.3` (restore intent by door), `PJ.13` (first push), `RV.197`, `RV.249`. Deferred and N/A: `PJ.39` `[v1.1]` (interrupted-restore row), `PJ.46` `[v2]` (server backup snapshot, decide-or-drop) - both cited, not re-filed. Read-only walk; no code, no build, no commit.

## Verdict

**NOT IMPLEMENTED** - one sequence hole: a restore-door user whose account is empty is sent to the wrong-provider question, and when the switched-to provider is *also* empty the flow re-asks the reverse question forever, with no in-flow door to F7's recovery entry point ("import a file you exported yourself") or "start fresh". Everything else in F7 is MET or reasoned N/A.

## Ticked rows found to be untrue

None. `RV.239` was walked against the tree and holds: `SignInFlowHost` declares its own `Route` destination (`SignInView.swift:61`), wrapped in a `NavigationStack` by `SignInSheet` (`SignInView.swift:88-96`); the three presenters each provide that stack - Settings via `SignInSheet()` (`SettingsView.swift:78`), Welcome via `SignInSheet(arrivedViaRestore:)` (`WelcomeRootView.swift:52`), the tab roots' `.signIn` sheet via `DiscardAwareSheet`'s `NavigationStack` (`Destinations.swift:84` -> `DiscardAwareSheet.swift:30`). `DestinationView` maps `.importWizard` to `ImportWizardView` (`Destinations.swift:46`). `PJ.13`, `PJ.3`, `RV.197`, `RV.249` were verified by `REVIEW-SCENARIO-J11a-2026-09-12.md` and spot-checked here (`SignInFirstPush.swift:53-61`; `SignInFlow.swift:250-253,442-443`).

## Promise-to-code map

| Journey promise (F7) | Status | Citation |
|---|---|---|
| **Source 1** - sync pull from zero is the normal restore path | MET | `RestoreEngine.restore` = `SyncEngine.synchronize(trigger: .userInitiated)` (`Restore.swift:116-121`); `SyncRestoreProvider` pulls from a 0-seeded cursor (`SignInFlow.swift:424-452`) |
| **Source 2** - a server backup snapshot | N/A (v2) | not built; `PJ.46` `[v2]` decide-or-drop owns it, including the "amend `JOURNEYS.md` F7 / `SYNC.md:103`" option (`TASKS.md` PJ.46). F7's line 700 is unmarked v1 but the middle source is a tracked v2 decision - cited, not re-filed |
| **Source 3** - "import a file you exported yourself" | MET | the recovery entry point on both failure screens, now reachable after `RV.239` (`RestoreFailureViews.swift:72-76` empty; `:194-198` unreachable) |
| **Sources shown honestly** | PARTIAL | pull + import are honestly named on the unreachable screen; the "sources tried listed" half is `PJ.46` `[v2]`. The copy itself never invents a source (`RestoreFailureViews.swift:183`) |
| **Backend down** - say exactly that, never generic | MET | `RestoreUnreachableView.titleBlock` = "Sync service unreachable - your data is safe on the server. You can import an export file, or it will all arrive when the service is back." (`RestoreFailureViews.swift:183`); matches `ERRORS.md:42` and has RU |
| **Truly nothing found** - say so *before* the user logs new, with an "expecting your data? ->" recovery entry point | MET | `EmptyRestoreView` title "No data found" + `recoveryCard` with "Expecting your data?" (`RestoreFailureViews.swift:54-68`); the import row and "Sign out and try another account" sit above "Start fresh" (`:72-84`, footer `:108-132`) |
| **Empty-restore recovery entry point reached 100%** (metric) | PARTIAL / MISSING | the entry point exists, but a restore-door empty account is intercepted by the wrong-provider question and can loop away from it - see Finding below |
| **Post-restore** - show J2's verification stats (entries, date range, last odometer) | MET | `RestoringView.foundCard` renders cars, entries with date range, and last odometer (`RestoringView.swift:83-123`); stats computed from what actually landed, never a stored counter (`Restore.swift:40-76`) |
| **Post-restore source device** ("from your Android phone, yesterday") | N/A (v2) | `RestoreSnapshot.lastOdometerDeviceName` is nil in production, seed-only - author attribution is a v2 field (`SignInFlow.swift:25-27`) |
| **Restore resolves honestly to full / empty / unreachable / revoked** | MET | `RestoreOutcome` (`Restore.swift:91-102`); interrupted-with-data -> `.restored`, interrupted-with-nothing -> `.unreachable` (`Restore.swift:126-132`) |
| **Interrupted restore gets its own row + both next steps** | N/A (v1.1) | `RestoreOutcome.interrupted` does not exist; `PJ.39` `[v1.1]` owns it, cited |
| **The spine - each source names its next step and survives being ignored** | MET | see sequence trace |

## Sequence trace

**Restore, account has data:** Welcome -> "Already use Tankbook? Restore your garage." (`arrivedViaRestore: true`, `WelcomeRootView.swift:39,52`) -> sign in -> `localHasData()` false -> `runRestore` (`SignInFlow.swift:250-255`) -> pull from 0 -> `.restored` -> `RestoringView` stats -> "Open my garage" (`RestoringView.swift:200-213`) -> dismiss -> tabs. The account identity (`signedInAccountId`) is carried for retry (`SignInFlow.swift:126,204-207`). No fact dropped.

**Restore, empty account, via peer/Settings door:** sign in -> empty -> not `arrivedViaRestore` -> `.emptyRestore` (`SignInFlow.swift:322-324`) -> recovery entry point -> "Start fresh" -> `acceptEmpty` -> one user-initiated push -> dismiss (`RestoreFailureViews.swift:110-112`, `SignInFlow.swift:223-234`). Correct - a new account is never asked about a sign-in it never made.

**Restore, empty account, via restore door (the hole):** Welcome -> restore door -> sign in -> empty -> `arrivedViaRestore && offersGoogle` -> `.wrongProvider` (`SignInFlow.swift:312-321`) -> "did you sign in with Google?" (`SignInView.swift:321-391`). If the user genuinely never used the other provider (data lost, or mis-tapped the restore door), "switch" -> `signOutLocally` + `startSignIn(other)` (`SignInFlow.swift:183-186`) -> other account is *created empty* -> `performRestore`'s `.empty` arm runs again with the same `arrivedViaRestore && offersGoogle` gate -> `.wrongProvider` for the *reverse* question. **The fact "this user has no data under either provider" is never carried to a terminal state** - the loop is unbounded (Apple <-> Google), and the only exits are "sign out" / "not now" (`SignInView.swift:332-340,373-380`), both of which return to Welcome; the F7 recovery entry point ("import a file") is reachable only by re-entering through the *peer* "Sign in to Tankbook" button, which the user has no reason to distinguish from the door they just used.

**Backend down:** sign in -> pull fails -> `.unreachable` (`Restore.swift:126-132`) -> `RestoreUnreachableView` -> "Import a file" / "Try again" (`retryRestore`, `SignInFlow.swift:204-207`) / "Sign out". All name a next step and survive being ignored.

**Guest's local data never touched by a failed restore:** the wrong-provider path issues no sync (`SignInFirstPush.complete(.wrongProvider)` returns false, `SignInFirstPush.swift:58-59`); a local log short-circuits to upload *before* any pull (`SignInFlow.swift:250-253`); `cancelRestore` cancels the pull, signs out, and leaves local data intact (`SignInFlow.swift:213-218`).

## Proposed rows

| ID | Deliverable | Journey stage it closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| (new) | Give `SignInFlow` a "both providers tried" terminal: once the user has already switched provider, a second empty account routes to `.emptyRestore` (the F7 recovery screen) instead of re-asking the wrong-provider question - one decision in `performRestore`'s `.empty` arm (`SignInFlow.swift:312-324`), e.g. a `didSwitchProvider` flag set in `switchProvider` (`:183-186`) | F7 "truly nothing found" + metric "empty-restore sessions reach the recovery entry point: 100%"; J11a wrong-provider handoff | Latent today (Release ships `GoogleClientID` empty, `offersGoogle` false, so a restore-door empty account goes straight to `.emptyRestore`); the moment Google is provisioned (SH.4 wired) a restore-door user whose data is genuinely gone loops Apple <-> Google with no in-flow path to "import a file" or "start fresh" | **gap** | L1 in `SignInFlow`: with the switch flag set, a `.empty` outcome resolves to `.emptyRestore`, never `.wrongProvider` a second time. L4 `SignInUITests` EN+RU: a switch-provider walk where the second provider is also empty lands on the empty-restore screen (or import wizard), not a second wrong-provider question. **Mutation**: reset the flag -> the second wrong-provider question reappears | F7 |

## Not settled

- **The loop is dormant until Google ships.** `offersGoogle` gates both the amber notice and the reactive question on `GoogleOAuth.Configuration.fromBundle() != nil` (`SignInView.swift:204`), and the J11a review measured a Release build ships the client id empty. So today the finding has no user-visible consequence - but the code path is live and F7/J11a promise the wrong-provider detection as v1. This is a launch-provisioning decision, not a code gate: the row above should land before (or with) the Google client id, not after.
- **"Not now" on the wrong-provider screen leaves the (empty) session in the Keychain.** The dismiss button calls `dismiss()` without `signOutLocally()` (`SignInView.swift:332-340`), so a user who ignores the question stays signed into the empty account; Welcome's `reevaluate()` then treats "has session" as onboarding-complete (`WelcomeRootView.swift:65-72`). This is J11a's "never show an empty garage as if their data were gone" surface rather than F7's spine; left for the J11a re-walk rather than filed here, since it does not touch restore data or F7's recovery entry point.
