# Tankbook – Customer Journey Maps

*Mobile UX companion to `VISION.md` (features, flows) and `DESIGN.md` (visual language). Each journey names its trigger, walks the stages with what the user does / thinks / feels, flags pain points (⚠) and design opportunities (→), and ends with the metric that tells us the journey works.*

## Scenario status - what "implemented" means here

**A journey is the specification, not a record of what was built.** Its stages and fallbacks are
what the user is promised; `docs/TASKS.md` rows are one team's guess at how to satisfy them, and the
gap between the two is where this project's defects have actually lived.

So a journey carries a **status line under its heading**, and only one thing may write it:

    **Status: implemented 2026-09-10** (reviewed by REVIEW-SCENARIO, <run>)

**No status line means unreviewed**, whatever its rows say. The line is set by the completion review
(`agents/briefs/REVIEW-SCENARIO.md`), dispatched when `scripts/scenario-index.py` reports that every
row naming the scenario is closed - and only on an `IMPLEMENTED` verdict. Ticked tasks are not
evidence: J7's Fallbacks sentence promised *"the user renames/splits by hand"* from the day it was
written, `PJ.23` shipped the rename, and the missing half was found by the product owner opening the
screen rather than by any row, test or review.

**A change to what the user is promised edits this file in the same change**, and clears the status
line: the story that was reviewed no longer exists.

## Personas

- **P1 · The commuter (Andrus, diesel Volvo).** Logs every fill-up for years, has history in another app, cares about consumption trends and typo-free data. Fills up 3–5×/month, often in a hurry, sometimes abroad.
- **P2 · The mixed household (Marta, petrol SUV + family EV).** Wants one place for both cars and one honest answer: what does each cost per 100 km? Charges at home and at public DC chargers.
- **P3 · The CIS driver (Sergei, petrol sedan, RU/KZ).** Receipts always carry a fiscal QR. Expects fines/insurance reminders from local apps, distrusts subscriptions, burned by dead-server apps before.

Journeys are grouped by lifecycle: **acquisition → core loop → periodic → edge/exit**. J2–J5 are the make-or-break ones.

**Version scope** (`CLAUDE.md` → Version scope): a heading without a marker is a **v1** journey – the launch build must complete it. **[v1.x]** and **[v2]** headings are planned journeys that v1 does not promise; their screens may exist as artboards only.

**Reconciled against the ledger:** where a journey's claim overreaches the code, an inline *(PJ.x: …)* footnote names the task that closes it; the reconciliation ledger is `docs/TASKS.md` → PJ.

---

## Acquisition

