# iOS dead-code assessment

Date: 2026-09-07  
Scope: `ios/App/Sources`, `ios/Sources/TankbookCore`, and the localization-gate targets  
Snapshot: commit `1c46ce3` plus the working-tree changes present during the review

## Result

The iOS codebase has a real dead-code hygiene problem, but most of it is not a large collection of abandoned screens. The common pattern is smaller and more dangerous: a tested helper or policy is left in production source while the app uses a separate implementation. Those tests stay green without protecting the behavior the user runs.

The review found:

| Category | Count | Interpretation |
|---|---:|---|
| Production Swift files reviewed | 449 | 234 app, 210 core, 5 tooling |
| Production lines reviewed | 75,886 | 41,080 app, 32,958 core, 1,848 tooling |
| Declarations with no code reference anywhere | 27 | Six are required framework/entry-point declarations; 21 are genuine repository-scoped findings |
| SwiftLint compiler-backed `unused_declaration` findings | 48 | 25 affect production behavior or ordinary app code; 23 are test-support declarations compiled into production targets |
| Overlap between the two passes | 9 | Counted once below |
| Unique high-confidence runtime-unused declarations | **37** | 21 no-reference declarations plus 16 additional semantic findings |
| Compiler warnings for dead local bindings/results | **6** | Separate from the 37 declaration findings |
| Actionable dead-code sites | **43** | 37 declarations plus 6 local fragments |
| Additional “tests reference it, the app does not” candidates | 67 | A review queue, not a dead-code count; protocol witnesses and intentional test APIs require manual classification |

The denominator for the 37 findings is declaration sites, not lines or files, so it should not be presented as a percentage of the codebase. The useful quality signal is that the compiler currently emits six basic unused-value warnings and CI does not run the analyzer rule that found the other 48 sites.

## Method and confidence

I used four checks:

1. Built the app target with `xcodebuild` in Debug configuration. The build succeeded.
2. Ran SwiftLint's compiler-backed `unused_declaration` analyzer against that build log. It returned 48 findings.
3. Scanned every production declaration and counted code references across app, core, tools, unit tests, app-hosted tests, and UI tests. Comments were excluded. This found public declarations that SwiftLint intentionally does not report.
4. Manually traced the important candidates to their runtime consumers, tests, protocol conformances, and documented user behavior.

“No reference” means no repository Swift code refers to the declaration's identifier outside its declaration. It does not prove that every such declaration should be deleted. Public package API, persisted schemas, Objective-C selectors, delegates, SwiftUI entry points, `Codable`, and protocol witnesses can be live without an ordinary call expression.

The following six single-occurrence declarations are live and were excluded from the findings:

- `TankbookApp`, the `@main` entry point.
- `CameraPreview.layerClass`, a UIKit override.
- `documentCameraViewControllerDidCancel`, a VisionKit delegate callback.
- The two `UIImagePickerControllerDelegate` callbacks in `ReceiptAttachSupport.swift`.
- `viewForZooming`, a `UIScrollViewDelegate` callback.

## Highest-priority findings: dead code that reveals missing behavior

These should be resolved before the mechanical cleanup because deletion alone would preserve or hide a product defect.

### Feedback retry is promised but never runs

**RESOLVED in RV.127 (2026-09-07).** `flush()` previously had no call site while its comment and the UI promised an automatic retry. `runAutomaticPass` now calls `FeedbackService.outbox.flush()` beside the delivery-outbox drain; `FeedbackService.outbox` is the single memoized outbox the About composer also submits through, and the flush comment names the real trigger (the next foreground), not connectivity. Pinned at L1 (`FeedbackTests`: cold-start persisted send, no-connectivity stays queued, racing flush posts once) and in the app target (`FeedbackForegroundFlushTests`: the pass source invokes the flush and shares one outbox).

### Odometer warnings ignore the vehicle's distance unit

