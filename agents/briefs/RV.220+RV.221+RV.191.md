# RV.220 + RV.221 + RV.191 - the import review row, and the dead-end card under it

**Scenarios: F6b · a flagged import row is fields, not a line of CSV, and F6 · the import file won't
parse.** These three are the only v1 rows holding both open. When they land, both are re-walked for
their `Status: implemented` lines. One brief because all three are `ImportReviewView` and its RU
layout; **`RV.220` is a hard rule 8 bug and is done first**, as its own commit-sized change inside
this run.

## RV.220 - "Import as service" and "Leave out" toggle the same bit

Verified by `REVIEW-SCENARIO-F6b-2026-09-11` and the orchestrator in the tree:

- The `.noFuel` row's deciding action label - *Import as service* / *Import as expense* - is a
  `Text` whose tap handler is `model.toggleSkipped(sourceRow:)`
  (`ios/App/Sources/Import/ImportReviewView.swift:418-424`).
- *Leave out* calls the **same** `toggleSkipped` (`:375`, `:382`).
- `toggleSkipped` is a flip-flop on `skippedSourceRows` (`ImportFlowModel+Wizard.swift:161-167`).
- The comment above the label says *"the record commits as what it is, never silently dropped
  (hard rule 8)"* (`:437-439`). One toggle, two buttons: whichever the default skip state of a
  `noFuel` row is, a tap on the keep button on an already-kept row **drops it**, and the user sees
  the label's colour change and nothing else.

**Build**: two intents, two methods. The keep actions **un-skip** (idempotent - keeping a kept row
keeps it); *Leave out* **skips**. No shared toggle. Rewrite the comment to what the code then does.
**Find the default first**: what `skippedSourceRows` holds for a fresh `noFuel` row decides whether
today's first tap keeps or drops - say which, because it decides how bad this has been.

## RV.221 - the review row never shows the station

- F6b promises the row renders *"date, station, litres, price, total, odometer, note"*.
- `fieldGrid` renders litres / price / total / odometer (`ImportReviewView.swift:248-276`); the
  header carries date and note (`:114-121`). **Station is rendered nowhere** - `grep -n station
  ImportReviewView.swift` returns nothing, and `ImportReview.dc.html` does not draw it either.
- It is carried end to end (`ImportConversion.swift:53-66`) and the user first sees it in the Log,
  after commit. A wrong mapping (`RV.189`'s family) surfaces too late to fix at review.

**Build**: a station cell in `fieldGrid`, and the artboard drawn to match - OR, if omitting it was a
deliberate design call, say so with the evidence and correct the journey text instead. **Decide,
do not do both.**

## RV.191 - RU: the dead-end card falls below the fold

At the real format count (two cards since `RV.190`), the dashed *"Your app isn't here?"* card is
clipped in RU and **"Send us the file" - the next step - is not visible without scrolling**.
Reachable, so a gap not a broken promise, but hard rule 7 is about the next step being *found*,
and `RV.84` already moved this card once for the same reason. Make it reachable without scrolling in
RU at the real format count - tighten the format cards, or pin the dead-end card - and say which.

## Environment axes

**RU is the whole point of two of these three.** A long free-text station name is where `RV.221`'s
cell truncates; the format subtitles are why `RV.191` clips. Every screenshot EN + RU, dark, capture
lines added. Shoot `RV.221` with a station name long enough to test the cell - use the existing seed
mechanism, and say what length you used.

## Tests you must add

- **L1 on the model, and it FAILS TODAY**: keep is idempotent - `keep(sourceRow:)` twice leaves the
  row kept; `leaveOut` skips; neither is the other.
- **L4 `ImportUITests` EN + RU**: seed a `noFuel` row, tap *Import as service*, finish, assert the
  service is in the Log. Seed again, tap *Leave out*, assert it is not. **The Log, not the button.**
- **L4 `ImportUITests` EN + RU**: a seeded fill whose candidate carries a station renders its name
  on the review row (or, if you chose to correct the journey text instead, no test and a doc diff).
- **L4 RU**: at two registered formats, *"Send us the file"* is hittable without scrolling.

## The mutation you must run - named

**RV.220**: restore the shared `toggleSkipped` on the keep label; the "service lands in the Log"
L4 goes red. **RV.221**: remove the station cell; its L4 goes red. Both restored byte-identical,
outputs verbatim.

## Vacuous traps

- Asserting the label's colour changed rather than that the row committed.
- A station cell that renders the id, not the name.
- Fixing `RV.191` by shrinking the font below the DESIGN.md scale.
- Leaving the comment at `:437-439` as it is because the code now happens to match - re-read it.

## Docs

`docs/JOURNEYS.md` F6b: edit only if you chose the "correct the text" branch of `RV.221`.
`docs/ERRORS.md` -> Import review: the dead-end card's row, if its placement rule changes.
