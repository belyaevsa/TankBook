# REVIEW-JOURNEYS run - 2026-09-12 (Group C + Group D)

*Fourth run of the recurring journeys walk (`agents/briefs/REVIEW-JOURNEYS.md`). Scope narrowed by the
dispatcher to **Group C (`PJ.3xx`)** and **Group D (`PJ.4xx`)**, both passes (reachability AND
sequence). Read-only: no edits, no builds, no tests, no commits. A build agent (`RV.226`) and the
parallel A/B review are live in this checkout; the working tree carries their uncommitted files
(`docs/ERRORS.md`, `CaptureCamera.swift`, `CapturePermissionCards.swift`, `CaptureView.swift`,
`CaptureSurface.swift`, `Localizable.xcstrings`, `CaptureRecoveryUITests.swift`, `CaptureSurfaceTests.swift`,
`scripts/capture-screenshots.sh`).*

## Run history

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows (36 since shipped, 30 open) |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`), 0 ticked-but-not-true |
| 2026-09-09b | `1ec2b1d` | 2 rows (`PJ.56`, `PJ.57`), Group A + B |
| 2026-09-10 | `ea20655` | 2 rows (`PJ.58`, `PJ.59`), 1 severity amplification (RV.187), 1 ticked-but-sibling-fake (PR.14) |
| 2026-09-12 | `42ac5a9e` | **this run** - Group C + D. **0 new rows.** The two rows the previous run gated on (PJ.58, PJ.59) and every shipped row since (RV.185-190, RV.220, RV.221, RV.239, RV.255, RV.259, RV.260, RV.261) are verified real in the tree. |

---

## 1. Re-check of what the previous run gated on

Both rows the 2026-09-10 run proposed are now shipped and the fixes are real:

| Row | 2026-09-10 claim | Verified today |
|---|---|---|
| **PJ.58** `[x]` | second hardcoded `.eur` on service line items (`ImportConversion.makeItem`) | **Real.** `makeItem` now takes a `homeCurrency` parameter (`ImportConversion.swift:140-141`) and `makeService` passes `vehicle.homeCurrency` (`:102`); `makeFill`/`makeExpense` use it too (`:45`, `:121`). No `.eur` hardcode remains in the import conversion. |
| **PJ.59** `[x]` | Recently deleted's "Overwritten by sync" section a `-forceSyncOverwritten` fixture while PR.14 is ticked | **Real.** `RecentlyDeletedSyncOverwrites.swift` reads the real device-local `syncOverwrite` undo log (`:5-6`, S1/S4); `RecentlyDeletedView.swift:21-22,161` renders it; the `-forceSyncOverwritten` seed now writes a REAL log row (`RecentlyDeletedTestSeed.swift:18-19,198-218`) rather than a fake section. |

The six owner defects the previous run confirmed as open (`RV.185`-`RV.189`, `RV.182`) are all shipped
and each `[x]` row's behaviour is present in code (verified in `TASKS-DONE.md` 527-531: `RV.188` chart
labels, `RV.186` annotation-vs-travel invariant, `RV.187` kind-column title fallback, `RV.190` derived
"Not yet" chips, `RV.185` editable name + declared currency). **None is ticked-but-untrue.**

---

## 2. Ticked rows whose behaviour the code does not have

**None.** Every `[x]` row in Group C/D scope that shipped since 2026-09-10 checks out against the
tree. The specific sequence-shaped ones the today-scenario reviews had found (`RV.255` import-selects-car,
`RV.259` wrong-provider loop, `RV.260` restore-from-backup door) are each real:

- `RV.260`: `RestoreFailureViews.swift:76-81,207-212` both failure screens now lead with `Route.restoreFromBackup` (the local `VehicleArchiveReader` door) and keep `Route.importWizard` beside it - the two are separate rows, never one.
- `RV.261`: `RestoringView.swift:115-129` renders "Last odometer N km · N days ago" via `recencySuffix`; the source device is marked `[v2]` in the comment (`:126-127`).
- `RV.255`: `ImportFlowModel.createdVehicle` + `ImportWizardView.confirm` selection write (per its TASKS-DONE row).

---

## 3. Journey-stage walks

### Group C (PJ.3xx) - Periodic, currency, import

**J8 · the monthly glance** (`Status: implemented 2026-09-11`)

| Stage | Status | Citation |
|---|---|---|
| Trends hero consumption metric | MET | `TrendsView.swift:136-145`, value from `stats.home.headline` |
| Trend arrow on the hero | **MISSING (deferred)** | cited `PJ.30` `[v1.1]` - `StatTile.swift:34,44-48` uses `trend:` for VoiceOver only, no visual arrow |
| Monthly spend bars | MET | `TrendsView.swift:184-194` (`bars: true`), series from `TrendsStats.spendSeries` (`TrendsStats.swift:157-180`) |
| Price-per-litre per station brand | **MISSING (deferred)** | cited `PJ.31` `[v1.1]` - only a single price tile with a sparkline (`TrendsView.swift:164-171`), no brand dimension |
| Monthly notification (opt-in) | MET | `TrendsView.swift:253-272` toggle (default off) -> `ReminderNotificationCoordinator.swift:495-512`; scheduler `MonthlySummaryNotification.swift:118-147` |

**J9 · anomaly nudge** (no status line - unreviewed)

| Stage | Status | Citation |
|---|---|---|
| Amber card in the Log, never push | MET | `AnomalyInsightCard.swift:56-60` (warn styling), `HomeView.swift:264-272`; no notification type (`HomeView.swift:317-318`) |
| Evidence sheet: chart + monthly cost, never a guessed cause | MET | `AnomalyInsightCard.swift:94-98,151-167` (rolling-vs-baseline chart), `:134-143` monthly cost from `AnomalyInsight.monthlyCostDelta` (`AnomalyInsight.swift:68-87`); no cause line (RV.121) |
| Dismiss teaches the model | **PARTIAL (tracked)** | reason collected + persisted (`AnomalyInsightCard.swift:288-377,375`, `AnomalyInsightStore.swift:34-40`) and the suppression half works (`AnomalyEngine.swift:238` checks `$0.cause`) - but the stored `reason` is **read by nothing**: cited `RV.240` `[ ]` |
| Dismissal persisted across devices/reinstall | **MISSING (deferred)** | cited `PJ.32` `[v1.x]` - `AnomalyInsightStore.swift:25,38` is UserDefaults-only, keyed `anomalyInsight.dismissals.<vehicleID>` |
| Act -> create service reminder | MET | `AnomalyInsightCard.swift:197-207` -> `HomeView.swift:319-335` (`ReminderLifecycle.makeReminder` on the anomaly's own `vehicle.id`) |

**J10 · cross-border trip** (`Status: implemented 2026-09-12`)

| Stage | Status | Citation |
|---|---|---|
| Currency auto-detected from the receipt | MET | `CurrencyDetection.swift:36-64`, called `FuelExtractor.swift:26` -> `ManualFillUpView.swift:400` |
| Two-amount card (original + home with ≈) | MET | `CurrencyConversionCard.swift:84-103` ("≈ 67.79 €"), original stays in the totals field (`ManualFillUpView.swift:282`) |
| Rate snapshot at the entry's date, never today | MET | `RateStore.swift:115-151` (exact entry-day only, "never a nearby-day or today substitution" `:111-112`); `Money.converted` copies `snapshot.rateDate` (`Money.swift:128-138`) |
| Manual rate per entry | MET | `CurrencyConversionCard.swift:190-209`, `ManualFillUpFormState.swift:107-109` |
| Original preserved | MET | `Money.swift:92-122` (original pair distinct from home pair) |

**J2 · parse / preview / commit** (`Status: implemented 2026-09-12`) - the import trace the previous run
walked end to end is now closed: `RV.185` (name + currency), `RV.187` (kind column as name), `RV.189`
(`remappingSourceRow` station drop), `RV.190` (derived "Not yet" chips) and `PJ.58` (item currency) all
shipped. Verified today:

| Stage | Status | Citation |
|---|---|---|
| Declare the source, never sniff | MET | `ImportSourceView.swift`; `ImportFormats.cs` server-driven; both shipping formats carry the same `helpUrl` (`ImportFormats.cs:38,56`) |
| Preview figures incl. derived consumption via the real engine | MET | `ImportSummary.compute` (`ImportConversion.swift:497-524`) calls `ImportConsumption.compute` on the merged history - the same engine the post-commit path uses (file comment `:6-14`) |
| S2 duplicate count in the preview | MET | `ImportSummary.duplicateCount` (`ImportConversion.swift:466,524`) |
| Currency question once per file | MET | `DrivvoParser.cs`; `ImportFlowModel+Wizard.swift` |
| Cancel deletes the stored parse | MET | `ImportFlowModel+Wizard.swift` (`DELETE`); delete-on-every-exit is cited `PJ.44` `[v1.1]` |
| Nothing written until confirm | MET | the one `commitImport` (`ImportFlowModel+Wizard.swift`) |

**F6 / F6a / F6b** - the flagged-row, preview and failure paths:

| Item | Status | Citation |
|---|---|---|
| F6 "send us the file" with consent, reachable | MET | `ImportSourceView.swift` (RV.191 pinned the card); `POST /feedback` `PJ.20`/`PJ.20a` |
| F6 units question "MPG or L/100km" once per file | **PARTIAL (tracked)** | cited `RV.228` `[ ]` - `ImportAmbiguity` reserves `"units"` (`ImportModels.swift:254`) but no parser emits it and no client handles it |
| F6b flagged row is fields, only the broken field marked | MET | `ImportReviewView.swift` field grid; `RV.221` added the station cell; `RV.220` fixed the keep/skip toggle |
| F6b non-fill row offered as service/expense | MET | `.noFuel` -> `keep(sourceRow:)` (`ImportReviewView.swift:418-424`); `ImportConversion.swift:328-336` |
| F6a "everything shown is adjustable here" | **PARTIAL (tracked)** | currency + date-format answerable (RV.113/PJ.10); units cited `RV.228`; target-car name editable since RV.185 |
| F9a ranked suggestions, receipt-date priority | MET | `TimelineValidator.suggestions` (`:368-393`), receipt-date preselects `.fixOdometer` (`:380-386`), date-override confirm alert `F9aFixRow.swift:36-41,66-75` |
| F9a save-anyway badge + segment exclusion + Trends footnote | MET | `HomeSections.swift:471-501`, `EntryExclusion.swift:46-64`, `ExcludedEntriesFootnote.swift:22-65` |
| F9 rate-pending footnote + manual rate + never today's rate | MET | `PendingRatesFootnote.swift:37-116`, `CurrencyConversionCard.swift:190-209`, `RateStore.snapshot` exact-day guard |

### Group D (PJ.4xx) - Account, sync, exit

**J11a · first sign-in** (`Status: implemented 2026-09-12`) - MET: provider token is registration, wrong-provider
notice + reactive detection (`SignInFlow`), first push on the two completion paths only (`SignInFirstPush`, PJ.13).
`RV.259` (wrong-provider loop -> `.emptyRestore` on a second empty account) is real in the tree.

**J11 · new phone / restore** (`Status: implemented 2026-09-12`) - MET: restore screen with verification stats
before finishing (`RestoringView.swift:93-129`, the `lastOdometerDaysAgo` recency is v1, source device `[v2]`).
Background photo download by recency is **PARTIAL** (`.blobPrefetch`/`LazyBlobFetcher` still unwired; `RestoreProgress`
only seeded via `-seedRestoreProgress`, `SignInFlow.swift:174`) - cited `PJ.35` `[v1.1]`.

**J12 · second driver** - **N/A** (`[v2]`, `VISION.md`).

**J13 · selling the car** (no status line - unreviewed)

| Stage | Status | Citation |
|---|---|---|
| Per-car export row | MET | `VehicleDetailView.swift:165-167` -> `VehicleExportRow.swift:20-52` |
| CSV per car (fills, charges, service, expenses) | MET | `CarCSVExport.swift:18-21,38-65`, wired `ExportBuilder.swift:33` |
| JSON (versioned backup archive) | MET | `VehicleArchiveWriter.swift:33-44,193-217` |
| Whole-account "Export everything" | MET | `SettingsView.swift:353-393`, `ExportBuilder.swift:17-23` |
| Archive/unarchive, history out of stats | MET | `Repository+VehicleArchive.swift:14-35`, `VehicleDetailSections.swift:39-48,146-166` |
| **PDF dossier** | **MISSING (deferred)** | cited `PJ.37` `[v1.1]` - no dossier generator; `ExportBuilder.swift:28-37` returns CSV + archive only |
| Share hand-off | **PARTIAL (tracked)** | the RV.181 fix is in the tree (`ActivityView.swift:28-79` presents from the top-most controller), row is `[~]` awaiting one physical-device confirmation - cited, not re-filed |

**F7 · restore fails / empty** (`Status: implemented 2026-09-12`) - MET: source order pull -> snapshot -> file
import, with the third source now a REAL local Tankbook-backup door (`RestoreFailureViews.swift:76-81,207-212`).
The snapshot middle source is cited `PJ.46` `[v2]` (decide-or-drop).

**F10 · sync conflicts after the fact** (`Status: implemented 2026-09-12`) - MET: S2 duplicate card (`HomeDuplicateCard`),
S3 timeline flags, the batch toast (`HomeView.swift:220`, `HomeBanners.swift:220`, PR.14), "Waiting to sync · N
changes" (`SettingsView.swift:252-256`, `L10n.swift:339`), Recently deleted + restore (PJ.59's section now real),
duplicate counted once (P1.8). The S5 "came back, stays archived" notice stays a no-op fixture - cited `PJ.40` `[v1.1]`.

---

## 4. Findings against REVIEWED scenarios

None. The scenarios carrying `Status: implemented` in scope (J8, J10, J2, J11a, J11, F6b, F7, F9, F9a, F10) were
re-walked stage by stage and hold; the three gaps the today-scenario reviews already filed (`RV.255`, `RV.259`,
`RV.260`) are cited above, not re-filed. No reviewed story has a gap this walk found that its rows did not.

---

## 5. Proposed rows

**None.** This run is a "0 new rows" outcome: every PARTIAL/MISSING stage in Group C/D maps to an existing row
(`PJ.30`, `PJ.31`, `PJ.32`, `PJ.35`, `PJ.37`, `PJ.40`, `PJ.44`, `PJ.46`, `RV.227`, `RV.228`, `RV.229`, `RV.240`,
`RV.256`, `RV.257`, `RV.181`, `RV.148`), and every shipped `[x]` row checked out.

---

## 6. Observations (not filed)

- **J9 evidence chart** (`AnomalyInsightCard.swift:151-167`) renders a two-bar rolling-vs-baseline comparison
  rather than a drift-over-time series. The journey says "a chart of the drift"; the two-bar form does visualise
  the drift and is a defensible reading. Noted for the J9 scenario review to rule on, not filed.
- **J13 copy drift**: the journey text says "Export history" while the row label is "Export this car's data"
  (`VehicleExportRow.swift:26`). Same affordance, wording only.
- **F9a "keep as is"** is not a literal third chip: `ResolutionSuggestion` (`TimelineValidator.swift:46-56`) has
  only `fixOdometer`/`fixDate`/`checkVolume`/`checkOdometer`. By design - the journey parenthesises "keep as is"
  as save-never-blocked + Accept-with-reason (RV.231), which is what ships.
- **Residual `.unmappable`/`.unparsed` dead end**: `ImportReviewView.swift:425-426` renders `EmptyView()` for the
  deciding action of a genuinely unmappable row, so the only action is "Leave out" (`:379`). Reachability is now
  narrow (RV.187's kind-column fallback made empty-title Drivvo services importable), and F6 explicitly allows
  "skip" for rows the parser cannot map - the meaningful data-loss case is the one RV.187 already closed. Not re-filed.
- **`scenario-index.py --check` passes** (399 rows, every open one attached to a scenario; exit 0).

---

## 7. Could not settle

- Whether the J9 "act" reminder being created due **today** (`HomeView.swift:327`, `dueDate: Date()`, no interval)
  is the intended behaviour or should carry a future anchor. A product-owner call at the J9 scenario review, not a bug.
- Whether the J9 evidence chart must be a time series to satisfy "a chart of the drift" - same call, same venue.
