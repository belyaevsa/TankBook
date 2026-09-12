# REVIEW-SCENARIO run: J11a - 2026-09-12 (first walk)

- **Scenario:** `J11a` - First sign-in (there is no "registration") (`docs/JOURNEYS.md:500-512`)
- **Run id:** REVIEW-SCENARIO-J11a-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J11a-2026-09-12.md`
- **Context:** First walk. Closed today naming J11a: RV.249 (`a7d59566`, the pull cursor is keyed by account), RV.155 (`88bb4e2`, the cursor advance is durable at the pull), RV.253 (`7b234946`). Closed earlier: PJ.13 (the just-signed-in card + first push), RV.197 (the guest Home log stream), PJ.3 (the Welcome root carries the restore intent), P4.4, SH.4 (Google wired without the SDK), PR.35 (token aud/iss verified), RV.54 (device count is LIVE only), RV.23 (restore intent carried by which door). Open and cited-not-re-filed: RV.256 (unkeyed sync state), RV.239 (dead import link on the empty-restore screen), RV.129 (`SignInRouter` dead code). Deferred rows are N/A for the v1 verdict. Read-only walk; no code, no build, no commit.

## Verdict

**IMPLEMENTED** - every stage, fallback and "→" note in J11a is MET or reasoned N/A in code, walked for both the guest-with-data case and the fresh-install case. The three residual defects the walk surfaced (the dead import link, the account-unkeyed sync state, the duplicated sign-in decision) are all already filed under their own rows; none is an unowned J11a promise. Two minor observations are recorded in "Not settled" and deliberately not filed.

## Ticked rows found to be untrue

None. Each closed row naming J11a was walked against the tree and holds:

- **RV.249** (cursor keyed by account): `UserDefaultsSyncCursorStore(accountId:)` stores under `tankbook.sync.cursor.<accountId>` with a one-time legacy-key migration and a per-account monotonic `save` (`SyncTransport.swift:39-87`); `AppSync.refresh` drops and rebuilds the coordinator when the session's account id differs (`AppSync.swift:345-352`); `SignInFlow`'s restore seeds 0 but writes through to the account-keyed store (`SignInFlow.swift:442-443`).
- **RV.155** (cursor advance durable at the pull): `SeededSyncCursorStore.save` writes through to `durable` at every advance (`SyncTransport.swift:116-121`), so a pull that earned the advance persists it before the surrounding cycle finishes.
- **PJ.13** (first push): `SignInFirstPush.complete` runs exactly one `.userInitiated` cycle on `.uploadLocalLog`/`.acceptEmpty` and returns `false` (no push) on `.wrongProvider` (`SignInFirstPush.swift:53-61`); the live seam is `AppSync.firstPushNow` (`AppSync.swift:410-425`), which the sign-in flow awaits before `onFinished` (`SignInFlow.swift:231-234`).
- **PJ.3** (restore intent real): the Welcome root's two doors carry the intent by which door was tapped - `.restore` passes `arrivedViaRestore: true`, the peer `.signIn` passes false (`WelcomeRootView.swift:38-39,47-53,100-108`); the `-signInWrongProvider` fixture is retired (`SignInTestSeed.swift:20-23`).
- **P4.4** (sign-in + J11a detection): the wrong-provider detection lives in `SignInFlow.performRestore`'s `.empty` arm (`SignInFlow.swift:306-324`), reachable in production through the Welcome restore door - no DEBUG door.
- **RV.54** (device count LIVE only): `DeviceCountCache` records `devices.liveDeviceCount` (`DeviceCountCache.swift:66-73`), computed by filtering `revoked` (`AccountClient.swift:41-42`).
- **RV.23** (benefit copy): out of J11a's spine; not walked.
- **RV.253** (quota card): F10/J11, not a J11a promise; not walked.

## Promise-to-code map

| Journey promise (J11a) | Status | Citation |
|---|---|---|
| **Choose** - Apple or Google, one tap, no form/password/email verification | MET | `SignInView.providerButtons` (`SignInView.swift:170-177`); Google button gated on `offersGoogle` (`:183`); no form exists anywhere in the flow |
| **Choose** - `POST /auth/session` creates the account on first sight | MET | `AuthService` → `FindOrCreateAccountAsync` (ON CONFLICT DO NOTHING, re-selects the winner) (`AuthRepository.cs:86-125`, `AuthService.cs:106-107`); no separate registration endpoint exists in `Program.cs` (`:559-567` maps session/refresh/sign-out only) |
| **Choose** - the word "register" appears nowhere in the app | MET | grep over `ios/App/Sources` + `ios/Sources`: no sign-in "register"; only technical "registered migration/schema/category" uses |
| **Choose** - the verified token IS the registration | MET | `AppleGoogleIdTokenVerifier` verifies aud/iss (PR.35, `[x]`); `AuthService` rejects before account resolution (`AuthService.cs:95-101`) |
| **Create** - invisible, same screen and tap | MET | `FindOrCreateAccountAsync` returns `(id, created, email)`; the client treats `created` and `matched` identically - `signIn` saves the session and proceeds (`SignInFlow.swift:236-255`); the created/matched split is only a log field (`AuthService.cs:127`) |
| **First push** - local log uploads, never overwritten | MET | `localHasData()` (`Repository.swift:116-118`) short-circuits to `.uploadLocalLog` BEFORE any restore pull (`SignInFlow.swift:250-253`); the push is the app's one coordinator via `firstPushNow` (`AppSync.swift:410-425`) |
| **First push** - user-initiated, before the sheet closes, never background | MET | `SignInFirstPush` emits `.userInitiated` (`SignInFirstPush.swift:55-57`); `finish` awaits it then calls `onFinished`/dismiss (`SignInFlow.swift:231-234`) |
| **First push** - pushes only on the two completion paths; wrong-provider never pushes | MET | `.uploadLocalLog` (local log) and `.acceptEmpty` ("Start fresh" → `acceptEmpty`, `SignInFlow.swift:223-225`) push; `.wrongProvider` returns false (`SignInFirstPush.swift:58-59`) |
| **Confirm** - "Your garage now follows your account", one line | MET | `justSignedIn` → `L10n.garageFollowsAccountMessage` on the account card (`SettingsView.swift:234-239`, `AppSync.swift:174`) |
| **Confirm** - "Synced just now · 1 device" | MET | `L10n.syncedStatus` appends the count only when a sync actually happened (`L10n.swift:643-650`); count read live on the sheet-dismiss refresh (`SettingsView.swift:68-78`) |
| **Confirm** - device count counts LIVE devices only | MET | `liveDeviceCount` filters `revoked` (`AccountClient.swift:41-42`); recorded through `DeviceCountCache` (`DeviceCountCache.swift:66-73`); L1 `LiveDeviceCountTests` |
| **Wrong-provider, proactive** - warn-amber "Pick one and keep it" at the decision moment | MET | `amberNotice` rendered when Google is offered (`SignInView.swift:100-102,255-276`) |
| **Wrong-provider, reactive** - empty account + restore intent → honest question + one-tap switch, never an empty garage | MET | `performRestore` `.empty` arm: `arrivedViaRestore && offersGoogle` → `WrongProviderView` (`SignInFlow.swift:306-324`, `SignInView.swift:297-370`); switch = `switchProvider` (`SignInFlow.swift:183-186`) |
| **Wrong-provider, reverse guard** - local log never overwritten, it uploads | MET | `localHasData` precedence in `SignInFlow.swift:250-253`; the same rule is the pure decision's first branch (the dead `SignInRouter`, see Not settled) |
| **Handoff** - "Start fresh" → account accepted → one push | MET | `EmptyRestoreView` footer `flow.acceptEmpty()` (`RestoreFailureViews.swift:108-132`) → `finish(.acceptEmpty)` → push |
| **Handoff** - the first pull from 0 IS restore (fresh install, account has data) | MET | `SyncRestoreProvider` pulls from a 0-seeded cursor (`SignInFlow.swift:428-452`); `.restored` → `RestoringView` with stats before "Open my garage" (`RestoringView.swift:200-213`) |
| **Success metric** (completion ≥90%, recoveries ≥95%) | N/A | metric, not code |

## Sequence trace

**Guest-with-data (the headline case):** Home (guest) → Settings "Sign in to sync" (`SettingsView.swift:161`) → `SignInFlowHost(arrivedViaRestore: false)` → tap Apple → `AppIDTokenProvider` → `RemoteAuthService` (`POST /auth/session`, account created) → session saved to Keychain → `localHasData()` true → `finish(.uploadLocalLog)` → `SignInFirstPush.complete` → `AppSync.firstPushNow` (`.userInitiated`, push local car+fill-ups, pull+merge) → `onFinished` dismisses → Settings `onDismiss` refreshes (`SettingsView.swift:68-78`) → card reads the new session, rebuilds the account-keyed coordinator, fetches the live device count → "Synced just now · 1 device" + "Your garage now follows your account". **No fact is dropped: the guest's records stay local and dirty until the push uploads them; nothing is pulled over or replaced.**

**Fresh install, existing account (J11 handoff):** Welcome → "Already use Tankbook? Restore your garage." (`arrivedViaRestore: true`) → sign in → no local data → `runRestore` → pull from 0 → `.restored` → `RestoringView` stats → "Open my garage" → dismiss. The fact carried end to end is the account identity (`signedInAccountId`), which the restore and the retry re-use.

**Fresh install, empty account, via restore door:** Welcome → restore door → sign in → no local data → restore `.empty` → `arrivedViaRestore && offersGoogle` → wrong-provider question (switch = `signOutLocally` then the other provider; sign out = `signOutLocally` + dismiss, local app intact). The fact carried is the restore intent; the empty account is never presented as data loss.

**Fresh install, empty account, via peer door / Settings:** sign in → no local data → restore `.empty` → not `arrivedViaRestore` → `.emptyRestore` (F7) → "Start fresh" → `acceptEmpty` → one push → dismiss. Correct - a brand-new account is never asked about a sign-in it never made.

**Where a fact stops being carried:** none in J11a's own spine. The one seam that does drop a fact is F7's, not J11a's: `EmptyRestoreView`'s "Import a file you exported yourself" is a `NavigationLink(value: Route.importWizard)` inside the sign-in sheet with no reachable `navigationDestination` - that is RV.239 (open, blocks F7), and J11a merely hands the user to that screen.

## Proposed rows

None. The residual defects are already owned:

- **RV.239** (open) - the dead "Import a file" link on `EmptyRestoreView`/`RestoreUnreachableView` (`RestoreFailureViews.swift:72,194`), which J11a's "Start fresh" and backend-down paths hand the user to. Filed as "blocks F7"; the L4 that fails today is already named in that row.
- **RV.256** (open) - `UserDefaultsSyncStateStore` under one key `tankbook.sync.state` (`SyncStateStore.swift:102`) bleeds account A's last success/failure onto B's card after a sign-out + different sign-in. It touches J11a's Confirm promise only in the account-switch/wrong-provider-recovery path, is a display defect (not pull correctness), and names J11a in its own scenario id. Cited, not re-filed.
- **RV.129** (open) - `SignInRouter` is referenced only by `SignInRouterTests`; the live decision is inline in `SignInFlow.swift:250-253` + `:307-324`. Code-hygiene (one implementation per decision), no user-facing consequence; the live branches are covered by `SignInUITests` through the stub. Cited, not re-filed.

## Not settled

- **The wrong-provider mitigations are dormant until Google is provisioned.** Both the amber notice and the reactive question gate on `SignInView.offersGoogle` (`GoogleOAuth.Configuration.fromBundle() != nil`), and SH.4 measured a Release build ships `GoogleClientID` empty. With only Apple offered there is no wrong-provider scenario to detect, so the gating is correct - but the journey's two mitigations never fire in the current shipping build. This is a launch-provisioning decision (fill the Google client id), not a code gap; it activates as-is when Google ships. Not filed.
- **`SignInFlow.Phase.uploading` is never set.** The case is declared (`SignInFlow.swift:98`, rendered `SignInView.swift:45`) but no code assigns `phase = .uploading` - the upload path stays on `.signingIn` (provider spinner) until `onFinished`. Dead state, no user-visible consequence; the RV.129 dead-code sweep would be its natural home. Not filed.
- **The "Your garage now follows your account" line is optimistic.** `AppSync.firstPushNow` sets `didJustSignIn = true` before its `guard` (`AppSync.swift:410-414`), so the confirmation renders even when the push was skipped (build decommissioned) or failed (server down, shown alongside an "unreachable" status). The account does exist (the session exchange succeeded) and the local data is never lost (hard rule 1, retry later), so this reads as a wording nuance rather than a hard-rule-8 break. Not filed; a one-line decision on the next change touching `firstPushNow` settles it.
