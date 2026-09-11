# RV.218 - the consumption outlier check on save that F2 promises

**Scenario: F2 · scan recognized WRONG data - the most dangerous failure.** The only v1 row holding
F2 open; on landing, F2 is re-walked for its status line.

## The gap

`docs/JOURNEYS.md:504`, F2's *"The residue"* stage: if all three numbers are wrong *consistently*
(rare), the cross-check passes falsely. The journey names two mitigations - the odometer delta
(*"+3,407 km since last?"*, shipped as `TimelineValidator`'s `order`/`pace` flags) and
**"consumption outlier check on save"**. The second has no code: `grep -rln outlier` over
`ios/Sources` and `ios/App/Sources` finds a price-band seed and a Home section. Save runs only
`TimelineValidator.validate` (`TimelineValidator.swift:106-131`, called at
`ManualFillUpView.swift:659-661`). Found by `REVIEW-SCENARIO-F2-2026-09-11`, verified by the
orchestrator. An unowned promise - the `PJ.23` shape.

## What to build - a flag, never a gate

On save of a fill-up, compute the consumption the new fill implies against the previous fill using
the **same `ConsumptionEngine`** Trends and Home derive from (`ConsumptionEngine.segments(for:)`,
`ConsumptionEngine.swift:130`) - hard rule 2, one derivation, never a second formula. When the
figure lands outside a conservative band, raise a **non-blocking `warn`** with a next step -
*check litres* / *check odometer* - beside the field most likely wrong.

**Never veto the save.** `docs/SCHEMA.md` (the paragraph above line 951): *"Bands are wide and soft
on purpose. They rank candidates; they never veto. A genuine outlier must still save."* The band
here is a HINT threshold; **read `docs/ERRORS.md`'s severity vocabulary** and put the new row there
with its next step. Decide the band from the vehicle: a powertrain's plausible L/100km range is a
per-vehicle fact (`docs/SCHEMA.md` -> Vehicle), not one number for all cars; say what you chose and
why, and where the constant lives per `docs/PRACTICES.md`'s constants-placement policy.

**This is a sibling of `TimelineValidator`'s flags.** Look at how `pace` is raised, rendered
(`NeighbourSide`, `F9aFixRow`), accepted and cleared (`flagAcceptance`) and put the outlier through
the SAME surface if it fits - a third rendering of "the app noticed something" is a defect. If it
does not fit, say why.

## Tests you must add

- **L1, and it FAILS TODAY**: a fill implying an absurd figure against its predecessor produces the
  flag; oracle is `ConsumptionEngine`'s own segment for the pair.
- **L1**: a plausible fill produces none; a first fill (no predecessor) produces none.
- **L1**: the flagged fill **saves** - assert the row is persisted with the flag, not refused.
- **L1**: the figure the flag quotes equals what Trends would show for the same pair - one engine.
- **L4 `CaptureUITests` EN + RU**: the warn renders with its next step and Save stays enabled.
  Capture lines; both frames.

## The mutation you must run - named

Make the save path skip the outlier computation; the "absurd figure produces the flag" L1 goes red
while "plausible produces none" stays green. Restore byte-identical; outputs verbatim.

## Vacuous traps

- A second consumption formula beside the engine.
- Gating Save - the whole `SCHEMA.md` paragraph exists to forbid it.
- A band so wide it never fires: prove it fires on a realistic absurd input (a misread litre digit,
  the F2 case) and not on the corpus's real outlier (AI-100 at shortage prices is a PRICE outlier,
  not a consumption one - make sure the check does not confuse them).

## Docs

`docs/ERRORS.md` -> Confirm: the new warn row, its next step, its severity. `docs/JOURNEYS.md` F2
already promises it; edit only if what ships differs.
