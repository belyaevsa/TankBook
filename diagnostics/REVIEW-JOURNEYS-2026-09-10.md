# REVIEW-JOURNEYS run - 2026-09-10 (Group C + Group D)

*Third run of the recurring journeys walk (`agents/briefs/REVIEW-JOURNEYS.md`). Scope narrowed by the
dispatcher to **Group C (`PJ.3xx`)** and **Group D (`PJ.4xx`)**, both passes (reachability AND
sequence), plus the four named items: the end-to-end import trace, F9/F9a after import, J13/F10,
and the `DEFECT-PATTERNS.md` Part 2 five shapes. Read-only: no edits, no builds, no tests, no
commits. A build agent (`RV.181`, the share-handoff fix) is live in this checkout; the working tree
carries its uncommitted files (`ActivityView.swift`, `ExportFlow.swift`, `ImportWizardView.swift`,
`AttachmentViewerView.swift`, `DiagnosticsPreviewView.swift`, `AppLog.swift`, three `RV181*Tests`).*

## Run history

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows (36 since shipped, 30 open) |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`), 0 ticked-but-not-true. One read-only agent, deep on J4 / J7b / money+rates / feedback |
| 2026-09-10 | `ea20655` | **this run** - Group C + D, 2 new rows (`PJ.58`, `PJ.59`), 1 severity amplification (RV.187), 1 ticked-but-sibling-fake (PR.14) |

---

## 1. Ticked rows whose behaviour the code does not have

**One, and it is a sibling, not the tick itself:**

| Row | Claim | What the code actually has |
|---|---|---|
| **PR.14** `[x]` | "Real 'Changed by sync' row from the `syncOverwrite` log … and the post-batch toast" | The **Edit entry** "Changed by sync" row and the batch toast ARE real (`EditEntryRows.swift:62-71`, `HomeBanners.swift:220`). But its sibling surface - the **Recently deleted → "Overwritten by sync" section** - still renders only from the `-forceSyncOverwritten` launch fixture (`RecentlyDeletedView.swift:52-54`, `:161-173`), and its header comment says *"fixture until P4"* (`:21-25`, `:159`) though **P4 shipped**. The real `syncOverwrite` log PR.14 built (migration v7) is never read by this screen. F10 promises "overwritten edits and deleted entries sit in a 30-day local undo log"; the undo-log half of that promise is real on one surface and fake on the other. Tracked only as a parenthetical in `TASKS.md` (PJ section intro, "PR.14 … its deliverable should also name Recently deleted's 'Overwritten by sync' section and Compare, both fixtures") - **not a row**. → `PJ.59` |

The other six owner defects (`RV.185`-`RV.189`, `RV.182`) are open and correctly filed; none is a
ticked-but-untrue. Each is confirmed in code below and **cited, not re-filed**.

---

## 2. The import sequence trace (item 1) - one Drivvo file, source → Log

`Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv` (the owner's own file; 3 sections, 324
lines, one car, no vehicle column, no currency column). Facts and where each stops being carried:

| Fact | Carried through | Breaks at | file:line | Severity / row |
|---|---|---|---|---|
| **Currency** | User picks KZT on the currency question → `effectiveCandidates`/`applyingCurrency` stamps the ENTRIES KZT | The **new car** the import creates is hardcoded `.eur`, so every KZT row is homed against EUR and becomes a rate-pending foreign entry for a car the user just declared KZT | `ImportService.swift:149` (`TargetCar.newCar(named:)` hardcodes `homeCurrency: .eur`) | **bug** · `RV.185` (open, `[!]`) |
| **Car name** | `newCarName` reads `vehicleName` (nil for Drivvo - no vehicle column) → falls to `pickedFormat.displayName` = "Drivvo" | The mapping/preview gate has no editable name field, so the derived name is a fact, not a default input (hard rule 13) | `ImportFlowModel.swift:323-327` (`newCarName`), `:319-321` (`selectNewCar`); no name field in `ImportCarsView.swift` | **bug** · `RV.185` |
| **Currency (2nd site)** | - | Service **line-item** costs are homed `.eur` even though the record total uses `vehicle.homeCurrency` | `ImportConversion.swift:145` (`makeItem` → `Money(…, homeCurrency: .eur)`) | **bug** · **NEW → `PJ.58`** (sibling of RV.185; RV.185's brief names only the `newCar` factory) |
| **Station** | Parser reads the station column → `candidate.station` → `trimmedStation` → `ImportStationResolver` → `fill.stationId` → `materializedStationRecords` writes the rows in the same `commitImport` → Log title prefers the station | **Chain intact**; the owner's "fills show 92, not the station" is not reproduced by this chain. Likely data (a different header/locale in the real file) or ordering (rows committed before RV.142). | `DrivvoParser.cs:260,287` · `ImportConversion.swift:57,66` · `ImportFlowModel+Wizard.swift:355,380-395` · `HomeSections.swift:567-569` | **cause not established** · `RV.189` (open, `[!]`) |
| **Title (expense)** | Expense title = `title ?? note`; the file's title/note columns are empty while the kind column names the thing | The kind column is read **only as a category**, never as a name, so `title` arrives nil and the expense renders "Expense" with no title | `DrivvoParser.cs:319-321` · `ImportConversion.swift:123` · `HomeSections.swift:577` | **gap** · `RV.187` (open) |
| **Title (service)** | Service title = `serviceName ?? title ?? note`; all three empty in the file | **Worse than RV.187 states**: `makeService` requires a non-empty item title (`makeItem` guard), so a service row with empty name/title/note returns nil → the row is classed `.unmappable("missing_required")`, shown "Couldn't read this row", and is **always left out** with no import action. The service history is **dropped at the review gate**, not merely unlabelled. | `ImportConversion.swift:102-103,141-142` · `ImportReviewView.swift:425-426` (no action for `.unmappable`), `:132` (badge) · `ImportFlowModel+Wizard.swift:147-156` (always-skipped) | **bug (data loss)** · `RV.187` severity should be raised; the fix it proposes ("fall back to the kind column") is exactly what closes this |
| **Odometer** | Parser reads odometer (Drivvo's `0.0` = nil, correctly) | `TimelineValidator.invariantHolds` requires strictly increasing odometer across **every** entry sorted by date, and CHECK 1 flags `odo <= previous` for any kind - so a service/expense at the SAME reading as a same-day fill is flagged and its segment excluded | `TimelineValidator.swift:70-73` (`invariantHolds`), `:140` (CHECK 1) | **bug** · `RV.186` (open, `[!]`) |

---

## 3. F9 / F9a after an import (item 2)

What a user can actually do from each surface, and whether the named next step exists:

| Surface | What the user sees | What they can DO | Next step exists? |
|---|---|---|---|
| **F9 footnote** (Home/Trends, rate-pending count) | "N entries pending rates" + "Check for rates" (or the dead-end "No rate exists … add a manual rate" once the demand drain has been tried, RV.111) | Check for rates (demand drain, RV.111) · open an entry → the conversion card's manual-rate field | Yes - `CurrencyConversionCard.swift`, `MoneyBackfillService.demandDrain` (cited in `ERRORS.md` F9 rows). MET |
| **F9 conversion card** (Confirm / Edit entry) | "≈ – · converts when online" + manual-rate entry on the card | Enter a manual rate · save anyway (converts later) | Yes (hard rule 7) - `ERRORS.md` Confirm/Edit rows. MET |
| **F9a inline conflict** (Confirm/Edit) | Amber + conflicting entry quoted; the neighbourhood panel (Edit entry) | Fix odometer · fix date · save anyway (flagged) | Partially - **the ranked suggestions the validator computes are discarded by the UI** (`PJ.34`, open `[v1.1]`: receipt/QR date priority never reaches the sheet). |
| **F9a neighbourhood panel** (Edit entry, RV.117b) | Chart + bracket rows "Previous entry" / "This entry" + one sentence per range side | Read the range, edit the odometer/date | **Broken in substance** - the bracket rows list only previous + this (`TimelineNeighbourhoodCard.swift:43-54`); the chart points carry accessibility labels only, **no visible labels** (`:201-208`, `:227-240`). When the culprit is the NEXT entry (a same-odometer sibling, RV.186) or a third point, the panel shows two consistent rows and declares them impossible, and the thing to check is not on screen. **Reported twice** - `RV.188` (open). |
| **Excluded entries list** (footnote, N>1) | Each excluded row + its reason | Tap → Edit entry | Yes (`ExcludedEntriesView.swift`, RV.141). MET |

No new F9/F9a sibling beyond `RV.188` (the "unlabelled third point" is the same mechanism
`TimelineNeighbourhoodChart` renders every neighbour as an identical ink circle). `RV.186`'s
culprit (the same-odometer service) is undiagnosable from the app precisely because this panel
never names the next neighbour - which is the observation `RV.188` already carries.

---

## 4. J13 and F10 (item 3)

**J13 (selling the car):** export is real but the hand-off is broken, and the dossier is unbuilt.

| Stage | Status | Citation |
|---|---|---|
| Per-car export row ("Export this car's data") | MET | `VehicleExportRow.swift:13-52` (Vehicle detail) |
| CSV per car (fill-ups, charges, service, expenses) | MET | `ExportBuilder.swift:28-37` (`CarCSVExport.write`) · PJ.38 `[x]` |
| JSON (the versioned backup archive) | MET | `ExportBuilder.swift:31-32` (`VehicleArchiveWriter.writeArchive`) · P5.5a `[x]` |
| Whole-account "Export everything" | MET (built; share broken, below) | `ExportBuilder.swift:17-23` · PJ.36 `[x]` |
| **The share hand-off** | **BROKEN - nothing dispatches to the chosen destination**; the fix is in flight in this checkout (`ActivityView.swift` now presents the controller from a host, `:28-39`) | `RV.181` (open, `[!]`) - **cite, never re-file** |
| Archive (history kept, out of active stats) | MET | `VehicleDetailView.swift:417-450` (archive/unarchive + reminder strip, RV.81); `GarageView.swift:212-224` (archived row) |
| Delete car → Recently deleted (group row) | MET | RV.98/RV.99/RV.100/RV.101 `[x]` |
| **PDF dossier** | **MISSING (deferred)** | `PJ.37` `[v1.1]` - the journey's one emotional beat |

J13's promise depends on exactly two unbuilt/blocked things, both already tracked: **RV.181** (the
share, `[!]`, in flight) and **PJ.37** (the PDF dossier, `[v1.1]`). Nothing else in J13 is unbuilt.

**F10 (sync conflicts surface after the fact):** mostly real, two fixture seams.

| Surface | Status | Citation |
|---|---|---|
| S2 duplicate combined card | MET | P1.8 `[x]`; `HomeDuplicateCard.swift` |
| S3 timeline flags (amber badge) | MET | P1.8/PJ.11 `[x]` |
| Batch toast "Synced. N entries need a look" | MET | `HomeBanners.swift:220`, `HomeView.swift:210` (PR.14) |
| "Waiting to sync · N changes" row | MET | `L10n.swift:343`, `SettingsView.swift:255` |
| Recently deleted + Restore | MET | `RecentlyDeletedView.swift` (P1.7, RV.98) |
| "Changed by sync" + "Restore my version" (Edit entry) | MET | `EditEntryRows.swift:30-71` (PR.14) |
| **"Overwritten by sync" section (Recently deleted)** | **FAKE - fixture only** | `RecentlyDeletedView.swift:21-25,52-54,161-173` - **→ `PJ.59`** |
| S5 "came back, stays archived" notice | **PARTIAL - no-op actions behind `-forceArchivedReturned`** | `HomeBanners.swift:37-54` ("Delete again"/"Keep" are `{}`), `HomePresentation.swift:35` - `PJ.40` (open, cite) |
| Duplicate counted once in stats | MET | P1.8 `[x]` |

---

## 5. `DEFECT-PATTERNS.md` Part 2 - the five shapes on C and D (item 4)

| Shape | C/D instance | Row |
|---|---|---|
| Orphan screen | none new (the C/D screens - Import, Trends, Garage, Recently deleted - all have production doors) | - |
| Orphan state | none new: imported stations are created by the commit (`materializedStationRecords`), and the station set is user-creatable since RV.156 | - |
| Broken promise | **RV.188** - the conflict panel's next step is "check it" and the thing to check (the next/third entry) is not on screen; **the "Overwritten by sync" section** - a screen section with no production data source (→ PJ.59) | RV.188; PJ.59 |
| Dead end / no feedback | **the `.unmappable` review row** - a Drivvo service row whose title columns are empty renders "Couldn't read this row" with the raw CSV and **no import action** (the "Import as service/expense" affordance exists only for `.noFuel` rows, `ImportReviewView.swift:418-424` vs `:425-426`), and `isSkipped` forces it out | RV.187 (fix closes it; severity amplified in §2) |
| Captured then discarded | N/A for C/D (that is PJ.28/RV.149, capture-side) | - |

The three shipped guards (`RV.162` screen routes, `RV.163` entity writers, `RV.167` money
aggregation) are **blind to everything in this table**: `RV.162` proves every `SCREENMAP.md`
screen is reachable (it is), not that a section inside one renders real data (the "Overwritten by
sync" section has no route of its own); `RV.163` proves every entity has a writer (a service
record *can* be written - the import just doesn't write it when the title is empty); `RV.167`
proves no `.reduce` zero-sums a pending row (the `makeItem` `.eur` hardcode is an assignment, not
a reduce). Each guard asserts a property of the spec's contents and is blind to what the spec
forgot - which is exactly the check this run is.

---

## 6. Journey-stage walks

### Group C

**J8 · the monthly glance**

| Stage | Status | Citation |
|---|---|---|
| Trends hero consumption metric | MET | `TrendsView.swift` (P1.10) |
| Trend arrow on the hero | **MISSING (deferred)** | `PJ.30` `[v1.1]` - only the price tile has one |
| Monthly spend bars | MET | `TrendsView.swift` (P1.10) |
| Price-per-litre per station brand | **MISSING (deferred)** | `PJ.31` `[v1.1]` (depends on PJ.19) |
| Monthly notification (opt-in) | MET | `MonthlySummaryNotification.swift` (P6.2); partial-pending push bug is `RV.148` (open, cite) |

**J9 · anomaly nudge**

| Stage | Status | Citation |
|---|---|---|
| Amber card in the Log (never push) | MET | `AnomalyInsightCard.swift:28` |
| Evidence sheet (chart + cost) | MET | `AnomalyInsightCard.swift:69-77,135-166` (RV.121 removed the guessed-cause copy) |
| Dismiss-with-reason (teaches the model) | MET | `AnomalyInsightCard.swift:240` (records `AnomalyDismissal`) |
| Dismissal persisted across devices/reinstall | **MISSING (deferred)** | `PJ.32` `[v1.x]` - `AnomalyInsightStore` is UserDefaults-only |
| Act → create service reminder | MET | `AnomalyInsightCard.swift:207` (act button) |

**J10 · cross-border trip**

| Stage | Status | Citation |
|---|---|---|
| Currency auto-detected, two-amount card | MET | `CurrencyConversionCard.swift` (P2.5) |
| Rate snapshot at the entry's date, never today | MET | hard rule 3; RV.88/RV.111/RV.135 `[x]` |
| Manual rate per entry | MET | `CurrencyConversionCard.swift` (ERRORS.md Confirm/Edit) |

**J2 · parse / preview / commit**

| Stage | Status | Citation |
|---|---|---|
| Declare the source (never sniff) | MET | `ImportSourceView.swift`; `GET /v1/import/formats` server-driven |
| Per-source export guide | MET | `helpUrl` + `PJ.33` `[x]` (MFM only; Drivvo guide is P5.4b's fence) |
| Map the cars (multi-car) | MET for MFM; **N/A for Drivvo** (one car per file, no vehicle column) | `ImportFlowModel+Cars.swift`; `DrivvoParser.cs:5-24` |
| Preview figures (count, range, span, currency, spend, consumption via the real engine) | MET | `ImportSummary.compute` `ImportConversion.swift:472-504` |
| S2 duplicate count when merging | MET | `ImportSummary.duplicateCount` `ImportConversion.swift:478` |
| Currency question once per file | MET | `DrivvoParser.cs:146-149` (ambiguity), `ImportFlowModel+Wizard.swift:54-58` |
| **Units question once per file (F6 "MPG or L/100km")** | **PARTIAL/N-A** - the wire `ImportAmbiguity` kind `"units"` exists (`ImportModels.swift:254`) but no parser emits it and no client handles it. Defensible for the two shipping formats (MFM declares units, Drivvo is metric-by-header) but unbuilt as a general promise. | see "could not settle" |
| Cancel deletes the stored parse | MET | `ImportFlowModel+Wizard.swift:273-287` (`cancelImport` → `DELETE`); **delete-on-every-exit** (back-to-source, swipe-down) is `PJ.44` (open, cite) |
| Nothing written until confirm | MET | `ImportFlowModel+Wizard.swift:322-371` (the one `commitImport`) |

**F6 · file won't parse** - partial parse, per-file survival, per-source reason, "send us the file"
with consent: all MET (`ImportSourceView`, `ImportWizardView`, `ImportFlowModel.ParseFailure`);
the offline/server-error/contract-error split is RV.68 `[x]`. N/A: "PDF report, not a data export"
copy names Drivvo's CSV location - the Drivvo importer (RV.113) is live, so the guide link is the
remaining P5.4b fence.

**F6a · nothing written until the user says so** - the preview gate is real (§ J2 preview row
above); **"everything shown is adjustable here"** is **PARTIAL**: currency is answerable (RV.113),
date-format is answerable (PJ.10), but **units and the target car's name are not editable in the
preview** - the units/currency row is a figure, not a picker (`P5.5b` `[~]`), and the name is
derived with no field (`RV.185`).

**F6b · a flagged row is fields, not a line** - MET for the field cases (missing odometer,
cross-check, timeline, `.noFuel` - `ImportReviewView.swift:247-276,199-223`); the raw line is one
tap behind "Original row" (`:329-332`). The **gap is the `.unmappable`/`.unparsed` row**: it shows
the raw line as its only content (`:164-185`) with no "import as what it is" action (`:425-426`),
so a service row the parser read but the client couldn't map is a dead end - see §2 title/service
and RV.187.

**F9 · rate unavailable** - see §3; MET (footnote, demand drain, manual rate, never today's rate).

**F9a · odometer contradicts the timeline** - see §3; MET for the amber + quote + save-anyway
flag + segment exclusion; PARTIAL for the ranked suggestions (PJ.34) and the neighbourhood panel's
missing third entry/labels (RV.188).

### Group D

**J11a · first sign-in (no registration)** - MET: provider token is registration, first push
before the sheet closes (`SignInFirstPush`, PJ.13 `[x]`), wrong-provider notice + reactive
detection (`arrivedViaRestore`, PJ.3/RV.23 `[x]`).

**J11 · new phone / restore** - MET: restore screen with verification stats before finishing
(P4.7 `[x]`), background photo download by recency is **PARTIAL** (`.blobPrefetch` is unwired -
PJ.35 `[v1.1]`, cite).

**J12 · second driver** - **N/A** (`[v2]`, `VISION.md`).

**J13 · selling the car** - see §4.

**F7 · restore fails / empty** - MET for the source order (pull → snapshot → file import) and the
empty-restore recovery entry point (`RestoreFailureViews.swift`, P4.7); the snapshot middle source
is `PJ.46` (decide-or-drop, `[v2]`), cite. **F7's third source ("import a file you exported
yourself")** is reachable only if the share actually dispatches - RV.181 `[!]`.

**F10 · sync conflicts after the fact** - see §4.

---

## 7. Proposed rows (fresh range `PJ.58`+)

### PJ.58 - the import's second hardcoded `.eur`: service line-item costs

**bug** · closes **J2 commit / F6a** (the money pair is homed right on every record the import
writes).

`ImportConverter.makeItem` (`ImportConversion.swift:145`) builds a service line item's cost as
`Money(amount:currency:homeCurrency: .eur)`, while the enclosing `makeService` uses
`vehicle.homeCurrency` (`:101`) and `makeFill`/`makeExpense` do too (`:45`, `:121`). The candidate's
*original* currency flows through `applyingCurrency` (`ImportModels.swift:220-235`), so only the
**home** side is hardcoded. A KZT service row on a KZT car therefore lands with a record total
homed in KZT and item costs homed in EUR - the item breakdown and the total disagree about the
car's money (hard rule 3). It is the exact `RV.185` shape one level down, and `RV.185`'s brief
names only the `newCar` factory, so its fix will not touch this site.

**Deliverable:** `makeItem` takes the vehicle's home currency (it is already called from
`makeService`, which has `vehicle`); the item cost's `homeCurrency` is the car's.

**Check:** L1 - importing a KZT service row into a KZT car produces item costs with
`homeCurrency == .kzt` (rate 1, no conversion); a EUR car is byte-unchanged. **Mutation:** reverting
the parameter to a literal `.eur` fails the KZT assertion.

### PJ.59 - the "Overwritten by sync" section in Recently deleted is a fixture while PR.14 is ticked

**gap** · closes **F10** (the 30-day undo log's overwrite half is real on one surface and fake on
the other).

PR.14 built the real `syncOverwrite` log and wired the Edit-entry "Changed by sync" row and the
batch toast, but the **Recently deleted → "Overwritten by sync" section** still renders only from
`-forceSyncOverwritten` (`RecentlyDeletedView.swift:52-54`, `:161-173`) and its comment says
*"fixture until P4"* (`:21-25`, `:159`) though P4 shipped. No row tracks this - it is only a
parenthetical in the `TASKS.md` PJ-section intro ("PR.14 … its deliverable should also name
Recently deleted's 'Overwritten by sync' section and Compare, both fixtures").

**Deliverable:** wire the section to the same `syncOverwrite` source the Edit-entry row reads (or,
if it is judged redundant with "Restore my version", delete the section and the fixture) - and fix
the stale "until P4" comment either way. Keep the "removed on iPad" attribution as the documented
v2 fixture it is (ERRORS.md:339) - do not conflate the two.

**Check:** L3 `SyncScenarioTests` - an S1/S4 overwrite produces a row in the section on a cold
read with no launch argument; the `-forceSyncOverwritten` seed is removed. **Mutation:** reverting
the section to read only the fixture fails the cold-read assertion.

---

## 8. Could not settle

- **The units question (F6 "MPG or L/100km").** The wire `ImportAmbiguity` reserves the `"units"`
  kind (`ImportModels.swift:254`) but no parser emits it and no client handles it. It is arguably
  correct for the two shipping formats (MFM declares units in-file, Drivvo is metric by its
  headers), so it reads as a deferred-importers concern rather than a live gap - but `P5.5b`'s
  "units/currency row not yet an editable picker" suggests the preview should at least let the user
  correct units, which today it cannot. Would settle on: a product-owner call on whether the two
  shipping formats' units are ever ambiguous enough to need the question.
- **RV.189 (station shows "92").** The chain parser → `stationId` → materialised Station → Log
  title is intact on the fixture (`DrivvoParser.cs:260,287` · `ImportConversion.swift:57,66` ·
  `ImportFlowModel+Wizard.swift:355,380-395` · `HomeSections.swift:567-569`). The cause is not in
  that chain, exactly as the row already concludes. Settling it needs the owner's real file (a
  different Drivvo header/locale) or a same-device re-import on the build that shipped RV.142.
- **Whether `RV.187` should be re-severitised from "title gap" to "data loss".** The service half
  drops rows at the review gate, not merely unlabelled (§2). Its proposed fix is correct and closes
  both; the severity of the *consequence* is the open question for the triage.
