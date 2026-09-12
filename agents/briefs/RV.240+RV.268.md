# RV.240 + RV.268 - the anomaly card: drop the reason prompt, date the reminder

**Scenario: J9 · anomaly nudge.** Two owner decisions of 2026-09-12 on one screen, one dispatch.

## RV.240 - option (b): stop asking for a dismissal reason

`AnomalyInsightCard.swift:288-377` collects a preset or custom reason; `AnomalyInsightStore.swift:34-40`
persists it; the cause is suppressed (that half of "dismiss teaches the model" stays); nothing reads
`AnomalyDismissal.reason` back. The owner chose (b): **drop the prompt and the field.** *Dismiss*
becomes one tap that suppresses the cause. Remove the reason sheet, its presets, its copy (EN + RU
keys), the `reason` column/field and its `SCHEMA.md` line; a migration drops the column only if the
persistence layer needs one (say which). `docs/JOURNEYS.md` J9 "dismiss teaches the model" is
reworded to what remains: the dismissed cause is not raised again. `PJ.32` [v1.x] (cross-device
dismissal) carries no reason either - amend its row text in one sentence.

## RV.268 - the *act* reminder is due next year, not today

`HomeView.actOnAnomaly` (`:325-330`) creates *Check fuel consumption* with `dueDate: Date()`.
Default the due date to the SAME default the reminder form offers a custom reminder (find it -
J7d's offer or the reminder form; do not invent a second constant), one year out per the owner,
and open the new reminder for edit so the date is seen and changeable (hard rule 13). If the
form's default is not a year, say what it is and use it - the owner's word was "usually next year",
the rule is "the shared default, never today".

## Tests

- **L1, FAILS TODAY**: the act reminder's due date is the shared default, not today.
- **L1**: dismissing stores no reason and suppresses the cause (the existing suppression test
  keeps passing without the reason).
- **L4 `HomeUITests` (anomaly seed) EN + RU**: *Dismiss* is one tap; *Create reminder* lands on a
  future date in the list. Screenshots `RV.240-anomaly-card` and `RV.268-anomaly-reminder`, EN +
  RU, dark.

## Mutations - named

RV.268: `Date()` back; the L1 goes red. RV.240: none needed - a deletion; show the grep that
`reason` is gone from the card, the store and the schema. Verbatim.