`ios/App/Sources/ConfirmManual/ManualFillUpFormState.swift:252` computes `unit = L10n.distanceUnit(distanceUnit)` and never uses it. The warning at line 257 hardcodes `km`. A miles-configured vehicle can therefore receive a kilometre-labelled conflict message even though the function accepts the correct unit.

Action: use the computed unit in the localized sentence and add a miles case. Treat this as a correctness/localization bug, not only an unused-local cleanup.

### Multi-car import has a tested-looking row-unit helper that the UI bypasses

`ios/App/Sources/Import/ImportFlowModel.swift:120` defines `distanceUnit(for:)` specifically so each row in a multi-car import uses its destination car's unit. `ImportReviewView.swift:268` passes the single global `model.distanceUnit` instead. The helper is compiler-confirmed unused.

Action: pass `model.distanceUnit(for: row)` to the row and add a UI/model integration test with one kilometre car and one mile car. A unit test of the unused helper alone would be insufficient.

### Tested sign-in routing is detached from the real sign-in flow

The complete `ios/Sources/TankbookCore/Auth/SignInRouter.swift` island (`SignInContext`, `SignInOutcome`, and `SignInRouter`) is referenced only by `SignInRouterTests`. `SignInFlow.swift` independently implements the local-data, restore, and wrong-provider decisions.

Action: make the live flow call a shared decision function, or delete the detached router and move its cases onto tests of `SignInFlow`. Keeping both implementations makes the exhaustive router tests misleading.

### Two other tested decisions are bypassed by production

- `ImportDateFormat` in `ImportModels.swift:360` is referenced only by tests. The app now applies date answers through `ImportBatchMerge.needsDMYRedating` and `reDatingAsDMY()`.
- `ConfirmLockAnimation.shouldAnimate` in `ConfirmPrefill.swift:264` is referenced only by tests. `ManualFillUpSections.swift:268` directly checks `reduceMotion` instead.

Action: choose one implementation for each rule and make both production and tests use it. Delete the duplicate implementation and its detached tests.

### Form discard logic exists but is never consulted

- `TireSetFormState.hasEdits()` at `TireSetFormState.swift:31`
- `ReminderFormState.hasEdits()` at `ReminderFormState.swift:96`

Neither form has a call site or an interactive-dismiss guard. The comments describe discard protection, but the views do not use the decisions.

Action: decide whether edits must be protected. If yes, wire the same discard pattern used by the fill-up and service forms and test an actual dismissal. If no, remove the methods and correct their comments.

### Trends carries a missing action or a false contract

`TrendsNoCarLayout.presentSheet` at `TrendsSections.swift:48` is unused. The adjacent comment claims there is a “Type-it escape a sheet,” but the view only renders “Add your first car.”

Action: resolve the intended user scenario. Add the action if it is required, or remove the closure and update the comment if adding a car is the only valid path.

### Catalog refresh is a known disconnected subsystem

`VehicleCatalogUpdater` and `RemoteVehicleCatalogFetcher` are heavily unit-tested but never instantiated by `ios/App`. `docs/SYNC.md` and `LowPowerModeTests` already acknowledge this. This is dormant production code, not protected runtime behavior.

Action: either wire one app-owned updater from launch/foreground and test the call site, or move the feature behind an explicit deferred boundary. Do not describe catalog refresh as implemented while the root object has no app construction site.

## Declarations with no repository code reference

These 20 declarations have no code reference in production or tests after comments are excluded. (`FeedbackOutbox.flush()` was on this list; RV.127 wired it into the automatic pass, so it is no longer unreferenced.)

### Core behavior and observability

| Declaration | Location | Assessment |
|---|---|---|
| `FiscalQRLogging` | `TankbookCore/Fiscal/FiscalQR.swift:354` | Unused logging facade; delete or emit it from the actual fiscal-QR parse path |
| `ServiceEntryDraft.isLumpSum` | `TankbookCore/Service/ServiceEntryDraft.swift:101` | Redundant derived property; delete |
| `FuelExtractor.discountedTotal(...)` | `TankbookCore/Extraction/FuelExtractorTotalFinder.swift:71` | Orphaned extraction heuristic; delete after confirming its replacement covers the intended corpus cases |
| `DataValidate` | `TankbookCore/Logging/LogEvents.swift:107` | Log event is never emitted or tested; delete or add a real emission site |

