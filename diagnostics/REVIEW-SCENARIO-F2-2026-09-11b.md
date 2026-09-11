# REVIEW-SCENARIO F2 – 2026-09-11b (second walk, after RV.218)

## Verdict

**IMPLEMENTED** – the single MISSING row from the first walk (the residue's
"consumption outlier check on save") is now shipped as **RV.218** and verified
in code, L1 and L4. Every promise in F2's text is MET or reasoned N/A.

## Ticked rows found to be untrue

None.

## What changed since the first walk

The first walk (`REVIEW-SCENARIO-F2-2026-09-11.md`) returned **NOT IMPLEMENTED**
on exactly one MISSING row: the residue's *"consumption outlier check on save"*
had no row, no code, no doc. **RV.218** (`c503d609`) filed and shipped it. Re-check
of that row and the sequence trace follows.

## Promise-to-code map (re-checked: the one MISSING row + the sequence)

| F2 text | Verdict | Evidence |
|---|---|---|
| Residue: "consumption outlier check on save" | **MET** (was MISSING) | `TimelineValidator` CHECK 5 derives the closing segment's `per100` from the SAME `ConsumptionEngine.segments` Trends uses and appends a `.consumption` flag when it falls outside the vehicle's powertrain band (`TimelineValidator.swift:304-314`, `consumptionConstraints` `:200-211`). Band is per-powertrain, tier-C compiled, a hint never a gate (`ConsumptionOutlier.swift:30-48`). Rendered on save through the existing odometer-card warn row + `F9aFixRow` chips (*Check litres* preselected, *Check odometer* – `F9aFixRow.swift:68-78`; `ManualFillUpFormState.odometerConflict` `:321-360`, `.consumption` case `:351-358`). Persisted as `conflict` on save (`ManualFillUpView.buildFillUp:661-663`); the save gate stays on two fields, never the flag (`ManualFillUpView.swift:533-536, 685`; `EntryValidation.isSaveable` always true `TimelineValidator.swift:93`). Clears through the same `flagAcceptance` (`suppressed` `:351-363`) and excludes its own segment so the flag is stable across re-validation (`ConsumptionOutlier.clearingSoftConflict`, `TimelineValidator.swift:204`). |
| Residue: "Accept residual risk; mitigate with the odometer delta" | **MET** (unchanged from first walk) | `OdometerDelta.evaluate` live caption (`ManualFillUpSections.swift:414-420`), order/pace enforced on save by CHECK 1/2 (`TimelineValidator.swift:251-301`). |
| Residue: "a price outlier can never trip it" | **MET** | CHECK 5 reads litres over distance only; `money` is never consulted (`TimelineValidator.swift:308-314`, `ConsumptionOutlier.swift:24-25`). L1 asserts it (`RV218ConsumptionOutlierTests.swift:96-109`). |
| "A fill with no predecessor closes no segment, never flagged" | **MET** | `consumptionConstraints` maps only closing fills; a first fill has no closing segment (`TimelineValidator.swift:202-208`). L1 (`RV218ConsumptionOutlierTests.swift:83-94`). |
| Detection / Surfacing / Recovery stages (cross-check, amber underline, source crop) | **MET** (unchanged from first walk) | See first walk map: `ManualFillUpMath.swift:118-126`, `TimelineValidator.swift:155-162`, `ManualFillUpSections.swift:266-319, 354-362`, `ExtractionAssembler.swift:73-87`, `CapturePipeline.swift:78-96`. |

## Sequence trace (one user, one scan that misreads all three numbers consistently)

1–5 unchanged from the first walk: scan → pre-fill → cross-check locks/warns →
tap magnifier → correct. Step 6 is the one the first walk broke, and it now
closes:

6. **Save**: `buildFillUp` runs `TimelineValidator.validate` over the candidate +
   existing timeline; CHECK 5 computes the segment this fill closes and, when the
   implied consumption lands outside the powertrain band, raises `.consumption`
   and the entry saves **with** the flag, never blocked
   (`ManualFillUpView.swift:661-663`).
7. The consistent-misread case F2 names: the cross-check still passes falsely
   (litres/price/total shifted together), but a misread litre or odometer digit
   now shifts the *implied consumption* the same factor and lands outside the
   band, so CHECK 5 flags it, quotes the engine's own figure, and names *check
   litres* (preselected) then *check odometer* (`F9aFixRow.swift:68-78`,
   `ManualFillUpFormState.swift:351-358`). The fact that stopped being carried in
   the first walk – the consumption the entry implies – is now computed and
   flagged at the moment the cross-check passes falsely.

The one honest residual the journey explicitly accepts: a misread that shifts
only total and price consistently (litres correct) leaves consumption unchanged,
so neither check fires. F2's residue text is *"accept residual risk; mitigate"*,
and both named mitigations are now in place.

## RV.229 does not block F2

**RV.229** (`docs/TASKS.md`, `[ ]`) is the **import** path (`F6b`): `ImportConversion.classify`
labels a `.consumption` flag "Breaks the timeline" with the odometer editor as
its next step. F2 is the **scan** path; its text (`docs/JOURNEYS.md:497-507`) makes
no promise about import labelling. RV.229 is already filed under F6b/F2 and cited
here, not re-filed. It is a real defect on the import surface but does not block
F2's story.

## Proposed rows

None. Every promise in F2 is MET or reasoned N/A; the single gap found in the
first walk is closed by RV.218.

## Could not settle

Nothing.
