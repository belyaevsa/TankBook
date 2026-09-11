# Decisions the queue is waiting on - 2026-09-11

Each row blocks a scenario's status line or a brief. Format: task · problem · why it matters ·
options. The first option is the orchestrator's recommendation. Record the answer in the row's
outcome cell and in `docs/JOURNEYS.md` where the text changes.

## Blocking a scenario's `Status: implemented`

### RV.232 · F1 - the Aftermath (silent improvement-sample queue + onboarding opt-in)
**Problem.** F1's text promises that a failed scan's photo and OCR text are *silently queued* as an
improvement sample, under an opt-in *set once during onboarding*. `PJ.20` shipped a manual
feedback composer in About and was cited as closing this. No code queues a sample.
**Why it matters.** Either the journey lies, or a privacy-sensitive data path is missing. Sending
receipt photos automatically is the kind of thing `SECURITY.md` and hard rule 12 exist for.
**Options.**
1. **Amend F1 to the manual path** (About composer with consent, default off) and mark the silent
   queue a later phase in `VISION.md`. Doc-only; F1 walks to implemented. *(recommended - v1 ships
   nothing that uploads a photo without a tap)*
2. Build it: an onboarding consent step, a queue through `FeedbackOutbox`/`POST /feedback`
   (`PJ.20a`'s server half is unimplemented), shape-only logging, and a `SECURITY.md` amendment
   naming what a sample may carry. One large row, backend included.
3. Build the opt-in only (onboarding moment, no queue) - **not recommended**: a consent for a thing
   that does not exist.

### RV.231 · F9a - "move entry" as the third ranked suggestion
**Problem.** `JOURNEYS.md:665` promises *fix odometer · fix date · move entry*. Only the first two
exist; `PJ.34` recorded *move entry* as not built.
**Why it matters.** The spec names an affordance no screen shows. No user is stranded - the two
fixes plus save-anyway cover every conflict.
**Options.**
1. **Strike *move entry*** from F9a; `ERRORS.md:279` already agrees. Doc-only. *(recommended)*
2. Define it - most plausibly *re-date this entry to the neighbour's slot* - and file a build row
   with an L1 in `TimelineValidator.suggestions` and an L4.

### RV.228 · F6 - the `units` import ambiguity exists nowhere
**Problem.** `API.md` and the model comment document a `units` ambiguity kind; no parser emits it,
no client reads it, `canCommit` checks only `dateFormat`.
**Why it matters.** Vacuously fine (both importers are metric); a silent guessed-units bug the day
an imperial importer ships.
**Options.**
1. **Mark `units` reserved** in all three places, N/A for v1 in F6, bind the three texts with a
   test. Briefed as `RV.228.md`. *(recommended)*
2. Build the once-per-file units question now, with no file that can trigger it.
3. Delete `units` from the wire contract - a breaking-change review for nothing.

### RV.204 · J3/J7 - one screen, two contracts when a photo write fails
**Problem.** On Edit entry, a fill-up's failed photo write BLOCKS and warns in place; a service's
DEGRADES and toasts (the entry saves without the photo). Both report; they differ by entry kind.
**Why it matters.** Same screen, same gesture, same failure, two behaviours. `ERRORS.md` documents
both, which is the tell it was never decided.
**Options.**
1. **Degrade everywhere**: the save the user asked for lands, the photo failure is reported after,
   re-attach is the next step (`RV.202` gives every kind that door). *(recommended - hard rule 8's
   floor is "reported", and a lost save is worse than a lost photo)*
2. Block everywhere: entry and receipt stay atomic; the user retries the whole save.
3. Keep both and write a reason a user would recognise - **not recommended**; none was found.

## Blocking a brief

### PJ.60 · J7b/J7d - `Expense.recurrence` is written nil and read nowhere
**Problem.** The column, the `RecurrenceRule` type and its `Codable` exist with zero function.
`SCHEMA.md` promises a recurring expense (*yearly insurance*); the REMINDER half is met by
`ReminderOffer`, the NEXT-ENTRY half is unbuilt.
**Options.**
1. **Delete the field, type and migration column**; `SCHEMA.md` says the reminder is the recurrence.
   *(recommended - the guard loop closes cleanly)*
2. Keep it as a reasoned `RV.196` exception naming a v1.1 row that will write it.
3. Build the next-entry half now (an expense that re-creates itself on its due date).

### PJ.61 · J7b - `ServiceItem.partNumber` is written nil and read nowhere
**Problem.** Not editable even after `PJ.23`'s item editor. `SCHEMA.md` promises it; the v2 parts
shelf (`PJ.52`) is its natural owner. `RV.207` (the guard blind spot) must land first either way.
**Options.**
1. **Reasoned `RV.196` exception naming `PJ.52`**; the field stays for v2. *(recommended)*
2. A `partNumber` field on the item editor in v1 - one more row on the card, EN+RV.
3. Delete it - loses a v2 seam for nothing.

### RV.115 · J4 - no station brand list
**Problem.** `Газпромнефть`, `ГАЗПРОМНЕФТЬ`, `Gazpromneft` are three stations. Nothing normalises.
`RV.180` (brand + site identity) is its `[v1.1]` sibling.
**Options.**
1. **Defer to v1.1 with `RV.180`**, one row: a curated brand vocabulary (seed JSON, the catalogue
   pattern) plus a case/transliteration-insensitive matcher at station creation. *(recommended -
   J4 stays open, honestly)*
2. Ship a minimal v1 matcher now: case-fold + strip whitespace, no vocabulary. Catches two of the
   three spellings above, not the transliteration.
3. Do nothing; accept duplicate stations in v1 and say so in J4.

### RV.108 · J11a - `GET /v1/account` is normative and does not exist
**Options.**
1. **Delete the row from `API.md`** if no client screen renders storage or quota (the brief tells
   the agent to check first). *(recommended if the check is empty)*
2. Implement it, backend + client, if Account & devices already shows figures that come from nowhere.

### PJ.51 · J1 - the store listing promises what the build does not ship
**Problem.** Both descriptions say *"petrol, diesel, hybrid and electric in one history"* and name
six importers; EV logging is v2 and one importer exists. App Review reads the listing.
**Options.**
1. **Change the words** now: drop *electric* and the `ev` keyword, name the two importers. Doc-only,
   ships with the next build. *(recommended)*
2. Ship the paths - EV logging (`PJ.49`, v2) and four importers (`P5.4b`, blocked on fixtures).
   Not a v1 option.

### RV.181 · J13/J8b - nothing is dispatched to a share destination
**Problem.** Skipped by you on 2026-09-10; hardening shipped (`ae775cf`) so a failed share is now
logged as `failed` with its activity and error code. Cause not established; does not reproduce on
the simulator.
**Options.**
1. **One share attempt from the physical iPhone 13 with a diagnostics export** - the only evidence
   that can settle it. *(recommended; nothing an agent can do)*
2. Close the row as "not reproducible" and reopen on the next report.

### RV.148 · J8 - the monthly-summary push sums a rate-pending month as complete
**Problem.** Deferred by you on 2026-09-09. Two candidate answers already on the row.
**Options.**
1. **Suppress the push while the month has rate-pending rows** - no wrong number leaves the device.
2. Send it with the figure marked *partial* in the body.
3. Keep deferred; J8 stays open.

## Smaller product calls raised by the walks (no row yet)

### F8 - the denied-camera surface is fill-up-only
`deniedLayout` hardcodes `ManualFillUpView`; a denied user must leave Capture to log a service or
expense. **Options:** (1) keep - the mode row belongs to the live camera, and *Type it* from Home
covers the other kinds *(recommended)*; (2) add the mode row to the denied card.

### F6b - only the total is editable on a cross-check mismatch
Volume and price are the marked operands; *Fix* opens the total editor only. **Options:** (1) keep -
the total is the field the file most often misstates *(recommended, say so in `ERRORS.md`)*;
(2) let *Fix* choose the operand, as `F9aFixRow` does for odometer/date.

### RV.138 / RV.158 · F9 - briefed together as `RV.158+RV.138.md`
No decision needed unless the agent finds the pack response cannot carry a coverage floor without
an `API.md` change - then: (1) additive field, documented *(recommended)*; (2) client-side heuristic
only.