### Symmetric repository API with no consumer

| Declaration | Location |
|---|---|
| `restoreChargeSession(id:)` | `TankbookCore/Persistence/Repository.swift:168` |
| `restoreServiceRecord(id:)` | `TankbookCore/Persistence/Repository.swift:194` |
| `restoreExpense(id:)` | `TankbookCore/Persistence/Repository.swift:225` |
| `softDeleteStation(id:at:)` | `TankbookCore/Persistence/Repository.swift:298` |
| `restoreStation(id:)` | `TankbookCore/Persistence/Repository.swift:304` |
| `softDeleteTariff(id:at:)` | `TankbookCore/Persistence/Repository.swift:331` |
| `restoreTariff(id:)` | `TankbookCore/Persistence/Repository.swift:337` |
| `restoreTireSet(id:)` | `TankbookCore/Persistence/Repository.swift:370` |

These methods appear to have been added for CRUD symmetry. They are concrete `TankbookRepository` methods, not protocol requirements, and none has a call site or test. Remove them unless a current restore/delete flow or compatibility boundary needs them. If retained, name the consumer and add a behavior test; symmetry alone is not a reason to ship an API.

### App and debug helpers

| Declaration | Location | Assessment |
|---|---|---|
| `AppInbox.hasItem(for:)` | `App/Inbox/AppInbox.swift:49` | `pendingEntryIDs` is used directly; delete wrapper |
| `RecentlyDeletedView.hasAnythingToDelete` | `App/RecentlyDeleted/RecentlyDeletedView.swift:37` | Body repeats the condition; delete property or use it once |
| `TireSetFormState.trimmedName` | `App/TireSets/TireSetFormState.swift:19` | Draft owns trimming/readiness; delete |
| `TireSetTestSeed.firstTireSetID()` | `App/TireSets/TireSetTestSeed.swift:115` | Dead `#if DEBUG` helper; delete |
| `SignInTestSeed.stubAuthService()` | `App/SignIn/SignInTestSeed.swift:101` | Dead `#if DEBUG` factory; delete |
| `ImportFlowModel.dateFormatAnswered` | `App/Import/ImportFlowModel+Wizard.swift:26` | `canConfirm` reads the answer directly; delete |
| `TargetCar.newName` | `App/Import/ImportService.swift:140` | No consumer; delete |
| `ImportFlowModel.carsGateHasUndecided` | `App/Import/ImportFlowModel+Cars.swift:51` | Readiness computes this condition directly; delete |

## Additional compiler-confirmed production findings

SwiftLint found these 16 unused declarations whose names were not unique enough for the lexical pass to prove independently:

| Area | Unused declarations | Recommended handling |
|---|---|---|
| Inbox | Outer `InboxView.toastCenter` | Delete; the nested card owns the environment value it uses |
| Navigation | `AppTabBar.contentHeight(safeAreaBottom:)` | Delete unused overload; the constant overload is live |
| Car switcher | Private `vitals(_:)` | Delete obsolete wrapper; the live path calls `VehicleVitals.line` |
| Tire sets | `TireSetFormState.hasEdits()` | Resolve missing discard behavior first |
| Vehicle units | `DistanceUnit.labelKey`, `VolumeUnit.labelKey`, `ConsumptionUnit.labelKey` | Delete; UI uses `L10n` helpers. Keep the live `FuelKind.labelKey` |
| Trends | `TrendsNoCarLayout.presentSheet` | Resolve missing-action/comment mismatch |
| Import | Root `showingSendFile`, `distanceUnit(for:)`, and `ImportCarDestination.targetCar` | Delete the stale state/conversion; wire the row-specific unit helper |
| Reminders | `ReminderFormState.hasEdits()` | Resolve missing discard behavior first |
| Localization | `L10n.carCount(_:)`, `L10n.entryCount(_:)` | Delete replaced helpers after localization-catalog cleanup |
| Rate seed | `ExchangeRateSeed.packVersion` | Decide whether pack version is contract validation or stale metadata; do not silently decode-and-ignore it |
| Fuel-price seed | `FuelPriceBandSeed.packVersion` | Same contract decision as the rate seed |

