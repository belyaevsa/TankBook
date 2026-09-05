# Where does "add a reminder" belong? A UX review, grounded in this app

Model: qwen3.8-max.

## 1. Where the trigger should live, and where it should not

**The frame:** a reminder is born in one of three states - planning ahead, just-finished-the-work, never-heard-of-this. RV.75-RV.77 already cover the first two; what is missing is not a new surface but the discovery path.

**ACCEPT, ranked:**

1. **The merged Reminders list** (`RemindersAll.dc.html`, RV.75). The user is there to answer "what needs me" - exactly the state in which "what should I add?" arises. The dashed "New reminder" card (mock line 105) with the footer "New reminder asks which car" (line 110) is the primary create door, and `SCREENMAP.md` rules it correctly: from here the form's car field arrives **empty and required**, because defaulting to the selected car is the quiet guess hard rule 13 forbids (RV.75 says the same).
2. **Just after a service or expense save** (`ServiceReminderOffer.dc.html`, RV.77). Where most reminders *should* be born: category, date and odometer are all known, and the mock's copy is honest - "Counted from this record, not from today", "A suggested interval, not a fact". It ranks second only because it is an offer, not a destination. Its rules are already right: never auto-create, suppress when a live reminder of that category exists, never mid-save.
3. **The per-car Reminders list** (`RemindersView.swift:273`, `newReminderCard`). Exists today, correct as-is: the intent named a car, so the form pre-fills it, still changeable - the right screen when you are looking AT a car (`SCREENMAP.md`, "Reminders across cars").
4. **The Home "Reminders" row** (`RemindersEntry.dc.html:53`, RV.76) - as a **discovery door, not a create trigger**. Its job is to exist when nothing is due, which is precisely when today's user has no path at all: the banner renders only inside the attention window (`ReminderBanner.swift:27` filters to `.attention`, `HomeBanners.swift:31` hides the card when nil). The row carries the count and opens the merged list; it should NOT carry its own "+". Two tap targets in one row split the affordance, and creation one tap deeper is cheap when lists are short.
5. **The empty state.** One primary action, and it already has it: `newReminderCard` renders unconditionally after the empty card (`RemindersView.swift:58-72`). With RV.76's row always present, the zero-reminder path becomes Home row -> empty list -> dashed card: two taps, no prior knowledge. The discovery gap closes without inventing anything. (J9, `JOURNEYS.md:226`, remains a fourth, incidental birth: anomaly card -> "act -> creates a service reminder".)

**REJECT:**

- **The tab bar and the Capture circle's "Type it" menu.** The five slots are decided and the fifth is reserved for Ask (RV.76 verbatim: "Do not put it on the tab bar"; `DESIGN.md:97`). The Type-it menu holds Service and Expense (`HomeView.swift:350-357`, `CaptureMode.swift:80-84`) - forms that write *entries*, with amounts, receipts and a scan door. A reminder has none of these; hard rule 15's two-doors framing does not even apply, because there is nothing to scan. "Reminder" on that menu would be a peer of things it is not, and would silently scope to the selected car - the rule-13 violation RV.75 forbids.
- **The Home banner.** The urgent path, and RV.76 says so ("Keep the banner for the urgent case"). Amber is attention only (hard rule 5); a create affordance there mixes planning into triage, and the banner derives from one car, so a "+" inherits the wrong scope.
- **The Garage car row** (`GarageReminderCounts.dc.html:46`). Its reminder element is a *diagnostic* - "1 needs attention" - and the user is there to pick a car, not plan work.
- **Vehicle detail.** The Reminders link row already exists (`VehicleDetailView.swift:102-108`); a second "+" beside it gives one destination two doors in the same card stack.
- **The car switcher** (`CarSwitcher.dc.html`). Its footer states its whole contract: "Capture always logs to the selected car." It is a modal decision about *which car*; creation needs that decision made, or made explicitly on the form.

## 2. The missing journey

House style per J7c (`JOURNEYS.md:197-208`): trigger, Action/What happens/Notes table, ⚠ line, measurable success metric.

