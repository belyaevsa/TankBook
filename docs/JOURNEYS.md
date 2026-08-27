# Tankbook – Customer Journey Maps

*Mobile UX companion to `VISION.md` (features, flows) and `DESIGN.md` (visual language). Each journey names its trigger, walks the stages with what the user does / thinks / feels, flags pain points (⚠) and design opportunities (→), and ends with the metric that tells us the journey works.*

## Personas

- **P1 · The commuter (Andrus, diesel Volvo).** Logs every fill-up for years, has history in another app, cares about consumption trends and typo-free data. Fills up 3–5×/month, often in a hurry, sometimes abroad.
- **P2 · The mixed household (Marta, petrol SUV + family EV).** Wants one place for both cars and one honest answer: what does each cost per 100 km? Charges at home and at public DC chargers.
- **P3 · The CIS driver (Sergei, petrol sedan, RU/KZ).** Receipts always carry a fiscal QR. Expects fines/insurance reminders from local apps, distrusts subscriptions, burned by dead-server apps before.

Journeys are grouped by lifecycle: **acquisition → core loop → periodic → edge/exit**. J2–J5 are the make-or-break ones.

---

## Acquisition

### J1 · First launch, empty garage
**Trigger:** installed from the App Store after seeing "scan, don't type".
**Goal:** from tap to first logged entry in under 3 minutes, no account asked.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Open | Skips a 1-screen promise ("Point. Scan. Done.") | "Show me, don't pitch me" – impatient | ⚠ Every extra onboarding screen loses users → one screen, skippable |
| Add car | Types make/model or plate, picks powertrain, home currency pre-filled from locale | "That was quick" | → RU locale defaults to ₽ + RU fuel grades; photo of car optional, adds emotional ownership |
| First entry | Prompted: "Have a receipt from your last fill-up? Scan it" | Curious – this is the promised magic | → The first scan IS onboarding; a bundled demo receipt if they have none |
| Payoff | Sees the Pump Card lock ✓, entry saved | Delight or disappointment – nothing in between | ⚠ A failed first scan kills trust permanently → confidence gating, instant manual fallback without losing the photo |

**Success metric:** ≥70% of installs log a first entry in session 1; time-to-first-entry < 3 min.

### J2 · Switching from another app
**Trigger:** frustration with incumbent (ads, paywalled export, dead sync) + years of history they refuse to lose.
**Goal:** full history alive in Tankbook in one sitting.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Export | Finds export in old app (Fuelio/Drivvo/Fuelly/Spritmonitor/CarScope/My Fuel Manager) | Anxious – "will it all come across?" | → In-app illustrated guide per source app, since their UIs hide export |
| Import | Shares the file to Tankbook (share sheet / file picker) | Skeptical | → Auto-detect format; never ask "which app is this from" if the file says it |
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
| Scan | Points at crumpled thermal receipt | "Will it read this?" | ⚠ Glare, dark canopy → torch auto-suggest; keep the photo regardless of OCR result |
| Confirm | Pump Card pre-filled; cross-check line locks ✓; types odometer, sees "+907 km since last" | Trust building with each correct field | ⚠ One wrong digit typed in odometer ruins consumption → live delta as sanity check; low-confidence fields dimmed until tapped |
| Done | Save → haptic → "6.8 L/100km – best this year" | Micro-reward; closes phone | → The insight one-liner is the habit hook, not the stored row |

**Mixed receipt variant:** the slip carries fuel + car wash + coffee. The arithmetic check finds liters × price matching the *fuel line* (not the grand total) – that mismatch IS the detection. The Pump Card shows the fuel block as usual, plus an "Also on this receipt" section listing the other lines, each one tap: add as expense (pre-categorized: wash → `.wash`) or skip as not car-related. Added lines become Expenses sharing the same receipt photo and `purchaseGroupId`; the Log shows them as one grouped moment. Fallback: line detection fails → the fill-up saves with the fuel numbers and the receipt attached; the user can add the wash from the entry later ("add expense from this receipt").

