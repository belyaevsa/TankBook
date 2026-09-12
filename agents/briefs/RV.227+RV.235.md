# RV.227 + RV.235 - content resting under a pinned bar, two screens, one decision

**Scenarios: F6 · import file won't parse (the source picker), J7 · the service edit (F9a's Fix).**
Polish, same defect on two screens: content scrolls under a pinned bottom element and the thing
the user needs sits half-hidden at the default scroll position.

- `RV.227`: the import source picker's *Not yet* chip row sits behind the pinned dead-end card
  (`RV.191`) - in RU four empty rounded rects with no text (the orchestrator's screenshot).
- `RV.235`: the long service form's F9a *Fix* chip renders under the pinned save bar at rest;
  `isHittable` lied (`PJ.7e`), the RV.230 L4 had to scroll it clear.

## Build

**Decide once, apply to both**: bottom padding on the scroll content equal to the pinned
element's height (measured, not a constant - RU makes the card taller), or a `safeAreaInset`
that the scroll view respects. Read how `RV.191` pins the card and how the save bar is pinned on
the service form; use the SAME mechanism on both screens, and say which. Then check the other
pinned-bar screens (`EditEntryView`'s save bar, the manual fill-up form, the capture sheet) for the
same defect - fix them here if it is the same mechanism, list them if not.

## Tests

- **L4 RU, FAILS TODAY** (`ImportUITests` or the RV.191 test's file): at the default scroll
  position no *Not yet* chip frame intersects the dead-end card's frame - frames, never
  `isHittable`.
- **L4, FAILS TODAY** (the RV.230 test's file): on the long service form the F9a Fix chip's frame
  does not intersect the save bar's frame at rest.
- Screenshots EN + RU: `RV.227-import-source-notyet` and `RV.235-service-fix-clear`, dark.

## Mutation - named

Remove the padding; both L4s go red on the frame intersection. Verbatim.
