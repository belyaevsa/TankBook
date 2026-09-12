# REVIEW-SCENARIO F2 – 2026-09-12 (re-walk: the flagged/excluded lists)

## Verdict

**IMPLEMENTED** – every stage, fallback and "→" note in F2's text is MET or reasoned
N/A. The re-walk of capture → confirm → save → edit → the flagged/excluded lists finds
two **polish** gaps (neither a broken promise), both proposed as rows below. RV.243
(fuel-kind boilerplate, open, F2-attached) and the misread-total post-save surface are
cited, not re-filed, and neither blocks the story F2's text tells.

## Ticked rows found to be untrue

None. RV.218 (CHECK 5 on save), RV.229 (import-path consumption label) and the ticked
RV.243 (deferred-expense photo) each do what their rows claim; verified in code below.

## Promise-to-code map

| F2 text | Verdict | Evidence |
|---|---|---|
| Detection: "the cross-check line refuses to lock: liters × price ≠ total" | MET | `.mismatch` branch draws the warn rule and no lock (`ManualFillUpSections.swift:278-289`); verdict from `TimelineValidator.crossCheck` (`:155-162`) via `ManualFillUpMath.crossChecked` (`ManualFillUpMath.swift:118-126`). |
| Surfacing: "mismatched field gets a warn amber underline + 'these don't multiply up – check the amber field'" | MET | Copy at `ManualFillUpSections.swift:283-286`; `isSuspect` maps `.mismatch` to a field and feeds `fieldUnderline(warn:)` (`:366-374`, applied `:231`). |
| "Never auto-fix by recomputing one field silently; the app doesn't know which one is wrong" | MET | `ManualFillUpMath.derive` derives a third value only when exactly two are typed; with all three it returns `crossChecked` and writes nothing back (`ManualFillUpMath.swift:64-70, 96-126`). The suspect is always `.total` (`TimelineValidator.swift:161`) – the field the trigger case most often gets wrong – which is the honest consequence the text accepts. |
| Recovery: "user taps the amber field, sees a crop … corrects it" | MET (affordance deviation) | Magnifier beside any cropped field opens `VerifyCropSheet` (`ManualFillUpSections.swift:256-268` → `ManualFillUpView.swift:190,230-232`); crop is real, per-field (`ExtractionAssembler`). Tap target is the magnifier, not the field itself, and it appears for any cropped field, not only the amber one – the deviation the 09-11 walk already recorded. |
| Residue: "odometer delta … flags the absurd" | MET | Live `OdometerDelta.evaluate` caption, warn on backwards/pace (`ManualFillUpSections.swift:430-436, 444-451`); enforced on save by CHECK 1/2 (`TimelineValidator.swift:251-301`). |
| Residue: "consumption outlier check on save" | MET | CHECK 5 derives the closing segment's `per100` from the SAME `ConsumptionEngine.segments` Trends uses, appends a `.consumption` flag when outside the powertrain band (`TimelineValidator.swift:200-211, 304-314`; `ConsumptionOutlier.swift:30-48`); money never read (`ConsumptionOutlier.swift:24-25`). |
| Metric: "corrected-field rate tracked per OCR version" | PARTIAL | `capture.pipeline` logs `userCorrected` as a per-ENTRY bool + per-field confidence + `crossCheck` (`CaptureCommitLog.swift:23-25`, `LogEvents.swift:532-545`), but carries no OCR/model version and no per-FIELD corrected flag. See proposed row F2.2. |

## Sequence trace (one user, one scan)

**Misread litre digit (42.30 → 12.30; price and total correct).**

1. Capture → `ConfirmPrefill` pre-fills total/liters/price (`ManualFillUpView.apply` `:369-412`).
2. Confirm: cross-check derives `.mismatch(field: .total)` → amber underline on Total, "these
   don't multiply up – check the amber field", lock withheld (`ManualFillUpSections.swift:278-289`).
   The amber lands on Total even though litres is the wrong field – the accepted "app doesn't
   know which one" consequence.
3. Save: `buildFillUp` persists `crossCheck = .mismatch` (`ManualFillUpView.swift:660`) but the
   entry is **not** a `conflict`, so nothing downstream flags it.
4. Edit: `buildUpdatedFill` re-derives `crossCheck` (`EditEntryFormState.swift:76`), amber re-surfaces.
5. Flagged/excluded lists: **absent** – `isConflicted = entry.conflict != .none`
   (`LogStream.swift:593`), and `crossCheck` is a separate field, so a misread total that the user
   ignores is silent once the sheet closes. Noted 2026-09-11 as non-blocking (F2's text promises
   no passive post-save badge); re-confirmed here.

**Misread odometer.**

1. Confirm: live delta caption warns, and `odometerConflict` raises the F9a order/pace row with
   ranked fixes (`ManualFillUpFormState.swift:355-394`, `F9aFixRow.swift:62-75`).