> ### J7d · A reminder is born
> **Trigger:** insurance lands in March, the oil was just changed, or the user has never had a reminder and finds the feature at all.
>
> | Action | What happens | Notes |
> |---|---|---|
> | **Plan it** | Home's permanent "Reminders" row (RV.76) -> the merged list -> the dashed "New reminder" card -> the form, car as its first field. From the merged list the car arrives **empty and required**; from a car's own list or Vehicle detail it arrives **filled in, still changeable** | The row exists when nothing is due - the calm path IS the discovery path. A silently defaulted car is a hard-rule-13 bug (RV.75) |
> | **Just did it** | Saving a service/expense record whose category has an interval -> after the save lands, the offer: "Remind you next time?" pre-filled from the record - category, its date, its odometer - with the interval editable in the same breath. Create / Not this time | Offer, never auto-create. Suppressed when a live reminder of that category exists on that car (RV.77). Anchored at the record, not at today, so the next cycle counts from the work. Never mid-save; dismissing costs nothing |
> | **Discover it** | A user with zero reminders: the Home row still reads "Reminders - across all your cars" (no count chip), and the empty list's only action is the dashed card, directly under the "No reminders yet" copy | Today this path does not exist: the banner renders only inside the attention window (`ReminderBanner.swift`), so a user with nothing due must already know the screen exists. J9's anomaly card is a fourth, incidental birth |
> | **Save** | The reminder lands in the list it was created from, naming its car; the notification arms; it renders under Scheduled until the window opens - then J7c takes over | The loop closes only if the birth happened; J7c covers everything after |
>
> ⚠ Birth is where silent guesses live: a defaulted car, a suggested interval dressed as a fact, a reminder quietly created as a side effect of saving a record. Every value here is a proposal the user can change at the moment it is offered and again afterwards (hard rule 13) - the created reminder is theirs permanently.
>
> **Success metric:** ≥50% of users with a live car hold ≥1 active reminder within 30 days of first launch; ≥50% of all reminders are born from the post-save offer rather than the form (the loop, not the screen, is the engine); offer acceptance ≥60%, matching J7's existing bar.

## 3. What makes this feel native on iOS, specifically

- **Header "+" versus the card at the end.** The platform pattern (Apple Reminders, Notes, Calendar; HIG toolbar guidance - convention, named as such) puts creation in the trailing toolbar slot. This app cannot: both Reminders headers already spend that slot on the car-scope chip (`Reminders.dc.html:22-25`, `RemindersAll.dc.html:23-27`). And the dashed add-card is house vocabulary - Garage's "Add car" is the identical card (`GarageReminderCounts.dc.html:82-85`, `CarSwitcher.dc.html:69-72`). Keep the card; a competing header "+" would be a second, inconsistent door. Scroll-off is tolerable because these lists are short by nature (the merged mock holds four rows); if that ever stops being true, pin the card, do not move it to the header.
- **Does the dashed outline read as a placeholder?** On the web a dashed border means drop zone; here it does not - the card carries a "+" and a label in `Theme.Palette.action` (`RemindersView.swift:276-281`), and every other dashed card in the app is a working button. The real risk is contrast: the mock's dash (#2A3140 on #101318) is near-invisible, so the cyan label carries the whole affordance. In the empty state the dashed card must stay the single primary action - the explanatory bell card may sit above it (`RemindersView.swift:58-72`), but nothing may come between them.
- **Is per-car creation from a merged list confusing?** Only if the form hides the car. It doesn't: car is the first card, with the rule printed on the mock itself (`ReminderForm.dc.html:27-33`). What makes it unconfusing is the round trip - the saved row returns to the merged list **naming its car** (the VOLVO V60 chip, `RemindersAll.dc.html:43`), so the user sees where it went. With one car in the garage the field still shows: it is the only place that says which car this is about (`SCREENMAP.md:259-260`).
- **One mock change.** `ReminderForm.dc.html` contradicts itself: the caption says "From the merged list nothing is picked for you" while the drawing shows Volvo already selected (line 30). The merged-list variant - no pill highlighted, car required - is the case hard rule 13 hinges on, and nobody has drawn it.

## Sources read

`docs/JOURNEYS.md` (J7-J9), `docs/SCREENMAP.md`, `docs/TASKS.md` (RV.74-RV.79), `docs/DESIGN.md`, `CLAUDE.md` (rules 2, 5, 13, 15); `RemindersView.swift`, `ReminderFormView.swift`, `ReminderBanner.swift`, `HomeBanners.swift`, `HomeView.swift`, `VehicleDetailView.swift`, `CaptureMode.swift`, `ScannedFillUpSheet.swift`; the eight mocks named in the brief.
