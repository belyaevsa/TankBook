# Tankbook – Errors & Warnings Catalog

*Per-screen inventory of everything that can go wrong, what the user sees, and what they can do next. Law: **no message without a next step** – every error/warning names its cause and carries at least one action; the user is never left alone with a fact. Companion to `JOURNEYS.md` (F-series), `SCREENMAP.md` (where back leads), `API.md` (error codes), `DESIGN.md` (voice: say what happened, say the fix, never apologize, never vague).*

**Server-sourced rows key on the `code` (PR.9, docs/API.md -> "Error envelope").** A row whose condition
names a `code` (e.g. `clock_skew`) is rendered because the server said that code, never because the
client guessed it from a status. A code the client has never seen falls back to the status-based
message – the row that names only a status is that fallback. A status row that names no code is
status-rendered today and stays exactly as written for an unknown code.

## Severity vocabulary (from DESIGN.md)

| Level | Looks like | Used for |
|---|---|---|
| **Hint** | `inkSoft` grey inline text/chip | Nothing is wrong, something is pending ("rate pending · converts when online") |
| **Warn** | amber underline / badge / card | Needs the user's attention or decision (cross-check mismatch, timeline conflict) |
| **Blocking alert** | system dialog | Rare: destructive confirmations and truly-cannot-proceed cases only |
| **Toast** | one line, auto-dismisses | Outcome reports ("Saved", "Synced. 2 entries need a look" – tappable when it carries work) |

Global rules: being offline is **never** an error (F3/S7 – features work; pending things show hints); a failed network call retries silently with backoff before ever surfacing; anything surfaced while the user is mid-task is non-modal.

## Per-screen catalog

### Welcome
| Condition | Shows | Next step |
|---|---|---|
| – | Welcome has no failable operations; all three paths lead onward | – |

### Sign in
| Condition | Shows | Next step |
|---|---|---|
| Provider sheet cancelled by user | Nothing – silent return to Sign in | Both buttons still there; "Not now" leaves |
| Provider auth fails (Apple/Google error) (`token_invalid`, `provider_unsupported`) | Inline under buttons: "Apple couldn't sign you in – try again, or use Google." | Retry same provider · switch provider · Not now |
| Our backend unreachable after provider success | "Signed in with Apple, but our sync service isn't answering. We'll finish setting up automatically – you can use the app meanwhile." | Continue to app (token retries in background) · Not now |
| Token clock-skew / device date wrong (`clock_skew`) | "Your device's date looks off (Aug 2019) – sign-in needs it correct. Set the date and time in Settings > General > Date & Time." Only the server knows the rejection was a clock skew, so only its `clock_skew` code can raise this row – a retry cannot fix a wrong date | Open Date & Time settings (deep link) · Not now |

### Restoring (welcome back)
| Condition | Shows | Next step |
|---|---|---|
| Empty account + user came via "Already use Tankbook?" | "Nothing is stored under this Apple ID. Last time, did you sign in with Google?" (J11a) | Try Google (one tap) · start fresh · sign out |
| Pull interrupted (network drop mid-restore) | Progress pauses: "Connection dropped – restore continues when you're back online." Entries already pulled remain usable | Open my garage (partial, keeps filling) · retry now |
| Server 5xx / down | "Sync service unreachable – your data is safe on the server. You can import an export file, or it will all arrive when the service is back." (F7) | Import a file · wait (auto-retry) · sign out |
| Wrong account realized mid-restore | Always-visible "Not my account · sign out" | Sign out → Welcome |
| Photo download stalls / user wants out (PR.6) | The "Receipt photos" progress carries a **Cancel** while downloading | Cancel (stops the download and signs out; the app's local data and the already-pulled entries stay) · Open my garage (photos keep filling in the background) |

### Add car
| Condition | Shows | Next step |
|---|---|---|
| Name empty on save | Warn underline on Name: "Give the car any name – you can change it later." | Type; save re-enables live |
| Odometer missing/implausible (e.g. 12 km on a 2015 car) | Warn: "That's the total distance the car has driven – check the dashboard." | Fix · confirm it's right (one tap – new cars exist) |
| Catalog lookup offline | Hint: "Suggestions unavailable offline – you can fill tank size later in Garage." | Continue manually; nothing blocks |

### Home (incl. guest/empty)
| Condition | Shows | Next step |
|---|---|---|
| Entry timeline conflict (F9a/S3) | Amber badge on entry; footnote "N entries excluded" | Tap badge → Edit entry with discrepancy pre-highlighted · Tap the footnote → the excluded entry when one is out, else the excluded-entries list that names all N and each one's reason (RV.141) |
| Possible duplicate (S2) | Combined card "Possible duplicate – Shell, 42.3 L logged twice" that shows BOTH members as rows – time of day, odometer, total, and which one carries the attachment (the Merge survivor) – each opening its own edit screen | Open either entry · Merge · Keep both (one counts until resolved) |
| Entries pending a rate (F9) | Passive footnote "N entries pending rates" (real plural rules, EN + RU) with a **"Check for rates"** action (RV.106: hard rule 7 - the count names its next step). **The month divider never prints a bare `0 €` while rows wait** (RV.106): a month whose rows are all pending shows "N entries pending rates" where the figure would be; a mixed month shows its known sum with the pending phrase beneath it. **The divider's figure is always the currency its rows were recorded in - never the car's (RV.145)**: a euro month on a dollar car reads `91 €`, and a month whose known rows span currencies lists per-currency subtotals (`91 € · 45 $`). **RV.111:** once a demand pass has reached the provider and still left a pre-window row pending, the footnote swaps "Check for rates" for the dead-end line "No rate exists for these dates. Add a manual rate to each entry." - it stops promising a check that cannot help. **RV.132:** a tap is acknowledged IMMEDIATELY - the action becomes "Checking for rates…" in place, before the network resolves - and the demand's outcome is then told apart (a filled or nothing-pending drain posts a toast; the dead end stays the footnote's own copy; offline stays silent), see the note below | Check for rates (RV.111: a DEMAND drain over the pending rows' own dates - the launch refresh's rolling 400-day pack cannot reach a row dated years back) · wait (rows fill automatically once the rate archive reaches their dates - RV.88; the divider only reports what the data supports) · edit the entry → the conversion card offers a manual rate (a rate the service can never serve, see the note below) |
| Archived car returned via sync (S5) | Quiet Garage notice "Volvo came back with 1 new entry – stays archived." | Delete again · keep |
| Post-outage sync batch (S7) | Toast "Synced. 2 entries need a look" | Tap → Log filtered to flagged entries · ignore (badges remain) |
| Reminder due | Amber banner "Insurance renews in 12 days · View" | View → Reminders |
| Consumption drift detected (J9) | Amber insight card in the Log, in the car's own unit, naming BOTH windows compared ("Consumption is up 21% vs a year ago" + "Last 90 days: 6.5 L/100km · a year earlier: 5.4 L/100km"); tap → evidence (chart of the drift + what it costs per month at the driver's own recent prices – RV.121, never a guessed cause, docs/VISION.md → "What we will not tell a driver") | Act → creates a service reminder · dismiss with reason (teaches the model) – both always present (a card with only dismiss teaches nothing; only act is a nag) |
| First fill logged, no segment yet (D4) | Hint on vitals: "One more full tank and your consumption appears" | Capture (the card links it) |

**The excluded count names its entries and each one's reason (RV.141).** The "N
entries excluded" footnote is a next step on Home AND Trends (hard rule 7): with
ONE entry out it opens that entry's editor; with MORE it opens the
excluded-entries list (docs/SCREENMAP.md -> "Excluded entries"), which shows ALL
N - the conflict-flagged entries (F9a/S3) plus the non-counting members of
unresolved duplicate pairs (S2) - newest first, each row naming its reason
because the fix differs: a row reads "Timeline conflict – check the odometer or
date" or "Possible duplicate – Merge or Keep both", and a tap opens the entry.
The list is CAR-scoped because the count it answers is (the count comes from the
selected car's `HomeStats`; the account-wide "Needs a look" list is a different
population - conflicts only, every car - and is NOT the destination). The count
and the list are ONE derivation (core `ExcludedEntries.derive`: conflicts union
the S2-excluded members), so the destination never shows fewer - or more - rows
than the number the user just tapped. **The footnote reads as a link, not a
label (PJ.57):** amber is attention, never action (hard rule 5), so the tappable
footnote carries the trailing `chevron.right` in `inkSoft` - the app's one
"this row leads somewhere" affordance (docs/DESIGN.md, RV.83) - and is never
recoloured; a passive caption would render the phrase alone.

**Imported money and the drain (F9, RV.88).** The import commit writes foreign rows
rate-pending on purpose (hard rule 3: `rateDate` is the ENTRY date, and a 2015 rate is not
on the device at import time). It then runs a drain over exactly the rows it wrote: it asks
the rate service for the dates they span (`GET /rates/pack`, chunked under the server's
400-day cap) and backfills each at its OWN day's rate - never today's - silently (S8). The
footnote drains as rows fill and disappears at zero.

**A row the drain cannot resolve is told apart from one that will convert.** The rate
service's archive is bounded (docs/SCHEMA.md -> Exchange rates): the app-bundle seed pack
covers one month, the rolling refresh the last 400 days, and a demanded date resolves only
when a feed's archive covers it - ECB now serves its own whole history since 1999 (RV.135),
the CIS feeds serve theirs - so a row in a pair outside every feed's archive has no rate
that will ever arrive. Such a row stays rate-pending and is
counted: it shows its original amount and is excluded from home-currency totals. The honest
next step for it is the entry's conversion card, where the user sets a rate manually (hard
rule 13) - the footnote never promises a conversion the service cannot deliver. Nothing is
silently zeroed and nothing is converted at the wrong date.