2. Save: `buildFillUp` stamps `conflict` from `TimelineValidator` (`ManualFillUpView.swift:661-663`).
3. Log badge: `isConflicted` chevron (`HomeSections.swift:471-481`).
4. Flagged list: `FlaggedEntriesView` iterates `entry.conflict != .none` (`:293-294`) → "car · date"
   row, no reason. Excluded list: `.timelineConflict` reason "check the odometer or date"
   (`EntryExclusion.swift:57-58`, `ExcludedEntriesView.swift:252-253`).
5. Edit: same F9a warn re-derived (`EditEntryView.swift:213-219, 577-579`).

**Misread litres + odometer consistently (all three numbers shifted together).**

1. Confirm: cross-check passes **falsely** (`.verified` locks) – the case F2 names.
2. Save: CHECK 5 fires `.consumption` (`TimelineValidator.swift:308-314`), entry saves with the
   flag, never blocked (`isSaveable` `:93`).
3. Confirm warn names it: "This fill implies … – check the litres or the odometer" with
   `Check litres` (preselected) / `Check odometer` chips (`F9aFixRow.swift:76-87`); the chips focus
   the litres/odometer fields (`ManualFillUpSections.swift:400-401`).
4. Excluded list: `.consumptionOutlier` reason "Unusual consumption – check the litres or odometer"
   + fuelpump icon (`EntryExclusion.swift:58`, `ExcludedEntriesView.swift:152-157, 254-255`).
5. Flagged list ("Needs a look"): the entry appears, but the row renders it **identically to a
   timeline conflict** – warning triangle, "car · date", no reason, no field name. The field is only
   named once the row is tapped into Edit. See proposed row F2.1.
6. Edit: consumption warn re-derived through the same `odometerConflict` (`ManualFillUpFormState.swift:385-392`).

The fact that stopped being carried in the first walk (the consumption the entry implies) is
computed and flagged at save (RV.218) and reaches both downstream lists; the only residual is the
flagged list not SAYING what kind of flag it is (F2.1).

## Proposed rows

| Row | Deliverable | Closes | Consequence today | Severity | Check | Scenario |
|---|---|---|---|---|---|---|
| F2.1 | The account-wide "Needs a look" list (`FlaggedEntriesView`) renders a CHECK 5 consumption flag with the same reason the excluded list gives – an "Unusual consumption" caption (and the litres/odometer next step), not the generic triangle + "car · date" it shares with a timeline conflict. RV.229's sibling one surface over: RV.229 named the field on the IMPORT review list; the scan path's account-wide list still does not. | F2 "The residue" – a misread surfaced on every list that carries it | A sync "N need a look" chip routes to a list where a consumption outlier and a timeline conflict are indistinguishable until the row is opened; the excluded list already names both, so the two conflict lists disagree. | **polish** | L4 `FlaggedEntriesUITests`: a seeded consumption-flagged entry renders its own reason caption (identifier distinct from the timeline row's); mutation: reason dropped → red. EN+RU. | F2 |
| F2.2 | `capture.pipeline` gains the fields that make F2's metric literally true: a per-field corrected signal (not only the entry-level `userCorrected` bool) and the OCR/model version that produced the read, so "corrected-field rate per OCR version" is answerable from a diagnostics export. Same shape as RV.225 (F3) and RV.233 (F1). | F2 "Metric" | The corrected rate is countable per entry but not per field, and "per OCR version" has no key today; a parser regression cannot be trended per version as the metric promises. | **polish** | L1: the event carries a field-level corrected list and a version identifier (shape only, never a value – hard rule 12); mutation: drop the version → red. | F2 |

## Cited, not re-filed

- **RV.243** (open, unticked – fuel kind committed from till boilerplate; `docs/TASKS.md`, F2/J3).
  A wrong fuel kind is "scan recognized wrong data" and is surfaced as an editable default with the
  mismatch notice (`FuelKindMismatchNotice.swift:20-83`), so the rule-13/rule-4 spine holds for the
  field; the defect is that the suggestion is confidently wrong from boilerplate, which F2's stage
  table (litres/price/total/odometer) does not cover. The row is filed and owns the fix; it keeps F2
  open in `scenario-index.py` but does not break a promise in F2's text.
- **Misread total → no post-save surface** (`crossCheck != conflict`): noted 2026-09-11, re-confirmed.
  Not a F2 promise; kept here as the reason a silently-ignored wrong total is silent after the sheet.

## Could not settle

- Whether the flagged-list omission (F2.1) is "by design" under the Routes comment
  ("`flaggedEntries` stays account-wide and conflicts-only"; the excluded list "states why"). The
  comment predates RV.218; the product owner decides whether a routing list may defer the field
  name to Edit. Filed as polish either way, because the excluded list already proves the reason
  caption is available and cheap.