### J1 · First launch, empty garage
**Trigger:** installed from the App Store after seeing "scan, don't type".
**Goal:** from tap to first logged entry in under 3 minutes, no account asked.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Open | Skips a 1-screen promise ("Point. Scan. Done.") | "Show me, don't pitch me" – impatient | ⚠ Every extra onboarding screen loses users → one screen, skippable *(PJ.3: the Welcome root and its three paths – "Add your car", "Import from another app", "Sign in to Tankbook" – are real since 2026-08-30, behind no `-force*` fixture. **RV.23 (2026-09-03) re-argued that one screen rather than adding a second one:** the third promise no longer says "No account needed" – which pre-empted the decision before the user knew what it cost them – but the two-sided "Your data stays on your phone – an account adds cloud features"; sign-in is a peer button naming what an account buys ("Smart receipt scanning, backups and sync with your other devices" – all free, RV.4) instead of a 13 pt link. **The final copy is the product owner's (2026-09-03) and it deliberately drops the word "cloud"**, which the earlier wording carried: the measurable difference an account makes to scanning is cloud reading (84/96 against 38.3% on-device, P4.12), and the shipped line names the benefit without naming that distinction. Recorded here because it was decided knowingly, not lost – a future rewrite that wants the distinction back should put it in this line rather than add a screen; and "Add your car" stays a peer that continues with no account, because a user who never signs in has chosen correctly.)* |
| Add car | Types make/model or plate, picks powertrain, home currency pre-filled from locale | "That was quick" | → RU locale defaults to ₽ + RU fuel grades; photo of car optional, adds emotional ownership |
| First entry | Prompted: "Have a receipt from your last fill-up? Scan it" | Curious – this is the promised magic | → The first scan IS onboarding; a bundled demo receipt if they have none. **RV.5:** the very first shot is reviewed before anything is read from it - on a first capture the user has no idea what the app does with a photo, and seeing their own receipt on screen with "Use this" is the cheapest possible proof that it went somewhere |
| Payoff | Sees the Pump Card lock ✓, entry saved | Delight or disappointment – nothing in between | ⚠ A failed first scan kills trust permanently → confidence gating, instant manual fallback without losing the photo. The review step is also where a *bad frame* is caught before it can be mistaken for bad recognition |

**Success metric:** ≥70% of installs log a first entry in session 1; time-to-first-entry < 3 min.

**RV.197 (2026-09-11): the first entry is visible without an account.** J1's payoff was unreachable
for a guest - the no-account Home rendered no log at all, so the entry the user had just typed or
scanned saved and then vanished. That is hard rule 1 in its plainest form (*no screen is ever
sync-gated*) and it contradicted the launch commitment that the app is useful before you have an
account. The guest Home now renders the **same** `HomeRecentEntries` stream the signed-in Home
shows, chosen by `HomeLayout.logArea(for:)` from the entry count alone. The Log tab IS Home, so
"on Home" and "in the Log" are one surface, reachable as a guest; only whether data syncs differs.
The empty state is unchanged (the garage card, capture card, import card and privacy line), and
once an entry exists the capture card drops its "first" wording.

### J2 · Switching from another app
**Trigger:** frustration with incumbent (ads, paywalled export, dead sync) + years of history they refuse to lose.
**Goal:** full history alive in Tankbook in one sitting.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Export | Finds export in old app (Fuelio/Drivvo/Fuelly/Spritmonitor/CarScope/My Fuel Manager) | Anxious – "will it all come across?" | → In-app illustrated guide per source app, since their UIs hide export |
| Import | Shares the file to Tankbook (share sheet / file picker) | Skeptical | → Declare the source app, never the format: "Which app is this from?" against the server-driven supported list (`GET /import/formats`). The app never sniffs the file – a format the picker cannot list is a format that does not exist, and a confident mis-mapping is worse than a question (hard rule 13; `ERRORS.md` → Import wizard). **RV.190 (2026-09-10):** the "Not yet" chips beside that list are **derived from the same response**, not written down. Drivvo sat in that row for the whole life of its own working parser, so a user with a Drivvo export was told the app could not read the file it was in fact reading - the picker above and the teaser below disagreed about the same product |
| Map the cars (RV.86, 2026-09-06) | A file whose parse exposes several source cars gets one extra question: **which cars do you want, and into which garage car does each go** (leave out / a new car / an existing one) | "Oh – that export holds all three cars" | → The old apps export per account, not per car: the real MFM export holds **five** cars, and before RV.86 every row landed on one car – the Volvo card read the Audi's 426 220 km. The wizard lists each source car with its own rows/odometer/dates and asks, never guessing by name (hard rule 13). A one-car file never sees the step |
| Name it (RV.185, 2026-09-10) | A lane the user sends to a **new** car offers that car's **name**, pre-filled and typed over, in the same card where the destination is chosen | "It's my Audi, not 'Drivvo'" | → Product owner, importing from Drivvo: *"I wasn't able to set the name of the car. I got default - drivvo."* The suggestion is the name the **file** gives the vehicle, else the neutral `Imported car`; the **format's display name is deliberately not in that chain** – a garage car called after the app you left is not a name, it is a leak of the tool. Editable at the moment it is offered and again in the Garage (hard rule 13), and the rename preserves the synthesized car's id, so fills already classified against that lane keep their destination |
| Verify | Sees preview: N entries, date range, detected currency/units, per-field mapping | Checking their known numbers | → Show *their* lifetime average consumption next to the old app's; matching numbers = instant trust |
| Commit | Confirms; garage now shows full history and trends from day one | Relief, sunk cost transferred | ⚠ Silent unit/currency misread poisons all trends → flag ambiguous rows for review instead of guessing. **RV.185:** the currency the user declared becomes the new car's own home currency, so a KZT import does not land as a log of rate-pending rows against a EUR home nobody chose |
| Read the log (RV.187, 2026-09-10) | Opens the Log and recognises the imported service and expense rows by name | "That's the timing belt, that's the insurance" | → Product owner, on their own import: a screen of rows reading only *Service* and *Expense* is a history you cannot navigate. A service now shows its vendor, else its first named line item (plus a count of the rest), else that item's category; an expense its title, else its category – the bare type name is the **last** resort, never the answer while better text exists. The other half was in the parser: the owner's real Drivvo export leaves the title and note columns empty on every expense and service row, so the **kind** column (`Вид расхода` / `Вид сервиса`) is the only text naming the thing and is now read as a name as well as a category. **One title function serves every surface** (the Log row, the duplicate card, the excluded and flagged lists, Recently deleted), so two screens cannot disagree about what an entry is called |

**Success metric:** import completion rate ≥90% once a file is opened; zero support tickets about corrupted history.

**RV.103 (2026-09-07): "see my imported history" works in place.** Before the reveal, Home's list ended after its newest ~20 rows with no way past them, so a committed decade was present (counted in every derived figure) yet impossible to scroll - the owner hit this on their own 513-row import. Now the Log tab (which IS Home) opens with the newest whole months and grows past a "Show N older entries" row at the list's end, adding whole months per tap until the whole history is shown; the reveal survives a same-car reload and resets on a car switch. A period/year filter is a separate, unbuilt affordance (SCREENMAP.md, the RV.103 note); a month divider's total never changes as the log grows, because a page never splits a month.

---

## Core loop

### J3 · The 5-second fill-up (receipt)
**Status: implemented 2026-09-12** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-J3-2026-09-12b)
**Trigger:** standing at the pump or walking back to the car, receipt in hand. Cold, dark, engine of the queue behind.
**Goal:** logged before the seatbelt clicks.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Open | Lock-screen widget / app opens on capture | In a hurry; one hand holds the receipt | → Camera ready in <1s; auto-shutter on document detect |
| Scan | Points at crumpled thermal receipt | "Will it read this?" | ⚠ Glare, dark canopy → torch auto-suggest; keep the photo regardless of OCR result *(PJ.1: shutter and Photos now feed one pipeline into `ConfirmPrefill` – a real image becomes the prefill, no `-seedConfirmPrefill` fixture in the path.)* |
| Review | Sees the shot filling the screen; "Use this" / "Re-take" / "Type it" | "That's readable – go" *(or: "that's a blur, again")* | → **RV.5**: the missing beat the device walk found - the shutter used to fire and move on with nothing shown, so the frame could be neither seen nor refused. The photo appears **immediately**, before any recognition: OCR runs only on *Use this*, so a re-take costs nothing and the wait is spent on a picture the user accepted. Re-take is the back path (nothing kept); "Type it" is a peer on the same row, never the failure branch (hard rule 15) |
| Confirm | Pump Card pre-filled; cross-check line locks ✓; types odometer, sees "+907 km since last" | Trust building with each correct field | ⚠ One wrong digit typed in odometer ruins consumption → live delta as sanity check; low-confidence fields dimmed until tapped. *(PJ.14: the delta is LIVE – typed > last shows "+N km since last", typed < last warns amber "went backwards", an implied pace over the vehicle's `paceLimitKmPerDay` warns amber "over the limit", equal shows neutral "Same as last"; none of them ever blocks the save, hard rule 13.)* *(RV.71: a scanned fuel kind the car does not offer - diesel on a petrol-95 car, say - warns amber under the fuel row at this moment and never blocks; the scanned kind stays an editable chip, and the grade case (92 on a 95 car) or an undeclared car never warns.)* |
| Done | Save → haptic → "6.8 L/100km – best this year" | Micro-reward; closes phone | → The insight one-liner is the habit hook, not the stored row. **RV.12:** Save also **leaves capture** – the sheet and the capture modal behind it both close, landing on the tab the capture started from with the entry visible. Until RV.12 the camera was on screen again after Save, so a finished entry read as a failed one and a second tap started a second entry |

**Mixed receipt variant:** the slip carries fuel + car wash + coffee. The arithmetic check finds liters × price matching the *fuel line* (not the grand total) – that mismatch IS the detection. The Pump Card shows the fuel block as usual, plus an "Also on this receipt" section listing the other lines, each one tap: add as expense (pre-categorized: wash → `.wash`) or skip as not car-related. Added lines become Expenses sharing the same receipt photo and `purchaseGroupId`; the Log shows them as one grouped moment. If the receipt photo cannot be kept, the whole group still saves – the fill-up and every accepted expense reference no photo at all (never an id the failed write left unreachable), and the one shared toast reports it (RV.173). Fallback: line detection fails → the fill-up saves with the fuel numbers and the receipt attached; the user can add the wash from the entry later ("add expense from this receipt"). *(PJ.2: a scanned save writes the receipt ONCE and references the same `Attachment` id from the fill-up and every accepted expense – the "same receipt photo" above is a shared id, not a copy per row.)*

**AdBlue variant (2026-08-30):** the diesel receipt also lists 10 L of AdBlue. The Pump Card shows the diesel fill as usual; "Also on this receipt" lists the AdBlue line as a **second fill-up**, pre-kinded `.adBlue`, one tap to add - it joins the purchase group and the Log shows one grouped moment with two fills. It never touches L/100 km; Trends shows the car's AdBlue rate (L / 1000 km) once two such fills exist. A standalone AdBlue top-up (a can from the shop) is just a fill-up whose fuel chip reads AdBlue - same door, same sheet (hard rule 15). `SCHEMA.md` → AdBlue.

**The receipt catches up with you (RV.38, generalised by RV.201).** A recognition that finishes
after the fill-up is saved – the cloud reading that outran the 3-second budget, or a reading that
only arrived on the next launch – does not die and does not silently rewrite the entry: it lands in
the **inbox** as a suggestion, "yours vs the receipt", with every field the receipt read that
differs from or fills a blank offered **per tick** and "leave it as it is" the default (hard rule
13). RV.201 made the same inbox serve a **service invoice** (J7) and a **shop receipt** (J7b), so
the catch-up flow is one flow, not three.

**Success metric:** median capture-to-save < 15s; ≥80% of fill-ups logged via capture (not manual form); D30 retention of users with ≥3 captures; mixed receipts with correctly isolated fuel totals ≥95% (wrong grand-total attribution is a stats-poisoning bug). The review step (RV.5) adds one tap to this journey and is worth it: an unreadable frame caught here costs a second, and caught on the Confirm sheet costs a re-shoot after a wasted OCR - so the metric to watch is the **re-take rate**, which should be non-zero (the step is catching real blurs) without exceeding the share of captures that used to arrive at Confirm with nothing resolved.

**RV.197 (2026-09-11): the saved fill-up is on Home even with no account.** J3's Done row promises
the save lands "with the new entry visible"; for a guest that was false - the guest Home rendered no
log, so the entry saved and was never shown again (the J1 note above carries the fix). A scan or a
typed save by a no-account user now lands on the same `HomeRecentEntries` stream a signed-in user
sees, and the entry opens its editor from there.

**RV.208 (2026-09-11): an entry can already carry a photo that was never saved.** The all-or-nothing
fix above stops a group *writing* a dangling id; it cannot reach the rows already on a user's phone
from a build that did. The reference is left in place and Edit entry shows the missing-photo card
with its re-attach next step (J8b) – a sweep cannot tell a never-written row from one a device has
not pulled yet (`docs/SYNC.md` -> Attachments), so deleting it would blank a valid receipt for a
user mid-restore.

### J4 · No receipt – pump display photo
**Trigger:** station prints no receipt / receipt skipped; the pump still shows liters, price, total.

Same shape as J3, with the deltas: camera pointed at the pump display before hanging up the nozzle (→ prompt tip on first use: "no receipt? Shoot the pump"); OCR reads the three numbers, arithmetic triple-match assigns them (⚠ glare/LED segments – the spike's ~95% gate applies before this ships); station name auto-suggested from location + favorites. This journey is **unowned by any competitor** – it must feel as reliable as J3 or not exist.

**Station suggestion – the logic (written 2026-08-30, shipped as PJ.19 [v1.1]).** The station
field is a default input (hard rule 13): the app proposes one, the user changes it in one tap, and
a changed station is theirs. The proposal is ranked, first match wins:

1. a **favourite** station within 300 m of the device (the one ranking field use cannot fill: the
   user sets it on the station in the Garage, PJ.55);
2. the **last-used** station within 300 m;
3. the **most recently used** station for this car, regardless of distance – this rung needs no
   location permission and is what most users get most of the time;
4. nothing – the pick menu's "Choose station", or the **add door** when no station exists (an
   empty station set is creatable, RV.156 - never the dead label this row once was).

Rungs 1–2 need location; rungs 3–4 never do. **Permission is asked on the first Confirm after the
second fill-up** – the earliest moment the question can be answered with a station on file –
never on launch and never before a car exists; denied means the ranking simply runs without its
distance rungs, forever, with no re-prompt. Location is read once per Confirm, while the sheet is
open, and is never stored on the entry – only `Station.location` is written, and only when the
user saves a fill at a station the app has no coordinate for (`SCHEMA.md` → Station). Offline is
a non-event: the ranking is local (F3). Coordinates are Sensitive and never logged (hard rule 12).

**The creation door (RV.156, shipped 2026-09-09).** PJ.19 ranks existing stations and never
creates one, so a user who typed their entries had an empty station set forever and every rung
starved. The row is now interactive in **both** states - an empty set offers "Add station", a
populated set keeps the menu and gains the same entry at its end (a user with one station must be
able to add a second) - and the Garage's Stations list carries the same door (a dashed tile in
both states), so a station can be named wherever the user notices they want one (hard rule 15's
spirit: never a dead end). **A name is all creation asks for**: `defaults` and `location` are
filled by use - RV.150's save already stamps `lastUsedAt`, the bought defaults and a missing
coordinate - never asked up front. **`favorite` is the exception (PJ.55)**: a favourite is a
statement, not an observation, so use never fills it and creation never asks for it either - the
user sets it afterwards on the station's own settings screen (Stations → the station →
**Favourite**), and can clear it there just as easily. Naming goes through the SAME deterministic minting
rule the import path uses (`ImportStationResolver.station(for:)`): two devices typing the same
name resolve to the same id and converge instead of duplicating, and a name that exactly matches
an existing station selects that one - a second row is never minted, so the UI never looks like it
created a duplicate (merging stays RV.115's fence). An empty or whitespace-only name creates
nothing (it is a cancel): a station's row and its Log title live on the name, so an unnamed
station is not creatable. A created station is a synced entity written `.dirty` like any station
edit, and it is **selected on the entry that created it** - the add is never a dead end in slow
motion.

**Implementation note (PJ.19, shipped 2026-09-09).** The ranking above is now a pure core
function (`StationSuggestion`, L1-tested over injected coordinates, no CoreLocation) called once
per Confirm sheet as a default input: it pre-selects the winning station, and pre-fills the
station's recorded last-visit fuel kind when the fuel row is still the sheet's untouched default
and the scan resolved no kind of its own. The permission ask fires **once, ever** (persisted),
only when a prior fill-up is on the car AND a station is on file; a `.restricted` status behaves
exactly like a denial. Rung 3's "most recently used for this car" is derived from the VEHICLE's
fill history – the station of its most recent fill-up that names one – because
`Station.lastUsedAt` is account-level, not per vehicle; rungs 1–2 rank on `Station.location` and
`Station.lastUsedAt`. A suggestion that arrives after the user has picked a station is never
applied (hard rule 13).

**Rung 1's favourite has a writer (PJ.55, shipped 2026-09-10).** Until this row `Station.favorite`
had a reader (rung 1), a column, a decoder and a dozen test seeds - and no production writer, so
rung 1 could never fire. The user now sets it on the per-station settings screen the Garage opens
(Stations → the station → **Favourite**), reversibly; it is the one ranking field the save stamp
never writes and the import path only ever sets to its `false` default, because a favourite is a
statement, not an observation (`docs/SCHEMA.md` → Station).

**The save stamps the ranking's inputs (RV.150, shipped 2026-09-09).** A fill-up saved at a
chosen station now writes the fields rungs 1–2 read: `lastUsedAt` = the save's moment,
`defaults` = what was actually bought there, and `location` adopted from the forecourt fix this
Confirm already read – **only when the station has none** (fill-blanks-only; a coordinate the
station already has is never overwritten, and no fix writes nothing, a non-event). The adoption
is **silent at capture** – no prompt, no toast – by product decision, and it is bounded there:
the coordinate is visible and removable on the station in the Garage (Stations → the station →
**Remove location**), documented in `docs/SECURITY.md`, and never logged (hard rule 12). The
stamp applies to the LIVE station row at save time and rides the ordinary `.dirty` sync path;
a save that changes nothing writes nothing ([RV.136]'s guard, `docs/SCHEMA.md` → Station).

**Success metric:** pump-photo share of all captures (target ≥15% – proves the niche is real); extraction accuracy ≥95% on the confirm screen.

### J3b · Type it (the peer path, every locale)

**Trigger:** the user would rather type than aim a camera - or the camera cannot deliver: a
faded thermal receipt, a dark forecourt, gloves on, a pump display that lost its decimal
points, a corporate fuel-card slip with no QR, or simply a preference.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Reach it | Taps "Type it" - present next to capture on Home, both empty states, the guest layout, inside Capture and on the **capture review step** (RV.5) | "I don't have to fight the camera" | → **Never behind a failed scan.** Reaching manual entry must not require attempting a capture first (hard rule 15). On the review step it sits beside Re-take at the same size, so a user looking at a bad photo picks between two equals rather than being handed a consolation prize |
| Fill | Types total and litres; price derives; odometer pre-filled from last known | Fast, predictable | → Same `ConfirmManual` sheet the capture paths land in - one screen, not a lesser one. Inside Capture, "Type it" opens the form for the **selected mode** (PJ.6): Service → ServiceEntry, Expense → ExpenseEntry, Fill-up → ConfirmManual |
| Save | Saves | "That was quicker than scanning" | → The cross-check locks exactly as it does for a scan. Typed **inside capture**, Save leaves the capture modal too (RV.12), exactly as the scan door does – the peer path cannot be the one that strands |
| Later (PJ.48, **[v1.1]**) | Finds the receipt in a pocket, opens the entry, taps "Add receipt" | "I can still keep the paper" | → The typed door is a peer, so its entries can carry the receipt too: attach from camera or Photos on Edit entry; OCR may then **fill blank fields only**, never overwrite a typed value (hard rule 13). The paperclip appears in the Log like a scanned entry's |

**Why this is a journey and not a fallback.** A capture-first design punishes the user on every
capture the camera cannot serve, and the measured corpus still says that is common. **Re-measured
2026-09-05** (this paragraph was written against 38.3% / 0% / 9-of-16): receipts resolve **188 of
220 asserted cells (85%)**, yet only **33 of 48 receipts (69%) come out with every cell right**;
**pump displays commit 24 of 178 numeric cells (13%)** and that mode ships off; Vision still
misreads digits at **confidence 1.00**; and a fiscal QR exists on **22 of 48** real receipts while
carrying only 2 of 5 fields. So roughly a third of receipt captures still need the user to correct
something, and making typing the punishment for a failed scan would make the app feel broken
precisely when it is being honest about uncertainty.

So the two paths are peers, and a capture is a **head start rather than an answer**: everything
it produces is a default input the user edits (hard rule 13), which means a thin scan degrades
to "correct two fields", never to "start over". J3 and J3b converge on the same sheet by
design - a user who typed and a user who scanned are editing the identical screen.

**Success metric:** manual entry is reachable in one tap from Home in every state; median
manual save time under 20 s; and no growth in abandoned captures - a user who backs out of a
scan should land on a filled-in manual form, not an empty one.

### J5 · The RU/KZ receipt (P3) – the fiscal QR as an anchor, never a feature
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-J5-2026-09-11b)
**Trigger:** a fill-up receipt in Russia or Kazakhstan; the FNS/ОФД QR printed on it is decoded as part of the same receipt scan. The user never "scans a QR" and the app never says it does (`VISION.md`, decided 2026-08-30).

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Scan | Scans the receipt exactly as in J3 | Nothing new to learn | → The QR is found on the receipt image by the same capture; no mode, no chip, no mention |
| Anchor, not fill | **Total and date land exact from the QR; litres, price and fuel kind still come from OCR** and stay editable | Quiet confidence: the money is right | → The QR confirms or corrects the OCR total, and a QR total *above* the extracted fuel line is the mixed-receipt signal (hard rule 4) |
| Confirm | Check the OCR'd litres and price, odometer, save | Fewer corrections than before | → Never claim "exact" for a field the QR cannot carry |

**Corrected 2026-08-24.** This journey used to promise "all fields land exact – no OCR
uncertainty" and a "100% correct, free" beat. **The QR cannot deliver that**: it carries only
timestamp, total and three fiscal ids, and the OFD lookup that would supply litres and price is
keyed on an id not derivable from the QR (verified against two OFDs). Only 9 of 16 corpus
receipts carry a decodable QR at all. Enrichment is permanently deferred, so J5 is now the
*anchoring* journey, not an exact-fill one - and **F5 below is the normal path, not the failure
path.** Evidence: `Spike/ReceiptSpike/fixtures/fiscal/README.md`.

**Success metric:** in RU/KZ locales, where a QR is present the saved total matches the QR in
≥99% of fill-ups, and the user corrects the total by hand in <5%. (The old ">=60% QR share of
captures" metric assumed QR was a capture path; it is not.)

### J6 · EV charge (P2) **[v1.x]**
**Trigger:** public DC session ends in a charging app; or the weekly home-charging ritual.

- **Public:** share the charging app's receipt screenshot to Tankbook (share extension) → same confirm card, in `headlight` cyan, kWh instead of liters → saved against the EV. ⚠ Dozens of charging-app layouts → the LLM-normalization layer earns its keep here; screenshots are the one place cloud fallback will be common.
- **Home:** quick-entry "home charge" with kWh from the wallbox (or charge % delta → kWh via battery size) × stored home tariff. → Tariff lives in vehicle settings, one-time setup; night/day tariff split later.
- **Payoff:** Trends shows both household cars in €/100 km on one chart – the moment Tankbook does what no competitor does.

**Success metric:** % of EV owners logging ≥4 sessions/month; the comparison screen's weekly views.

### J7 · Service visit
**Trigger:** leaving the workshop with a multi-page invoice, or DIY oil change in the garage.

**The manual door (RV.61, hard rule 15):** typing is a peer path, never a camera fallback. The same form is reached with no camera from Home's header - "Type it" → its menu → "Service" opens the empty `ServiceEntryView` (odometer pre-filled from the last known value, editable). A capture is a head start, never a gate.

Scan invoice (document camera, multi-page) → the **deterministic parser** splits line items ("oil service", "brake pads front") into categorized records with attachments, with the opt-in cloud LLM (tier 3) as the only model-assisted path. *(The on-device model was the original plan here; tier 2 was **cut on 2026-08-25** because Foundation Models has no Russian - `docs/VISION.md` -> "Why tier 2 was cut". Invoices are messier than receipts, so this makes the manual split path load-bearing rather than a fallback.)* → app proposes the *next* reminder from item lifetimes ("Oil change in 15,000 km or 12 months?") → accept = the maintenance loop closes itself. ⚠ Invoices are far messier than fuel receipts – expectations set accordingly: pre-fill what's confident, never fake precision. P3 addition: insurance (ОСАГО) expiry as a first-class reminder type.

**Fallbacks:** OCR can't split the invoice → the *same screen* holds one uncategorized item with the full total; the user renames/splits by hand or leaves it as "Annual service · 148 €" – a lump sum with the bill attached is a perfectly good record (never force itemization). No invoice at all (DIY) → manual line items, parts pulled from the shelf (J7b). Unknown category → `.other` with free text, promoted to a real category later without data loss. Odometer: pre-filled from the last known value (usually right, the car was just driven there) – one glance to confirm, editable. It anchors a km lifetime and a mounted tire set's mileage: a mounted set must carry it to save, while a km lifetime with a blank odometer still saves and the reminder offer names the missing odometer (RV.212) – the create and edit doors accept the same pair.

**The record names itself (RV.187, 2026-09-10).** Whatever door it came through - scanned, typed or
imported - a service in the Log shows its **vendor**, else its first named line item plus a count of
the rest, else that item's category; the bare word *Service* is the last resort, never the answer
while better text exists. This matters most for the lump-sum fallback above: "Annual service · 148 €"
is a good record only if the row actually says *Annual service*. One title function serves the Log
row, the duplicate card, the excluded and flagged lists and Recently deleted, so no two screens can
call the same entry different things.

**The create gate accepts what the Log can name (RV.214, 2026-09-12).** The create screen used to
demand a **titled** line item, which refused a record the Log could already name: a vendor-only
service, and the invoice splitter's honest fallback - one untitled line carrying the whole total,
named by its category. The rule is now **one function both doors call**: a vendor, or a single line
item (titled or categorised), makes the record; a wholly blank service is refused and the disabled
Save names the missing step. So the scan fallback above is a first-class record on the door that
produces it, not only after a save-and-reopen, and the create and edit doors cannot disagree about
what a service is.

**[v1.x] Editing the work (PJ.23, 2026-09-10; add/delete RV.198, 2026-09-10; lifetime PJ.22,
2026-09-11; part number PJ.61, 2026-09-12).** Opening a service in Edit entry shows its **line
items** - title, category, cost, **lifetime** and **part number** - and writes them back, so the
`.other` promotion promised above happens where the user can see the text [RV.187] titles the row
from. The user can also **add a line and delete one**, not only correct the rows that exist: a
workshop invoice gains a line as often as it corrects one. An **empty item list is legal** - a
vendor plus a lump-sum Amount with no itemised lines is the same lump-sum record the scan fallback
produces, so deleting the last row leaves it rather than being forbidden. The item's **lifetime**
(km and months) is the one field that drives the next reminder: setting or changing it and saving
raises the same "Remind you next time?" offer J7d describes, anchored at the record. The item's
**part number** is optional free text on the same card (PJ.61, v1): a blank field stores no part
number, it is keyed to the row it was loaded from so a delete never shifts it onto a neighbour, and
it is editable at the moment it is offered and again afterwards (hard rule 13).

**[v1.x] The total and the lines agree, or say why not (RV.199, 2026-09-11).** The record's
**Amount stays independently editable**, because an invoice's grand total legitimately differs from
its lines - tax, a discount, a line the user did not itemise (the same truth hard rule 4 encodes
for fuel) - and a total the user set is theirs (hard rule 13). What the screen no longer does is
stay silent: the money card states the **line sum** beside the Amount, in amber when the two
disagree, and never a summed cross-currency figure (hard rule 3 - a set of lines in two currencies
shows the per-currency breakdown instead). The sum is the same one the create screen's header
derives, so the two doors cannot state different totals for the same service. The mismatch is
attention, never a gate: nothing is wrong and Save is never blocked.

**The receipt can be given, not only shown (RV.202, 2026-09-11).** Opening a service in Edit
entry shows the same receipt strip a fill-up has. An entry that already carries a photo shows it -
view, replace and delete live there (J8b) - but an entry that arrived **without** a photo used to
show no card at all and had no way to gain one. It now offers **Add receipt** through the same
camera/Photos door the fill-up uses (hard rule 15 - typing and scanning are peers). Attaching is
**local**: the photo is written to the shared pool when Save runs and nothing here touches the
network (hard rule 1). A write that fails never blocks the save - the service still lands without
the photo, and the shared "could not be kept" message says so **after** the entry is on disk (hard
rule 8, docs/ERRORS.md -> Confirm, RV.149), the same contract an expense already had. **The fill-up
edit obeys the same contract (RV.204)**: every entry kind on this screen degrades, so the save the
user asked for is never lost to a storage failure, and re-attach is the next step.

**A late invoice reading reaches the same inbox (RV.201, 2026-09-11).** The per-field "yours vs the
receipt" ask is no longer fuel-only: a service recognition that finishes after the record is saved
lands in the **inbox** with the service's own fields – its **vendor**, each **line item** and its
**total** – offered per tick, "leave it as it is" the default (hard rule 13). The merge is ONE
function over the entry kind (`GatewayInboxPolicy.merged`), so a fill-up, a service and an expense
cannot drift into three implementations. The attach-path merge (PJ.48, blank-fields-only) is
unchanged and separate: it fills blanks silently at attach time, while a DIFFERING value from a
late reading is offered and never applied. **The producing side is deferrable (RV.215,
2026-09-11).** A service scan no longer awaits its OCR before the form opens: the read runs in the
background and the form opens on whatever is available, so a read that finishes before the save
fills the open form and one that finishes after it becomes the inbox item above, through the SAME
`GatewayInboxPolicy.item(recognition:entry:)` the fuel path uses (one policy, never a second
producer). The **cloud** half - carrying a service or expense reading through the delivery outbox -
stays fuel-shaped and is **[PJ.29]**'s; the device-local half is this row. **The captured pages are
persisted when the scan starts (RV.243, 2026-09-12):** a record saved before the read finishes still
keeps its invoice, and the late read only offers values - deferring a reading never costs the user
the pages the shutter already captured (hard rule 8).

**Success metric:** ≥50% of service records carry an attachment; reminder acceptance rate ≥60%.

### J7b · Parts, tires, consumables
**Trigger:** a filter ordered online, brake pads bought on sale, a winter tire set – purchased *now*, installed *later* (or never; the car is sold with the shelf).

| Stage | Doing | Notes |
|---|---|---|
| Purchase | Scans the order confirmation / shop receipt → Expense `.parts` ("MANN W 712/75 · 12.40 €") | Odometer not asked – the car isn't even present. Cost counts in totals from day one |
| Shelf | The part sits visible under Garage → "Parts shelf" with an "on shelf" state | ⚠ Silent shelf = forgotten parts → the next matching service suggests them |
| Install | Creating a service record, app offers shelf parts: "Install oil filter from Mar 3?" → link, don't re-price | Cost counted once (at purchase); the service shows the part via link. No double counting in cost/km – the F-series equivalent sin here is a part priced twice |
| Tires | A tire purchase becomes a TireSet; each seasonal swap (a small ServiceRecord) marks which set went on | Set mileage derives from odometer spans between swaps – "Winter Nokian: 18 400 km" answers the real question (are these tires done?) plus the swap reminder each season |

**The swap reminder is born from the mount.** A tire mount (a `ServiceRecord` carrying
`tireSetId`) proposes a `.tires` reminder anchored at the mount date, recurring by
`ReminderOffer.seasonalSwapMonths` (6 months) - the same post-save offer J7d describes, never an
auto-create (hard rule 13). It is the one `.tires` offer there is: a tire line item has no universal
cadence, and a live `.tires` reminder on the car suppresses a second. The user stops the season the
way any reminder stops - **Dismiss** (keeps the row with a reason, feeds the anomaly logic) or
**Delete** (a tombstone with the 30-day undo) from the row's own menu.

**Fallbacks:** part logged without a receipt → plain manual expense, one field + price. User skips the shelf entirely and just types parts inside service records → works fine, the shelf is an optimization, never a gate. Tire mileage without logged swaps → unavailable, shown as "–", never estimated.

**The Expense capture door (RV.62, extended RV.200):** scanning a shop receipt in Expense mode
runs the same recognition as a fill-up but pre-fills only **total, currency and date** into the
expense form's VALUE fields – a shop receipt has no liters or fuel kind, and those fields are
dropped at the extraction → pre-fill boundary (`ExpensePrefill`, core), never offered. The scan
also reads the **kind** of expense when its words say so – a parking ticket, a toll, a car wash,
an insurance invoice – and offers it as the category pre-selection, editable at the moment it is
offered and afterwards (hard rule 13). Merchant is not guessed, and an unrecognised kind opens
the form at its default and says nothing: a suggestion the user can always change, never a fact
presented as one. A scan that reads nothing opens the EMPTY expense form with no error (hard
rule 7), the same contract the fill-up path honours. The amount is offered only when the
receipt's currency is nil or is the car's home currency – the expense form cannot express a
foreign total, so one is never offered as if it were home money (hard rule 13: a wrong fact is
worse than none). The form saves on the **amount alone** (RV.206): the category always has a
value, and the Log row is named from it when the title is empty (RV.187), so a scan that read the
kind and the total is a complete entry. A title stays available and is still a peer way to name
the row - it is simply never demanded (hard rule 15).

**A late shop-receipt reading reaches the inbox (RV.201, 2026-09-11).** When an expense
recognition finishes after the expense is saved, the inbox offers what RV.200's recognition
produces – the **amount** and the **category** – as per-field ticks against what the user saved,
"leave it as it is" the default (hard rule 13). A differing amount or category is offered, never
applied on its own; the same merge function serves the service and fill-up kinds, so the three
cannot drift. **The producing side is deferrable (RV.215, 2026-09-11):** an Expense-mode scan runs
its read in the background, so the form opens before the recognition lands - a read that finishes
before the save fills the open form, and one that finishes after it reaches this inbox through the
one policy. **The photograph is persisted at save whether or not the read has finished (RV.243,
2026-09-12):** the late read only offers values, and losing the receipt a scan already captured is
never a trade the deferral makes (hard rule 8).

**Success metric:** shelf-suggested parts accepted ≥40%; tire-swap reminders acted on ≥70% in season.

---

## Periodic

### J7d · A reminder is born **[v1.1]**

**Trigger:** insurance lands in March, the oil was just changed, or the driver has never made a
reminder and has to find the feature at all. J7c covers what a reminder does once it exists; this is
where it comes from, and until 2026-09-05 it was the journey nobody had written - which is how the
only trigger ended up at the bottom of a list four taps deep.

| Action | What happens | Notes |
|---|---|---|
| **Plan it** | Home's permanent "Reminders · N due" row (present whether or not anything is due) → the merged list → "New reminder" → the form, with the **car as its first field**. From the merged list nothing is picked and Save waits for the choice; from a car's own list or Vehicle detail the car arrives filled in and still changeable | A silently defaulted car is a hard-rule-13 bug: on that screen the user may not have looked at a car at all. The count is what earns the row its tap; creation waits one hop behind it, because a "+" on the row could only guess. *(RV.75 built the merged list - every row naming its car, active cars only - and the form's car-first rule. **RV.76 built the permanent Home row this row starts from** - `HomeRemindersEntryRow`, under the banner on Home, with the count derived from the same live rows the merged list groups.)* |
| **Just did it** | Saving a service or expense record whose category has an interval → after the save lands, "Remind you next time?", pre-filled from the record: its category, its date, its odometer, with the interval editable in the same breath. A **service line item's own lifetime** (PJ.22, the km/months editor on Edit entry) states that interval directly, so "oil in 15,000 km or 12 months" is the user's number rather than a category guess | An offer, never an auto-create. Suppressed when a live reminder of that category already exists on that car - that is how a user ends up with three oil reminders. Anchored at the record, never at today, so a schedule cannot drift. Never mid-save; declining costs nothing. *(RV.77 built this door - `ReminderOffer` in core, the offer sheet over the surface the record saved from. The interval suggestion is the driving item's own `lifetime` when it has one, else a curated per-category default - oil 15,000 km/12 months, insurance 12 months - a compiled constant the user edits in the same breath, never a fact. A category with no curated interval (brakes, tires, battery, filters, inspection, repair, parts, wash, custom, other) offers nothing unless an item states a lifetime.)* |
| **Discover it** | Zero reminders: the Home row still reads "Reminders", the empty list explains what a reminder is for, and its **one action is a filled button** - not the dashed card that means "add one more" at the end of a populated list | This is the path that did not exist, and **RV.76 built it**: the row is always present, count or no count, and a driver with no reminders at all reaches the empty state (`RemindersEmpty.dc.html`) whose filled "New reminder" is the discovery action. Before RV.76 the Home banner rendered only inside the attention window (`ReminderBanner.bannerReminder` filters to `.attention`), so a driver with nothing due had to already know the screen was there. J9's anomaly card is a fourth, incidental birth |
| **Save** | The reminder lands in the list it was created from, **naming its car**, the notification arms, and it sits under Scheduled until its window opens - where J7c takes over | The round trip is what makes per-car creation from a merged list unconfusing: the user sees where the reminder went |

⚠ Birth is where silent guesses live - a defaulted car, a suggested interval dressed as a fact, a
reminder created as a side effect of saving a record. Every value here is a proposal the user can
change when it is offered and again afterwards (hard rule 13), and once changed it is theirs.

⚠ **The whole journey was gated on the calm path existing, and RV.76 closed that gate.** Before the
permanent row, a driver who was not already overdue reached the only trigger through Garage → car →
Reminders → scroll, and one who had never made a reminder had no idea the screen existed. The row
now sits under the banner on Home whatever the count - so the surface that should say "plan your
March insurance" is reachable exactly when the user is calm enough to plan, and its count keeps the
"two things this month" promise even when nothing is late yet.

**Success metric:** ≥50% of reminders are born from the post-save offer rather than the form – the
loop, not the screen, is the engine; offer acceptance ≥60% (J7's existing bar); and ≥50% of users
with a live car hold at least one active reminder within 30 days of first launch.

### J7c · Reminder lifecycle
**Trigger:** the "Oil change" reminder fires – or the user just did the thing early.

*(RV.74: a fired reminder's TAP lands on the merged all-cars list - every active car in one
list, the tapped reminder's completion sheet surfaced over it - never on a car-scoped screen,
which is how a reminder on the non-selected car used to vanish as a "stale tap". The tap selects
the reminder's own live car first, never an archived one, so the app context - and "Type amount",
which logs to the selected car - follows the reminder; a deleted reminder still lands on the plain
list, hard rule 7. `docs/SCREENMAP.md` -> "Reminders across cars".)*

*(RV.78: a fired reminder is actionable FROM THE BANNER, so snoozing beats ignoring at the red
light. The banner's two actions are **Mark done** and **Push a week**
(`design/screens/ReminderNotification.dc.html`): Mark done opens the app on the completion sheet
rather than completing silently - declining the cost log is first-class but it stays the user's
choice, exactly as the sheet below makes it - and Push a week defers by seven days and re-arms,
needing no screen. Both route through the same lifecycle the Reminders screen uses, never a
second implementation; what "a week" defers and how an odometer-only reminder behaves are written
in `docs/NOTIFICATIONS.md` -> the actions.)*

| Action | What happens | Notes |
|---|---|---|
| **Complete** | Sheet: "Done! Log the cost?" → one tap opens the service/expense entry pre-filled (category, title, today, current odometer); scan the invoice or type a lump sum. Then: "Next oil change in 15 000 km or Aug 2027" – the next cycle is already scheduled, anchored at *completion* (not the original due date, so schedules never drift) | Declining the cost log is first-class – completion never forces bookkeeping (.done without entry) |
| **Reschedule** | Push the due date/odometer; a fired notification re-arms | For "next month, honestly" moments – snoozing beats ignoring |
| **Delete** | Gone (tombstone, 30-day undo like everything) | Distinct from **dismiss-with-reason**, which keeps history and teaches insights ("sold the tires") |

⚠ The completion→entry→next-cycle chain is where competitors leak: a reminder marked done with no record and no follow-up is a dead end (Drivvo's pattern). Ours is a loop. *(PJ.4: Reminders has a production entry point – the Home banner derives from real reminders and VehicleDetail carries a reminders row, so this journey is reachable in a Release build.)*

**Success metric:** completed reminders that create an entry ≥50%; recurring reminders auto-rescheduled 100%.

### J8 · The monthly glance
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-J8-2026-09-11c)
**Trigger:** idle curiosity, end of month, or the "August: €212 on the Volvo" notification (opt-in).
**Journey:** open Trends → hero consumption metric with trend arrow → monthly spend bars → price-per-liter line per station brand ("Shell costs you 4% more than Neste"). Feeling sought: *control*, not accounting homework. → Every chart answers a sentence-shaped question; no chart junk. Exit within 60 seconds, satisfied.

**Success metric:** ≥40% of MAU open Trends monthly; session length short (it's a glance, not a report).

### J8b · Look at the receipt again (RV.9, RV.17, RV.37, RV.202)
**Trigger:** a figure is questioned weeks later – "did that fill really cost 71.02?" – or the paper is gone and the photo is the only record.
**Journey:** Log → the entry → the receipt strip's chip is a **tap target**, not decoration → the photo opens full-screen, fitted, and pinch or double-tap magnifies it to read a printed line the 44x56 chip could never show. A PDF invoice opens in the PDF viewer instead of a blank frame. When the full rendition has not reached this device, the viewer shows the payload's thumbnail from the first frame and says so, naming the next step – it never shows an empty screen and never blocks the entry (hard rules 1 and 7). If the receipt carried anything recognised, a second page beside the photo shows what was read (the OCR lines and the scan timestamp) – a swipe away, not chrome over the photo, and absent when there was nothing. The Share affordance (RV.17) hands the **full** rendition to the system share sheet – Save Image, Save to Files, share to apps – and is offered only once that rendition is local, never over the thumbnail; sharing is the user's deliberate act. Close or swipe down and the entry is exactly as it was, still editable. An entry that arrived without a receipt offers **Add receipt** on the same strip (RV.202), so the photo this journey is about can be supplied after the fact, not only viewed. An entry that references a photo that was never saved - the dangling id RV.173's failed grouped write left – shows **"The photo for this entry was never saved"** with the same Add receipt door (RV.208); the reference stays because a device mid-restore cannot tell a missing row from one it has not pulled yet (docs/SYNC.md -> Attachments).

**Delete and replace (RV.37):** the viewer also offers **Delete** – system-confirmed, which removes the receipt from this entry and tombstones the attachment record for the 30-day window (the blob itself is left alone; reclamation is a separate concern) – and **Replace photo**, which opens the same camera/Photos door as "Add receipt", writes a **new** attachment and tombstones the old one (never an in-place mutation, so the 30-day undo has something to restore). The replace then asks – *"Re-read this and update the entry?"* – and "Leave it as it is" is the default: a silent re-read would overwrite values the user already confirmed, which hard rule 13 forbids. On an explicit "Update entry" the extracted values are still suggestions filling **blank fields only**, each dimmed until tapped. "Use a different receipt" is just replace again.

**Success metric:** the receipt can be read without leaving the app or hunting for the paper; opening a photo never ends in a blank screen.

### J9 · Anomaly nudge
**Trigger:** app-detected consumption drift ("+12% over 3 months").
**Journey:** gentle `warn`-amber card in the Log (never a push alarm) → tap explains the evidence (chart of the drift and what it costs per month at the driver's own recent prices – never a guessed cause, RV.121; the app cannot see a motorway week, an idling hour, a tow or a different driver, docs/VISION.md → "What we will not tell a driver") → dismiss ("it's winter") teaches the model, or act → creates a service reminder. ⚠ False alarms erode trust fastest → thresholds conservative, seasonality-aware, always dismissible with a reason.

**Success metric:** anomaly cards acted on or explicitly dismissed ≥70% (ignored cards = noise signal).

### J10 · Cross-border trip (P1)
**Trigger:** filling up in Poland with a Euro-currency car.
**Journey:** scan as always → currency auto-detected as PLN from the receipt → card shows both: "289.50 zł · ≈ €67.79" (converted at the entry-date rate – `rateDate` is the entry's date, never "today", hard rule 3) → saved with the historical rate snapshot; trends stay in the car's home currency, original always preserved on the entry. No settings visited at any point.

**Success metric:** multi-currency entries with zero manual currency picks.

---

## Edge & exit

### J11a · First sign-in (there is no "registration")
**Trigger:** the user wants a second device, or taps "Sign in to sync" in Settings – typically weeks after installing, with a local log already on the phone.

| Stage | Doing | Notes |
|---|---|---|
| Choose | Sign in screen → Apple or Google, one tap | No form, no password, no email verification – the provider's verified token IS the registration (`POST /auth/session` creates the account on first sight). The word "register" appears nowhere in the app |
| Create | Backend finds no account for this identity → creates it | Invisible; same screen, same tap as a returning sign-in – the user never has to know which case they are |
| First push | The local log uploads (everything becomes the account's record stream) | Settings card flips to "Synced just now · 1 device". Nothing on the phone changed – sync added, not migrated. The upload is a **user-initiated** sync that runs BEFORE the sheet closes (`SignInFirstPush`, PJ.13): it must never be a background cycle, because Low Power Mode defers those and a first push the user just asked for must not wait. It pushes **only** on the two completion paths (local log present; empty restore accepted); the wrong-provider path never pushes into an account the user has not accepted |
| Confirm | "Your garage now follows your account" | One line, no ceremony – the account card shows it (with the device count) right after the first push. *(RV.54, product owner, 2026-09-04: the device count counts LIVE devices only – it answers "how many devices can reach my data", a revoked device's next pull gets 410 so it does not count, and a revoke therefore visibly decrements the number. The revoked rows stay in the Account & devices list, marked – the number changed meaning, the list never loses history. `docs/SYNC.md` -> The Settings sync surface.)* |

**⚠ The wrong-provider trap:** the user signed in with Google on Android but taps Apple on the new iPhone → two identities, two accounts, and the "restore" finds an empty account. v1 ships **no account linking**; two mitigations. *Proactive:* the Sign in screen carries a warn-amber notice at the decision moment – "Pick one and keep it. Apple and Google create separate accounts – use the same one on every device." *Reactive:* honest detection – if the signed-in account is empty *and* the user came through "Already use Tankbook?", say "Nothing is stored under this Apple ID. Last time, did you sign in with Google?" with a one-tap provider switch – never show an empty garage as if their data were gone. (Same guard in reverse when a local log exists: J11a never overwrites local data – it uploads it.) *(PJ.3: "came through 'Already use Tankbook?'" is now REAL – the Welcome root carries the restore intent, so a fresh install over an empty account asks the honest question; the `-signInWrongProvider` fixture that used to stand in for it is retired. **RV.23:** since Welcome now offers a general-purpose "Sign in to Tankbook" door too, the intent is carried by **which door was tapped** – only "Already use Tankbook? Restore your garage." passes `arrivedViaRestore: true`. The peer button passes `false`, so a brand-new user whose account is empty *because it is new* lands on the F7 empty-restore screen and is never asked about a previous sign-in they never made.)*

**Success metric:** first-sign-in completion ≥90% from the Sign in screen; wrong-provider recoveries resolved in-flow ≥95%; zero "my data disappeared" reviews traced to provider mix-ups.

### J11 · New phone / platform switch
**Trigger:** bought a new iPhone – or, later, moved to Android.
**Entry points:** on a fresh install, the Welcome screen's restore line – "Already use Tankbook? Restore your garage." – exists precisely for this (an Android→iOS migrant or a reinstall must never be funneled into "Add your car" as if they were new); on a running app, Settings' account card.
**Journey:** Welcome → Sign in (Apple ID / Google – the same account works across platforms, that's the whole point of the neutral identity) → the "Welcome back" restore screen shows the F7 verification stats *before* finishing (cars, entry count, date range, last odometer with its source device – "from your Android phone, yesterday") → text records land in seconds, the garage is immediately usable, photos download in the background by recency → "Open my garage." ⚠ The category's graveyard moment (Fuelly, Мой Авто) → restore must be boringly reliable, tested in CI, and the local file export always available as the user-held fallback.

**Success metric:** restore success ≥99.5%; zero data-loss reviews – the reviews that kill this category.

### J12 · Second driver (family car) **[v2]**
**Trigger:** both partners fuel the same car.
**Journey (v2):** owner shares the vehicle (backend vehicle-sharing over the sync protocol – `SYNC.md` phasing) → partner accepts, sees the same log; both capture; entries show who logged them → consumption math merges both drivers' fill-ups seamlessly. ⚠ Odometer entered out of order by two drivers → sort by odometer, not timestamp, and flag impossible sequences as `warn`.

**Success metric:** shared vehicles ≥10% of active garages; conflict-flag rate <1% of entries.

### J13 · Selling the car
**Trigger:** the Volvo is going to a new owner.
**Journey:** Garage → vehicle → "Export history" → a clean PDF service-and-fuel dossier (resale value in paper form) plus CSV/JSON → then archive the car (history retained, out of active stats). → The dossier is a quiet marketing artifact: it carries the app's name into a stranger's hands at the exact moment they acquire a car. **Landed 2026-08-30 (PJ.38):** the per-car export row now shares the CSV files (fill-ups, charge sessions, service, expenses - flat rows with the money pair and ISO dates) as their own share items, inside the archive too; the **PDF dossier is PJ.37 (v1.1, deferred)**.

**Success metric:** exports per archived vehicle; installs attributed to dossiers (long-shot, but trackable via QR on the PDF).

---

## Failure journeys

*The unhappy paths, mapped with the same care. Design stance: a failure is a fork in the journey, never a dead end – the user always leaves with their data logged and their photo kept. Copy follows DESIGN.md voice: say what happened, say the next step, never apologize, never modal-panic.*

### F1 · Scan recognized nothing (or almost nothing)
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F1-2026-09-11c)
**Trigger:** faded thermal receipt, receipt in a language/layout we've never seen, shot too dark.

| Stage | Experience | Design rule |
|---|---|---|
| Capture | Shutter fires, brief processing shimmer (<2s) | Never a spinner longer than 2s – commit to an answer |
| Verdict | Pump Card opens **empty but alive**: photo attached at top, fields blank, keyboard already up on Total | ⚠ The failure state IS the manual form – same screen, zero navigation, no "recognition failed" error banner. A quiet caption: "Couldn't read this one – type it, the photo stays attached." |
| Recovery | User types 3 numbers (total, liters, odometer), price/unit auto-derives, saves | Typing 3 fields ≈ 20s – degraded, not broken. The receipt photo remains as evidence. *(PJ.2: the photo survives the save – a scanned save persists the receipt as an `Attachment` with scan provenance, whatever the OCR resolved.)* |
| Aftermath | **[v2]** Photo + OCR text silently queued as an (opt-in) improvement sample - deferred with the cloud-OCR consent surface (product owner, 2026-09-11: v1 cloud OCR has no opt-in/opt-out; it is on by default). **v1**: the manual path - About & feedback → the composer, consent default off (`PJ.20`) | → **[v2]** Opt-in "help improve scanning" set once during onboarding |

**Metric:** save-completion rate after failed scans ≥85% (users finish manually instead of quitting).

### F2 · Scan recognized *wrong* data – the most dangerous failure
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F2-2026-09-11b)
**Trigger:** OCR misreads 42.30 as 12.30; a VAT line mistaken for the total. Unlike F1, the user may not notice.

| Stage | Experience | Design rule |
|---|---|---|
| Detection | The cross-check line refuses to lock: liters × price ≠ total | The arithmetic check is the safety net – this is why it exists |
| Surfacing | Mismatched field gets a `warn` amber underline + "these don't multiply up – check the amber field" | Never auto-"fix" by recomputing one field silently; the app doesn't know which one is wrong |
| Recovery | User taps the amber field, sees a crop of the receipt region it was read from, corrects it | → Showing the source crop turns correction into verification – seconds, not archaeology |
| The residue | If all three numbers are wrong *consistently* (rare), the cross-check passes falsely | ⚠ Accept residual risk; mitigate with the odometer delta ("+3,407 km since last?" flags the absurd) and consumption outlier check on save |

**Metric:** corrected-field rate tracked per OCR version (rising = regression); zero support tickets about silently wrong totals.

### F3 · No internet at the pump
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F3-2026-09-11)
**Trigger:** underground garage, roaming disabled abroad, rural dead zone. The most common "failure" of all – and by design, a non-event.

- Capture, on-device OCR, parsing, cross-check, save: **all work identically offline.** The user should be unable to tell.
- What silently defers: currency conversion for a foreign receipt (entry saves with original amount + "rate pending" chip, converts on next connectivity – trends momentarily exclude it from home-currency sums), station auto-suggest from maps (favorites still work – they're local), backup upload (queued).
- The one visible seam: a foreign-currency entry shows "≈ – · converts when online" instead of the home amount. `inkSoft`, not `warn` – nothing is wrong.

**Metric:** offline captures complete at the same rate as online ones (instrumented locally, reported in aggregate).

### F4 · Cloud LLM fallback unavailable (offline, backend down, or quota spent)
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F4-2026-09-11c)
**Trigger:** hard image (crumpled receipt, odd charging-app screenshot) where on-device gave low confidence and the user's Pro fallback can't be reached.

- The app **never waits on the gateway to show the card**: on-device results (however partial) render immediately; the fallback was always an *enhancement* pass.
- **The wait has a 3-second budget** (`API.md` -> "The device's side of `/extract`"). At 3 s the UI stops presenting the call as something to wait for and says so, naming the next step: carry on with what was read locally. The request may still finish in the background - the budget bounds the **user's** wait, not the work - and its late answer is **never applied to the open editor**: **RV.57 (product owner, 2026-09-04)** *"if a user keeps the edit entry open (they fill up odometer) and recognition has arrived - there is no need to async update"*. It lands in the **inbox** instead, never as a value that moves under the user's cursor (hard rule 13). A **within-budget** answer still applies directly, filling blank untouched fields only. **RV.38 (2026-09-03) amended "After save it arrives nowhere":** once the entry is saved a late answer no longer dies - it lands in the **inbox** (the bell on the tab-root header), and the app *asks*. The ask is what makes the reversal legitimate, and it has a required shape: **"leave it as it is" is the default** (the entry is untouched unless the user taps "update from the receipt"). **RV.45 (2026-09-04) made the accepted update per-field:** the card lists every field the receipt read that differs from or fills what the user saved as "yours vs the receipt", and the user **ticks per field** what to take - filling a blank and replacing a typed value are different acts and read differently, and a field that merely agrees is not a choice. This is the user deciding, so it is compatible with hard rule 13 (the app never overwrites a value on its own). A reading that would change nothing says so and offers no update. A late answer that agrees with what was saved creates no item at all. The decision lives in core (`GatewayInboxPolicy`); the store is device-local and **best-effort** - the extraction lives on the device (rule 9: the gateway holds no conversation), so an app killed mid-request loses the answer, and the inbox never promises one that can vanish. A *durable* re-read (from RV.33's ledger on next launch) would need a read endpoint over the ledger, which RV.33's own amendment forbids ("written by the gateway and read by no endpoint") - a second rule-9 reversal that is the product owner's to make, never an agent's. **RV.201 (2026-09-11)** generalised that same inbox over the entry kind: a late **service** recognition lands here offering its vendor, line items and total per tick, and a late **expense** recognition offers its amount and category - all through the one `GatewayInboxPolicy.merged`, so the kinds cannot drift. Making those readings deferrable on the device is **[RV.215]** (2026-09-11): the service and expense scans now run their reads in the background and route a late one through the same `GatewayInboxPolicy.item`; the cloud/outbox half remains **[PJ.29]**'s.
- **The upload is compressed on device** before any of this, because on a forecourt signal the upload is the slowest step in the flow. How hard it may be compressed is settled by the corpus, not by taste: if compression costs extraction hits, it is too aggressive.
- If fallback is unreachable: low-confidence fields stay dimmed with "check these – enhanced reading unavailable right now." User confirms or fixes by hand, saves. A retry never re-asks the user – if the photo later re-processes successfully in background, we *don't* silently change a saved entry; corrections post-save are the user's alone. *(PJ.18: this unreachable hint is still open ([v2]) – today only the timeout branch of F4 renders.)*
- **A signed-in session that merely went stale no longer loses the cloud reading (RV.26).** The gateway is armed only when the session can actually authenticate: a guest has no session and correctly gets no gateway (on-device OCR still runs), and a session whose refresh has already been rejected is marked `authExpired` and never re-arms. On a 401 the gateway refreshes once and retries, exactly as sync does – so an expired access token recovers instead of being refused silently. Only when the refresh itself is rejected is the session marked `authExpired`, and that mark surfaces where the account lives (Settings, the sync state chip) with its next step, "sign in again" – never blocking capture: the on-device result still stands.
- **A dead session no longer uploads the photo twice, and no longer fails silently (RV.65).** The 401 refresh-and-retry replays the WHOLE request, image included – correct when the bearer genuinely rotated, wasted bytes when it did not. The client therefore replays only when the refresher returned a **different** bearer; an unchanged token means the server already rejected exactly this request, so it fails immediately (the production log: eight captures, sixteen 53 KB uploads, no `/auth/refresh` round trip, never a word to the user). When `/extract` ends in that auth failure – refresh rejected **or** unchanged – the **capture surface** says so: a `warn` card on the Confirm sheet names the next step, "sign in again to use cloud reading", and reassures that the entry still saves. The image goes out once or not at all, never twice for nothing.
- If quota is spent: same UX, plus a quiet, non-blocking note in Settings – never an upsell interstitial mid-capture. ⚠ Monetization pressure must never leak into the capture flow; that is the incumbents' disease.

**Metric:** capture abandonment when fallback is down: no different from baseline.

### F5 · The receipt's QR decodes, and nothing more is fetched (P3)
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F5-2026-09-11b)

**Trigger:** the QR on the receipt decodes. No fiscal-service lookup is attempted – enrichment is permanently deferred (J5 above) – so this is the normal path, not a failure.

- Parse locally what the QR string itself carries (total, date-time, fiscal IDs) → card pre-fills total and date instantly; liters/price are the user's, from OCR and editable as always (hard rule 13) – the anchor never pretends to know the volume.
- No copy: nothing failed, and the QR is not named. The Confirm sheet simply shows the anchored total and date as verified.

**Metric:** RU/KZ receipts with a decodable QR save with the anchored total in ≥95% of cases.

### F6 · Import file won't parse (J2's failure)
**Trigger:** truncated export, exotic CSV dialect, an app version we haven't seen, wrong file shared entirely.

- Partial parse is the goal: import what parses, then show "214 of 220 entries imported – 6 rows need a look," with the 6 raw rows listed for inline fix or skip. All-or-nothing imports are how switchers bounce. **RV.93 (2026-09-07): this now also applies across files of one export** - a whole-export pick where one file fails to parse names the file and its next step, and the rest of the export continues (the run survives; hard rule 7).
- Nothing parses at all → name the reason plainly ("this looks like a PDF report, not a data export – here's where the CSV export lives in Drivvo") and offer to send us the file (explicit consent) so the importer learns. **The "here's where the CSV export lives" step is the site's per-source guide (PJ.33)**: the import wizard's format row and its 422 / not-listed messages link to `tankbook.live/import-guide/` via the format's `helpUrl`, so a stuck switcher lands on a page that exists (hard rule 7). With only My Fuel Manager shipping, the guide covers that one source and says so - never implying the deferred importers (P5.4b).
- ⚠ Never import with guessed units/currency: ambiguity pauses those rows for one question ("MPG or L/100km?"), asked once for the whole file.

**Metric:** recovery rate of failed imports after guidance ≥50%; importer coverage grows from submitted samples.

### F6a · The import preview: nothing is written until the user says so

**Trigger:** a file parsed (fully or partially) and is about to become someone's history.

The server parses and returns **candidates**; the garage is untouched until the user confirms
(hard rules 9 and 13). Between those two moments sits a preview, and it follows **F7's rule
rather than a progress bar: trust is re-established with numbers, not a checkmark.**

- **Show what was understood, as figures the user can check against their own memory:** fill-up
  count, date range, odometer span, detected currency and units, total spend, and - the one that
  matters most - **the consumption it derives**. A driver knows their own average. `8.2 L/100km`
  reads as right or wrong instantly, where "220 rows parsed" does not, and that is the same
  number the importer's acceptance test asserts.
- **Say where it will land** before it lands: a new car, or merged into a named existing one
  (per-car scope, `SCHEMA.md` → Backup format). Merging into a car that already has entries shows
  the S2 duplicate count **in the preview**, not after the fact. **RV.86 (2026-09-06): when the
  file holds more than one source car this question is asked per car, on its own mapping step**
  - each car listed with its own row count, odometer span and date range and an explicit
  destination (leave out / a new car / an existing garage car), Continue disabled until every car
  is decided, and each car's odometers validated and committed against ITS OWN destination - two
  cars can never corrupt each other's timeline. A single-car file keeps this preview exactly as
  before, byte-for-byte.
- **The journey now takes an export, not a file** (RV.93, 2026-09-07): a My Fuel Manager history
  is six files (`fuel.csv`, `costs.csv`, `vehicles.csv`, `trips.csv`, `incomes.csv`,
  `reminders.csv`), and the picker accepts several at once (`allowsMultipleSelection: true`, one
  staged copy and one `POST /import/parse` call per file - the server stays a per-file pure
  function). The **car mapping is asked once for the whole export**: the `Vehicle name` column is
  identical across files, so one mapping answers for all of them, and the merged view validates
  one car's rows from different files as **one timeline** (a costs service at 106 722 km sits
  between fuel fills and must not flag). The write stays ONE `commitImport` - a half-imported
  export can never become a state nothing can undo. A single-file pick keeps the pre-RV.93 flow
  exactly as it was.
- **Everything shown is adjustable here** - currency, units, the target car, and the individual
  rows that need a look (hard rule 13: editable at the moment it is offered). **RV.185:** when the
  import will create a new car, its name is an editable field pre-filled with the derived
  suggestion, and the currency the user chooses becomes that new car's home currency - so the
  entries land in the car's own currency instead of arriving rate-pending against a hardcoded EUR.
  An existing destination car is never renamed or re-homed. The F6 ambiguity question is answered
  in this screen, once per file.
- ⚠ **The date-format question is asked here, never guessed** (PJ.10): when the server reports
  genuinely ambiguous dates (the real MFM export has them), the preview asks `M/D/YYYY` vs
  `D/M/YYYY` **once per file** and **disables confirm until it is answered**. The parser's guess
  standing silently is how a year of history shifts by up to eleven months (J2's stats poisoning).
  Answering re-dates the counted rows - the preview figures and the review rows rebuild against
  the corrected dates, so the number the user approves is the number that lands. An
  `outOfScope` file (income, reminders) is surfaced here too: "this file has N income rows; income
  isn't imported in v1" - read-but-not-imported is stated, never silent.
- **Cancel leaves nothing behind**: no entries, and the stored file is deleted rather than left to
  age out (`DELETE /import/{importId}`).
- ⚠ **The preview is not a receipt.** If it renders a number the parse did not actually produce -
  a total assembled for display, a consumption computed differently from the engine - it is worse
  than no preview, because the user has now approved something they never saw. Every figure comes
  from the candidates themselves, through the same engine that will compute them after commit.

**Metric:** imports abandoned at preview are a *success* signal, not a funnel loss - they are
mis-parses caught before they became someone's history; zero "my imported data is wrong" reports
traced to a figure the preview showed correctly.

### F6b · A flagged import row is fields, not a line of CSV

**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F6b-2026-09-11b)

**Trigger:** a row reached the review list, so something about it needs a person.

**It renders as parsed, labelled fields - date, station, litres, price, total, odometer, note -
and only the field that is actually wrong is marked.** Showing the raw comma line instead makes
the user do the parser's job: they have to count separators to find which value is missing, on a
phone, for six rows.

This is the same rule Confirm already follows for OCR. An extracted value becomes an editable
field, never raw text, because a value the app cannot use is still a **default input the user
edits** (hard rule 13) - and a missing one stays **blank, never `0`**, since a zero is a wrong
fact where a blank is an honest absence.

- **Only the broken field carries the marker.** A missing odometer marks the odometer; a
  cross-check failure marks the two operands that disagree, and names the residual in money. A row
  outlined entirely in amber tells the user nothing about where to look.
- **The raw line stays one tap away** behind "Original row". It is the right answer for the rarer
  failure - the *mapping* is wrong, not the value - and the wrong answer for the common one.
- **A row that is not a fill-up is offered as what it is** rather than discarded: a tyre change
  with a total and an odometer imports as a service entry (hard rule 8). The row renders its
  parsed, labelled fields (date, total, odometer, note) beside an **"Import as service" /
  "Import as expense"** action, and the commit writes it as that kind of record with
  `provenance = .import` (PJ.9) - shown, never silently dropped at commit.

**Metric:** flagged rows resolved rather than skipped ≥60% - a review list people skip wholesale
is a review list that failed to explain itself.

### F7 · Restore fails or comes back empty (J11's nightmare)
**Trigger:** new phone, sign-in works, but the backup is missing, corrupt, or the backend is down. The category's fatal moment – this journey gets engineered redundancy, not just good copy.

- Restore sources, tried in order and shown honestly: sync pull from zero (the normal path – `SYNC.md`) → a server backup snapshot → "import a file you exported yourself."
- If the backend is down: say exactly that ("sync service unreachable – you can import an export file, or your data will arrive as soon as it's back"), never a generic "something went wrong."
- If truly nothing is found: the app says so *before* the user logs anything new (an empty garage with "expecting your data? →" recovery entry point), because the worst sequence is: user re-adds car manually, backup later reappears, and now there's a merge problem.
- Post-restore: show the same verification stats as J2 (entries, date range, last odometer) so trust is re-established with numbers, not a checkmark.

**Metric:** restores resolving to full data ≥99.5%; empty-restore sessions that reach the recovery entry point: 100%.

### F8 · Permissions and hardware said no
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F8-2026-09-11b)
**Trigger:** camera permission denied at first capture; or camera in use / hardware fault.

- Denied: the capture tab doesn't become a dead button – it opens the manual form with a top card: "Scanning needs the camera – enable in Settings" (deep link). The core promise degrades but the app remains fully usable, permanently, for the paranoid.
- A grant in Settings resumes the camera on return, without a relaunch: the scenePhase handler restarts the session, so the deep link's payoff is real rather than a blank preview.
- Camera in use / hardware fault: the live surface stays and a card names the manual door ("The camera didn't respond – type the entry instead"), with the shutter still there for a retry. It never points at Settings - a grant cannot fix a busy camera - and it is a transient presented state, not a permission state.
- Photo-library-only users: "add from photos" is always present on the capture surface (also serves the screenshot journey J6).

**Metric:** permission-denied users still logging entries at D7 (they're future converts, not losses).

### F9a · Odometer contradicts the timeline
**Status: implemented 2026-09-11** (reviewed by REVIEW-SCENARIO, REVIEW-SCENARIO-F9a-2026-09-11c)
**Trigger:** a new or edited entry breaks the invariant – sorted by date, the reading never falls and strictly increases between the kinds that MEASURE travel (FillUp, ChargeSession), while a ServiceRecord or Expense may share a reading with the fill it annotates – a typo (119 486 → 11 948), an out-of-order backfill, or two drivers logging the same car.

- Checks on every write (not just capture): order against date-neighbors, and implied pace (default flag above ~1 500 km/day, per-vehicle tunable).
- The discrepancy is shown inline – amber underline on the offending field plus the conflicting entry quoted ("Aug 17 already recorded 119 486 km") – with ranked suggestions: fix odometer · fix date · **keep as is** (the entry saves with its flag - Save is never blocked - and on Edit entry the flag can be **accepted** with a reason, persisted and synced, undoable, so it stops flagging on every device; decided 2026-09-11 in place of the never-built *move entry*). **The ranking is a fill-up's** (`PJ.34`): a service, an expense or a charge conflict presents the single odometer fix instead, because its odometer is the field the warn names and the fill-up's no-receipt order would preselect the date (`RV.211`, `docs/ERRORS.md` → Service & expenses). An edited non-fill entry shows the same warn and Fix in Edit entry, where the save stamps the flag (`RV.230`).
- **Receipt priority:** when a scanned receipt or fiscal QR carries a printed timestamp, that date is ground truth – the fix-odometer suggestion is preselected, and overriding the date requires an explicit "the receipt says Aug 17" confirmation. A fiscal document beats a typed number.
- Saving anyway is always allowed (it's the user's log): the entry gets a quiet amber conflict badge, its segment is **excluded from consumption math** until resolved (one bad odometer otherwise poisons two segments and the headline), and Trends footnotes the exclusion. Resolving is one tap from the badge into edit with the discrepancy pre-highlighted.

**Metric:** unresolved conflict badges older than 30 days <1% of entries; zero support tickets about "my consumption is wrong" traced to odometer typos.

### F9 · Currency rate unavailable for that date
**Trigger:** obscure currency pair, rate feed gap (RUB after ECB delisting), or first-ever launch offline abroad.

- Entry always saves with the original amount – conversion is metadata, never a save-blocker.
- Rate arrives later → conversion fills in *(PJ.8: the S8 backfill is live – it runs after every successful `AppRates.refresh()` and on foreground, fill-blanks-only, behind no DEBUG flag.)*; rate *never* exists (feed gap) → entry shows original currency in trends with a footnote count ("3 entries pending rates"), and the user may set a manual rate per entry.
- ⚠ Never apply today's rate to last month's fill-up silently: a wrong-date rate is worse than no rate.

**Metric:** entries stuck >7 days without a rate <0.5%.

### F10 · Sync conflicts surface after the fact
**Trigger:** two devices (or two drivers) changed the same data while apart – possibly during a server outage, so conflicts arrive in a batch when sync recovers. Full scenario matrix: `SYNC.md` S1–S9.

- **Never modal, never at sync time.** Conflicts materialize as badges where the data lives: amber timeline flags on entries (S3), a "possible duplicate" combined card (S2), a quiet Garage notice when an archived vehicle returns with new entries (S5). A batch after an outage gets one summary toast – "Synced. 2 entries need a look" – that filters the Log to flagged items.
- **Nothing is lost silently:** overwritten edits and deleted entries sit in a 30-day local undo log ("Recently deleted" / "restore my version" from the entry's edit screen).
- **Stats stay honest during limbo:** an unresolved duplicate counts once, not twice; a flagged timeline entry is excluded from consumption with the Trends footnote.
- **Server down = non-event** (extends F3): a passive "Waiting to sync · N changes" row in Settings is the only surface; no screen in the app is sync-gated.

**Metric:** conflicts auto-resolved without user action ≥95%; badge-resolution within 7 days ≥80%; zero modal interruptions attributable to sync.

### F13 · The share that reached no destination (RV.181, OPEN)

*(`F11` and `F12` are the v2 agent failures below; this v1 journey takes the next free id rather than renumbering them.)*

**Trigger:** the user shares something – a receipt photo (J8b), a diagnostics bundle, an export
(J13), the file behind a failed import (F6) – picks a destination, and nothing arrives.

Product owner, 2026-09-10, on iOS 26 / iPhone 13: *"I can see the share proposal, select a
destination, but in the end, nothing is dispatched to the destination source."* **This journey is
written because it is NOT yet solved**, and a failure journey nobody has written is a failure
nobody is designing for.

- **Every share in the app is one seam** (`Shared/ActivityView.swift`): the diagnostics bundle, the
  receipt photo or PDF, the whole-account and per-car exports, and "send us the file". So this is a
  single failure with four faces, and **J13's promise depends on it** – *export always free* is a
  launch commitment (`VISION.md`) and `DELETE /account` points the user at export as the way to keep
  their data.
- **The presentation shape changed on 2026-09-11.** `SharePresenter` now presents the system sheet
  from the key window's **top-most** controller, never as the root of a nested SwiftUI `.sheet`; the
  old shape buried the activity two or three modal levels deep and left the chosen destination's UI
  to be presented from a host SwiftUI could tear down. SwiftUI's `ShareLink` is deliberately not
  used: it presents natively but reports nothing, so a `ShareLink` share could never name its
  destination error in the diagnostics bundle. The device step that closes or re-opens this journey
  is unchanged: one share attempt on the owner's iPhone 13, then the diagnostics preview's `share`
  line (`activity=`/`error=`), which is now on screen without the share sheet having to arrive.
- **The cause is unestablished.** The first diagnosis – that the activity controller had no
  presenter – was withdrawn: UIKit forwards a presentation up the parent hierarchy, and *Save to
  Files completes on both the old and the new shape*. What is known is that it does not reproduce on
  the simulator, which carries almost no share extensions and whose working destination is
  in-process; the reported failures are **out-of-process app extensions** on a real device.
- **What the user sees today is nothing at all, and that is the design question.** The system reports
  a cancelled share and a failed one identically, so the app cannot honestly say "that failed"
  without also saying it every time somebody closes the sheet. The destination owns its own error
  surface (Mail's composer, the Files browser), so Tankbook stays quiet – `docs/ERRORS.md` records
  the decision.
- **The outcome record is the diagnosis.** The seam records the whole outcome – the activity type,
  whether it completed, and the error's domain and code, all shape and never the shared content
  (hard rule 12) – and logs `failed` as an outcome distinct from `cancelled`. **A report of this is
  answerable from the user's own diagnostics bundle**, which the one that opened this journey was
  not.

**Metric:** a share that a user reports as never arriving can be explained from their diagnostics
export without a new build. Resolution of the underlying defect is verified **on a physical device**,
never on the simulator.

## Cross-journey principles

1. **The confirm screen is the product.** J3–J7 all funnel through the Pump Card; its trust mechanics (cross-check lock, confidence dimming, live odometer delta) are shared infrastructure – build once, polish forever.
2. **Never block on the network.** Every journey completes offline except restore (J11) and cloud-LLM fallback; anything async happens after Save, invisibly.
3. **Failure always degrades to the manual form pre-filled with whatever was read** – captured photos are never discarded, and the user never re-does work. *(PJ.2: the receipt photo is persisted on a scanned save, and the saved entry's `provenance` names the door it came through; the typed path stays a peer – `.manual`, no attachment.)*
4. **One emotional beat per journey.** J3's beat is the ✓ lock; J5's is "exact, free"; J6's is the two-car chart; J13's is the dossier. Everything else stays quiet.

---

## Agent journeys **[v2]** (Pro) – the Ask tab

*Added 2026-08-29 with `docs/AGENT.md`, the single authority for how these are built. The agent
is a Pro feature and a v2 phase; none of these journeys is a v1 condition. Personas as above;
each journey carries its **user stories** with acceptance criteria, because the stories are what
the agent fixtures (`AGENT.md` §8) are written from.*

**The agent's four rules, restated so every journey below can lean on them:** numbers come from
the app's tools and render as cards, never as model prose (§2) · every write is a pre-filled
screen the user saves, never a chat-bubble "done" (hard rule 13) · the agent is never the only
door to anything (hard rule 1) · offline, not-Pro and quota-spent are states with next steps,
not errors (§6).

### J14 · Ask about the car (P1) **[v2]**
**Trigger:** idle curiosity that Trends' four tiles do not answer – "what did the Volvo cost me
this year, all in?", "when did I last do the brakes?", "which station do I actually pay least at?"
**Goal:** a sentence-shaped question gets a figure-shaped answer in under ten seconds, and the
figure is the same one Trends would compute.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Open | Taps Ask; sees the car chip, the last thread, three example questions | "It knows which car I mean" | → The car chip is the same control as Home's; switching car switches context |
| Ask | Types or dictates the question | Testing it with a number they already know | ⚠ The first answer decides trust – same as the first scan (J1) → the first example question is one whose answer the user can verify on Trends |
| Answer | A **card** (spend by month, or the service row, or the station table) with a one-paragraph narration under it; "Open in Trends" on the card | Checks the number against memory – matches | → Every figure is a tool result rendered by the app; the model narrates. A number in prose that is not on a card is a defect (`AGENT.md` §8) |
| Follow-up | "and last year?" – the thread keeps context | Conversation, not a query language | → Follow-ups reuse the same tool with a new range; the card updates, not a new screen |

**Stories**
- As Andrus, I want to ask "how much did this car cost me in 2025, everything included?" and
  get a total with the breakdown by type, so that I do not add up Trends tiles by hand.
  *Accepted when:* the total equals `TrendsStats` for the same range to the cent; rate-pending
  entries are named as excluded with a count; the card opens Trends filtered to 2025.
- As Andrus, I want "when did I last change the brake pads and at what mileage?" answered from my
  service log, so that I stop scrolling the timeline. *Accepted when:* the answer is the service
  row card with its odometer and attachment glyph; if no such record exists the answer says so and
  offers "log a past service", never guesses a date.
- As Marta, I want to ask across both cars ("which car costs us more per km?"), so that the
  household comparison Trends promises is one question away. *Accepted when:* two cost/km cards
  from the two vehicles' engines, side by side, in each car's accent.
- As anyone, I want to ask in Russian and get Russian back, with numbers formatted my way.
  *Accepted when:* the RU fixture passes with `42,3 л` and `1 234,50 ₽` rendering from the app's
  formatters, not from the model.

**Success metric:** first-answer figure matches the app's own computation in 100 % of fixtures
(the gate); ≥60 % of Pro users ask at least one question a month.

### J15 · "Remind me" (P3) **[v2]**
**Trigger:** the user knows a date or a mileage and would rather say it than fill a form:
«Напомни про ОСАГО за две недели до 4 сентября», "remind me to rotate the tyres at 125 000".
**Goal:** the reminder exists, with the user's words turned into the right fields, and the user
saw and could change every field before it was saved.

| Stage | Doing | Notes |
|---|---|---|
| Say it | Types or dictates | → Category, due date/odometer, lead time and recurrence are parsed by the model into a `draftReminder` call; ambiguity is asked back in one line ("Insurance – the ОСАГО policy on the Lada?") |
| See it | The **Reminder form opens, pre-filled**, dimmed like OCR rows until touched, Save under the thumb | ⚠ A chat bubble saying "Done, reminder created" is a hard-rule-13 bug – the user never saw the fields |
| Save | Taps Save (or edits first) | → The thread shows the saved reminder as a card; the agent is told the outcome and does not re-offer |
| Cancel | Swipes the form away | → Nothing written; the thread says "not saved" in `inkSoft`; no retry pressure |

**Stories**
- As Sergei, I want to say the insurance renewal date in Russian and get the reminder form filled
  with the insurance category, the date, and a lead time, so that the app's forms stop feeling
  like paperwork. *Accepted when:* the form opens with exactly those fields set, the lead time is
  a field (not folded into the date), and the RU fixture's date «4 сентября» lands as 2026-09-04
  in the user's time zone.
- As Andrus, I want "every 15 000 km or 12 months, starting from the oil change I logged last
  week" to create a recurring reminder anchored at that record, so that the maintenance loop
  closes itself (J7c). *Accepted when:* the form shows recurrence and the anchor entry; saving
  links `sourceEntryId`.
- As anyone, I want to decline the draft and have nothing saved. *Accepted when:* the repository
  is unchanged and the thread records the decline as a count, not a nag.

**Success metric:** drafts saved without an edit ≥70 % (the parse was right); drafts dismissed
≤15 % (tracked as a count – a dismissed draft is the agent being wrong).

### J16 · Invoice through the agent (P2) **[v2]**
**Trigger:** Marta leaves the workshop with a three-page invoice in German for the SUV and does
not know what half the lines are.
**Goal:** the invoice becomes a categorised service record with the bill attached, the lines she
did not understand are explained, and the next reminder is offered – in one thread.

| Stage | Doing | Notes |
|---|---|---|
| Hand it over | Taps the camera in the composer; document camera, multi-page (the same capture as J7) | → `captureInvoice()` returns the `InvoiceSplitter` result and the page attachments; the model reads the *result*, not the image, unless she opts this image into the tier-3 pass |
| Read it | The thread shows the split as an **items card** – each line named, categorised, with a one-line plain-language explanation ("Bremsbeläge VA – front brake pads") and the ones the parser could not place marked | ⚠ Never fake precision: an unplaced line stays unplaced and says so (J7's rule) |
| Fix it | "the 148 is an annual service, not parts" – the card updates | → Corrections are edits to the draft, in the thread, before any screen opens |
| Save it | "Save it" → `ServiceEntryView` opens pre-filled with the items, vendor, date, odometer from last known, pages attached; she saves | → Same screen as J7; the agent never writes |
| Close the loop | "Want a reminder for the pads – about 40 000 km?" → J15 | → Lifetime proposal from item categories (the PJ.22 gap, delivered here) |

**Stories**
- As Marta, I want a photographed invoice explained line by line in my language, so that I know
  what I paid for. *Accepted when:* every parsed line has a name, a category and an explanation
  or an explicit "couldn't place this"; the sum of placed lines plus unplaced equals the invoice
  total (hard rule 4's arithmetic, applied to services).
- As Marta, I want the record saved through the ordinary Service screen with the pages attached,
  so that it looks like every other service record. *Accepted when:* the saved record is
  indistinguishable from a J7 record except `provenance = .agent`.
- As Marta, I want the agent to notice a part on my shelf ("the oil filter from March") and offer
  to link it, so that cost is counted once (J7b). *Accepted when:* the link appears in the draft
  as a suggestion; declining leaves the shelf untouched.

**Success metric:** invoices saved through the agent carry an attachment 100 % (it captured it);
lines the user renames ≤20 %.

### J17 · Diagnosis with the car's context (P1) **[v2]**
**Trigger:** "there's a whine that gets higher with speed, not with revs". Or a photo of a lit
warning lamp. Andrus wants to know whether to worry before Monday.
**Goal:** a ranked, evidence-backed second opinion, an honest urgency call, and next steps that
are all things the app can do.

| Stage | Doing | Notes |
|---|---|---|
| Describe | Types the symptom, or photographs the dashboard | → `carProfile`, `lastService`, `consumption`, `anomaly` run first; the **context card** ("Volvo V60 D4, 119 486 km · brakes 41 000 km ago · consumption +9 % vs last winter") is shown *before* the answer so the user sees what the model was told |
| Read | Ranked causes – most likely / also possible / less likely – each with the fact from the log that supports it, or "general knowledge, not from your log" | ⚠ A cause with no evidence label is a defect; the fixture checks every cause carries one |
| Urgency | A fixed row: **drive on · book this week · stop driving** – amber for the middle, the system-red dialog only for the last | → Brakes, steering, fuel smell, red lamps and smoke escalate by rule (`AGENT.md` §5); the model cannot talk a user out of a workshop |
| Act | Buttons: "Remind me to book" (J15), "Note it on the car", "Questions for the workshop" (copyable) | → All three are app actions; no parts-shop links, no ads, no "find a garage" |

**Stories**
- As Andrus, I want the causes ranked and each tied to something in my log or clearly marked as
  general knowledge, so that I can tell an informed guess from a lookup. *Accepted when:* every
  cause in the fixture carries an evidence label; a cause citing the log names a real record.
- As Andrus, I want a clear "can I drive it till Monday?" answer, so that the app says something
  a forum thread won't. *Accepted when:* the urgency row is present on every diagnosis turn with
  one of the three values; brake/steering/fuel-smell fixtures never resolve to "drive on".
- As Sergei, I want the same in Russian with the same triage vocabulary, so that «можно ехать»
  means exactly what "drive on" means. *Accepted when:* the RU fixture passes; the vocabulary is
  from the String Catalog, not translated by the model.
- As anyone, I want the screen to say it is a second opinion, once, without nagging. *Accepted
  when:* the `inkSoft` line is present at the top of a diagnosis thread and nowhere else.

**Success metric:** diagnosis turns ending in a reminder or a note ≥40 %; "that's not right" taps
per 100 answers, trended per model version (the F2 metric of chat).

### F11 · Ask is unavailable – offline, not Pro, quota spent **[v2]**
**Trigger:** underground garage; a free-tier user curious what the tab does; a Pro user whose
monthly turns are used up; the gateway is down.

- The tab stays. The thread stays readable. The composer explains the state in one line and
  names the next step; the three example questions become taps that open the ordinary screen
  that answers them (Trends, Reminders, Garage). Nothing in the app is gated by Ask (hard rule 1).
- Not Pro: the examples plus the Pro card – the one surface besides the car-limit sheet that
  offers Pro. Tapping an example opens the ordinary screen, not a paywall.
- Quota / gateway: F4's copy, no upsell, never mid-turn pressure.

**Metric:** free-tier users who open Ask and then open Trends or Reminders from it (the tab
teaches the app even when it cannot answer).

### F12 · The agent is wrong **[v2]**
**Trigger:** a figure looks off; a draft has the wrong category; a diagnosis names a part the car
does not have.

- **Figures cannot be wrong in the model's favour**: they are the app's numbers rendered as
  cards. If a card is wrong, the engine is wrong, and that is a bug with a fixture, not an AI
  problem – say so in the copy ("this is your log's number; if it's wrong, the entry is").
- **Drafts are corrected before they are saved** – in the thread or on the form; a saved record
  the user disagrees with is edited like any other (hard rule 13) and the agent is never asked to
  "undo".
- **"That's not right"** on any answer: one tap, optional reason, counted, never sent with the
  content unless the user opts to attach the thread (the same consent shape as F1's improvement
  sample). It teaches the fixture set, not the model in production.
- A diagnosis the user rejects stays on screen with its evidence labels – the user can see *why*
  it was wrong, which is the honest version of confidence.

**Metric:** "not right" rate per 100 answers falls across model versions; zero support tickets
about a figure the agent stated that the app did not.
