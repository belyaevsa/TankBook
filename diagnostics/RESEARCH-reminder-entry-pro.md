# Where does "add a reminder" belong? — a UX review, grounded in this app

Model: `pro` (deepseek-v4-pro). Scope: placing the *create* action inside the
decided world (merged list, counts, offer sheet — RV.75–RV.79). No redesign.

---

## 1. Where the trigger lives, and where it does not

The single fact that governs every candidate: **a reminder is inherently
per-car, but its moment of use is cross-car.** "Insurance on the Skoda" and "oil
on the Volvo" compete for the same weekend (TASKS.md RV.75). So the create
action belongs on the surface that can *name the car and ask which one* — the
merged list — and nowhere that would force a silent car guess (hard rule 13).

**Ranked, best to worst:**

1. **The merged Reminders list (`RemindersAll.dc.html`), the "New reminder"
   card — keep, and make it the primary.** It is the one surface that already
   renders a car name on every row (the `VOLVO V60` / `SKODA OCTAVIA` chips) and
   whose form can therefore open with "Car" *empty and required* rather than
   guessed (`ReminderForm.dc.html:27-34`, `SCREENMAP.md:252`). The card is the
   right affordance in the right place. Its problem is reachability, not design.

2. **The Home "Reminders" row (`RemindersEntry.dc.html`, RV.76) — the doorway,
   not a button.** This is what closes the "no path from Home" bug. It must
   *navigate* to the merged list, not create directly: creating needs the
   which-car decision, and a `+` on the Home row would either default to the
   selected car silently (the exact quiet guess rule 13 forbids) or open the
   form with car empty — which is one tap later than the merged list's card
   anyway. The count ("2 due") is what earns the row its tap; the create affordance
   waits one hop behind it.

3. **The empty state's primary action — the discovery path, and it is missing.**
   A user with zero reminders is precisely the driver who must discover the
   feature, and `RemindersView.swift:250-269` (`emptyState`) renders a bell, a
   title and two lines of text with **no action at all**. The empty state should
   carry a filled "New reminder" button — see §3 for why the dashed card fails
   here.

4. **The post-service offer (`ServiceReminderOffer.dc.html`, RV.77) — the
   "just logged the work" opening.** Correct and decided: a proposal, not a
   create, anchored at the record's own date/odometer. It covers one of the
   three births and needs no change.

**Rejected, with reasons:**

- **The tab bar's centre button / its "Type it" menu.** The centre button is
  Capture, "the app's front door" for logging a value *now* (`DESIGN.md:97`). A
  reminder is scheduling *later* — a different verb. The five slots are decided
  and the fifth is Ask (`DESIGN.md:98`), so a tab argument would need to displace
  Capture or Ask and has no case. The "Type it" menu is worse than wrong: it is
  derived from `CaptureEntryForm.doorMenuForms` over entry-form `allCases`
  (`SCREENMAP.md:326-331`), an exhaustive switch over *entry* types. A reminder
  is not an entry, and forcing it in would break the "type it = log a value
  now" contract and the exhaustiveness that is a deliberate safety property.
- **The Garage car row (`GarageReminderCounts.dc.html`).** Browsing cars is not
  "I want to remember my insurance in March". Its attention count (RV.79) should
  *navigate* to the merged list; a create affordance there adds a second
  behaviour to a row whose job is one-line vitals, and it inherits the merged-vs-
  per-car ambiguity with no benefit.
- **The Vehicle-detail Reminders row (`VehicleDetailView.swift:102-108`).** It
  already navigates to the per-car list, whose own card (`RemindersView.swift:273`,
  `Reminders.dc.html`) creates with the car pre-filled. Adding a second create
  affordance here is one hop from that card and duplicates it for nothing.
- **The per-car list's own card.** It exists and is correct — car pre-filled,
  still changeable — but it is the *special* case, not the primary. The brief's
  own complaint (Garage → car → Reminders → scroll) is what this card costs when
  it is treated as the only door.

**One-sentence answer:** the create trigger's home is the merged list's dashed
card, its doorway is the permanent Home "Reminders" row (RV.76), its discovery
path is a filled action on the empty state, and it must never live on the tab
bar, the "Type it" menu, or the Garage row, because all three either conflate
"remember later" with "log now" or force a silent per-car guess.

---

## 2. The missing journey: J7a · Creating a reminder

*Drafted in the file's house style. Sits before J7c, which it feeds. J7c covers
what a reminder does after it exists (complete / reschedule / delete); this is
its birth, which J7c notably never describes (`JOURNEYS.md:197-208`).*

