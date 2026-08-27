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
| First fill logged, no segment yet (D4) | Hint on vitals: "One more full tank and your consumption appears" | Capture (the card links it) |

### Capture (camera)
| Condition | Shows | Next step |
|---|---|---|
| Camera permission denied (F8) | Capture opens the manual form with a top card: "Scanning needs the camera – enable in Settings." | Deep link to Settings · Type it (full manual path) · Photos (library) |
| Too dark / glare detected | Live hint: "Dark – tap for torch" | Torch toggle · shoot anyway |
| Nothing detected for ~4s | Hint: "Fill the frame with the receipt – or type it instead." | Keep trying · Type it |
| Storage full (can't save photo) | Warn sheet: "No space to keep the photo. The entry can still be saved without it." | Save without photo · manage storage (deep link) |

### Confirm (all variants: standard / foreign / mixed / manual)
| Condition | Shows | Next step |
|---|---|---|
| Cross-check mismatch (F2) | Amber underline on the suspect field + "these don't multiply up – check the amber field"; check line refuses to lock | Tap field → source crop shown → correct · save anyway (entry flagged) |
| Low-confidence fields (F1 partial) | Fields dimmed at 60% | Tap to confirm or edit each; save enabled once required fields exist |
| OCR read nothing (F1) | The Manual variant IS the answer: photo kept, caption "Couldn't read this one – type it in." | Type 3 fields · Rescan · photo stays attached regardless |
| Currency low-confidence (schema rule) | Currency chip amber: "Which currency is this?" – never silently converts | One tap on the chip row |
| No exchange rate for that date (F9) | Hint on conversion card: "≈ – · converts when online", with the manual-rate entry offered on the card itself (hard rule 7: the hint names its next step) | Save anyway (converts later) · enter rate manually (on the card) |
| Cloud-fallback unavailable/quota spent (F4) | Hint: "check these – enhanced reading unavailable right now"; **never an upsell here** | Confirm/fix by hand · save |
| Cloud fallback still working after **3 s** (F4, timeout branch) | Hint replaces the spinner: "Still reading in the background – carry on with what we read here." The sheet was never blocked; the message exists so the wait does not read as a hang | Carry on with the local values · a late answer fills **blank untouched fields only**, as a suggestion, and never after save |
| On-device model unavailable (hardware lacks Apple Intelligence, the device language is unsupported – **Russian always is**, it is switched off, or the model is still downloading). **Since the tier 2 cut (2026-08-25) this is the state on every device**, so the row documents behaviour that is now universal rather than conditional | **Nothing at all.** Rules-only extraction is the normal path for most devices, not a degraded one – announcing its absence would invent a problem the user does not have | Confirm/fix as usual; the capability is checked at runtime and simply not used |
| Odometer breaks timeline (F9a) | Amber + conflicting entry quoted: "Aug 17 already recorded 119 486 km." Receipt date pre-trusted | Fix odometer (preselected) · fix date (needs explicit override) · save anyway (flagged) |
| Odometer breaks timeline – pace (F9a) | Amber: "Odometer breaks the timeline – check it." (the pace check flags without a conflicting entry to quote) | Fix odometer (preselected) · fix date · save anyway (flagged) |
| Volume > tank capacity | Warn: "That's more than the 71 L tank holds – check liters." | Fix · confirm (jerry can happens) |
| Swipe-down with typed input | "Keep editing / Discard" (typed input only – pure scans discard silently, photo re-offerable) | Either |
| No vehicle yet (manual variant) | Hint card: "No car yet – add one from Garage to start logging fill-ups." | Add a car from Garage · close |

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
| Shelf part suggested but wrong | – (suggestion, not warning) | Dismiss chip; never auto-links |

### Edit entry
| Condition | Shows | Next step |
|---|---|---|
| Foreign-currency entry | The conversion card, resolved honestly from the rate store (P5.2): converted from the feed (with "Edit rate"), converted from a manual rate (shown as Manual, editable - hard rule 13's "and again afterwards"), or rate-pending (with the manual-rate entry offered on the card) | Enter/change the rate on the card · leave it (saves as-is, pending converts later) |
| Edit re-breaks cross-check or timeline | Same amber mechanics as Confirm | Same fixes; save-anyway keeps flag |
| Entry was changed by sync (S1) | Quiet row: "Changed by sync · iPad, Aug 21" | Restore my version · keep |
| Delete tapped | System confirmation (the one place red lives) | Delete (→ Recently deleted, 30 days) · cancel |
| Edit shifts stats | Toast on save: "Consumption updated: 6.9 → 6.8 L/100km" | Informational; tap → Trends |

### Recently deleted
| Condition | Shows | Next step |
|---|---|---|
| A tombstoned entry (within the 30-day window) | Row with what the entry was ("Neste · 51.1 L · 84.77 €"), when it was deleted, the days left ("27 days left" – plural rule, EN + RU), and Restore | Restore (tombstone cleared; entry back in the Log and the stats) · let it expire |
| Entry deleted on another device (S1/S4) | Same row, plus "· removed on iPad" (device attribution arrives with sync, P4) | Restore · let it expire |
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
| Sync auth expired / device revoked (410) | Card: "This device was signed out – sign in to reconnect. Your data on this phone is untouched." | Sign in · stay local |
| Storage quota near/full (blob 429) | Row: "Photo storage 95% full – older photos stay on this phone only." | Manage · Pro |
| Export fails (disk) | "Not enough space to build the export." | Free space · try smaller (no photos) export |

### Import wizard (planned screen; F6 rules)
| Condition | Shows | Next step |
|---|---|---|
| File partially parses | "214 of 220 imported – 6 rows need a look" + row list | Fix inline · skip rows |
| Nothing parses | "This looks like a PDF report, not a data export – here's where the CSV lives in Drivvo." | Guide per source app · send us the file (consent) |
| Ambiguous units/currency | One question, once per file: "MPG or L/100km?" | Answer; import proceeds |

### About & feedback
| Condition | Shows | Next step |
|---|---|---|
| Feedback send fails offline | "Saved – sends automatically when you're online." (queued, like everything) | Nothing to do |
| Rate-limited (429) | "That's a lot of feedback today – this one's queued for tomorrow." | Nothing to do |

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

## The audit rule (for CI-of-design and future screens)

Every new error/warning must answer three questions before it ships: (1) what happened, in the user's words; (2) what is the **preselected** next step; (3) what happens if they ignore it (and it must be survivable). If any answer is missing, the design isn't done. Monetization never appears in an error surface except the explicit car-limit sheet.
