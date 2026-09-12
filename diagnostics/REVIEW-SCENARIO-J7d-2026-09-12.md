# REVIEW-SCENARIO run: J7d - 2026-09-12

- **Scenario:** `J7d` (`docs/JOURNEYS.md:404-431`)
- **Run id:** REVIEW-SCENARIO-J7d-2026-09-12
- **Report path:** `diagnostics/REVIEW-SCENARIO-J7d-2026-09-12.md`
- **Context:** First walk. The heading is `[v1.1]` but the offer shipped in v1 (`PJ.22`, `RV.213`, `PJ.27`). Walk the text against the tree; `PJ.60` is the one open row and awaits the owner.

## Verdict

**IMPLEMENTED** - every promise in the J7d text is MET in code with a live call site; `PJ.60` is open but its unbuilt half (next-entry) is a `docs/SCHEMA.md` field comment, not a sentence in J7d's journey text, and its own row states the reminder half (J7d's actual promise) is already met.

## Ticked rows found to be untrue

None. Every ticked row the text leans on holds in the tree:

- **RV.76** (permanent Home row): `HomeRemindersEntryRow` is rendered unconditionally in `fullLayout` (`HomeView.swift:256`), not gated on count; the amber chip alone is conditional (`HomeBanners.swift:183`).
- **RV.75** (merged list): `Route.remindersAll` -> `RemindersView(scope: .allCars)` (`Destinations.swift:31`), rows name their car (`RemindersView.swift:173`).
- **RV.77** (the offer): `ReminderOffer` in core + `ServiceReminderOfferSheet`, staged by `ReminderOfferSession`, promoted on sheet dismissal (`TabRootSheetHost.swift:24`).
- **PJ.22** (item lifetime drives the offer): `ReminderOffer.propose` uses `item.lifetime` (`ReminderOffer.swift:232`), the edit door gates on `serviceLifetimeChanged` (`EditEntryView.swift:416`).
- **RV.213** (same lifetime editor on the create card): `ServiceEntrySections.swift:386` renders `ServiceItemLifetimeFields(lifetime: $item.lifetime)`, bound into the draft (`ServiceEntryFormState.swift:92`).

## Promise-to-code map

| Journey promise (J7d) | Status | Citation |
|---|---|---|
| **Plan it** - Home's permanent "Reminders · N due" row, present whether or not due | MET | `HomeView.swift:256` renders `HomeRemindersEntryRow` unconditionally; chip only when `attentionCount > 0` (`HomeBanners.swift:183`) |
| Row navigates to the merged list | MET | `HomeBanners.swift:169` `NavigationLink(value: Route.remindersAll)` |
| "New reminder" opens the form | MET | `RemindersView.swift:252-274` (populated dashed card), `RemindersEmptyStateView.swift:35` (empty filled button) -> `Route.reminderForm` |
| The car is the form's first field | MET | `ReminderFormView.swift:65` renders `ReminderFormCarCard` first in the stack |
| From the merged list nothing is picked and Save waits | MET | `RemindersView.swift:281-282` (allCars `vehicleID: nil`); `ReminderFormView.swift:113` (`saveEnabled` needs `selectedVehicleID`), `:118` (`"Pick a car to save"`) |
| From a car's own list / Vehicle detail the car arrives filled, still changeable | MET | `RemindersView.swift:284` (`vehicleID: vehicle?.id`); Vehicle detail door `VehicleDetailView.swift:226-231` -> `Route.reminders`; chips re-select (`ReminderFormSections.swift:68-71`) |
| **Just did it** - saving a service/expense whose category has an interval raises the offer after save | MET | `ServiceEntryView.swift:441` (`stage(afterService:)`), `ExpenseEntryView.swift:271` (`stage(afterExpense:)`), `EditEntryView.swift:419` (lifetime-edit door) |
| Offer pre-filled from record (category, date, odometer), interval editable in the same breath | MET | `ReminderOffer.Proposal` carries all five (`ReminderOffer.swift:31-60`); editable fields `ServiceReminderOfferSheet.swift:109-120` |
| A line item's own lifetime states the interval directly (user's number, not a category guess) | MET | `ReminderOffer.swift:232` (explicit lifetime wins), `:245` (explicit chosen over fallback) |
| An offer, never an auto-create | MET | only `createReminder` persists (`ServiceReminderOfferSheet.swift:167`, `:263`); "Not this time" is a peer button (`:188`) |
| Suppressed when a live reminder of that category exists on that car | MET | `ReminderOffer.swift:175-183` (`isSuppressed` checks `ReminderLifecycle.isActive`) |
| Anchored at the record, never today | MET | `ReminderOffer.swift:320` (`calendar.date(byAdding:to: proposal.date)`) |
| Never mid-save; declining costs nothing | MET | `TabRootSheetHost.swift:24,33` promote on `onDismiss`; `decline()` only emits + dismisses (`ServiceReminderOfferSheet.swift:296`) |
| A category with no curated interval offers nothing unless an item states a lifetime | MET | `ReminderOffer.swift:98-105` (`defaultInterval` nil for brakes/tires/etc.), `:232-235` (item lifetime overrides) |
| **Discover it** - zero reminders: row still reads "Reminders", empty list explains, one action is a filled button | MET | `HomeBanners.swift:175` (title always "Reminders"); `RemindersView.swift:80-82,241-243`; `RemindersEmptyStateView.swift:27-42` (filled primary, `remindersEmptyNewReminderButton`) |
| **Save** - lands in the list it was created from, naming its car | MET | `ReminderFormView.swift:157` `dismiss()` -> `RemindersView.swift:106` `onAppear` reload; merged rows name their car (`RemindersView.swift:173`) |
| The notification arms | MET | `ReminderFormView.swift:149-156`; `ServiceReminderOfferSheet.swift:283-284` (`requestPermissionIfFirstReminder` + `reconcile`) |
| Sits under Scheduled until its window opens (J7c takes over) | MET | created `.scheduled` (`ReminderOffer.swift:336`, `ReminderDraft.swift:71`); `ReminderListGroups.grouped` (`RemindersView.swift:70-72`) |