**A month divider states only what the data supports (RV.106).** A rate-pending row's home
amount is not known, so it is never summed as zero: `LogStream.MonthTotal` is `.complete`
(exact figure - every row converted), `.partial` (some rows converted - the known sum with
the pending count) or `.pending` (no row converted yet - the divider says "N entries pending
rates" instead of a number). `0 €` beside rows that carry no amount was a wrong number, not a
missing one, and is not an option. Rows whose rate the server had not yet published at import
time DO resolve: they sit inside the rolling 400-day pack window, so a later launch (or the
footnote's "Check for rates") re-fetches the pack and the S8 backfill fills them - measured by
RV.106's L4 reproduction.

**A month total is stated in the currency its rows were recorded in, and a mixed month lists
per-currency subtotals (RV.145, decided 2026-09-08).** A history can legitimately hold rows
homed in two currencies (docs/SCHEMA.md -> Money: re-homing touches only rate-pending rows, so
rows converted before a Garage home change keep their old home currency). A derived figure over
such rows is printable only when its addends share ONE home currency; the symbol printed beside
a total is always the currency the total is denominated in - never the vehicle's. The Log
divider's `91 $` above rows of `36.06 €`, `28.78 €` and `26.59 €` (36.06 + 28.78 + 26.59 =
91.43) on a USD car was the figure and the symbol read from two different objects. So the
month's stated figure is `.complete(amount, currency)` / `.partial(amount, currency,
pendingCount)` - the amount carries its currency with it - and a month whose KNOWN figures
span home currencies is `.mixed`: it displays **per-currency subtotals**, each figure exact
with its own currency's symbol ("91 € · 45 $" - the same decision SCHEMA.md recorded: "stats
mixing home currencies render per-currency subtotals (rare, surfaced honestly)"). Chosen over a
"mixed" marker because the numbers are real and exact and hiding them tells the user less than
the rows beneath already show, and over the dominant currency's subtotal because an understated
figure that omits a whole currency is the same lie in a smaller font. **No currency is converted
to force one number** (hard rule 3, RV.88's defect). A `.mixed` month with rows still waiting
on a rate carries the pending phrase beneath the breakdown exactly as a `.partial` month does.

**Every other surface that derives a month's spend states the same honesty (RV.112).** The tile
and the Trends series used to sum a pending row as zero while the divider did not - the shape
survived RV.106 because its fix stopped at the divider. All three now reduce through ONE shared
accumulator (`LogStream.MonthTotal.Accumulator`): the Home vitals tile and the Trends spend tile
show the same `.complete` / `.partial` / `.pending` classification as the month's divider, and a
`.mixed` month prints the same per-currency breakdown (RV.145). A
`.partial` current month prints its KNOWN sum with the "N entries pending rates" phrase as the
tile's caption (visibly partial, never a bare total); a `.pending` month prints NO number at all -
the tile is omitted, exactly as any other data-hungry vital is omitted, and the F9 footnote below
says why. A `0 €` beside rows that carry no home amount is a wrong number wherever it appears,
not just on the divider. **The purchase-group header states the same honesty (RV.166).** A receipt
whose known lines total 30.00 EUR beside a rate-pending line is `.partial`: its header prints the
known sum with the pending phrase beneath it, never a bare `30.00 €` that reads as the whole
receipt - the group's figure is the same `MonthTotal` from the same accumulator, so a group header
and the month divider that sums it can never disagree about the same receipt. **The header never
stays silent where the divider over the same members speaks (PJ.56).** A receipt whose members are
ALL rate-pending is `.pending`: its header prints "N entries pending rates" in place of a figure -
never blank space over a divider that already says the same sentence - and a receipt whose known
lines span home currencies is `.mixed`: its header prints the per-currency breakdown
(`91.02 € · 8.00 $`, RV.145's divider vocabulary in the group's own two-fraction figure style),
never a "mixed" marker and never a summed cross-currency total (hard rule 3). A `.mixed` receipt
that still has a member waiting carries the pending phrase beneath the breakdown exactly as
`.partial` does. `.pending` is reachable - a foreign receipt logged offline and dated outside
every rate source's reach stays pending, and `.mixed` is reachable too, through the same mechanism
that makes a month mixed (RV.145): a member snapshotted before a Garage home change keeps its old
home currency forever, while an RV.144 amount/currency edit of one member of the same receipt
re-homes that member to the car's current home - one edited line beside siblings still snapshotted
under the old home is a real, if rare, state.

**A rate-pending month is a GAP in a Trends chart, never a dipped point (RV.112).** The monthly
spend and cost/km series plot a point only for a `.complete` month. A `.partial` month is not
plotted at its known-so-far sum and a `.pending` month is not plotted at zero - both would read as
"spend fell" (hard rule 2). Each such month is a hole in the series: the line chart BREAKS its
path there and the bar chart leaves the slot empty, so the absence reads as unknown, never as a
drop. A `.mixed` month (known figures spanning home currencies, RV.145) is a hole for the same
reason: no single number exists to plot. The F9 footnote carries the pending phrase whenever such
a month is inside the plotted window. **The windowed COST / KM headline follows the monthly series,
one surface further out (RV.147).** A cost-per-km is a RATIO: a partial numerator (pending rows
omitted) over a COMPLETE odometer denominator is low by an unknown amount while looking perfectly
plausible - worse than a visibly missing number - so the tile reports nothing while any
money-bearing row inside its 90-day window is still waiting on a rate, and nothing when the
window's known figures span home currencies. The tile appears the moment the rates land; until
then the F9 footnote says why.

**A row dated outside the pack window needs the DEMAND check, and its empty answer is a dead
end (RV.111).** The launch pass refreshes the rolling 400 days only, so a row from a
multi-year import committed while the archive was still publishing is never asked for again
by any automatic path - and the old "Check for rates" could not reach it either, because it
re-ran the same rolling refresh. The check now runs a demand drain over the pending rows'
own dates (`MoneyBackfillService.demandDrain`, chunked under the server's 400-day cap), so
an old row is actually asked. If the provider is reached and the row is STILL pending, its
date is one no feed's archive covers (docs/SCHEMA.md -> Exchange rates - before 1999, a
currency ECB never listed, or a non-publishing day beyond the carry window), and the
footnote stops offering "Check for rates": it names the
manual rate on each entry instead, in its own localised phrase - never another promise that a
check will help. An offline check is a non-event and never triggers the dead-end copy (the
row may simply resolve on a later launch).

**A "Check for rates" tap reports its outcome (RV.132).** The demand drain is the only
USER-INITIATED rate door, so it is the one place the rate flow may speak: the automatic
launch pass stays silent (S8), and the distinction the surfaces write down is
user-initiated vs automatic, never "rates are noisy now". The surface split:

- **In-flight acknowledgement, in the footnote.** The moment the action is tapped it
  becomes "Checking for rates…" in place (a live region), BEFORE the network resolves - a
  slow provider never reads as a dead button. It stays until the drain returns, then the
  outcome below takes over. Never a modal, never blocking (a notice, this table's severity
  vocabulary).
- **Filled rows → a toast naming the count: "N entries converted"** (real RU plural rules:
  запись конвертирована / записи конвертированы / записей конвертировано). A fill drains
  the footnote as its standing state, but the tap itself was the user's and a user-initiated
  fill is exactly what S8's silence does NOT cover.
- **Asked and the provider has none → the footnote's own dead-end copy** (RV.111 above).
  Unresolvable rows flip the footnote to the manual rate - a standing, persistent state - so
  no toast competes with it.
- **Nothing pending → a toast: "Rates are up to date".** Distinct from "asked and answered
  empty" by construction (`MoneyBackfillService.DemandOutcome`: `.nothingPending` is not a
  `.drained` run - nothing was asked, so nothing is implied about the provider). Reached when
  a tap races a silent fill, never a wrong claim about what the provider holds.
- **Never reached the provider (offline) → nothing.** An offline check is a non-event (hard
  rule 1, F3): the footnote stays exactly as it was and the row may resolve on a later
  launch. The immediate acknowledgement already told the user the tap registered.
- **Low Power Mode never defers this check.** A user-initiated demand passes `.userInitiated`
  (RV.111) and `LowPowerPolicy` never defers a user-initiated rate fetch, so there is no Low
  Power deferral message for a tap - the one rate refresh Low Power does defer is the
  automatic pass, which is silent (S8). If a demand drain is ever invoked with a background
  trigger, that deferral must be reported and must name Low Power Mode by name (the one
  outcome the user can act on); today it is structurally unreachable and is pinned by L1 tests.

### Capture (camera)
| Condition | Shows | Next step |
|---|---|---|
| Camera permission denied (F8) | Capture opens the manual form with a top card: "Scanning needs the camera – enable in Settings." | Deep link to Settings · Type it (full manual path) · Photos (library) |
| Too dark / glare detected | Live hint: "Dark – tap for torch" | Torch toggle · shoot anyway |
| Nothing detected for ~4s | Hint: "Fill the frame with the receipt – or type it instead." | Keep trying · Type it |
| Storage full (can't save photo) | Warn sheet: "No space to keep the photo. The entry can still be saved without it." | Save without photo · manage storage (deep link) |

#### The capture review step (RV.5)

The shot is shown before anything is read from it, with one question - "Can you read the total
on it?" - and three actions: **Use this**, **Re-take**, **Type it**.

| Condition | Shows | Next step |
|---|---|---|
| A shot has been taken (every shot, no condition) | The photo fitted to the screen under "Check the photo" / "Can you read the total on it?" | Use this (runs the recognition, then Confirm) · Re-take (back to the camera, nothing kept) · Type it (the form for the selected mode) |
| The photo is unreadable - blurred, glared, half a receipt | **Nothing.** The app makes no judgement about the frame here | Re-take · Type it - both already on screen, so the "error" has no message because it needs none: the user can see the problem and both fixes are one tap away |

Three things this screen is deliberately not:

- **It is not an error surface.** Nothing on it is amber and nothing says a scan failed - at
  this point nothing has been read. The severity vocabulary does not apply because there is no
  condition to report.
- **It does not frame typing as the failure branch** (hard rule 15). "Type it" sits on the same
  row as "Re-take", the same size and the same weight, and its copy never says typing is what
  you do when the photo is bad.
- **It cannot become a dead end** (hard rule 7). Every state of it carries three next steps, and
  Re-take is itself the back path, so there is no state in which the only option is to stare at
  a bad photo.

#### The alpha-testing disclosure (P6.10)

Recognition is honest about itself: the corpus measures **receipts 88/175** and **pump 21/84** today, and Vision returned a **wrong digit at confidence 1.00** on `pump-004` (`docs/EXTRACTION.md`) - which is why pump mode ships off (`PumpPhotoGate`). So the capture surface carries a passive disclosure:

> "Recognition is in alpha testing – it can't get every field right yet. Your captures improve it, so keep them coming and bear with mistakes."

- **It is a disclosure, not an error.** Never `warn` amber, never a next-step action bar (rule 5: no action bar on a non-error). It renders as an `inkSoft` footnote, the same weight as `PendingRatesFootnote`, directly above the shutter - the last thing read before pressing it. It lives **only on the live camera surface**: never on a Confirm sheet, never on the manual form, never between shutter and result (it is a static part of the surface, so mid-capture is structurally impossible).
- **Placement, persistence and dismissal (decided P6.10):** it appears on every capture-surface open while active. A tap on the × hides it for the rest of the **calendar day**, persisted in UserDefaults (a same-day relaunch stays dismissed). It **retires permanently** once the device has logged **3 captures** (any entry, all live vehicles - the app's own floor-3 experience threshold) **or** the notice has been dismissed on **3 separate days**, whichever comes first: after three captures the user judges recognition from their own scans; after three dismissals the notice has been read three times and further repetition is a nag, not teaching. It is a feature to cut wholesale when recognition exits alpha (the gate data says so), not a flag.
- **The "send us this case" path is deliberately not wired into the notice.** Rule 5 forbids an action bar on a non-error, and the one place feedback lives already exists: About & feedback (`POST /feedback`, `docs/API.md`), reachable from Settings. The notice's ask is to keep captures coming - a scan that goes wrong is a case for that screen, exactly as the import wizard's "send us the file" routes there (line below).
- It must never steer a user toward typing instead of capturing (hard rule 15): scanning and typing are peers, and the whole point of the disclosure is to keep captures flowing, not to retire them.

### Confirm (all variants: standard / foreign / mixed / manual)
| Condition | Shows | Next step |
|---|---|---|
| Cross-check mismatch (F2) | Amber underline on the suspect field + "these don't multiply up – check the amber field"; check line refuses to lock | Tap field → source crop shown → correct · save anyway (entry flagged) |
| Low-confidence fields (F1 partial) | Fields dimmed at 60% | Tap to confirm or edit each; save enabled once required fields exist |
| OCR read nothing (F1) | The Manual variant IS the answer: photo kept, a quiet inkSoft caption "Couldn't read this one – type it, the photo stays attached." (never amber - this is not an error state, hard rule 5; the caption is a hint, never a banner), Total focused on appear | Type 3 fields · photo stays attached regardless |
| Currency low-confidence (schema rule) | Currency chip amber: "Which currency is this?" – never silently converts | One tap on the chip row |
| Currency chips caption (home-currency state, RV.146) | The `inkSoft` caption under the chip row while the entry is in the home currency: EN "Your currency first, then recent and nearby · a foreign amount converts to %@ automatically", RU "Сначала ваша валюта, затем недавние и соседние · иностранная сумма автоматически переводится в %@", with the car's home currency code in the slot. It describes the offer's ACTUAL order (docs/SCHEMA.md → Currency offer: home first, then the car's recent currencies, then the device region's) – copy that promised "Recent first" was a lie the code did not implement, which is a hard rule 7 problem on its own | None – the row caps at what fits and "More…" is the complete list |
| No exchange rate for that date (F9) | Hint on conversion card: "≈ – · converts when online", with the manual-rate entry offered on the card itself (hard rule 7: the hint names its next step) | Save anyway (converts later) · enter rate manually (on the card) |
| Cloud-fallback unavailable/quota spent (F4) | Hint: "check these – enhanced reading unavailable right now"; **never an upsell here** | Confirm/fix by hand · save |
| Cloud reading still in flight (F4; **RV.57 replaced RV.8's spinner banner**) | The proceed note, a quiet `inkSoft` hint with a ×: "A more reliable reading may still arrive. You can proceed now." Never amber (nothing needs a decision), never a spinner (the point is that the user need not wait), and the request is **not** cancelled at the 3 s budget – it keeps running in the background | Dismiss · proceed now · save whenever ready. A late answer lands in the **inbox**, never as a value that moves under the user's cursor (RV.57, hard rule 13) |
| **Dead session on `/extract` (RV.65): a 401 the refresh could not fix** (`token_invalid`) | A `warn` card on the cloud-extract capture (the Confirm sheet), dismissable with a × and blocking nothing: "Your session has expired – sign in again to use cloud reading. This entry still saves." It appears when the cloud reading ends in an auth failure - the refresh was rejected (RV.26's `authExpired`) **or** it handed back the same bearer, which means the image was **not** re-uploaded (RV.65: a 401 replay happens only when the token genuinely rotated, never against the same rejected token) | Sign in (the Settings account card names the action, RV.26) · save the entry - the manual path is untouched (hard rules 1 and 15) · dismiss |
| **Update required (`.required`, docs/CONFIG.md): the server no longer supports this build** | Non-dismissible notice on the cloud-extract surface: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The `/extract` request is withheld client-side; the on-device result stands | Update the app (App Store button only when a listing exists) · confirm/fix by hand · save - the manual path is untouched (hard rule 1) |
| On-device model unavailable (hardware lacks Apple Intelligence, the device language is unsupported – **Russian always is**, it is switched off, or the model is still downloading). **Since the tier 2 cut (2026-08-25) this is the state on every device**, so the row documents behaviour that is now universal rather than conditional | **Nothing at all.** Rules-only extraction is the normal path for most devices, not a degraded one – announcing its absence would invent a problem the user does not have | Confirm/fix as usual; the capability is checked at runtime and simply not used |
| Odometer breaks timeline (F9a) | Amber + conflicting entry quoted: "Aug 17 already recorded 119 486 km." Receipt date pre-trusted. The quote is one full localised sentence per distance unit, chosen from the vehicle's own units (km or mi, EN and RU) – never a unit label spliced onto a shared stem (RV.126) | Fix odometer (preselected) · fix date (needs explicit override) · save anyway (flagged) |
| Odometer breaks timeline – pace (F9a) | Amber: "Odometer breaks the timeline – check it." (the pace check flags without a conflicting entry to quote) | Fix odometer (preselected) · fix date · save anyway (flagged) |
| **The timeline neighbourhood (RV.117b, [v1.1])** – shown on Edit entry's F9a while the entry flags, reached both from Home's conflict badge and from the flagged list (the whole-row tap already opens Edit entry) | A card under the odometer: the surrounding entries charted with the offending point off the trend (amber diamond vs the neighbours' ink circles - shape and label as well as colour, docs/DESIGN.md), the bracketing rows (previous entry and this one, DIN figures), and the bidirectional statement built from `EntryValidation.validRange` - **the view reads the validator's intervals, it never recomputes one**. Three copy cases per side, each a full localised sentence: **between** ("On 13 Jul, the odometer must be between 490 501 and 492 000 km"), **open end** ("If the odometer is 100 900 km, the date must be no earlier than 18 Jul" - a `nil` bound is never a sentinel), and **`.none` on the date side** - the row's point: when the reading sits at or below its previous one, no date between the neighbours works, and the sentence says so: "no date between the neighbouring entries works – check the odometer" (the odometer is the field to question). A `.none` on BOTH sides (the neighbourhood itself is inconsistent - a multi-year import) is one sentence, never a blank panel. An entry with no odometer has no `validRange` and renders **no panel and no empty box** | Fix odometer (preselected) · fix date (needs explicit override) · save anyway (flagged) - the ranked fixes and Accept (RV.104) are unchanged; the panel is what makes them a last resort rather than the only option |
| Volume > tank capacity | Warn: "That's more than the 71 L tank holds – check liters." | Fix · confirm (jerry can happens) |
| Scanned fuel kind isn't offered by the car (**RV.71**, 2026-09-05) | `warn` card under the fuel row, at the scan moment only, dismissable with a × and never blocking: "The receipt reads Diesel, but this car is set up for 95. Check the fuel kind before saving." The comparison IS the fuel chips' own offer set (`FuelKind.shouldWarnFuelMismatch`, core, L1-tested), so a grade choice (92 on a 95 car) never warns and a car with no declared kinds never warns; electricity never warns either way. The scanned kind is never silently written - the disagreeing value is not even applied as the form's default, so the chips stay the user's input (hard rule 13) | Check the fuel kind (the chips and the "+" correction reach every kind - hard rule 15: nothing about a scan makes it the only correct door) · dismiss (per-sheet; the next scan warns again) · save anyway - the warn never blocks the save |
| Swipe-down with typed input | "Keep editing / Discard" (typed input only – pure scans discard silently, photo re-offerable) | Either |
| No vehicle yet (manual variant) | Hint card: "No car yet – add one from Garage to start logging fill-ups." | Add a car from Garage · close |
| A scanned fill-up's receipt photo could not be kept – the image would not encode, or there was no space (RV.149) | The fill-up SAVES anyway (never a blocked save, hard rule 1 – the photo is a head start, never a requirement) and a toast reports it after the sheet closes: "No space to keep the receipt photo – the entry was saved without it. Free up space and re-scan it." – **the SAME sentence the expense save shows for the identical situation (PJ.28)**: one situation, one message, never a second near-identical string that drifts in wording or in RU (the fill-up path silently dropped the photo until RV.149). Nothing is lost silently (hard rule 8): the failure is named, and the entry keeps its data | Free up space and re-scan the receipt (the photo is gone from this save only; the fill-up stands) |

> **The receipt-photo-lost sentence is shared (2026-09-09, RV.149).** A fill-up and an expense are the same situation – an entry saved while its receipt photo could not be kept – so both surfaces show one full localised phrase per language ("the entry was saved without it" / «запись сохранена без него»), held in one catalogue key and asserted by a source-scan guard (`ReceiptPhotoSaveReportGuardTests`) that fails if a surface stops reporting or starts reporting through a different string. The toast fires only after the entry is on disk, so a failed save never claims it succeeded.

> **Superseded (2026-09-05, RV.71):** the 2026-08-30 AdBlue row that once sat here ("warn under the fuel row → 'This car isn't set up for AdBlue - add it to the car?' → one tap adds `.adBlue` to the car's fuel kinds") described a flow the v1 build does not carry - `.adBlue` is not in the shipped `FuelKind` enum (its SCHEMA plan is unchanged). The same shape - *kind not in the car's offer set* - is now governed by the RV.71 row above, and RV.71 decided **against** the mid-capture add-to-car offer: per-car fuel kinds are a Garage setting (docs/DESIGN.md), a possibly-misread scan value is the least trustworthy source for a config change, and the row must not put a modal question in the capture path. The warn names the check instead; logging a kind the car does not declare never required declaring it (hard rule 13).

| Station: no stations on file (RV.156) | The row's right side is the action-coloured **Add station** door - a station set is user-creatable, so an empty set is "nothing picked yet", never "nothing possible". The dead `inkSoft` "Not set" label that preceded it is gone | Add a station - it is created and **selected on the entry** in one step, and the entry's typed values are never touched |
| Station: stations exist but none proposed (PJ.19 - none ever used by this car) | None - the pick menu's "Choose station" label | Pick from the menu, or add one (the menu's last entry) |
| Station: location denied or restricted (PJ.19) | None - no banner, no re-prompt | The ranking runs without its distance rungs: the car's most recent station is still proposed |
| Station: none within 300 m (PJ.19) | None | Falls through to the most recent station; else the menu's "Choose station", or the add door when no station exists |

### Tank level (sheet)
| Condition | Shows | Next step |
|---|---|---|
| No tank capacity set | Liters equivalence hidden; hint: "Set tank size in Garage to see liters." | Set it later · percentages still work |

### Service & expenses
| Condition | Shows | Next step |
|---|---|---|
| Invoice OCR can't split lines (J7 fallback) | One lump-sum item with full total, editable | Keep as lump sum (legitimate) · split by hand |
| Multi-page scan interrupted | "Page 2 didn't save – rescan it or continue with 1 page." | Rescan page · continue |
| Odometer required but empty (km lifetime set) | Warn on odometer card: "Needed to schedule 'next in 15 000 km'." | Fill (pre-filled value one tap away) · remove the km lifetime |
| Odometer breaks timeline (F9a, PJ.11) | Amber on the odometer card as the user types, the conflicting entry quoted ("Aug 17 already recorded 119 486 km.") - the same F9a mechanics as Confirm. **The check is on every write, not just capture**: a service odometer typo must flag, never silently skew spans and cost/km | Fix (focuses the odometer) · save anyway (the record saves `.flagged`; its segment is excluded until resolved) |
| Shelf part suggested but wrong | – (suggestion, not warning) | Dismiss chip; never auto-links |
| Expense-mode scan read nothing (RV.62) | The ordinary EMPTY expense form – no caption, no warning (the expense form is not the fill-up Confirm, so the F1 caption does not apply) | Type the expense; the empty form IS the contract (hard rule 7) |
| Expense-mode scan priced in a currency the home-only expense form cannot express (RV.62) | The amount stays BLANK – the recognised total is never offered as if it were home currency (a wrong fact is worse than none, hard rule 13); the date still pre-fills | Type the amount; currency mismatches are not an error, just an honest absence |
| A scanned Expense's receipt photo could not be kept – the image would not encode, or there was no space (PJ.28) | The expense SAVES anyway (never a blocked save, hard rule 15 – the photo is a head start, never a requirement) and a toast reports it after the sheet closes: "No space to keep the receipt photo – the entry was saved without it. Free up space and re-scan it." – the SAME sentence the fill-up save shows for the identical situation (RV.149), generalised from "the expense" so one message serves both entry kinds (see the note under Confirm). Nothing is lost silently (hard rule 8): the failure is named, and the row keeps its data | Free up space and re-scan the receipt (the photo is gone from this save only; the entry stands) |

### Edit entry
| Condition | Shows | Next step |
|---|---|---|
| Foreign-currency entry | The conversion card, resolved honestly from the rate store (P5.2): converted from the feed (with "Edit rate"), converted from a manual rate (shown as Manual, editable - hard rule 13's "and again afterwards"), or rate-pending (with the manual-rate entry offered on the card) | Enter/change the rate on the card · leave it (saves as-is, pending converts later) |
| A currency/amount edit resolves at commit (RV.144) | The edited money RE-HOMES to the car's CURRENT home currency (docs/SCHEMA.md -> Money) and converts on Save, not on the next automatic pass: an edit to the car's home needs no rate at all (rate 1, no network); a foreign edit converts at the entry's own day's rate when the cache holds one | None - it happened on Save. A rate the cache lacks is a silent non-event: the row stays rate-pending and is counted (F9), converting later (S8) or by the card's manual rate |
| Edit re-breaks cross-check or timeline | Same amber mechanics as Confirm | Same fixes; save-anyway keeps flag |
| Entry was changed by sync (S1) | Quiet row: "Changed by sync · iPad, Aug 21" | Restore my version · keep |
| Delete tapped | System confirmation (the one place red lives) | Delete (→ Recently deleted, 30 days) · cancel |
| Edit shifts stats | Toast on save: "Consumption updated: 6.9 → 6.8 L/100km" | Informational; tap → Trends |
| Receipt chip tapped, the full rendition is on the device (RV.9) | The attachment viewer: the photo full-screen and fitted, pinch or double-tap to zoom and drag to pan; a PDF opens in the PDF viewer, which brings its own zoom and paging | Close (or swipe-down) → back to the entry, unchanged and still editable |
| Receipt chip tapped, the full rendition has not downloaded and there is no account on this device (RV.9) | The inline thumbnail from the payload (so the viewer is never blank) under "The full photo is not on this device yet" | "Sign in from Settings to download the original. This preview came with the entry." – the entry stays open and editable throughout (hard rule 1) |
| Receipt chip tapped, the fetch failed – offline, or the bytes did not verify (RV.9) | The same thumbnail and headline, with the failure named rather than a spinner that never ends | "Check your connection and tap Try again." plus the **Try again** control on the card |
| The attachment's bytes are not readable – not a photo, or a PDF that will not open (RV.9) | "This file could not be opened" over the placeholder, never a silent blank frame | "Attach the receipt again from the entry to replace it." |
| Share tapped, the full rendition is local (RV.17) | The system share sheet over the **full** rendition – Save Image / Save to Files / share to apps. The 44 pt thumbnail is never what gets handed over | Choose an activity, or cancel – either way the entry underneath is untouched and still editable |
| Share cancelled – the sheet is dismissed without choosing an activity (RV.17) | Nothing: the sheet closes and the viewer is exactly as it was | None needed. Sharing is a deliberate act; a cancel changes nothing and is logged shape-only (hard rule 12), never what was about to be shared |
| The full rendition needed to share could not be downloaded – offline, or the bytes did not verify (RV.17) | The share affordance is **withheld** (never a dead button); the "The full photo is not on this device yet" state with its Try again | "Check your connection and tap Try again." – the share affordance appears only once the rendition lands |

| Add receipt to an existing entry (PJ.48): photo could not be saved (disk full, permission) | `warn` line under the receipt card | "Couldn't save the photo – the entry is unchanged." | Try again · free up space (Settings deep link); the entry's fields are never touched by a failed attach |
| Add receipt: OCR read values that disagree with what was typed (PJ.48) | none – no amber, no dialog | – | Typed values win silently; only blank fields are offered a pre-fill, each dimmed until tapped (hard rule 13). The photo is kept either way |
| Delete receipt tapped (RV.37) | System confirmation (the one place red lives): "Delete this receipt?" | Delete (removes the receipt from this entry; the attachment is tombstoned for the 30-day window like any other record, never a file quietly unlinked – hard rule 8) · cancel |
| Replace photo tapped (RV.37) | The camera/Photos choice – the same door "Add receipt" uses (hard rule 15) | Camera · Photos → the new photo is written and the old one tombstoned, never mutated in place (the 30-day undo has something to restore) |
| The replacement landed (RV.37) | The ask: "Re-read this and update the entry?" – "Leave it as it is" is the default; the photo is already swapped, and the entry's values change only on an explicit "Update entry" | Leave it as it is · Update entry (re-reads and fills blank fields only, each dimmed until tapped – hard rule 13) · Use a different receipt (replace again) |
| The replacement could not be written – disk full, the photo would not encode (RV.37) | `warn` line: "Couldn't replace the photo – the entry is unchanged." | Try again; the entry's fields are never touched by a failed replace |

### Recently deleted
| Condition | Shows | Next step |
|---|---|---|
| A tombstoned entry (within the 30-day window) | Row with what the entry was ("Neste · 51.1 L · 84.77 €"), when it was deleted, the days left ("27 days left" – plural rule, EN + RU), and Restore | Restore (tombstone cleared; entry back in the Log and the stats) · let it expire |
| A tombstoned car (RV.98) | One car row naming the car and how many entries its Restore brings back ("Volvo V60 and 512 entries"), when it was deleted, the days left, and Restore - NEVER one row per entry: the entries that share the car's tombstone stamp belong under its row, and a Restore of their own would strand them on a deleted vehicle | Restore (the car and the entries that went down with it return to the Garage and the Log; entries the user deleted individually before the car stay tombstoned) · let it expire |
| Entry deleted on another device (S1/S4) | Same row, plus "· removed on iPad" **(device attribution is [v2]** – the sync record's author attribution arrives with shared garages (`SCHEMA.md` → Identifiers), never in v1) | Restore · let it expire |
| Entry lost to a sync merge (S1/S4) | "Overwritten by sync" section: "Shell · your version from iPhone / Replaced Aug 21 · odometer differed · 28 days left" + Compare | Compare (presentational until the merge log lands, P4) · leave it |
| "Delete all now" tapped | System confirmation (the one place red lives) | Delete all now (purges every tombstone immediately, regardless of age) · cancel |
| Nothing deleted (the normal case) | Reassuring empty state; no fabricated rows (cars, entries and reminders are all absent) | Nothing to do – this screen existing at all is the reassurance |

### Trends
| Condition | Shows | Next step |
|---|---|---|
| Entries excluded (conflicts/duplicates) | Footnote "N entries excluded" (real plural rules, EN + RU) | Tap → the excluded entry when one is out, else the excluded-entries list that names all N and each one's reason (RV.141) |
| Entries pending a rate (F9) | Passive footnote "N entries pending rates" (real plural rules, EN + RU) with a **"Check for rates"** action (RV.106: hard rule 7 - the count names its next step). **A rate-pending month is a GAP in the spend/cost charts, never a dipped bar or point** (RV.112); the spend TILE prints no number for a `.pending` month and marks a `.partial` one with the pending phrase (docs/DESIGN.md -> Trends). **The windowed COST / KM tile reports a figure only when its 90-day window's money is exact (RV.147)**: a rate-pending row - or known figures homed in more than one currency - inside the window withholds the tile ENTIRELY, never a plausible-but-low `0.07 €`. The figure is a RATIO, so an understated numerator over a complete odometer span is low by an unknown amount while looking real - absent (with this footnote saying why) reads as unknown, which is the truth | Check for rates (RV.111: a DEMAND drain over the pending rows' own dates) · wait (rows fill automatically once the archive reaches their dates) · edit the entry → the conversion card offers a manual rate, see Home's F9 note |
| Below data floor | Honest label: "first estimate · 1 fill cycle" / extended window "last 5 months" | Keep logging; label explains itself |
| Anomaly detected (J9) | Amber insight card with evidence chart | Act (creates reminder) · dismiss with reason (teaches the model) |

### Reminders / Reminder complete
| Condition | Shows | Next step |
|---|---|---|
| Notification permission off but reminders exist | One-time card: "Reminders can't notify you – they'll only show here." | Enable (deep link) · fine as is |
| Overdue reminder | Amber "overdue by 12 days" | Complete · reschedule · delete |
| Completing with km-recurrence but stale odometer | Hint: "Next cycle counts from 119 486 km – update if you've driven since." | Edit odometer · accept |

### Car switcher / Garage
| Condition | Shows | Next step |
|---|---|---|
| Free-tier car limit reached on "Add car" | Sheet explains the cap (never mid-capture): "Free keeps up to 3 cars. Archive one to add another." | Archive a car · cancel. **The "Pro" action was removed in v1 (RV.70)**: it pushed `Route.paywall`, which resolves to a blank screen, and a reachable placeholder is an App Review rejection while the store metadata declares no paid tier. Restore it together with a real paywall, not before. Existing cars are never locked (anti-CarScope rule) |

### Vehicle detail
| Condition | Shows | Next step |
|---|---|---|
| Home currency changed on a car WITH a log (RV.152) | The question is asked BEFORE the vehicle write, only when the currency actually changed and the car has entries. Title: "Change home currency to USD?". Message, complete sentences: what Convert does; the pending count **upfront** when the convert cannot resolve every date ("N entries have no rate for their date and will show as pending until one arrives." - real plural rules, EN + RU); what Keep means for the stats; and the fair warning that **the original receipt amounts are never changed, and this can't be undone**. Two answers, no cancel: **Convert the log** and **Keep the entries as they are**. **RV.177 (2026-09-10) draws this as a custom sheet, not a system alert**: the accent IS taillight red, so an alert tinted the irreversible Convert and the harmless Keep identically; the sheet separates them structurally - Convert is the filled primary, Keep a quiet outlined secondary. **RV.178 (2026-09-10) makes "Save means Save" a deliberate decision, not an accident of two buttons**: Save already committed the currency change, so the sheet asks only what to do with the entries and offers NO cancel - both answers commit, and a swipe-down cannot dismiss it (`interactiveDismissDisabled(true)`, no close affordance), because abandoning the question would silently drop the pending save | **Convert the log** restates each entry's derived home figure from the amount as paid, at that entry's OWN date (hard rule 3, never today); rows whose date has no rate become rate-pending and counted (the ordinary F9 state) - a partial convert is expected, and the prompt says so before the user commits. **Keep the entries as they are** leaves existing entries in their home currency and gives new ones the new currency; totals then show per-currency subtotals (RV.145), because there is no honest way to add two currencies (hard rule 2). Either answer runs RV.140's pending-row re-home. An **empty log** and **re-picking the same currency** ask nothing |

### Settings
| Condition | Shows | Next step |
|---|---|---|
| Synced, nothing pending | Account card, relative: "Synced just now" / "Synced 3 hours ago" | None. **This is reassurance, not a warning** - it never turns amber with age |
| Signed in, **never synced on this device** (OB.3) | Account card: "Not synced yet" - the honest reading of a device that has no stored success date. Previously nil mapped to "Synced just now", a claim a cold relaunch could not support | None; the automatic cycle handles it |
| **Relaunch after a stored failure** (OB.3) | Account card caption (`settingsLastFailure`): the same copy the live cycle would have shown for that class, with its next step - 426/tier/unknown-4xx amber "update the app", an auth-expired/revoked "sign in", a 5xx "service unreachable", a 429 "retrying in a moment". A **statement of the last outcome, never an alarm** (colour follows the live split), shown only until a live cycle supersedes it. `.offline` never captions - offline is never an error surface. The raw `code`/`traceId` are persisted and exported (OB.4), never shown | Per class, the live vocabulary's step (update / sign in / wait / try again). A support id on screen is a separate decision nobody has made |
| Sync pending (S7) | Passive row: "Waiting to sync · 5 changes" | None needed; tap for detail |
| Offline with a queue | Same passive row, plus "Will sync when you're back online" | None. **A long queue is not an error state** - a week offline is the same as an hour (S7) |
| **Sync now** tapped, offline | Row settles back to "Will sync when you're back online" | None. The tap is never punished with an error |
| **Sync now** tapped, server 5xx | "Sync service unreachable - your data is safe on this phone. It will go up automatically when the service is back." | Try again · leave it (auto-retry continues) |
| **Sync now** tapped, already syncing | Action is inert while a sync is in flight (spinner on the row) | None; the tap is idempotent, never a second push |
| Entries flagged by a merge (S1-S5) | Summary row: "2 entries need a look" | **Tap -> Log filtered to flagged entries.** Settings never resolves a conflict - the badge lives where the data lives (hard rule 8). **RV.66: the sync chip's whole body is a second door into that filtered Log** whenever the account-wide flagged count is non-zero - the chip is the account-wide signal, so the account-wide list must be one tap from it (the 10 pt dot alone was the route the user could not find) |
| Device revoked (`device_revoked`) | Card: "This device was signed out – sign in to reconnect. Your data on this phone is untouched." **RV.58: a real 410 is terminal - the sync cycle stops and the client DROPS the session (docs/SECURITY.md: a revoked device discards its tokens and stops syncing), so the card renders as the account card's signed-out branch (it survives relaunch through a persisted `deviceRevoked` mark, the RV.26 `authExpired` pattern). The local log is untouched and the dirty queue stays dirty (S7) - signing in again re-attaches the device row and the queue pushes.** The signed-in variant of the card (a session that still exists) is a test/screenshot fixture only | Sign in · stay local |
| Session expired (refresh token rejected - PR.1, RV.26; `refresh_reused` / `token_invalid`) | Card: "Your session has expired – sign in again. Your data on this phone is untouched." The access token was refreshed and the refresh token came back rejected, so the session is gone - an auth event, **never "update the app"** (hard rule 7). `refresh_reused` (a rotated token replayed, chain revoked) and `token_invalid` (expired/unknown) render the same card - signing in again is the honest next step for both - but the code tells the log and OB.3 which of the two it was; reuse is the security-relevant one (docs/API.md -> Auth). The queue stays dirty (S7), nothing is lost. Reachable from a sync cycle **or** from the cloud-reading gateway (RV.26): a capture whose `/extract` 401s (`token_invalid`) and whose refresh is rejected marks the session `authExpired`, so this card names the next step instead of the capture failing silently (F4) | Sign in · stay local |
| **Sign out (RV.40)** | The account surface's "Sign out" row. Confirmation: a clean sign-out reassures "Your entries stay on this phone. You can sign in again anytime."; a dirty queue names the count - "You have N unsynced changes. They stay on this phone and sync when you sign in again." Signing out revokes the refresh chain server-side (best-effort) and clears the local session; it is **not** a device revoke (the row survives, so a later sign-in reuses it) and **not** deletion - the log is untouched and unsynced changes are kept, never silently dropped (hard rule 8) | Sign out · Cancel |
| Storage quota near/full (blob 429, `blob_quota_exceeded`) | Row: "Photo storage 95% full – older photos stay on this phone only." plus the card's next-step line: "Everything on this phone keeps working – new photos upload when space frees up." (**RV.70** replaced the old "Tankbook Pro" button - it pushed a blank screen) | **Nothing to fix and nothing to buy (RV.70): no tier exists in v1 (P6.16, `docs/STORE.md` §5), so the card names the wait as its next step and carries no control** - keep using the app on this phone (hard rule 1), older photos stay on this phone only, nothing is lost, and new photo uploads resume when the account's space frees (a tombstoned record's 30-day orphan sweep, never a periodic reset). A button that pushes a screen which does not exist is the bug this row now forbids (hard rule 7) |
| **Server ahead: app below the server's minimum schema (`upgrade_required`)** | Account card, attention (amber): "This needs a newer version of Tankbook – update to sync" | **Update the app.** Version-first, never an upsell (hard rule 7 - there is no Pro tier). The pull still works, so nothing local is lost |
| **Server gated this client (`tier_refused`)** | Account card, attention (amber): "A newer version of Tankbook is needed for this account" | **Update the app.** No tier exists, so the honest reading is an out-of-date client, never "buy something" |
| **Unknown gate from a newer server (any other 4xx / any code this client has not seen)** | Account card, attention (amber): "Tankbook needs an update – the server has moved ahead" | **Update the app.** No invented reason (F7). This is the unknown-code fallback (PR.9): a code this client does not know renders exactly this status-based row, never a blank |
| **Sync paused by the server (`rate_limited`)** | Account card, reassurance (`inkSoft`, never amber): "Retrying in 2 minutes" / "Retrying in a moment" | **None; it retries itself.** A wait, not a failure - no update prompt (the distinction is the point of the P6.11 core half) |
| **Update required (`.required`, docs/CONFIG.md)** | The sync surface (the "Sync now" row and its cards) is replaced by a non-dismissible notice: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The App Store button renders only when a compiled-in app id exists - none today | **Update the app.** Everything local keeps working (hard rule 1); a paused push leaves the queue dirty (S7) |
| Export fails (disk) | Alert: "Not enough space to build the export." | Free some space · **Try again** (the alert's button re-runs the export). Never a crash - the app stays usable (hard rule 7) |
| Export fails (anything else) | Alert: "Couldn't build the export." | Try again · OK |
| **Language changed (RV.24, RV.42)** | On the Settings Language row itself: "Language changes the next time you open Tankbook". RV.42 moved it there because the picker-only caption died with the sheet, leaving a setting that visibly took effect against an app that visibly did not change (a broken switch, not a pending one). The prompt renders exactly while the stored choice differs from the language actually running - **derived, never stored** - and self-clears on the next launch; it also still shows below the list while the picker is open | Close and reopen the app. **Never a programmatic restart** - an app that exits itself to apply a setting reads as a crash and risks App Store rejection. The prompt is the next step; the row value updates immediately |

**A failed share shows the user nothing, and is recorded in full (RV.181, decided
2026-09-10).** The destination owns its own error surface - Mail's composer, the Files browser -
and a second alert from Tankbook on top of it would fire on the cancel path too, which is the
common one; that teaches the user to dismiss it. So no user-facing message.

**The log is the other half of that decision, and it was the missing half.** The seam used to keep
only `completed`, which the system reports as `false` for a cancel and for a share whose activity
failed alike - so a report of "I picked a destination and nothing arrived" looked in the log
exactly like closing the sheet. Each surface now logs `outcome` as one of `completed` /
`cancelled` / **`failed`** (`diagnostics.share`, `attachmentViewer.share`, `export.share`,
`import.sendFile.share`), and a `failed` share adds a Warning carrying the activity type and the
error's domain and code. All of it is shape - system codes and the payload class (photo / pdf /
csv / text / file) - never a filename, a destination app's content, or the shared item itself
(hard rule 12). `docs/LOGGING.md` -> Shares carries the field list. **A user who reports a share
that never arrived can now be answered from their diagnostics bundle**; before this row they could
not.

### Inbox (RV.38, RV.45, RV.64)

The bell's screen: work that finished after the user moved on. The first case is a cloud
reading that landed **after** the entry was saved (`docs/JOURNEYS.md` F4, amended). It is a
**home for suggestions, never a rewrite** - the app asks, and "leave it as it is" is the
default (hard rule 13). **RV.45 (2026-09-04) made the ask per-field:** the card lists every
field the receipt read that differs from or fills what the user saved as **yours vs the
receipt**, and the user ticks per field what to take. A field that matches is not a choice
(it is shown as agreement, or not at all), and a card with nothing to change says so and
offers no update action (hard rule 7 - an action must name what it does, and one that does
nothing is not offered).

**RV.64 (2026-09-05) made the button WEIGHT follow the state, never the position.** The two
acts keep their ORDER; only which one is loud changes. While NOTHING is ticked, "leave it as
it is" stays the prominent filled action (hard rule 13 - nothing is decided yet, so the
default is loud). Once at least one field is ticked, a tick IS the user deciding, so "update
from the receipt" - the act that honours the ticks - becomes the prominent filled action and
leave-as-is dims to the secondary treatment. The loudest control must never be the one that
throws the ticks away (hard rule 8 - they are user work, and discarding them with no
confirmation and no undo is "lost silently"). The decision lives in core
(`GatewayInboxPolicy.recommendedAction`), in one place, so the two buttons cannot drift apart.

| Condition | Shows | Next step |
|---|---|---|
| Nothing pending (the normal case) | Reassuring empty state: "Nothing needs your attention" (the Recently-deleted sibling - the screen existing at all is the reassurance) | Nothing to do |
| A cloud reading landed after save, and it differs or fills a blank | An item: "Receipt reading ready · Finished after you saved." with a **per-field comparison** - every field the receipt read that differs or fills a blank renders "you entered X · receipt Y", marked, with a tick. The two acts read differently: a blank field carries **"Fills the empty field"**, a differing one **"Replaces what you entered"**. The entry keeps its own badge (hard rule 8). | Tick the fields to take · **Update from the receipt** (takes the ticked fields only, disabled until one is ticked; the prominent filled action once a field is ticked - RV.64) · **Leave it as it is** (nothing changes; the prominent filled action only while nothing is ticked - RV.64) · **Use a different receipt** (routes to Edit entry, where the receipt lives; deliberately not "replace" - that verb belongs to the FIELDS, RV.64) |
| A reading that would change nothing | The card says "Nothing to change – the receipt matches what you saved." and offers **no update action** - an item whose entry has since come to agree with the reading (the user edited it, or sync brought it in line) | **Leave it as it is** (clears the item) · **Use a different receipt** |
| The reading agrees with what was saved (at creation) | **Nothing.** An answer that adds no blank and disagrees with nothing is noise, not work - no item is created | Nothing to do; the answer is silently absorbed |
| The entry the item is about no longer exists | "The entry this reading was about no longer exists." The item routes to the entry; a deleted entry has nothing to update | Leave it as it is - the item clears and nothing is written |

**Durability, stated plainly.** The inbox is device-local and best-effort: the extraction lives
on the device (rule 9 - the gateway holds no conversation), so an app killed mid-request loses
the answer, and the inbox never shows an item that vanished. An answer that DID arrive is
persisted and cleared by resolution, never by age. A durable re-read (from RV.33's ledger) is a
second rule-9 reversal and the product owner's call, not an agent's.

### Import wizard (planned screen; F6 rules)

| Condition | Shows | Next step |
|---|---|---|
| File partially parses | "214 of 220 imported – 6 rows need a look" + row list. **Rows render as parsed, labelled fields - never raw CSV** (`JOURNEYS.md` F6b): the server mapped most of the row, so only the field that is actually wrong is marked, and a blank stays blank rather than becoming `0`. The original line stays available behind "Original row" for the rarer case where the *mapping* is wrong rather than a value | Fix inline · skip rows |
| Nothing parses | "This looks like a PDF report, not a data export – here's where the CSV lives in Drivvo." | Guide per source app · send us the file (consent) |
| Ambiguous units/currency | One question, once per file: "MPG or L/100km?" (ambiguous **dates** have their own row below, PJ.10) | Answer; import proceeds |
| **Choosing the source** (not an error - the first step) | "Which app is this file from?" with the **server-driven** supported list (`GET /v1/import/formats`). The user declares it; the app never sniffs, because two vendors' CSVs look alike and a confident mis-mapping is worse than a question (hard rule 13) | Pick the app · "My app isn't listed" |
| **The source list fails to load - genuinely offline** (RV.68) | The offline card: "Importing needs a connection - reading these files happens on our server." Reachable ONLY from a genuine connectivity failure (`URLError.notConnectedToInternet`/`.networkConnectionLost`/`.cannotFindHost`/DNS/`.timedOut` family) - the named exception's network half | Retry when online · everything else in the app keeps working |
| **The source list fails to load - server error** (RV.68) | "The server couldn't load the list - it's on our side, try again in a moment." A non-2xx response from a reachable server is never "you need a connection" | Retry |
| **The source list fails to load - the response is not our JSON** (RV.68) | "We couldn't read the list of apps - the app and server don't match, try again, and update Tankbook if it keeps happening." A decode break is a client/server contract bug, never an offline state | Retry · update the app |
| **The source list fails to load - anything else** (RV.68) | "We couldn't load the list - something went wrong, try again in a moment." A non-connectivity transport failure (TLS, unknown) or a client-bug refusal is never "check your connection" (a wrong next step is worse than none, hard rule 7) | Retry |
| **Parse in flight** (PR.6, PR.6b - not an error - the upload) | The source screen's bar shows **"Reading file…"** next to its spinner - a bare spinner would tell the user nothing about what is happening (PR.6b) - and a **Cancel** affordance sits below it. PR.6b: the Cancel is anchored above the owned tab bar, so it is **visible**, not merely present - PR.6's half rendered it under the tab bar, present for the test and not for the user (`isHittable` does not model occlusion, HANDOVER). The upload's budget is bounded (docs/PRACTICES.md U6), so a half-connected radio can never freeze the wizard for a minute | Cancel (stops the upload; nothing was written - the garage is untouched). A stalled upload times out into the **Offline** row, never a generic failure |
| **Source app not listed** | "We don't read that one yet." Names what *is* supported rather than dead-ending, and offers to take the file so the format can be added - the same ask as the capture notice (P6.10). **"Send us the file" now attaches the actual file** (PJ.20): it picks the file, shows an explicit consent step naming the exact file and what it may contain, and only then opens the share sheet with the file riding it - never the sentence alone | Send us the file (explicit consent) · pick a different app · cancel |
| **File does not match the declared source** (`import_mismatch`) | Specific, never generic: "This doesn't look like a My Fuel Manager export." Offers the picker again with the likely alternatives, because picking the wrong app is the expected mistake, not a rare one | Choose a different app · send us the file · cancel |
| **File mixes two date formats** (`import_inconsistent_dates`, RV.85) | "This file mixes two date formats." Some rows only read as `M/D/YYYY` and others only as `D/M/YYYY`, so no single order fits the file. Not the `dateFormat` question (a file with no single answer cannot be answered correctly) and not the mismatch card (it IS an MFM export) - its own message naming the fix | Fix the dates in the export (one format throughout) · pick the file again · cancel |
| **Preview before commit** (not an error - the gate) | "Here's what we read: 220 fill-ups · Mar 2023 - Aug 2026 · 118 930 km · EUR · **8.2 L/100km**". Figures the user can check from memory, F7's "numbers, not a checkmark" (`JOURNEYS.md` F6a). Names the target car, and the S2 duplicate count when merging | Import · adjust currency/units/car · fix flagged rows · cancel |
| **Ambiguous dates (`dateFormat`)** (PJ.10, `JOURNEYS.md` F6, RV.85) | The preview asks once per file: "Date format matters – N dates read either way" with `M/D/YYYY` / `D/M/YYYY` as choices. **RV.85: asked only when the file's own rows cannot settle the order** - every date has both components ≤ 12, so no row proves which reading the file uses. A file any row settles is **resolved, not asked**: one export has one format, so a single `13/05` (only D/M can read it) or `05/13` (only M/D) proves the order for the whole file and the parser applies it to every row - asking when the answer is on disk is the RV.85 defect. **Confirm stays disabled until the question is answered** - the M/D convention standing silently is how a year of history shifts by up to eleven months | Pick a format; import proceeds |
| **Rows the file holds that import doesn't read (`outOfScope`)** | "This file has N income rows; income isn't imported in v1." (same for reminders) - read-but-not-imported is stated, never a silent drop | Nothing to do; the rows are named, not hidden |
| **A parsed row that isn't a fill-up** (PJ.9, `JOURNEYS.md` F6b) | The review row renders its parsed fields and an **"Import as service / expense"** action; it commits as that kind with `provenance = .import`, never silently dropped (hard rule 8) | Import as service/expense · leave out |
| **A row that breaks the car's timeline** (PJ.11, `JOURNEYS.md` F9a) | The review list shows the fill before anything is written, badged "Breaks the timeline" with the conflicting entry quoted; the odometer cell is the one field marked (F6b). The row commits flagged and its segment is excluded - never repaired, never silently accepted (the real MFM `9` row is this state) | Fix (edit the odometer) · import as-is (flagged) · leave out |
| **Preview shows a figure the parse did not produce** | Nothing - this must not be possible. Every number comes from the candidates through the **same engine** that computes them after commit; a display-only total is worse than no preview, because the user approved something they never saw | (design constraint, not a state) |
| **Cancelled at preview** | Nothing imported, and the stored file deleted rather than left to age out | Nothing to do; the garage is untouched |
| **Offline during the parse upload** | The same offline card, reached when the upload times out or the device drops offline mid-parse (the "Parse in flight" row's stall lands here, never on a generic failure). RV.68: like every offline state, this fires only from a genuine connectivity failure - never from a cancellation, a decode break or a server response | Retry when online · the garage is untouched |
| **The picked file cannot be read - local, before any upload** (RV.73) | The read-failure card: **"We couldn't read that file. It may still be downloading from iCloud Drive - in Files, open it once, then pick it again."** The file picker's URL is security-scoped; its bytes are **copied into the app container under the scope at pick time**, and a pick whose bytes cannot be copied never reaches the server - **no parse was attempted**, so "send us the file" is NOT the next step for THIS state (it would fail the same way). The failure is logged with the error's type and code, never the path or the file name (`import.read.fail`, docs/LOGGING.md) | Open the file once in Files (so iCloud downloads it) · pick it again (the picker stays available below the card) |
| **The file was read but the parse could not be obtained - unknown reason** (RV.73) | "We read the file, but couldn't process it. Try again, or send us the file." The read SUCCEEDED and the upload/parse did not (a contract break, a transport failure, an unanswered server). DISTINCT from an unreadable file, whose next step is re-picking, not re-uploading (hard rule 7) | Try again · send us the file · choose a different app |
| **The "send us the file" pick cannot be read** (RV.73) | The not-listed sheet shows the same read-failure copy inline; the consent step never opens for a file whose bytes could not be copied (there is nothing to share) | Open the file once in Files · pick it again · cancel |
| **One file of a whole-export pick fails** (RV.93) | The source screen names the file and says what happened, one card per failed file ("N files couldn't be imported" + per-file card: file name, reason, next step). The successful files are NOT dropped - a whole-export pick is several files, and one bad file never kills the rest | If any file parsed: **"Continue with N files"** (the survivors go on to the mapping/preview; nothing has been written). If none parsed: pick the files again (the picker stays available below the cards) |

The staged copy's lifecycle is decided (RV.73): a picked file is copied into the app's Caches under
`TankbookImport/` and is **deleted as soon as its consumer is done** - immediately after the parse
path reads the bytes into memory, and when the consent/share flow settles on the send-us-the-file
path. It never survives to the end of the wizard, it holds user data and must not outlive its use,
and the Caches location is additionally evictable by the OS. `SECURITY.md`'s
`completeUntilFirstUserAuthentication` class is applied to the copy on write.

The source picker's standing offline strip ("Reading the file happens on our server…") **yields to a
parse-error card** (RV.80): the error names its own next step, and showing both doubles the fixed
chrome below the list - which pushed the dead-end card's action below the fold in RU, whose text runs
20-30% longer. `.transportUnreachable` renders no card, so the standing strip is its surface and
stays.

**An import says what it is NOT bringing in, at the review gate** (RV.116). Every foreign
format carries columns Tankbook has no home for - Drivvo's `Водитель` (driver), payment method,
discount and second/third-fuel blocks; MFM has its own set. The parse used to read what it
understands and let the rest evaporate silently, which is not hard rule 8 (nothing is deleted, and the
rows that do land are complete) but is a **completeness promise**: a migration that quietly narrows
the data is one the user cannot trust. The notice - "Not imported" + *"Some columns in this file
aren't imported. The file stays on your phone if you need them."* - names each unsupported column and
**how many rows carried a value in it** ("Driver · 250 rows carry a value"), because the count is what
tells the user whether it matters to them. It appears at the review gate, before anything is written
(F6a), is never a blocking dialog and never an error, and **Continue is never disabled by it**. A
column empty in every row is omitted from the notice - a notice about nothing buries the column that
matters. The unsupported list is declared per format by `GET /import/formats` (data, not client code)
and the counts ride the parse response, so a new importer cannot forget it and the copy does not rot
in the client (docs/API.md -> Import parsing).

**The parse-error card is scroll content, never bottom chrome** (RV.84). The card used to live in the
`safeAreaInset` bottom bar - the one region that does not scroll - and RU's longer text made the 422
card (the tallest, ~150pt with its help link) shrink the ScrollView's budget until RU overflowed by
13-30pt and clipped the last scroll child at the fold. The card now **leads the scroll content under
the title**: its full message and its "How to export" link are on screen without scrolling in both
locales, and the scroll owns any overflow. A locale-tall card must never live in a `safeAreaInset`
(general shape: an actionable card whose height follows the text must not occupy fixed chrome). While
a parse-error card is showing, the dead-end "Send us the file" card is **ordered directly under the
format list, above the "Not yet" teaser** - the error moment's actionable card stays above the fold
in RU (hard rule 7); nothing is dropped, the order yields.

| **Update required (`.required`, docs/CONFIG.md)** | The non-dismissible update notice replaces the source picker: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The parse (the one server read import needs) is withheld client-side | Update the app (App Store button only when a listing exists). Everything else about import - the review list, the edits, the commit - stays local |

### About & feedback

The composer (design/screens/About.dc.html "Tell us"): category chips (feature/problem/other), the
message, an "Attach device model" toggle (default off - `deviceModel` rides only with it,
docs/API.md), and "Reply to (optional)". **The load-bearing part is the consent**: "Send this case
to help improve scanning", default OFF, persisted, and changeable afterwards (hard rule 13). A
case is queued only with consent; without it Send surfaces the opt-in and queues nothing.

**The consent reads as the gate it is, never as a twin of "Attach diagnostics" (RV.159, decided
2026-09-10).** Two pixel-identical opt-ins used to sit on About - "Attach diagnostics" (OB.4) and
the consent - and only one of them gated the send, so a user who enabled the diagnostics one had
every reason to believe they had already agreed. The consent now sits in its own section inside
the composer under the **"Before you send"** eyebrow (`SectionEyebrow`, the idiom
StationSettingsView uses) and its label no longer says "attach"; the diagnostics opt-in is a
separate card above the composer with no such heading. The treatment rule: `docs/DESIGN.md` -> "A
sending gate is never drawn as an optional attachment". `docs/DEFECT-PATTERNS.md` -> "Comprehension"
names why a test on presence could never have caught this.

**"Attach diagnostics" (OB.4, docs/LOGGING.md §5)** sits on About above the composer: a once-asked
opt-in, default OFF and persisted (the same consent shape as above; hard rule 13). It is a
separate consent from the feedback one, because it sends log data where the feedback consent sends
none. While it is off the preview is unreachable; turning it on reveals **"Preview what will be
shared"**, which opens the Diagnostics preview sheet showing the exact text that would be sent -
not a summary (docs/LOGGING.md §5: the user reads the bytes). Sharing goes through the system share
sheet (`ActivityView`); the bundle is never posted automatically.

**A send acknowledges itself where the user is looking (RV.160, decided 2026-09-10).** The complaint
was "after feedback sent, there is no confirmation that the feedback was sent". A confirmation
existed but could not do its job: it rendered as a muted `inkSoft` caption BELOW the Send button at
the bottom of a tall composer inside About's scroll view - below the fold at the moment of the tap
on a small screen, under the keyboard when one was up, and the only loud change was the form
emptying, which read as "my message vanished". The fix is the same surface split RV.132 settled for
the rate door: a user-initiated action that completes speaks. **A terminal outcome (sent OR queued)
collapses the composer into a confirmation panel** where the form's top was: a bordered `dash` card
with a leading status glyph, `ink` text, and each outcome's own accessibility identifier (= its
localization key). The queued ones are reassurance, never errors - the message is stored and will
go, so each phrase leads with "Saved –" (the 429 row was re-worded to do so; the other two already
did). `.sent` is the one positive-done state and uses `Theme.Palette.ok` (RV.22). `consentRequired`
is a refusal, NOT an outcome: it leaves the whole form in place and shows its warn line above the
Send button - the toggle it names is the next step. After any terminal outcome the draft is cleared
and the composer stays collapsed for the rest of this About visit: a submitted message no longer
lives in the composer (it is with the server or in the outbox), so an editable-looking copy would
invite "fix a typo and send again", which queues a duplicate of a case that is already stored.
Re-entering About starts a fresh composer.

| Condition | Shows | Next step |
|---|---|---|
| **Update recommended (`.recommended`, docs/CONFIG.md)** | Dismissible row in About: "A newer version of Tankbook is available." The App Store button renders only when a compiled-in app id exists - none today | Update (App Store, when a listing exists) · dismiss. Quiet information - nothing is withheld |
| **Send without consent** | Amber line above the Send button, under the "Before you send" section: "Turn on "Send this case to help improve scanning" to send." - the toggle is the next step, named in the words on that toggle, nothing is queued, the draft stays | Toggle consent on · leave it |
| Feedback sent (202) | The composer collapses into a confirmation panel: "Thanks – your feedback is on its way." (`feedbackSent`, `ok` checkmark) | Nothing to do |
| Feedback send fails offline | Composer collapses into: "Saved – sends automatically when you're online." (`feedbackQueuedOffline` - queued, never an error) | Nothing to do |
| Rate-limited (`rate_limited`) | Composer collapses into: "Saved – today's limit is reached, so this one's queued for tomorrow." (`feedbackRateLimited`) | Nothing to do |
| Service error (other non-202) | Composer collapses into: "Saved – we'll try again when the service is back." (`feedbackQueuedRetry` - queued, hard rule 8) | Nothing to do |
| **Diagnostics opt-in off** | The "Attach diagnostics" row shows its toggle (default OFF) and explanation; no preview affordance | Toggle it on · leave it off |
| **Diagnostics preview** | The preview sheet renders the exact bundle text, with Share in the bar | Share (system sheet) · Close / swipe-down - nothing was sent |

### Vehicle catalog updates (background, `SYNC.md` → Reference data)

The catalog is curated server-side and the server is master, but **every failure here is invisible**: the
app always has a usable catalog (bundled seed pack at minimum), so there is nothing the user could do and
nothing worth interrupting them for. Same principle as remote config.

| Condition | Shows | Next step |
|---|---|---|
| Pack fetch fails (offline, 5xx, timeout) | **Nothing.** Suggestions keep working from the pack already on device; retry with backoff | Nothing to do |
| Pack fails validation, or is malformed | **Nothing.** Rejected whole – never partially applied – previous pack stands, logged at WARN | Nothing to do |
| Pack `packVersion` not greater than the one held | **Nothing.** Ignored - an older pack is rollback protection, an equal one (an honest empty delta) is "nothing changed". `>` vs `>=` is the client guard (P5.7) | Nothing to do |
| Catalog cache unreadable or truncated | **Nothing.** Falls back to the bundled seed pack and refetches | Nothing to do |
| Model genuinely not in the catalog | On Add car: "Can't find it? Type the name yourself – you can add tank size in Garage." The miss is counted (a **count only**, never the typed text – hard rule 12) and feeds curation | Type it manually; nothing blocks, nothing is lost |

**Never shown, by design:** anything announcing that a catalog update corrected a figure. A pack update
changes what the *next* car pre-fills; it never rewrites a car already in the garage, and a value the user
typed over is theirs permanently (`SYNC.md` → the master rule and its limit). There is no such thing as a
catalog-vs-garage conflict to surface.

### Ask **[v2]** (Pro – `docs/AGENT.md`)

| State | Severity | Copy | Next step |
|---|---|---|---|
| Offline | `inkSoft` status | "Ask needs a connection – your log works as always." | The three example questions become taps to Trends / Reminders / Garage; thread stays readable |
| Not Pro | `inkSoft` + the Pro card | "Ask is part of Pro." (examples above it) | Example → the ordinary screen that answers it; Pro card → Paywall. The one Pro surface besides the car-limit sheet |
| Quota spent | `inkSoft` | "Your Ask turns for this month are used up – resets on the 1st." | The examples as taps; no upsell |
| Gateway unreachable / timed out | `inkSoft` | "Ask isn't answering right now." | "Try again" + the examples; the turn is kept in the composer, never lost |
| Draft dismissed | `inkSoft` line in thread | "Not saved." | Nothing; no re-offer |
| Ambiguous request | question in thread | one line, one question ("Which car?") | Answer inline; car chip also switches |
| Diagnosis: stop driving | system dialog (the only red) | "This can be unsafe to drive. Have it checked before driving further." | "Remind me to book" · "Questions for the workshop" |
| "That's not right" | `inkSoft` | "Noted. Attach this thread to help improve answers?" | Opt-in per thread; declined = count only |

## The audit rule (for CI-of-design and future screens)

Every new error/warning must answer three questions before it ships: (1) what happened, in the user's words; (2) what is the **preselected** next step; (3) what happens if they ignore it (and it must be survivable). If any answer is missing, the design isn't done. Monetization never appears in an error surface except the explicit car-limit sheet.
