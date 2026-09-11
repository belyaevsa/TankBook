# RV.164 + RV.211 - two decisions about error surfaces, written down and bound

**Scenarios: F1 · scan recognized nothing (RV.164) and F9a · odometer contradicts the timeline
(RV.211).** Each is the only v1 row holding its scenario open. One brief because both are the same
kind of work: a rule about what an error surface promises, decided, written into `docs/ERRORS.md`,
and bound to a check that can fail. **Neither is a feature build.**

## RV.164 - an error can name a next step that does not exist

`docs/ERRORS.md`'s 3-question audit asks whether every error names its next step; nothing asks
whether **that step exists in code**. Four past instances: `RV.98`'s delete alert promised *"moves
to Recently deleted for 30 days"* while the view never queried deleted vehicles; `PJ.36`'s dead
*Export everything*; `RV.146`'s *Recent first* with no history lookup; `ERRORS.md`'s own *Storage
full* sheet, documented and unbuilt.

**Build**: a fourth audit question - *does the next step EXIST?* - and bind the part that can be
mechanised. A route named in copy can be checked against `SCREENMAP.md` with `RV.162`'s
`ScreenRouteScanner` machinery; a promised behaviour can only be bound by naming the test that
proves it. **Decide what is mechanisable and be explicit about the residue** - a rule that cannot
fail is not shipped; the residue goes into `ERRORS.md` as a stated limit and into the journey walk
(`REVIEW-SCENARIO.md`'s question 5) as a manual check.

Tests: **L1** - an error whose copy names a route `SCREENMAP.md` does not carry fails the audit;
**L1** - the teeth proven against `RV.98`'s original copy (reconstruct it from git, do not
guess). **Mutation**: add a fake route name to one error string; the guard goes red.

## RV.211 - the service and expense F9a shows one "Fix" and ignores the ranking

`PJ.34` wired a ranked, evidence-named fix list for a fill-up's odometer conflict; `RV.192`'s
`NeighbourSide` names which neighbour. `ServiceEntryConflictWarning` /
`ServiceEntryFormState.odometerConflict` render a single fix and never read
`validation.suggestions`. **Their documented next step IS one fix**, so this is a decision, not a
bug - the third time a fill-up got a behaviour its siblings did not.

**Decide it.** A service has no receipt-date priority to rank by, so the honest answer may be that
one fix is right for a service and an expense - **if so, write the reason into `ERRORS.md`
explicitly rather than by omission**, and add the L1 that asserts both entry kinds follow the same
rule so they cannot drift. If instead the ranking belongs there, the seam is `PJ.34`'s `F9aFixRow`
and it is already shared-shaped - reuse it, never copy it. **Say which you chose and why.**

Tests: **L1 from both entry kinds asserting the SAME rule**, whichever it is. **L4** in the service
path EN + RU only if copy changes. **Mutation**: make the service path diverge from the rule; the
cross-kind L1 goes red.

## Vacuous traps

- An audit that reads the doc and never the code.
- Copying the fill-up's ranking onto a screen with nothing to rank.
- "Deciding" `RV.211` by leaving it as it is without the written reason and the cross-kind test.

## Docs

`docs/ERRORS.md` is the deliverable for both. `docs/JOURNEYS.md` F1 and F9a: edit only if the
decision changes what the user is promised.