## Dead local bindings and ignored results

The successful app build emitted six distinct Swift warnings:

| Location | Finding | Meaning |
|---|---|---|
| `Home/RV103HomeTestSeed.swift:67` | Unused `stations` array | Pure debris; remove |
| `Import/ImportReviewView.swift:459` | Bound `index` is unused | Preserve the existence check with `contains` if needed, or remove the redundant guard |
| `ConfirmManual/ManualFillUpFormState.swift:252` | Unused `unit` | Reveals the hardcoded-km bug described above |
| `ConfirmManual/ManualFillUpView.swift:547` | Bound `vehicle` is unused | Use `vehicle != nil` as the gate |
| `Settings/AccountDevicesService.swift:65` | Result of `Set.insert` ignored | Use `_ =` if intentional; otherwise inspect whether duplicate revocation should change the response |
| `EditEntry/EditEntryView+Attachment.swift:20` | Bound `fillUp` is unused | Use `fillUp != nil` as the gate or remove it if `fillForm` already proves the entry kind |

Warnings this basic should be zero before enabling warnings-as-errors. They are useful because unused values often reveal an ignored input, as the distance-unit case does.

## Production code referenced only by tests

The source scan produced 67 additional declarations whose identifier appears at the declaration and in tests, but nowhere else in production code. This is a triage set because static text scanning cannot prove protocol dispatch, and some test-only API is intentional.

The most important manually confirmed groups are:

| Group | Runtime status | Decision |
|---|---|---|
| `SignInRouter.swift` | Entire decision island used only by its tests | Wire into `SignInFlow` or delete |
| `VehicleCatalogUpdater` + `RemoteVehicleCatalogFetcher` | No app construction site; explicitly documented as unwired | Wire or mark/remove as deferred |
| `VehicleArchiveReader` | Used as a round-trip test oracle; app exposes export but no archive-import entry point | Keep as an explicit test/future-restore boundary or move reader support out of shipping code |
| `ImportDateFormat` | Tests only; app uses newer batch logic | Consolidate and delete duplicate |
| `ConfirmLockAnimation` | Tests only; view uses direct condition | Consolidate and delete duplicate |
| `DataRecompute` | Constructed only by a logging test | Emit from real recomputation or delete |
| `FiscalQRPayload.fiscalDocumentIdentity` | Tests only; its own comment says duplicate detection is not wired | Wire with duplicate detection or mark as deferred |
| `RestoreHash`, `SyncedEntityCatalog` | Test oracles/invariant catalogues | Move to test support unless production diagnostics needs them |
| `InMemorySink`, `InMemoryFeedbackQueueStore` | Test doubles in the core product target | Move to test support |

The compiler-backed analyzer also reported 23 test-support declarations because the build action did not compile the hosted tests. Those include `AppStore.fileProtectionApplier`, `dropCachedRepositoryForTests`, `ReminderNotificationActionTestSupport`, logging/config inspection helpers, CSV/archive inspection helpers, and UUID bit inspection. They should not be deleted blindly. Their placement should be made explicit:

- Put SwiftPM-only doubles and assertions in `ios/Tests/TankbookCoreTests`.
- Keep app-hosted seams in the app target only when the test bundle cannot reach the underlying package seam; wrap them in `#if DEBUG` and give them a `TestSupport`, `TestSeed`, or `ForTests` name.
- Do not count a test reference as evidence that a user path is wired.

## Improvement plan

### 1. Fix behavior gaps before deleting helpers

1. Use the requested distance unit in manual fill-up warnings.
2. Use row-specific units in multi-car import review.
3. Decide and implement discard behavior for tire-set and reminder forms.
4. Resolve the Trends no-car action/comment mismatch.

