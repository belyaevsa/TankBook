# RV.230 - a service or expense edited into a timeline conflict is flagged and never told

**Scenarios: F9a · odometer contradicts the timeline, J7 · the service edit.** F9a's one open
build row (`RV.231` is a product decision, not a build). Sibling of `RV.211`, one door over.

## The defect

`EditEntryView.writeNonFill` (`EditEntryView+NonFillSave.swift:44-51`) runs `TimelineValidator`
and stamps `conflict` on a service, expense or charge - and `EditEntryNonFillView` renders **no
warning at all**, while `docs/ERRORS.md` -> Edit entry promises *"Same amber mechanics as Confirm"*.
It is the expense's ONLY F9a surface (an expense has no create-time odometer conflict), so today an
expense can carry a flag the user can never see or clear from the entry. Hard rules 7 and 8. Found
by the `RV.211` agent and confirmed by F9a's first walk.

## Build

Render the SAME warn row and the SAME single *Fix* the fill-up edit uses - through `F9aFixRow` and
`F9aFixPresentation.fixes(_:for:)` (`RV.211`'s one rule, which already answers *one fix* for these
kinds) - on `EditEntryNonFillView`. **Cover charge as well as service and expense**: all three
share `writeNonFill`. The flag clears through the existing `flagAcceptance`. Not a copy of the
component; the component.

**Check the neighbourhood**: the fill-up edit also renders `TimelineNeighbourhood`. Decide whether a
non-fill edit shows it (the conflict quotes a neighbour, so probably yes) and say why.

## Tests

- **L1, FAILS TODAY**: a non-fill edit into a conflict produces the flag AND the view model exposes
  it for rendering - asserted from service, expense and charge in one test file.
- **L4 `EditEntryUITests` EN + RU**: a seeded conflicting service shows the amber row and one *Fix*;
  tapping it resolves; the flag clears. Frames of the row on the non-fill edit screen; capture lines.
- **L1**: the fix list is `F9aFixPresentation`'s for `.service` - one entry - not the fill-up ranking.

## Mutation - named

Remove the warn row from `EditEntryNonFillView`; the L4 goes red. Byte-identical restore; verbatim.

## Vacuous traps

- A second warn component.
- Asserting the flag is stored rather than that it is shown.
- Covering service and skipping charge.