**Trigger:** the driver decides something must be remembered — insurance in
March, oil in 15 000 km, the winter tyre swap — and reaches for the app. Three
openings, three paths:

| Action | What happens | Notes |
|---|---|---|
| **Decide to add one** (planned intent) | Home → the "Reminders · N due" row (always present, RV.76) → merged list → "New reminder" → the form opens with **Car empty and required** | The car field is a default input, not a fact: defaulting to the selected car is the quiet guess hard rule 13 forbids (`SCREENMAP.md:252`). From a car's own screen the same form opens with the car filled and still changeable |
| **Just logged the work** (the loop closes) | Saving a ServiceRecord or Expense whose category has an interval offers "Remind you next time?" anchored at the record's own date/odometer, never today | A proposal, never an auto-create (`ServiceReminderOffer.dc.html`). Suppressed when a live reminder of that category already exists on that car — otherwise a user ends up with three oil reminders (RV.77) |
| **Has none, must discover** (the empty garage case) | The empty Reminders list shows its empty state, whose primary action is "New reminder" — filled, not a dashed placeholder | Today this path is dead: the empty state (`RemindersView.swift:250`) offers text and no action, and the Home banner only renders while something is already attention-due (`ReminderBanner.bannerReminder` filters `.attention`) |

⚠ **The whole journey is gated on the calm path existing.** Without RV.76, a
driver who is not already overdue reaches the only trigger via Garage → car →
Reminders → scroll — and a driver who has never made a reminder has no idea the
screen exists. The surface that should say "plan your March insurance" is
hardest to reach exactly when the user is calm enough to plan.

**Success metric:** ≥40% of reminders are born from either the post-service
offer (accepted, not auto-created) or a session that started at the Home row —
i.e. the two paths that do not require the user to already know where Reminders
lives; and a new user reaches their first created reminder without a search or a
support ticket, measured as time-to-first-reminder < 1 week from first entry.

---

## 3. What makes this feel native on iOS, specifically

**A "+" in the header vs a card at the end of the list.** The standard iOS
pattern for a pushed list's create action is a `+` pinned to the trailing edge
of the navigation header (Apple Reminders, Calendar, Mail). This app has
deliberately abandoned the system nav bar for a custom one-row header
(`DESIGN.md:102-103`), but the pushed Reminders screens still draw a trailing
control there — `RemindersAll.dc.html:23-27` puts the "All cars" chip on the
right, and `Reminders.dc.html:22-25` the car chip. A `+` could sit beside it. The
dashed card, by contrast, is the *last item in a `ScrollView`*
(`RemindersView.swift:53-78`): it is correct when the list is short, and it
**scrolls away below the fold** the moment the list grows — exactly the failure
the brief names ("scroll"). A create action that disappears when you have many
reminders is backwards: the people with the most reminders are the ones adding
more.

**Does a dashed outline read as a placeholder?** As the *last row* of a list it
is the right idiom — the app uses it consistently for "add one more" (`Add car`
in `CarSwitcher.dc.html:69-72`, `GarageReminderCounts.dc.html:82-85`), and it
says "insert here". As the **primary action of an empty state**, a dashed
outline is wrong: it says "nothing here yet", not "start here". The app's own
empty states already render a *filled* `formCard()` (`RemindersView.swift:250-269`)
but then fail to put a button in it. An empty state's hero action should be
filled and in the accent colour — the difference between "this slot is empty"
and "do the thing". Right now the code has neither.

**Is creating a per-car reminder from a merged list confusing?** It is the one
genuine risk in the plan, and the mocks have already defused it three ways: every
row names its car (a merged row that does not is unreadable, `SCREENMAP.md:229`),
the form makes Car the **first and required** field (`ReminderForm.dc.html:27-34`),
and the caption states the rule out loud — *"From the merged list nothing is
picked for you – from a car's own screen this is filled in and still changeable"*
(`ReminderForm.dc.html:33`). The one thing that would make it confusing is a
silent default to the selected car, and the docs forbid exactly that
(`SCREENMAP.md:252`). It is mildly confusing by nature, and correctly mitigated.

---

## The one thing I would change about the mocks

Give the empty Reminders state a **filled primary action** ("New reminder"),
rather than leaving creation to the dashed card at the bottom of the scroll — and
pin that card (or a header `+`) so it never scrolls out of reach. As drawn, the
only user who cannot *reach* the trigger is the one with nothing to lose, and the
dashed outline is the least discoverable affordance to hand them.
