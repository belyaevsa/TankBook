# Tankbook – Customer Journey Maps

*Mobile UX companion to `VISION.md` (features, flows) and `DESIGN.md` (visual language). Each journey names its trigger, walks the stages with what the user does / thinks / feels, flags pain points (⚠) and design opportunities (→), and ends with the metric that tells us the journey works.*

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

### J2 · Switching from another app
**Trigger:** frustration with incumbent (ads, paywalled export, dead sync) + years of history they refuse to lose.
**Goal:** full history alive in Tankbook in one sitting.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Export | Finds export in old app (Fuelio/Drivvo/Fuelly/Spritmonitor/CarScope/My Fuel Manager) | Anxious – "will it all come across?" | → In-app illustrated guide per source app, since their UIs hide export |
| Import | Shares the file to Tankbook (share sheet / file picker) | Skeptical | → Declare the source app, never the format: "Which app is this from?" against the server-driven supported list (`GET /import/formats`). The app never sniffs the file – a format the picker cannot list is a format that does not exist, and a confident mis-mapping is worse than a question (hard rule 13; `ERRORS.md` → Import wizard) |
| Verify | Sees preview: N entries, date range, detected currency/units, per-field mapping | Checking their known numbers | → Show *their* lifetime average consumption next to the old app's; matching numbers = instant trust |
| Commit | Confirms; garage now shows full history and trends from day one | Relief, sunk cost transferred | ⚠ Silent unit/currency misread poisons all trends → flag ambiguous rows for review instead of guessing |

**Success metric:** import completion rate ≥90% once a file is opened; zero support tickets about corrupted history.

---

## Core loop

