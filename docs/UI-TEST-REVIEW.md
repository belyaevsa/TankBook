# UI Test and Task Review

Reviewed 2026-09-07 against:

- `docs/TASKS.md`
- `docs/JOURNEYS.md`
- `docs/SCREENMAP.md`
- `docs/TESTING.md`
- `ios/App/UITests/`
- the iOS project and CI configuration

This is a semantic review: whether the tests represent realistic user behavior, which important
scenarios are missing, which checks have little product value, and how the task and verification
process can improve. It does not assess the current runtime pass/fail status of the suite.

## Overall assessment

The suite is strong at preserving individual requirements and reviewer fixes, but weak at proving
that a regular user can complete the main journeys. It behaves more like a large regression
specification than a customer journey suite.

The current suite contains:

- 443 UI tests across 58 files and approximately 13,847 lines;
- 38 test files that use `-presentScreen`, with 152 occurrences;
- 417 occurrences of `-seed...` launch arguments;
- at least 27 app-side test seed/support files totaling approximately 4,079 lines.

Direct launch and seeding are useful for deterministic screen-state tests. They become a weakness
when those tests are treated as proof of a complete journey: they bypass production navigation,
state construction, persistence boundaries, and transitions between features, which are precisely
where integration bugs occur.

The documented verification matrix is customer-oriented and sensible
([`TESTING.md`](TESTING.md#per-story-verification-journeys--checks)). Its implementation does not
fully match that intent. Most L4 tests prove leaf states, while the matrix describes complete flows.

## Coverage by user journey

| Journey | Assessment |
|---|---|
| First launch and first entry | **Partial.** Welcome paths and car creation are tested, including persistence across relaunch, but there is no single Welcome -> add car -> first manual/scanned entry -> Log -> relaunch journey. J1 defines success as logging the first entry, rather than merely leaving Welcome. See [`JOURNEYS.md`](JOURNEYS.md#j1--first-launch-empty-garage) and `WelcomeUITests.testWelcomeNeverReappearsOnceACarExists`. |
| Routine manual fill-up | **Good form coverage, partial journey coverage.** Validation, derivation, mismatch, currency, odometer, save, and discard behavior are extensively tested. Repeated normal use across several entries and days, followed by visible Home/Trends changes, is mostly assembled from seeded states. |
| Receipt capture | **Strong.** `CapturePipelineUITests` passes a real fixture through OCR, review, Confirm, and save. It still starts through a direct-screen hook; production navigation is tested separately instead of as part of the same journey. |
| Failed or inaccurate scan | **Strong.** Empty recognition, late cloud results, fuel mismatch, timeline warnings, and manual continuation are covered with meaningful outcomes. |
| Import | **Strong branch coverage, partial outer journey.** Review states, date ambiguity, multi-car mapping, error handling, and commit results are well tested. Welcome/file handoff -> choose source -> parse -> map -> review -> commit -> relaunch is not covered as one journey. Share-to-Tankbook remains an open product task (`PJ.21`). |
| Service and expenses | **Partial.** Normal manual service and expense creation starts from Home and ends with a saved Log row. Invoice capture, attachment retention, line-item correction, parts, tires, and reminder creation are fragmented or explicitly deferred. |
| Reminder lifecycle | **Good state coverage, incomplete loop.** Creation, skip, recurrence, notification routing, and the post-service offer are individually meaningful. There is no complete service -> reminder offer -> notification -> completion -> cost record -> next reminder journey. |
| Multi-car use | **Good, with one important gap.** Switching, car-specific views, reminders, and import mapping are covered. There is no scenario that switches to car B, records an entry, and proves car A remained unchanged. |
| Sign-in and restore | **Strong UX state coverage through stubs.** The UI does not prove a real first push followed by restoration into another client. Core/L3 tests carry most of this risk, while the rendered restore counts are seeded. |
| Offline and server failure | **Strong.** Tests generally assert that local work remains possible rather than merely checking error copy. |
| Visual and accessibility behavior | **Partial.** Many geometry, copy, localization, and hit-target assertions exist. Visual verification is mostly a collection of manually captured PNGs rather than an executable snapshot comparison. |
| Real device and system integration | **Mostly manual.** Actual camera behavior, Photos/file pickers, provider sign-in, notification delivery, VoiceOver navigation, backgrounding, and floor iOS 18 behavior are outside the automated UI suite. This is reasonable only if the release checklist explicitly owns and records them. |

## Meaningful tests

The following patterns provide strong product confidence and should be retained:

- A real receipt fixture flows through OCR into editable Confirm fields in
  `CapturePipelineUITests.testShutterOpensConfirmWithLitresPrefilledAndDimmed`.
- Saving a scanned entry proves that both Confirm and the Capture modal close, rather than merely
  asserting that the Save button exists.
- Late cloud answers are checked against unchanged visible values and the persisted saved entry in
  `GatewayCaptureUITests` and `RV57CapturePrefillUITests`.
- Manual service and expense doors start from Home and assert the saved records in the Log in
  `HomeUITests`.
- Multi-car imports assert that each car receives its own data in `ImportCarsUITests`, rather than
  stopping after the mapping screen appears.
- Reminder completion asserts the old row leaves attention and the next recurring row is scheduled
  in `RemindersUITests`.
- Offline, revoked-session, and server-ahead tests regularly prove that unrelated local actions
  remain usable.
- Tests for destructive choices commonly assert both Cancel and Confirm outcomes and verify the
  durable state afterward.

These tests use a user-visible consequence as their oracle. That is more valuable than checking
that a component rendered.

## Low-value or misleading tests

Some tests have little or no value as product verification.

### Tests that do not prove their stated behavior

- `AttachmentViewerUITests.testThePhotoSurvivesAPinch` explicitly cannot determine whether zoom
  occurred. It proves only that the image remains visible after receiving a gesture. Move zoom to
  the manual checklist or expose a test-readable zoom scale.

### Debug and screenshot harness tests counted as product tests

- `ServiceReminderOfferUITests.testScreenshotHookPresentsTheOfferOverTheSeededLog` verifies a debug
  screenshot hook. The following tests already exercise the real save path.
- `AttachmentViewerUITests.testTheReplaceAskScreenshotSeamPresentsTheAsk` verifies another debug
  presentation hook while the real replace flow has its own tests.
- Similar screenshot-hook checks should live in a small harness-validation suite and should not be
  counted as user-journey coverage.

### Assertions already subsumed by stronger tests

- `TankbookShellUITests.testThreeTabRootsExist` is redundant because later tests interact with each
  tab and assert its destination.
- `SyncChipUITests.testChipIsHittable` is redundant because destination tests tap the same chip and
  verify what opens.
- The seven separate sync-chip label tests launch the entire app to verify a state-to-copy mapping.
  Keep one or two representative UI cases and test the full mapping as a parameterized unit test.

### Checks that are useful but are not user scenarios

Exact frame comparisons, chip widths, Russian phrases, absence of duplicate navigation bars, and
specific visual prominence checks have caught real regressions. They should remain classified as
visual, localization, accessibility, or reviewer-regression checks. They must not be counted as
evidence that a user journey works.

## Reliability and maintenance concerns

### Fixed sleeps

Gateway tests contain fixed waits of 9, 16, and 26 seconds. These add more than 50 seconds to the
suite and depend on machine scheduling. A controllable transport, injected clock, or test-visible
completion state would prove event ordering deterministically.

### Excessive launch configuration

The large vocabulary of independent launch arguments makes it possible to construct states that
production can never reach. It also makes each test responsible for knowing which combination of
seeds, resets, session flags, and presentation hooks is valid.

Replace common combinations with named scenario fixtures. Keep raw flags for low-level harness
development, but expose stable scenarios such as `freshGuest`, `signedInFullHistory`,
`receiptCaptureLateGateway`, and `multiCarImportReview` to tests.

### Visual baselines are not executable

`design/screenshots/` contains many useful review artifacts and `scripts/capture-screenshots.sh`
can reproduce them, but the UI tests contain no snapshot comparison. A stale or accidentally
changed screenshot does not fail a build.

### UI and app tests do not run in CI

The `Tankbook` scheme includes `TankbookTests` and `TankbookUITests` in `project.yml`, but
`.github/workflows/ios.yml` runs `swift test` followed by `xcodebuild ... build`. It never invokes
`xcodebuild test`, so neither app-target unit tests nor UI tests gate pull requests.

This conflicts with the completion rule in `TASKS.md`, which says a task is done when its checks
pass, and with the CI gate described in `TESTING.md`.

### Documentation mixes current state and history

`TASKS.md` contains useful reasoning, but it combines:

- current backlog;
- product requirements;
- implementation plans;
- investigation transcripts;
- commit and agent history;
- old and new test counts;
- verification results and postmortems.

Some completed rows still contain historical phrases such as "NOT ticked" or old suite counts.
This makes the leading status marker harder to trust and obscures the current acceptance criteria.

The foundation tasks in P0 are not user scenarios, and they should not be. Persistence, security,
API, canonicalization, and algorithm work is best proven through unit and contract tests. The gap is
a small vertical acceptance layer spanning those implementation phases.

## Missing regular-user scenarios

The most important missing automated scenarios are:

1. **First success:** fresh install -> add an ordinary car -> enter the first fill-up -> see it in
   the Log -> relaunch and find it still present.
2. **Everyday captured fill-up:** use the production Home/Capture entry point -> review a receipt ->
   correct one suggested field -> save -> see Home and Trends update -> reopen the receipt.
3. **Graceful scan failure:** capture an unreadable receipt -> retain the image -> finish manually ->
   save -> reopen the retained image later.
4. **Complete migration:** enter Import from Welcome/Settings -> pick a real fixture -> resolve date
   and car questions -> commit -> verify Garage, Log, Trends, and persistence after relaunch.
5. **Car isolation:** select car B -> add a record -> verify it appears only on B and does not change
   A's totals or Log.
6. **Closed maintenance loop:** save an oil service -> accept its reminder -> route from a fired
   reminder -> log the completion cost -> verify the next reminder is anchored at completion.
7. **First sync and restore:** begin with local history -> sign in -> complete first push -> restore
   through a second simulated client -> compare visible counts and representative records.
8. **Offline to online:** create/edit/delete while offline -> reconnect -> sync -> verify no duplicate,
   lost edit, modal interruption, or silent overwrite.
9. **Sell/recover a car:** export a car -> archive or delete it -> restore it -> verify its entries and
   totals return together.
10. **Interrupted foreground use:** decide and test what happens when the app backgrounds or is killed
    during entry, capture review, import parsing, and restore.

Several experience gaps are already recorded as product tasks rather than test omissions. These
include capture readiness (`PJ.16`), Share-to-Tankbook (`PJ.21`), service/reminder connections
(`PJ.22`-`PJ.29`), interrupted restore (`PJ.39`), and the widget/Shortcut entry point (`PJ.53`). Tests
should follow the product decision rather than pretending those journeys exist today.

## Improvement plan

### 1. Create a journey coverage matrix

Give every v1 journey and failure journey one owning acceptance test. Record:

- journey and user goal;
- production entry point;
- external boundaries that may be faked;
- durable user-visible outcome;
- lower-level supporting tests;
- manual checks and target device;
- current coverage status.

The matrix belongs in `TESTING.md` or should replace its current per-story table. It should link to
actual test names so documentation drift is detectable.

### 2. Classify the existing UI tests

Use four explicit groups:

1. **Critical journeys** -- production navigation and a durable outcome.
2. **Screen/state contracts** -- isolated seeded states and edge cases.
3. **Reviewer regressions** -- a precise oracle for a previously observed defect.
4. **Harness checks** -- screenshot hooks, seed construction, and test infrastructure.

Tests in the critical-journey group must not use `-presentScreen`. They may fake external boundaries
such as camera frames, authentication providers, files, clocks, and network responses.

### 3. Add the missing vertical scenarios

Implement the first eight scenarios from "Missing regular-user scenarios" in priority order. Each
should assert a durable result after navigating away or relaunching, rather than ending when a form
or label appears.

### 4. Move cheap assertions down the test pyramid

Move these into parameterized unit or view-model tests where possible:

- state-to-copy mappings;
- formatting and pluralization;
- visibility decisions;
- button emphasis decisions;
- static capability matrices;
- pure navigation-route mapping.

Retain UI coverage where hit testing, keyboard behavior, SwiftUI composition, production navigation,
system sheets, or accessibility hierarchy is the actual risk.

### 5. Remove or relocate redundant tests

Begin with:

- the pinch-survival test;
- screenshot-hook tests duplicated by real flows;
- standalone existence/hittability checks followed elsewhere by successful interaction;
- repeated full-app launches for static label mapping.

Do not set a target test-count reduction. Remove a test only when a stronger oracle already owns its
risk or when it cannot prove its stated claim.

### 6. Make asynchronous tests deterministic

Replace fixed sleeps with:

- injected clocks;
- test-controlled transports that can be released at a named step;
- accessibility-visible phases where the phase is itself user-facing;
- bounded predicate expectations for observable outcomes.

The late-answer scenarios should control "before budget", "after budget", and "after save" as events,
not as 8-, 15-, and 25-second delays.

### 7. Automate visual verification

Add a screenshot manifest keyed by:

- runtime;
- device size;
- locale;
- light/dark appearance;
- Dynamic Type size;
- scenario fixture.

CI should capture and compare screenshots with a documented tolerance and retain baseline, actual,
and diff images on failure. Exact XCUITest geometry checks can then be limited to interaction
requirements such as minimum target size, ordering, and overlap.

### 8. Run the appropriate suites in CI

Recommended tiers:

- **Every pull request:** SwiftPM tests, app-target unit tests, and a sharded critical-journey smoke
  suite.
- **Nightly and after large merges:** all state and reviewer-regression UI suites.
- **Before release/TestFlight:** the complete UI suite, automated visual matrix, and named manual
  device checklist.

Run `scripts/check-ui-test-count.sh` after every UI invocation so a zero-match filter or under-run
cannot report success. Upload `.xcresult`, screenshots, and diffs on failure.

### 9. Simplify task definitions

Keep an active task row limited to:

- user trigger or technical risk;
- intended outcome;
- scope and explicit exclusions;
- acceptance checks by level;
- version and dependencies.

Move investigation history, old measurements, agent dispatch details, and completed verification
transcripts into an archive or decision record. Feature tasks should include one vertical acceptance
check. Foundation tasks should name the downstream invariant they protect instead of inventing an
artificial UI scenario.

## Completion criteria for this improvement

The test strategy is improved when:

- every v1 J/F journey has a named owner test or a named manual owner;
- no critical journey is considered covered solely by separate leaf-screen tests;
- critical journey tests enter through production navigation;
- critical saves are verified after relaunch or from another consuming screen;
- fixed sleeps are gone from UI tests;
- app-target and UI smoke tests run in CI;
- every UI run passes the under-run count gate;
- screenshot differences produce reviewable CI artifacts;
- harness tests are reported separately from product tests;
- `TASKS.md` exposes current work without requiring readers to reconstruct it from historical prose.

The goal is to preserve the suite's strongest property -- careful regression oracles -- while adding
the missing proof that Tankbook works as a sequence of ordinary user decisions.