**Success metric:** median capture-to-save < 15s; ≥80% of fill-ups logged via capture (not manual form); D30 retention of users with ≥3 captures; mixed receipts with correctly isolated fuel totals ≥95% (wrong grand-total attribution is a stats-poisoning bug).

### J4 · No receipt – pump display photo
**Trigger:** station prints no receipt / receipt skipped; the pump still shows liters, price, total.

Same shape as J3, with the deltas: camera pointed at the pump display before hanging up the nozzle (→ prompt tip on first use: "no receipt? Shoot the pump"); OCR reads the three numbers, arithmetic triple-match assigns them (⚠ glare/LED segments – the spike's ~95% gate applies before this ships); station name auto-suggested from location + favorites. This journey is **unowned by any competitor** – it must feel as reliable as J3 or not exist.

**Success metric:** pump-photo share of all captures (target ≥15% – proves the niche is real); extraction accuracy ≥95% on the confirm screen.

### J3b · Type it (the peer path, every locale)

**Trigger:** the user would rather type than aim a camera - or the camera cannot deliver: a
faded thermal receipt, a dark forecourt, gloves on, a pump display that lost its decimal
points, a corporate fuel-card slip with no QR, or simply a preference.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Reach it | Taps "Type it" - present next to capture on Home, both empty states, the guest layout and inside Capture | "I don't have to fight the camera" | → **Never behind a failed scan.** Reaching manual entry must not require attempting a capture first (hard rule 15) |
| Fill | Types total and litres; price derives; odometer pre-filled from last known | Fast, predictable | → Same `ConfirmManual` sheet the capture paths land in - one screen, not a lesser one |
| Save | Saves | "That was quicker than scanning" | → The cross-check locks exactly as it does for a scan |

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

### J5 · Fiscal QR fill-up (P3, RU/KZ)
**Trigger:** every receipt has an FNS/ОФД QR square.

| Stage | Doing | Thinking / feeling | Notes |
|---|---|---|---|
| Scan | Points capture at the QR corner | "Апps never do this" | → Same capture surface auto-detects QR vs text – zero mode switching |
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

### J6 · EV charge (P2)
**Trigger:** public DC session ends in a charging app; or the weekly home-charging ritual.

- **Public:** share the charging app's receipt screenshot to Tankbook (share extension) → same confirm card, in `headlight` cyan, kWh instead of liters → saved against the EV. ⚠ Dozens of charging-app layouts → the LLM-normalization layer earns its keep here; screenshots are the one place cloud fallback will be common.
- **Home:** quick-entry "home charge" with kWh from the wallbox (or charge % delta → kWh via battery size) × stored home tariff. → Tariff lives in vehicle settings, one-time setup; night/day tariff split later.
- **Payoff:** Trends shows both household cars in €/100 km on one chart – the moment Tankbook does what no competitor does.

**Success metric:** % of EV owners logging ≥4 sessions/month; the comparison screen's weekly views.

### J7 · Service visit
**Trigger:** leaving the workshop with a multi-page invoice, or DIY oil change in the garage.

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

⚠ The completion→entry→next-cycle chain is where competitors leak: a reminder marked done with no record and no follow-up is a dead end (Drivvo's pattern). Ours is a loop.

**Success metric:** completed reminders that create an entry ≥50%; recurring reminders auto-rescheduled 100%.

### J8 · The monthly glance
**Trigger:** idle curiosity, end of month, or the "August: €212 on the Volvo" notification (opt-in).
**Journey:** open Trends → hero consumption metric with trend arrow → monthly spend bars → price-per-liter line per station brand ("Shell costs you 4% more than Neste"). Feeling sought: *control*, not accounting homework. → Every chart answers a sentence-shaped question; no chart junk. Exit within 60 seconds, satisfied.

**Success metric:** ≥40% of MAU open Trends monthly; session length short (it's a glance, not a report).

### J9 · Anomaly nudge
**Trigger:** app-detected consumption drift ("+12% over 3 months").
**Journey:** gentle `warn`-amber card in the Log (never a push alarm) → tap explains the evidence (chart of the drift, possible causes: tire pressure, air filter, winter) → dismiss ("it's winter") teaches the model, or act → creates a service reminder. ⚠ False alarms erode trust fastest → thresholds conservative, seasonality-aware, always dismissible with a reason.

**Success metric:** anomaly cards acted on or explicitly dismissed ≥70% (ignored cards = noise signal).

### J10 · Cross-border trip (P1)
**Trigger:** filling up in Poland with a Euro-currency car.
**Journey:** scan as always → currency auto-detected as PLN from the receipt → card shows both: "289.50 zł · ≈ €67.79 at today's rate" → saved with the historical rate snapshot; trends stay in the car's home currency, original always preserved on the entry. No settings visited at any point.

**Success metric:** multi-currency entries with zero manual currency picks.

---

## Edge & exit

### J11a · First sign-in (there is no "registration")
**Trigger:** the user wants a second device, or taps "Sign in to sync" in Settings – typically weeks after installing, with a local log already on the phone.

| Stage | Doing | Notes |
|---|---|---|
| Choose | Sign in screen → Apple or Google, one tap | No form, no password, no email verification – the provider's verified token IS the registration (`POST /auth/session` creates the account on first sight). The word "register" appears nowhere in the app |
| Create | Backend finds no account for this identity → creates it | Invisible; same screen, same tap as a returning sign-in – the user never has to know which case they are |
| First push | The local log uploads (everything becomes the account's record stream) | Settings card flips to "Synced just now · 1 device". Nothing on the phone changed – sync added, not migrated |
| Confirm | "Your garage now follows your account" | One line, no ceremony |

**⚠ The wrong-provider trap:** the user signed in with Google on Android but taps Apple on the new iPhone → two identities, two accounts, and the "restore" finds an empty account. v1 ships **no account linking**; two mitigations. *Proactive:* the Sign in screen carries a warn-amber notice at the decision moment – "Pick one and keep it. Apple and Google create separate accounts – use the same one on every device." *Reactive:* honest detection – if the signed-in account is empty *and* the user came through "Already use Tankbook?", say "Nothing is stored under this Apple ID. Last time, did you sign in with Google?" with a one-tap provider switch – never show an empty garage as if their data were gone. (Same guard in reverse when a local log exists: J11a never overwrites local data – it uploads it.)

**Success metric:** first-sign-in completion ≥90% from the Sign in screen; wrong-provider recoveries resolved in-flow ≥95%; zero "my data disappeared" reviews traced to provider mix-ups.

### J11 · New phone / platform switch
**Trigger:** bought a new iPhone – or, later, moved to Android.
**Entry points:** on a fresh install, the Welcome screen's third path – "Already use Tankbook? Sign in" – exists precisely for this (an Android→iOS migrant or a reinstall must never be funneled into "Add your car" as if they were new); on a running app, Settings' account card.
**Journey:** Welcome → Sign in (Apple ID / Google – the same account works across platforms, that's the whole point of the neutral identity) → the "Welcome back" restore screen shows the F7 verification stats *before* finishing (cars, entry count, date range, last odometer with its source device – "from your Android phone, yesterday") → text records land in seconds, the garage is immediately usable, photos download in the background by recency → "Open my garage." ⚠ The category's graveyard moment (Fuelly, Мой Авто) → restore must be boringly reliable, tested in CI, and the local file export always available as the user-held fallback.

**Success metric:** restore success ≥99.5%; zero data-loss reviews – the reviews that kill this category.

### J12 · Second driver (family car)
**Trigger:** both partners fuel the same car.
**Journey (v2):** owner shares the vehicle (backend vehicle-sharing over the sync protocol – `SYNC.md` phasing) → partner accepts, sees the same log; both capture; entries show who logged them → consumption math merges both drivers' fill-ups seamlessly. ⚠ Odometer entered out of order by two drivers → sort by odometer, not timestamp, and flag impossible sequences as `warn`.

**Success metric:** shared vehicles ≥10% of active garages; conflict-flag rate <1% of entries.

### J13 · Selling the car
**Trigger:** the Volvo is going to a new owner.
**Journey:** Garage → vehicle → "Export history" → a clean PDF service-and-fuel dossier (resale value in paper form) plus CSV/JSON → then archive the car (history retained, out of active stats). → The dossier is a quiet marketing artifact: it carries the app's name into a stranger's hands at the exact moment they acquire a car.

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
| Recovery | User types 3 numbers (total, liters, odometer), price/unit auto-derives, saves | Typing 3 fields ≈ 20s – degraded, not broken. The receipt photo remains as evidence |
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
- **The wait has a 3-second budget** (`API.md` -> "The device's side of `/extract`"). At 3 s the UI stops presenting the call as something to wait for and says so, naming the next step: carry on with what was read locally. The request may still finish in the background - the budget bounds the **user's** wait, not the work - and its late answer may fill only **blank, untouched** fields, as a suggestion (hard rule 13). After save it arrives nowhere.
- **The upload is compressed on device** before any of this, because on a forecourt signal the upload is the slowest step in the flow. How hard it may be compressed is settled by the corpus, not by taste: if compression costs extraction hits, it is too aggressive.
- If fallback is unreachable: low-confidence fields stay dimmed with "check these – enhanced reading unavailable right now." User confirms or fixes by hand, saves. A retry never re-asks the user – if the photo later re-processes successfully in background, we *don't* silently change a saved entry; corrections post-save are the user's alone.
- If quota is spent: same UX, plus a quiet, non-blocking note in Settings – never an upsell interstitial mid-capture. ⚠ Monetization pressure must never leak into the capture flow; that is the incumbents' disease.

**Metric:** capture abandonment when fallback is down: no different from baseline.

### F5 · Fiscal QR scans but lookup fails (P3)
**Trigger:** the QR decodes, but full line-item data needs an FNS/ОФД fetch that times out, or the fiscal service is down (common).

- Parse locally what the QR string itself carries (total, date-time, fiscal IDs) → card pre-fills total and date instantly, liters/price left for the user or a later fetch.
- Enrichment retries in background after save; when it lands, it *fills blanks* only – never overwrites anything the user typed.
- Copy: "Fiscal service isn't answering – saved the total from the QR itself."

**Metric:** QR entries saved on first attempt ≥95% regardless of FNS availability.

### F6 · Import file won't parse (J2's failure)
**Trigger:** truncated export, exotic CSV dialect, an app version we haven't seen, wrong file shared entirely.

- Partial parse is the goal: import what parses, then show "214 of 220 entries imported – 6 rows need a look," with the 6 raw rows listed for inline fix or skip. All-or-nothing imports are how switchers bounce.
- Nothing parses at all → name the reason plainly ("this looks like a PDF report, not a data export – here's where the CSV export lives in Drivvo") and offer to send us the file (explicit consent) so the importer learns.
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
  with a total and an odometer imports as a service entry (hard rule 8).

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
- Rate arrives later → conversion fills in; rate *never* exists (feed gap) → entry shows original currency in trends with a footnote count ("3 entries pending rates"), and the user may set a manual rate per entry.
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
3. **Failure always degrades to the manual form pre-filled with whatever was read** – captured photos are never discarded, and the user never re-does work.
4. **One emotional beat per journey.** J3's beat is the ✓ lock; J5's is "exact, free"; J6's is the two-car chart; J13's is the dossier. Everything else stays quiet.
