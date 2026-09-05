# Tankbook – Errors & Warnings Catalog

*Per-screen inventory of everything that can go wrong, what the user sees, and what they can do next. Law: **no message without a next step** – every error/warning names its cause and carries at least one action; the user is never left alone with a fact. Companion to `JOURNEYS.md` (F-series), `SCREENMAP.md` (where back leads), `API.md` (error codes), `DESIGN.md` (voice: say what happened, say the fix, never apologize, never vague).*

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
| Provider auth fails (Apple/Google error) | Inline under buttons: "Apple couldn't sign you in – try again, or use Google." | Retry same provider · switch provider · Not now |
| Our backend unreachable after provider success | "Signed in with Apple, but our sync service isn't answering. We'll finish setting up automatically – you can use the app meanwhile." | Continue to app (token retries in background) · Not now |
| Token clock-skew / device date wrong | "Your device's date looks off (Aug 2019) – sign-in needs it correct." | Open Date & Time settings (deep link) · Not now |

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
| Entry timeline conflict (F9a/S3) | Amber badge on entry; footnote "N entries excluded" | Tap badge → Edit entry with discrepancy pre-highlighted |
| Possible duplicate (S2) | Combined card "Possible duplicate – Shell, 42.3 L logged twice" | Merge · Keep both (one counts until resolved) |
| Entries pending a rate (F9) | Passive footnote "N entries pending rates" (real plural rules, EN + RU) | Edit the entry → the conversion card offers a manual rate · wait (it converts when a rate arrives) |
| Archived car returned via sync (S5) | Quiet Garage notice "Volvo came back with 1 new entry – stays archived." | Delete again · keep |
| Post-outage sync batch (S7) | Toast "Synced. 2 entries need a look" | Tap → Log filtered to flagged entries · ignore (badges remain) |
| Reminder due | Amber banner "Insurance renews in 12 days · View" | View → Reminders |
| Consumption drift detected (J9) | Amber insight card in the Log, in the car's own unit, naming BOTH windows compared ("Consumption is up 21% vs a year ago" + "Last 90 days: 6.5 L/100km · a year earlier: 5.4 L/100km"); tap → evidence (chart of the drift + possible causes: tire pressure, air filter, winter) | Act → creates a service reminder · dismiss with reason (teaches the model) – both always present (a card with only dismiss teaches nothing; only act is a nag) |
| First fill logged, no segment yet (D4) | Hint on vitals: "One more full tank and your consumption appears" | Capture (the card links it) |

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
| No exchange rate for that date (F9) | Hint on conversion card: "≈ – · converts when online", with the manual-rate entry offered on the card itself (hard rule 7: the hint names its next step) | Save anyway (converts later) · enter rate manually (on the card) |
| Cloud-fallback unavailable/quota spent (F4) | Hint: "check these – enhanced reading unavailable right now"; **never an upsell here** | Confirm/fix by hand · save |
| Cloud reading still in flight (F4; **RV.57 replaced RV.8's spinner banner**) | The proceed note, a quiet `inkSoft` hint with a ×: "A more reliable reading may still arrive. You can proceed now." Never amber (nothing needs a decision), never a spinner (the point is that the user need not wait), and the request is **not** cancelled at the 3 s budget – it keeps running in the background | Dismiss · proceed now · save whenever ready. A late answer lands in the **inbox**, never as a value that moves under the user's cursor (RV.57, hard rule 13) |
| **Update required (`.required`, docs/CONFIG.md): the server no longer supports this build** | Non-dismissible notice on the cloud-extract surface: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The `/extract` request is withheld client-side; the on-device result stands | Update the app (App Store button only when a listing exists) · confirm/fix by hand · save - the manual path is untouched (hard rule 1) |
| On-device model unavailable (hardware lacks Apple Intelligence, the device language is unsupported – **Russian always is**, it is switched off, or the model is still downloading). **Since the tier 2 cut (2026-08-25) this is the state on every device**, so the row documents behaviour that is now universal rather than conditional | **Nothing at all.** Rules-only extraction is the normal path for most devices, not a degraded one – announcing its absence would invent a problem the user does not have | Confirm/fix as usual; the capability is checked at runtime and simply not used |
| Odometer breaks timeline (F9a) | Amber + conflicting entry quoted: "Aug 17 already recorded 119 486 km." Receipt date pre-trusted | Fix odometer (preselected) · fix date (needs explicit override) · save anyway (flagged) |
| Odometer breaks timeline – pace (F9a) | Amber: "Odometer breaks the timeline – check it." (the pace check flags without a conflicting entry to quote) | Fix odometer (preselected) · fix date · save anyway (flagged) |
| Volume > tank capacity | Warn: "That's more than the 71 L tank holds – check liters." | Fix · confirm (jerry can happens) |
| Swipe-down with typed input | "Keep editing / Discard" (typed input only – pure scans discard silently, photo re-offerable) | Either |
| No vehicle yet (manual variant) | Hint card: "No car yet – add one from Garage to start logging fill-ups." | Add a car from Garage · close |

| AdBlue chosen on a car whose offer set has no `.adBlue` (2026-08-30) | `warn` under the fuel row | "This car isn't set up for AdBlue - add it to the car?" | One tap adds `.adBlue` to the car's fuel kinds (needs diesel; otherwise the row explains that); save proceeds either way (hard rule 13) |

| Station: nothing to suggest yet (no stations on file; or PJ.19 not shipped) | none – `inkSoft` placeholder "Not set" | – | Type or pick one later; the row is never action-coloured while it cannot act |
| Station: location denied (PJ.19) | none – no banner, no re-prompt | – | The ranking runs without its distance rungs: the car's most recent station is still proposed |
| Station: none within 300 m (PJ.19) | none | – | Falls through to the most recent station, else "Not set" |

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

### Edit entry
| Condition | Shows | Next step |
|---|---|---|
| Foreign-currency entry | The conversion card, resolved honestly from the rate store (P5.2): converted from the feed (with "Edit rate"), converted from a manual rate (shown as Manual, editable - hard rule 13's "and again afterwards"), or rate-pending (with the manual-rate entry offered on the card) | Enter/change the rate on the card · leave it (saves as-is, pending converts later) |
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
| Entry deleted on another device (S1/S4) | Same row, plus "· removed on iPad" **(device attribution is [v2]** – the sync record's author attribution arrives with shared garages (`SCHEMA.md` → Identifiers), never in v1) | Restore · let it expire |
| Entry lost to a sync merge (S1/S4) | "Overwritten by sync" section: "Shell · your version from iPhone / Replaced Aug 21 · odometer differed · 28 days left" + Compare | Compare (presentational until the merge log lands, P4) · leave it |
| "Delete all now" tapped | System confirmation (the one place red lives) | Delete all now (purges every tombstone immediately, regardless of age) · cancel |
| Nothing deleted (the normal case) | Reassuring empty state; no fabricated rows | Nothing to do – this screen existing at all is the reassurance |

### Trends
| Condition | Shows | Next step |
|---|---|---|
| Entries excluded (conflicts/duplicates) | Footnote "N entries excluded" (real plural rules, EN + RU) | Tap → the flagged entry |
| Entries pending a rate (F9) | Passive footnote "N entries pending rates" (real plural rules, EN + RU) – a hint, never amber: nothing is wrong, the home amount is simply not known yet | Edit the entry → the conversion card offers a manual rate · wait (it converts when a rate arrives) |
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
| Free-tier car limit reached on "Add car" | Sheet explains the cap (never mid-capture): "Free keeps up to 3 cars. Archive one, or go Pro." | Archive a car · Pro · cancel. Existing cars never locked (anti-CarScope rule) |

### Settings
| Condition | Shows | Next step |
|---|---|---|
| Synced, nothing pending | Account card, relative: "Synced just now" / "Synced 3 hours ago" | None. **This is reassurance, not a warning** - it never turns amber with age |
| Sync pending (S7) | Passive row: "Waiting to sync · 5 changes" | None needed; tap for detail |
| Offline with a queue | Same passive row, plus "Will sync when you're back online" | None. **A long queue is not an error state** - a week offline is the same as an hour (S7) |
| **Sync now** tapped, offline | Row settles back to "Will sync when you're back online" | None. The tap is never punished with an error |
| **Sync now** tapped, server 5xx | "Sync service unreachable - your data is safe on this phone. It will go up automatically when the service is back." | Try again · leave it (auto-retry continues) |
| **Sync now** tapped, already syncing | Action is inert while a sync is in flight (spinner on the row) | None; the tap is idempotent, never a second push |
| Entries flagged by a merge (S1-S5) | Summary row: "2 entries need a look" | **Tap -> Log filtered to flagged entries.** Settings never resolves a conflict - the badge lives where the data lives (hard rule 8) |
| Device revoked (410) | Card: "This device was signed out – sign in to reconnect. Your data on this phone is untouched." **RV.58: a real 410 is terminal - the sync cycle stops and the client DROPS the session (docs/SECURITY.md: a revoked device discards its tokens and stops syncing), so the card renders as the account card's signed-out branch (it survives relaunch through a persisted `deviceRevoked` mark, the RV.26 `authExpired` pattern). The local log is untouched and the dirty queue stays dirty (S7) - signing in again re-attaches the device row and the queue pushes.** The signed-in variant of the card (a session that still exists) is a test/screenshot fixture only | Sign in · stay local |
| Session expired (refresh token rejected - PR.1, RV.26) | Card: "Your session has expired – sign in again. Your data on this phone is untouched." The access token was refreshed and the refresh token came back rejected, so the session is gone - an auth event, **never "update the app"** (hard rule 7). The queue stays dirty (S7), nothing is lost. Reachable from a sync cycle **or** from the cloud-reading gateway (RV.26): a capture whose `/extract` 401s and whose refresh is rejected marks the session `authExpired`, so this card names the next step instead of the capture failing silently (F4) | Sign in · stay local |
| **Sign out (RV.40)** | The account surface's "Sign out" row. Confirmation: a clean sign-out reassures "Your entries stay on this phone. You can sign in again anytime."; a dirty queue names the count - "You have N unsynced changes. They stay on this phone and sync when you sign in again." Signing out revokes the refresh chain server-side (best-effort) and clears the local session; it is **not** a device revoke (the row survives, so a later sign-in reuses it) and **not** deletion - the log is untouched and unsynced changes are kept, never silently dropped (hard rule 8) | Sign out · Cancel |
| Storage quota near/full (blob 429) | Row: "Photo storage 95% full – older photos stay on this phone only." | Manage · Pro |
| **Server ahead: app below the server's minimum schema (426)** | Account card, attention (amber): "This needs a newer version of Tankbook – update to sync" | **Update the app.** Version-first, never an upsell (hard rule 7 - there is no Pro tier). The pull still works, so nothing local is lost |
| **Server gated this client (402)** | Account card, attention (amber): "A newer version of Tankbook is needed for this account" | **Update the app.** No tier exists, so the honest reading is an out-of-date client, never "buy something" |
| **Unknown gate from a newer server (any other 4xx)** | Account card, attention (amber): "Tankbook needs an update – the server has moved ahead" | **Update the app.** No invented reason (F7) |
| **Sync paused by the server (429)** | Account card, reassurance (`inkSoft`, never amber): "Retrying in 2 minutes" / "Retrying in a moment" | **None; it retries itself.** A wait, not a failure - no update prompt (the distinction is the point of the P6.11 core half) |
| **Update required (`.required`, docs/CONFIG.md)** | The sync surface (the "Sync now" row and its cards) is replaced by a non-dismissible notice: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The App Store button renders only when a compiled-in app id exists - none today | **Update the app.** Everything local keeps working (hard rule 1); a paused push leaves the queue dirty (S7) |
| Export fails (disk) | Alert: "Not enough space to build the export." | Free some space · **Try again** (the alert's button re-runs the export). Never a crash - the app stays usable (hard rule 7) |
| Export fails (anything else) | Alert: "Couldn't build the export." | Try again · OK |
| **Language changed (RV.24, RV.42)** | On the Settings Language row itself: "Language changes the next time you open Tankbook". RV.42 moved it there because the picker-only caption died with the sheet, leaving a setting that visibly took effect against an app that visibly did not change (a broken switch, not a pending one). The prompt renders exactly while the stored choice differs from the language actually running - **derived, never stored** - and self-clears on the next launch; it also still shows below the list while the picker is open | Close and reopen the app. **Never a programmatic restart** - an app that exits itself to apply a setting reads as a crash and risks App Store rejection. The prompt is the next step; the row value updates immediately |

### Inbox (RV.38, RV.45)

The bell's screen: work that finished after the user moved on. The first case is a cloud
reading that landed **after** the entry was saved (`docs/JOURNEYS.md` F4, amended). It is a
**home for suggestions, never a rewrite** - the app asks, and "leave it as it is" is the
default (hard rule 13). **RV.45 (2026-09-04) made the ask per-field:** the card lists every
field the receipt read that differs from or fills what the user saved as **yours vs the
receipt**, and the user ticks per field what to take. A field that matches is not a choice
(it is shown as agreement, or not at all), and a card with nothing to change says so and
offers no update action (hard rule 7 - an action must name what it does, and one that does
nothing is not offered).

| Condition | Shows | Next step |
|---|---|---|
| Nothing pending (the normal case) | Reassuring empty state: "Nothing needs your attention" (the Recently-deleted sibling - the screen existing at all is the reassurance) | Nothing to do |
| A cloud reading landed after save, and it differs or fills a blank | An item: "Receipt reading ready · Finished after you saved." with a **per-field comparison** - every field the receipt read that differs or fills a blank renders "you entered X · receipt Y", marked, with a tick. The two acts read differently: a blank field carries **"Fills the empty field"**, a differing one **"Replaces what you entered"**. The entry keeps its own badge (hard rule 8). | Tick the fields to take · **Update from the receipt** (disabled until at least one field is ticked) · **Leave it as it is** (the default - nothing changes) · **Replace the receipt** (routes to Edit entry, where the receipt lives) |
| A reading that would change nothing | The card says "Nothing to change – the receipt matches what you saved." and offers **no update action** - an item whose entry has since come to agree with the reading (the user edited it, or sync brought it in line) | **Leave it as it is** (clears the item) · **Replace the receipt** |
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
| **Choosing the source** (not an error - the first step) | "Which app is this file from?" with the **server-driven** supported list (`GET /import/formats`). The user declares it; the app never sniffs, because two vendors' CSVs look alike and a confident mis-mapping is worse than a question (hard rule 13) | Pick the app · "My app isn't listed" |
| **Parse in flight** (PR.6, PR.6b - not an error - the upload) | The source screen's bar shows **"Reading file…"** next to its spinner - a bare spinner would tell the user nothing about what is happening (PR.6b) - and a **Cancel** affordance sits below it. PR.6b: the Cancel is anchored above the owned tab bar, so it is **visible**, not merely present - PR.6's half rendered it under the tab bar, present for the test and not for the user (`isHittable` does not model occlusion, HANDOVER). The upload's budget is bounded (docs/PRACTICES.md U6), so a half-connected radio can never freeze the wizard for a minute | Cancel (stops the upload; nothing was written - the garage is untouched). A stalled upload times out into the **Offline** row, never a generic failure |
| **Source app not listed** | "We don't read that one yet." Names what *is* supported rather than dead-ending, and offers to take the file so the format can be added - the same ask as the capture notice (P6.10). **"Send us the file" now attaches the actual file** (PJ.20): it picks the file, shows an explicit consent step naming the exact file and what it may contain, and only then opens the share sheet with the file riding it - never the sentence alone | Send us the file (explicit consent) · pick a different app · cancel |
| **File does not match the declared source** (`422`) | Specific, never generic: "This doesn't look like a My Fuel Manager export." Offers the picker again with the likely alternatives, because picking the wrong app is the expected mistake, not a rare one | Choose a different app · send us the file · cancel |
| **Preview before commit** (not an error - the gate) | "Here's what we read: 220 fill-ups · Mar 2023 - Aug 2026 · 118 930 km · EUR · **8.2 L/100km**". Figures the user can check from memory, F7's "numbers, not a checkmark" (`JOURNEYS.md` F6a). Names the target car, and the S2 duplicate count when merging | Import · adjust currency/units/car · fix flagged rows · cancel |
| **Ambiguous dates (`dateFormat`)** (PJ.10, `JOURNEYS.md` F6) | The preview asks once per file: "Date format matters – N dates read either way" with `M/D/YYYY` / `D/M/YYYY` as choices. **Confirm stays disabled until it is answered** - the parser's M/D guess standing silently is how a year of history shifts by up to eleven months. Answering re-dates the counted rows before anything is committed | Pick a format; import proceeds |
| **Rows the file holds that import doesn't read (`outOfScope`)** | "This file has N income rows; income isn't imported in v1." (same for reminders) - read-but-not-imported is stated, never a silent drop | Nothing to do; the rows are named, not hidden |
| **A parsed row that isn't a fill-up** (PJ.9, `JOURNEYS.md` F6b) | The review row renders its parsed fields and an **"Import as service / expense"** action; it commits as that kind with `provenance = .import`, never silently dropped (hard rule 8) | Import as service/expense · leave out |
| **A row that breaks the car's timeline** (PJ.11, `JOURNEYS.md` F9a) | The review list shows the fill before anything is written, badged "Breaks the timeline" with the conflicting entry quoted; the odometer cell is the one field marked (F6b). The row commits flagged and its segment is excluded - never repaired, never silently accepted (the real MFM `9` row is this state) | Fix (edit the odometer) · import as-is (flagged) · leave out |
| **Preview shows a figure the parse did not produce** | Nothing - this must not be possible. Every number comes from the candidates through the **same engine** that computes them after commit; a display-only total is worse than no preview, because the user approved something they never saw | (design constraint, not a state) |
| **Cancelled at preview** | Nothing imported, and the stored file deleted rather than left to age out | Nothing to do; the garage is untouched |
| **Offline** | "Importing needs a connection - reading these files happens on our server." Says so plainly rather than failing vaguely: this is hard rule 1's named exception (rule 9), and it is the *only* part of import that needs the network | Retry when online · everything else in the app keeps working |
| **Update required (`.required`, docs/CONFIG.md)** | The non-dismissible update notice replaces the source picker: "This version of Tankbook is out of date – sync, cloud reading and import are paused. Update the app to use them again." The parse (the one server read import needs) is withheld client-side | Update the app (App Store button only when a listing exists). Everything else about import - the review list, the edits, the commit - stays local |

### About & feedback

The composer (design/screens/About.dc.html "Tell us"): category chips (feature/problem/other), the
message, an "Attach device model" toggle (default off - `deviceModel` rides only with it,
docs/API.md), and "Reply to (optional)". **The load-bearing part is the consent**: "Help improve
scanning – attach this case", default OFF, persisted, and changeable afterwards (hard rule 13). A
case is queued only with consent; without it Send surfaces the opt-in and queues nothing.

| Condition | Shows | Next step |
|---|---|---|
| **Update recommended (`.recommended`, docs/CONFIG.md)** | Dismissible row in About: "A newer version of Tankbook is available." The App Store button renders only when a compiled-in app id exists - none today | Update (App Store, when a listing exists) · dismiss. Quiet information - nothing is withheld |
| **Send without consent** | Amber line: "Turn on "Help improve scanning – attach this case" to send." - the toggle is the next step, nothing is queued | Toggle consent on · leave it |
| Feedback sent (202) | "Thanks – your feedback is on its way." | Nothing to do |
| Feedback send fails offline | "Saved – sends automatically when you're online." (queued, like everything) | Nothing to do |
| Rate-limited (429) | "That's a lot of feedback today – this one's queued for tomorrow." | Nothing to do |
| Service error (other non-202) | "Saved – we'll try again when the service is back." (queued, hard rule 8) | Nothing to do |

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