### J3 · The 5-second fill-up (receipt)
**Trigger:** standing at the pump or walking back to the car, receipt in hand. Cold, dark, engine of the queue behind.
**Goal:** logged before the seatbelt clicks.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Open | Lock-screen widget / app opens on capture | In a hurry; one hand holds the receipt | → Camera ready in <1s; auto-shutter on document detect |
| Scan | Points at crumpled thermal receipt | "Will it read this?" | ⚠ Glare, dark canopy → torch auto-suggest; keep the photo regardless of OCR result *(PJ.1: shutter and Photos now feed one pipeline into `ConfirmPrefill` – a real image becomes the prefill, no `-seedConfirmPrefill` fixture in the path.)* |
| Review | Sees the shot filling the screen; "Use this" / "Re-take" / "Type it" | "That's readable – go" *(or: "that's a blur, again")* | → **RV.5**: the missing beat the device walk found - the shutter used to fire and move on with nothing shown, so the frame could be neither seen nor refused. The photo appears **immediately**, before any recognition: OCR runs only on *Use this*, so a re-take costs nothing and the wait is spent on a picture the user accepted. Re-take is the back path (nothing kept); "Type it" is a peer on the same row, never the failure branch (hard rule 15) |
| Confirm | Pump Card pre-filled; cross-check line locks ✓; types odometer, sees "+907 km since last" | Trust building with each correct field | ⚠ One wrong digit typed in odometer ruins consumption → live delta as sanity check; low-confidence fields dimmed until tapped. *(PJ.14: the delta is LIVE – typed > last shows "+N km since last", typed < last warns amber "went backwards", an implied pace over the vehicle's `paceLimitKmPerDay` warns amber "over the limit", equal shows neutral "Same as last"; none of them ever blocks the save, hard rule 13.)* |
| Done | Save → haptic → "6.8 L/100km – best this year" | Micro-reward; closes phone | → The insight one-liner is the habit hook, not the stored row. **RV.12:** Save also **leaves capture** – the sheet and the capture modal behind it both close, landing on the tab the capture started from with the entry visible. Until RV.12 the camera was on screen again after Save, so a finished entry read as a failed one and a second tap started a second entry |

**Mixed receipt variant:** the slip carries fuel + car wash + coffee. The arithmetic check finds liters × price matching the *fuel line* (not the grand total) – that mismatch IS the detection. The Pump Card shows the fuel block as usual, plus an "Also on this receipt" section listing the other lines, each one tap: add as expense (pre-categorized: wash → `.wash`) or skip as not car-related. Added lines become Expenses sharing the same receipt photo and `purchaseGroupId`; the Log shows them as one grouped moment. Fallback: line detection fails → the fill-up saves with the fuel numbers and the receipt attached; the user can add the wash from the entry later ("add expense from this receipt"). *(PJ.2: a scanned save writes the receipt ONCE and references the same `Attachment` id from the fill-up and every accepted expense – the "same receipt photo" above is a shared id, not a copy per row.)*

**AdBlue variant (2026-08-30):** the diesel receipt also lists 10 L of AdBlue. The Pump Card shows the diesel fill as usual; "Also on this receipt" lists the AdBlue line as a **second fill-up**, pre-kinded `.adBlue`, one tap to add - it joins the purchase group and the Log shows one grouped moment with two fills. It never touches L/100 km; Trends shows the car's AdBlue rate (L / 1000 km) once two such fills exist. A standalone AdBlue top-up (a can from the shop) is just a fill-up whose fuel chip reads AdBlue - same door, same sheet (hard rule 15). `SCHEMA.md` → AdBlue.

**Success metric:** median capture-to-save < 15s; ≥80% of fill-ups logged via capture (not manual form); D30 retention of users with ≥3 captures; mixed receipts with correctly isolated fuel totals ≥95% (wrong grand-total attribution is a stats-poisoning bug). The review step (RV.5) adds one tap to this journey and is worth it: an unreadable frame caught here costs a second, and caught on the Confirm sheet costs a re-shoot after a wasted OCR - so the metric to watch is the **re-take rate**, which should be non-zero (the step is catching real blurs) without exceeding the share of captures that used to arrive at Confirm with nothing resolved.

### J4 · No receipt – pump display photo
**Trigger:** station prints no receipt / receipt skipped; the pump still shows liters, price, total.

Same shape as J3, with the deltas: camera pointed at the pump display before hanging up the nozzle (→ prompt tip on first use: "no receipt? Shoot the pump"); OCR reads the three numbers, arithmetic triple-match assigns them (⚠ glare/LED segments – the spike's ~95% gate applies before this ships); station name auto-suggested from location + favorites. This journey is **unowned by any competitor** – it must feel as reliable as J3 or not exist.

**Station suggestion – the logic (written 2026-08-30, shipped as PJ.19 [v1.1]; until then the
Confirm row shows an honest "Not set" placeholder and promises nothing).** The station field is a
default input (hard rule 13): the app proposes one, the user changes it in one tap, and a changed
station is theirs. The proposal is ranked, first match wins:

1. a **favourite** station within 300 m of the device;
2. the **last-used** station within 300 m;
3. the **most recently used** station for this car, regardless of distance – this rung needs no
   location permission and is what most users get most of the time;
4. nothing – the row stays "Not set".

Rungs 1–2 need location; rungs 3–4 never do. **Permission is asked on the first Confirm after the
second fill-up** – the earliest moment the question can be answered with a station on file –
never on launch and never before a car exists; denied means the ranking simply runs without its
distance rungs, forever, with no re-prompt. Location is read once per Confirm, while the sheet is
open, and is never stored on the entry – only `Station.location` is written, and only when the
user saves a fill at a station the app has no coordinate for (`SCHEMA.md` → Station). Offline is
a non-event: the ranking is local (F3). Coordinates are Sensitive and never logged (hard rule 12).

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
capture the camera cannot serve, and the measured corpus says that is common: receipts extract
at **38.3%**, pump displays at **0%**, Vision misreads digits at **confidence 1.00**, and a
fiscal QR exists on **9 of 16** real receipts while carrying only 2 of 5 fields. Making typing
the punishment for a failed scan would make the app feel broken precisely when it is being
honest about uncertainty.

So the two paths are peers, and a capture is a **head start rather than an answer**: everything
it produces is a default input the user edits (hard rule 13), which means a thin scan degrades
to "correct two fields", never to "start over". J3 and J3b converge on the same sheet by
design - a user who typed and a user who scanned are editing the identical screen.

**Success metric:** manual entry is reachable in one tap from Home in every state; median
manual save time under 20 s; and no growth in abandoned captures - a user who backs out of a
scan should land on a filled-in manual form, not an empty one.

### J5 · The RU/KZ receipt (P3) – the fiscal QR as an anchor, never a feature
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

**Fallbacks:** OCR can't split the invoice → the *same screen* holds one uncategorized item with the full total; the user renames/splits by hand or leaves it as "Annual service · 148 €" – a lump sum with the bill attached is a perfectly good record (never force itemization). No invoice at all (DIY) → manual line items, parts pulled from the shelf (J7b). Unknown category → `.other` with free text, promoted to a real category later without data loss. Odometer: pre-filled from the last known value (usually right, the car was just driven there) – one glance to confirm, editable; required only when an item sets a km lifetime or a tire set is mounted, since those anchor on it.

**Success metric:** ≥50% of service records carry an attachment; reminder acceptance rate ≥60%.

### J7b · Parts, tires, consumables
**Trigger:** a filter ordered online, brake pads bought on sale, a winter tire set – purchased *now*, installed *later* (or never; the car is sold with the shelf).

| Stage | Doing | Notes |
|---|---|---|
| Purchase | Scans the order confirmation / shop receipt → Expense `.parts` ("MANN W 712/75 · 12.40 €") | Odometer not asked – the car isn't even present. Cost counts in totals from day one |
| Shelf | The part sits visible under Garage → "Parts shelf" with an "on shelf" state | ⚠ Silent shelf = forgotten parts → the next matching service suggests them |
| Install | Creating a service record, app offers shelf parts: "Install oil filter from Mar 3?" → link, don't re-price | Cost counted once (at purchase); the service shows the part via link. No double counting in cost/km – the F-series equivalent sin here is a part priced twice |
| Tires | A tire purchase becomes a TireSet; each seasonal swap (a small ServiceRecord) marks which set went on | Set mileage derives from odometer spans between swaps – "Winter Nokian: 18 400 km" answers the real question (are these tires done?) plus the swap reminder each season |

**Fallbacks:** part logged without a receipt → plain manual expense, one field + price. User skips the shelf entirely and just types parts inside service records → works fine, the shelf is an optimization, never a gate. Tire mileage without logged swaps → unavailable, shown as "–", never estimated.

**The Expense capture door (RV.62):** scanning a shop receipt in Expense mode runs the same
recognition as a fill-up but pre-fills only **total, currency and date** into the expense form –
a shop receipt has no liters or fuel kind, and those fields are dropped at the extraction →
pre-fill boundary (`ExpensePrefill`, core), never offered. Merchant and category are not
guessed: the user picks the category on the form, exactly as J7's "pre-fill what's confident,
never fake precision" demands. A scan that reads nothing opens the EMPTY expense form with no
error (hard rule 7), the same contract the fill-up path honours. The amount is offered only
when the receipt's currency is nil or is the car's home currency – the expense form cannot
express a foreign total, so one is never offered as if it were home money (hard rule 13: a wrong
fact is worse than none).

**Success metric:** shelf-suggested parts accepted ≥40%; tire-swap reminders acted on ≥70% in season.

---

## Periodic

### J7c · Reminder lifecycle
**Trigger:** the "Oil change" reminder fires – or the user just did the thing early.

| Action | What happens | Notes |
|---|---|---|
| **Complete** | Sheet: "Done! Log the cost?" → one tap opens the service/expense entry pre-filled (category, title, today, current odometer); scan the invoice or type a lump sum. Then: "Next oil change in 15 000 km or Aug 2027" – the next cycle is already scheduled, anchored at *completion* (not the original due date, so schedules never drift) | Declining the cost log is first-class – completion never forces bookkeeping (.done without entry) |
| **Reschedule** | Push the due date/odometer; a fired notification re-arms | For "next month, honestly" moments – snoozing beats ignoring |
| **Delete** | Gone (tombstone, 30-day undo like everything) | Distinct from **dismiss-with-reason**, which keeps history and teaches insights ("sold the tires") |

⚠ The completion→entry→next-cycle chain is where competitors leak: a reminder marked done with no record and no follow-up is a dead end (Drivvo's pattern). Ours is a loop. *(PJ.4: Reminders has a production entry point – the Home banner derives from real reminders and VehicleDetail carries a reminders row, so this journey is reachable in a Release build.)*

**Success metric:** completed reminders that create an entry ≥50%; recurring reminders auto-rescheduled 100%.

### J8 · The monthly glance
**Trigger:** idle curiosity, end of month, or the "August: €212 on the Volvo" notification (opt-in).
**Journey:** open Trends → hero consumption metric with trend arrow → monthly spend bars → price-per-liter line per station brand ("Shell costs you 4% more than Neste"). Feeling sought: *control*, not accounting homework. → Every chart answers a sentence-shaped question; no chart junk. Exit within 60 seconds, satisfied.

**Success metric:** ≥40% of MAU open Trends monthly; session length short (it's a glance, not a report).

### J8b · Look at the receipt again (RV.9, RV.17, RV.37)
**Trigger:** a figure is questioned weeks later – "did that fill really cost 71.02?" – or the paper is gone and the photo is the only record.
**Journey:** Log → the entry → the receipt strip's chip is a **tap target**, not decoration → the photo opens full-screen, fitted, and pinch or double-tap magnifies it to read a printed line the 44x56 chip could never show. A PDF invoice opens in the PDF viewer instead of a blank frame. When the full rendition has not reached this device, the viewer shows the payload's thumbnail from the first frame and says so, naming the next step – it never shows an empty screen and never blocks the entry (hard rules 1 and 7). If the receipt carried anything recognised, a second page beside the photo shows what was read (the OCR lines and the scan timestamp) – a swipe away, not chrome over the photo, and absent when there was nothing. The Share affordance (RV.17) hands the **full** rendition to the system share sheet – Save Image, Save to Files, share to apps – and is offered only once that rendition is local, never over the thumbnail; sharing is the user's deliberate act. Close or swipe down and the entry is exactly as it was, still editable.

**Delete and replace (RV.37):** the viewer also offers **Delete** – system-confirmed, which removes the receipt from this entry and tombstones the attachment record for the 30-day window (the blob itself is left alone; reclamation is a separate concern) – and **Replace photo**, which opens the same camera/Photos door as "Add receipt", writes a **new** attachment and tombstones the old one (never an in-place mutation, so the 30-day undo has something to restore). The replace then asks – *"Re-read this and update the entry?"* – and "Leave it as it is" is the default: a silent re-read would overwrite values the user already confirmed, which hard rule 13 forbids. On an explicit "Update entry" the extracted values are still suggestions filling **blank fields only**, each dimmed until tapped. "Use a different receipt" is just replace again.

**Success metric:** the receipt can be read without leaving the app or hunting for the paper; opening a photo never ends in a blank screen.

### J9 · Anomaly nudge
**Trigger:** app-detected consumption drift ("+12% over 3 months").
**Journey:** gentle `warn`-amber card in the Log (never a push alarm) → tap explains the evidence (chart of the drift, possible causes: tire pressure, air filter, winter) → dismiss ("it's winter") teaches the model, or act → creates a service reminder. ⚠ False alarms erode trust fastest → thresholds conservative, seasonality-aware, always dismissible with a reason.

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
**Trigger:** faded thermal receipt, receipt in a language/layout we've never seen, shot too dark.

| Stage | Experience | Design rule |
|---|---|---|
| Capture | Shutter fires, brief processing shimmer (<2s) | Never a spinner longer than 2s – commit to an answer |
| Verdict | Pump Card opens **empty but alive**: photo attached at top, fields blank, keyboard already up on Total | ⚠ The failure state IS the manual form – same screen, zero navigation, no "recognition failed" error banner. A quiet caption: "Couldn't read this one – type it, the photo stays attached." |
| Recovery | User types 3 numbers (total, liters, odometer), price/unit auto-derives, saves | Typing 3 fields ≈ 20s – degraded, not broken. The receipt photo remains as evidence. *(PJ.2: the photo survives the save – a scanned save persists the receipt as an `Attachment` with scan provenance, whatever the OCR resolved.)* |
| Aftermath | Photo + OCR text silently queued as an (opt-in) improvement sample | → Opt-in "help improve scanning" set once during onboarding |

**Metric:** save-completion rate after failed scans ≥85% (users finish manually instead of quitting).

### F2 · Scan recognized *wrong* data – the most dangerous failure
**Trigger:** OCR misreads 42.30 as 12.30; a VAT line mistaken for the total. Unlike F1, the user may not notice.

| Stage | Experience | Design rule |
|---|---|---|
| Detection | The cross-check line refuses to lock: liters × price ≠ total | The arithmetic check is the safety net – this is why it exists |
| Surfacing | Mismatched field gets a `warn` amber underline + "these don't multiply up – check the amber field" | Never auto-"fix" by recomputing one field silently; the app doesn't know which one is wrong |
| Recovery | User taps the amber field, sees a crop of the receipt region it was read from, corrects it | → Showing the source crop turns correction into verification – seconds, not archaeology |
| The residue | If all three numbers are wrong *consistently* (rare), the cross-check passes falsely | ⚠ Accept residual risk; mitigate with the odometer delta ("+3,407 km since last?" flags the absurd) and consumption outlier check on save |

**Metric:** corrected-field rate tracked per OCR version (rising = regression); zero support tickets about silently wrong totals.

### F3 · No internet at the pump
**Trigger:** underground garage, roaming disabled abroad, rural dead zone. The most common "failure" of all – and by design, a non-event.

- Capture, on-device OCR, parsing, cross-check, save: **all work identically offline.** The user should be unable to tell.
- What silently defers: currency conversion for a foreign receipt (entry saves with original amount + "rate pending" chip, converts on next connectivity – trends momentarily exclude it from home-currency sums), station auto-suggest from maps (favorites still work – they're local), backup upload (queued).
- The one visible seam: a foreign-currency entry shows "≈ – · converts when online" instead of the home amount. `inkSoft`, not `warn` – nothing is wrong.

**Metric:** offline captures complete at the same rate as online ones (instrumented locally, reported in aggregate).

### F4 · Cloud LLM fallback unavailable (offline, backend down, or quota spent)
**Trigger:** hard image (crumpled receipt, odd charging-app screenshot) where on-device gave low confidence and the user's Pro fallback can't be reached.

- The app **never waits on the gateway to show the card**: on-device results (however partial) render immediately; the fallback was always an *enhancement* pass.
- **The wait has a 3-second budget** (`API.md` -> "The device's side of `/extract`"). At 3 s the UI stops presenting the call as something to wait for and says so, naming the next step: carry on with what was read locally. The request may still finish in the background - the budget bounds the **user's** wait, not the work - and its late answer is **never applied to the open editor**: **RV.57 (product owner, 2026-09-04)** *"if a user keeps the edit entry open (they fill up odometer) and recognition has arrived - there is no need to async update"*. It lands in the **inbox** instead, never as a value that moves under the user's cursor (hard rule 13). A **within-budget** answer still applies directly, filling blank untouched fields only. **RV.38 (2026-09-03) amended "After save it arrives nowhere":** once the entry is saved a late answer no longer dies - it lands in the **inbox** (the bell on the tab-root header), and the app *asks*. The ask is what makes the reversal legitimate, and it has a required shape: **"leave it as it is" is the default** (the entry is untouched unless the user taps "update from the receipt"). **RV.45 (2026-09-04) made the accepted update per-field:** the card lists every field the receipt read that differs from or fills what the user saved as "yours vs the receipt", and the user **ticks per field** what to take - filling a blank and replacing a typed value are different acts and read differently, and a field that merely agrees is not a choice. This is the user deciding, so it is compatible with hard rule 13 (the app never overwrites a value on its own). A reading that would change nothing says so and offers no update. A late answer that agrees with what was saved creates no item at all. The decision lives in core (`GatewayInboxPolicy`); the store is device-local and **best-effort** - the extraction lives on the device (rule 9: the gateway holds no conversation), so an app killed mid-request loses the answer, and the inbox never promises one that can vanish. A *durable* re-read (from RV.33's ledger on next launch) would need a read endpoint over the ledger, which RV.33's own amendment forbids ("written by the gateway and read by no endpoint") - a second rule-9 reversal that is the product owner's to make, never an agent's.
- **The upload is compressed on device** before any of this, because on a forecourt signal the upload is the slowest step in the flow. How hard it may be compressed is settled by the corpus, not by taste: if compression costs extraction hits, it is too aggressive.
- If fallback is unreachable: low-confidence fields stay dimmed with "check these – enhanced reading unavailable right now." User confirms or fixes by hand, saves. A retry never re-asks the user – if the photo later re-processes successfully in background, we *don't* silently change a saved entry; corrections post-save are the user's alone. *(PJ.18: this unreachable hint is still open ([v2]) – today only the timeout branch of F4 renders.)*
- **A signed-in session that merely went stale no longer loses the cloud reading (RV.26).** The gateway is armed only when the session can actually authenticate: a guest has no session and correctly gets no gateway (on-device OCR still runs), and a session whose refresh has already been rejected is marked `authExpired` and never re-arms. On a 401 the gateway refreshes once and retries, exactly as sync does – so an expired access token recovers instead of being refused silently. Only when the refresh itself is rejected is the session marked `authExpired`, and that mark surfaces where the account lives (Settings, the sync state chip) with its next step, "sign in again" – never on the capture surface, and never blocking capture: the on-device result still stands.
- If quota is spent: same UX, plus a quiet, non-blocking note in Settings – never an upsell interstitial mid-capture. ⚠ Monetization pressure must never leak into the capture flow; that is the incumbents' disease.

**Metric:** capture abandonment when fallback is down: no different from baseline.

### F5 · The receipt's QR decodes, and nothing more is fetched (P3)
**Trigger:** the QR on the receipt decodes. No fiscal-service lookup is attempted – enrichment is permanently deferred (J5 above) – so this is the normal path, not a failure.

- Parse locally what the QR string itself carries (total, date-time, fiscal IDs) → card pre-fills total and date instantly; liters/price are the user's, from OCR and editable as always (hard rule 13) – the anchor never pretends to know the volume.
- No copy: nothing failed, and the QR is not named. The Confirm sheet simply shows the anchored total and date as verified.

**Metric:** RU/KZ receipts with a decodable QR save with the anchored total in ≥95% of cases.

### F6 · Import file won't parse (J2's failure)
**Trigger:** truncated export, exotic CSV dialect, an app version we haven't seen, wrong file shared entirely.

- Partial parse is the goal: import what parses, then show "214 of 220 entries imported – 6 rows need a look," with the 6 raw rows listed for inline fix or skip. All-or-nothing imports are how switchers bounce.
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
  the S2 duplicate count **in the preview**, not after the fact.
- **Everything shown is adjustable here** - currency, units, the target car, and the individual
  rows that need a look (hard rule 13: editable at the moment it is offered). The F6 ambiguity
  question is answered in this screen, once per file.
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
**Trigger:** camera permission denied at first capture; or camera in use / hardware fault.

- Denied: the capture tab doesn't become a dead button – it opens the manual form with a top card: "Scanning needs the camera – enable in Settings" (deep link). The core promise degrades but the app remains fully usable, permanently, for the paranoid.
- Photo-library-only users: "add from photos" is always present on the capture surface (also serves the screenshot journey J6).

**Metric:** permission-denied users still logging entries at D7 (they're future converts, not losses).

### F9a · Odometer contradicts the timeline
**Trigger:** a new or edited entry breaks the invariant *sorted by date, odometer strictly increases* – a typo (119 486 → 11 948), an out-of-order backfill, or two drivers logging the same car.

- Checks on every write (not just capture): order against date-neighbors, and implied pace (default flag above ~1 500 km/day, per-vehicle tunable).
- The discrepancy is shown inline – amber underline on the offending field plus the conflicting entry quoted ("Aug 17 already recorded 119 486 km") – with ranked suggestions: fix odometer · fix date · move entry.
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