The two `⚠` principle paragraphs (lines 418-427) are rules, not testable promises; each is honoured at its call site (car default: `ReminderFormCarCard` no auto-select `ReminderFormSections.swift:43-49`; interval-as-suggestion: `ServiceReminderOfferSheet.swift:122`).

The "J9's anomaly card is a fourth, incidental birth" note is a cross-reference, not a J7d promise; it exists (`AnomalyInsightCard.swift:198` "Create reminder").

## Sequence trace (one user, form path and offer path)

Form path: Home (row always present) -> tap -> merged list -> "New reminder" -> form, car card first, nothing picked -> Save inert ("Pick a car to save") -> pick car, fill -> Save -> `upsertReminder` + `reconcile` (arms) -> `dismiss` -> merged list `onAppear` reload -> new row visible, naming its car, under Scheduled/attention.

Offer path: log a service with an oil item -> `save` -> `stage(afterService:)` computes the proposal from the saved record -> `dismiss` -> `TabRootSheetHost.onDismiss` `promote()` -> offer sheet -> edit interval -> "Create the reminder" -> `ReminderOffer.reminder(accepting:)` anchored at the record -> `upsertReminder` + `reconcile` -> dismiss.

**Where a fact stops being carried:** none. Category, date and odometer travel from the saved record into `Proposal` and out as the created `Reminder` (`sourceEntryId`, `dueDate`, `dueOdometer`, `category`). The one value the create-door fix was about - a stated lifetime - reaches `propose` because the create card binds into the same draft item that `ServiceEntryFormState` writes (`ServiceEntryFormState.swift:92`), closing what `RV.213` opened.

## Proposed rows

None. The only open row naming J7d is `PJ.60`, and it is not a J7d promise gap (below), so proposing against it would duplicate an existing row.

## Not settled

- **Why `PJ.60` does not block J7d.** `PJ.60` (`docs/TASKS.md:793`) records that `Expense.recurrence` is written nil and read nowhere, and splits its own finding: the **reminder** half is "already met by the shipped `ReminderOffer`", the **next-entry** half is unbuilt. The J7d journey text promises only the reminder half ("Saving a service or expense record whose category has an interval -> ... 'Remind you next time?'"). It never promises "auto-suggests the next expense entry" - that sentence lives only in `docs/SCHEMA.md:249`'s field comment (`// yearly insurance auto-suggests next entry + reminder`), which no journey owns. The row's own consequence cell says "Nothing user-visible today: the insurance reminder works through a different path." So `PJ.60` is a schema dead-field finding filed against the closest journeys, not a J7d promise left unbuilt; it awaits its drop-or-write owner and does not change this verdict.
- **The `[v1.1]` marker on the heading.** The offer and every promise here shipped in v1 (`PJ.22`, `RV.213`, `PJ.27` all `[x]`). The heading still reads `**[v1.1]**` while nothing in the journey's text is version-gated. This is doc drift, not a code gap, and per the brief I do not touch the heading (only the status line is mine); the marker should be reconsidered in the next change that edits this journey.