These changes should have tests that enter through the production owner or screen, not tests that call a detached helper directly.

### 2. Collapse duplicate decision paths

For sign-in routing, import date handling, and reduce-motion behavior, choose one function as the production decision point. Make the app call it, make tests call it through the production owner where practical, and delete the superseded path in the same change.

### 3. Remove low-risk debris

Delete the six local fragments and the clearly redundant wrappers/state: unused outer environment values, obsolete formatting wrappers, duplicate booleans, dead debug factories, unused unit-label properties, and replaced localization helpers. Run the focused screen/unit tests after each feature-area batch.

### 4. Review dormant public API by feature, not one method at a time

- Repository restore/delete symmetry: remove unused methods or connect them to a current user flow and test it.
- Catalog refresh: wire the subsystem or move it behind a documented deferred boundary.
- Archive reader: decide whether restore is a supported user capability, a test oracle, or future work.
- Logging events: every shipped event type should have a real emission site.
- Seed `packVersion` fields: validate/use them or remove them from the domain envelope while preserving required decoding explicitly.

### 5. Separate test support from shipping behavior

Move pure test doubles and test-only parsers into test targets. Keep the small number of app-hosted seams that genuinely need app sandbox access, and make their `#if DEBUG` boundary visible. This reduces both binary surface and analyzer noise.

### 6. Add a dead-code gate

Use the existing toolchain first:

1. Capture the app build log in CI.
2. Run `swiftlint analyze --only-rule unused_declaration --compiler-log-path <log>`.
3. Clean the 48-result baseline, then fail CI on new findings.
4. Make ordinary compiler unused-value warnings fail the build after the current six are fixed.
5. Optionally add a pinned whole-project analyzer later to detect unused public APIs; no such tool is currently installed in this workspace.

The analyzer must run with the app and relevant test targets represented. Otherwise intentional hosted-test support appears dead, while public detached code remains invisible.

## Rules for an implementation agent

1. A new production declaration must have a production consumer in the same change, unless it is a protocol/serialization requirement or is tied to a named, current deferred task.
2. “A unit test calls it” does not prove runtime wiring. For extracted policy, add at least one test through the production owner that invokes the policy.
3. Do not duplicate a tested decision inline in a view or coordinator. Route the live code through the tested function.
4. When replacing a path, remove the old helper, its stale tests, and comments that describe it in the same change.
5. Do not add CRUD methods for symmetry. Add the smallest API required by a current user, sync, migration, backup, or compatibility flow.
6. Put test doubles and inspection helpers in test targets. If an app-hosted test requires an app-target seam, wrap it in `#if DEBUG` and name it explicitly for tests.
7. Treat a source-scanning test as documentation of wiring, not proof of behavior. Pair it with a runtime test at the owning boundary.
8. Before deleting a candidate, check protocol conformances, SwiftUI entry points, Objective-C selectors, delegates, notification selectors, `Codable`/persistence fields, and dynamically loaded resources.
9. Before finishing any feature change, run the compiler-backed unused-declaration rule and inspect new warnings. Do not add a baseline entry without explaining why the declaration must remain.
10. If a comment says a helper is used by a screen, retry loop, or lifecycle event, verify the call site. Update or remove the comment when the call graph changes.

## Validation performed

- `swift build`: passed.
- Debug app build with `xcodebuild`: passed.
- SwiftLint compiler-backed `unused_declaration`: completed with 48 findings, which were manually classified above.
- Ordinary `swiftlint lint --quiet`: completed successfully with the repository's existing warnings.
- Localization gate: passed with 771 keys, 100% Russian coverage, and zero app-code violations.
- Repository-wide production/test reference scan: completed over 449 production and 251 test Swift files.
- Manual tracing: completed for framework callbacks, the highest-risk detached policies, repository methods, and all six compiler warnings.

This is a static reachability assessment. It does not measure linker-stripped machine code or runtime coverage, and it deliberately avoids claiming dynamically invoked framework declarations are dead.
