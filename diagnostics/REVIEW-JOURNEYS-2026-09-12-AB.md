# REVIEW-JOURNEYS run, 2026-09-12 (Group A + Group B)

*Recurring brief `agents/briefs/REVIEW-JOURNEYS.md`, narrowed to this run by the dispatch note.
Tree `42ac5a9e` (HEAD). READ-ONLY: nothing edited, built, or tested. A build agent (RV.226) and
two scenario reviews hold uncommitted changes in this checkout; every citation below is against the
committed tree. Read the previous run for these groups (`diagnostics/REVIEW-JOURNEYS-2026-09-09b.md`)
first - nothing it filed is re-filed here, and its two rows (PJ.56, PJ.57) shipped and are re-checked.*
Two passes run (reachability AND sequence). Group A + Group B, both walked to code with file:line.

---

## 1. Ticked rows found to be untrue

**None.** The spot-checks of every recently-shipped row in this run's cluster hold:

| Row | Claim | Holds at |
|---|---|---|
| PJ.26 | a `.parts` expense becomes a TireSet via a production writer, `purchaseExpenseId` written | `EditEntry/EditEntryView.swift:255-271` → `TireSetPurchase.makeSet` (`Service/TireSetPurchase.swift:37-46`) → `repository.upsertTireSet`; guard exception deleted in the same change (`TASKS-DONE.md` PJ.63/PJ.26) |
| PJ.27 | a mount proposes a `.tires` reminder anchored at the mount, recurring `seasonalSwapMonths` | `ReminderOffer.propose` tireSetId branch (`Service/ReminderOffer.swift:212-226`), staged on save (`Reminders/ReminderOfferSession.swift:52-74`); `seasonalSwapMonths = 6` (`:116`) |
| RV.212 | the km-lifetime odometer rule lives in ONE core function both doors call; neither refuses the save | `Service/ServiceEntryDraft.swift:96-116`; create `ServiceEntryFormState.swift:210-222`, edit `EditEntry/EditEntryFormState.swift:134-150`; offer names the missing odometer `ServiceReminderOfferSheet.swift:222-228` |
| RV.247 | "Type amount" from the merged list writes to the reminder's own car | `ReminderCompletionSession.swift:17-43` (`entryVehicle` prefers `Pending.vehicleId`), set from the reminder `ReminderCompleteSheet.swift:249-254` |
| PJ.22/PJ.23/RV.213 | lifetime + line-item editing reachable on BOTH create and edit cards, one shared view | `ServiceEntryItemCard`/`EditEntryServiceItemRow` both render `ServiceItemLifetimeFields` (`EditEntry/ServiceItemLifetimeFields.swift:10-86`) |
| RV.197 | guest Home renders the SAME `HomeRecentEntries` the signed-in Home does, entry editable | `HomeView.swift:196-202`; `HomeLayout.logArea(for:)` is session-free; rows are `NavigationLink(value: Route.editEntry)` (`HomeSections.swift:454,:640`) |
| RV.208 | Edit entry shows the missing-photo card + re-attach | `EditEntryRows.swift:72-105`, wired `EditEntryView+Attachment.swift:81-86` |
| RV.243 | a deferred expense read keeps the photo (staged at scan start) | `ExpenseEntrySession.swift:102-108` (`stageScan`) consumed by `ExpenseReceiptWrite.write` on save |

Stated explicitly: *no `PJ.n`/`RV.n` is ticked but lacking its behaviour in this cluster.* The three
findings below are gaps in sibling states/surfaces those rows did not claim to cover.

---

## 2. Group A walk (acquisition and capture)

| Journey stage | Verdict | Evidence |
|---|---|---|
| J1 Welcome root, three peer paths + restore line | MET | `WelcomeView.swift:127-185` (three paths), `:191-201` (restore line); `WelcomeGate.swift:92-95` (`!hasVehicle && !hasSession`) |
| J1 restore intent carried by which door | MET | `WelcomeRootView.swift:39` (`onRestore` → `arrivedViaRestore: true`), `SignInRequest` `:100-108` |
| J1 guest Home log stream (RV.197) | MET | `HomeView.swift:190-202`; `HomeLayout.logArea(for:)` |
| J1 guest Home "first" wording drops after an entry | MET | `HomeGuestLayout.swift:205-213` |
| J2 entry points (Welcome restore door; import door; guest import card) | MET | `WelcomeRootView.swift:38-39`; `HomeGuestLayout.swift:246-253` (`Route.importWizard`) |
| J3 cross-check lock + dimming + live odometer delta | MET | `ManualFillUpSections.swift:279-331` (lock), `:214-237` (dim 0.6), `:409-451` (delta captions, never blocks); save gated on total+litres `ManualFillUpView.swift:535-538` |
| J3 "Also on this receipt" + shared `purchaseGroupId`/attachment | MET | `MixedReceiptSection.swift:13-113`; `ManualFillUpView.swift:560-595` (`purchaseGroupId` `:578`, shared receipt id) |
| J3 insight one-liner after save | MISSING (tracked) | **cited PJ.15 [v1.1]** - `save()` (`ManualFillUpView.swift:553-635`) posts no insight toast |
| J4 pump display | N/A (ships off) | `PumpPhotoGate.swift:96-98` (`allowsPumpPhoto == false`); caption respects the gate `CaptureView.swift:510-515` |
| J3b "Type it" one tap in every state | MET (see §4a for one gap) | signed-in header `HomeView.swift:422-460`; empty `HomeEmptyStates.swift:25,:95-98`; guest `HomeGuestLayout.swift:218-225`; inside Capture `CaptureView.swift:598-617`; review step `CaptureReviewView.swift:110-112`; mode-typed form `CaptureMode.swift:67-74` |
| J5 QR anchors total+date, litres/price stay OCR, no "exact" copy | MET | `FuelExtractorTotalFinder.swift:24-43`; `FiscalQR.swift:253-275` (`liters/unitPrice/fuelKind` nil); no "exact" string on the QR surface |
| F1 all-nil scan: photo kept, Total focused, quiet caption | MET | `ConfirmPrefill.swift:239-254`; `EmptyScanCaption.swift:23-52`; photo survives via `ManualFillUpReceiptSave.swift:203-216` |
| F2 amber underline + tap-to-verify crop | MET | `ManualFillUpSections.swift:279-289,:366-374` (suspect), `:256-268` → `VerifyCropSheet` |
| F3 rate-pending chip "converts when online" | MET | `CurrencyConversionCard.swift:144-149`; `ManualFillUpCurrencySupport.swift:379-392` |
| F4 3 s budget + Settings quota surface | MET | `GatewayBudget.swift:20`; `ManualFillUpGatewayBanner.swift:19-46`; quota card `SettingsView.swift:555-576` (RV.253) |
| F4 "enhanced reading unavailable" hint | MISSING (tracked) | **cited PJ.18 [v2]** - only the timeout branch renders |
| F5 QR decodes, nothing fetched, no failure copy | MET | same as J5; no "exact"/"failed" copy |
| F8 denied-camera card + Settings deep link + "add from photos" | MET | `CapturePermissionCards.swift:15-50,:109-112`; photos always present `CaptureView.swift:577-596` |
| F8 `.restricted` (device policy) | PARTIAL (tracked) | **cited RV.226 [open]** - `.restricted` shows only "Type it", no Photos/Settings (`CapturePermissionCards.swift:58-62`) |

---

## 3. Group B walk (service, parts, reminders, EV)

| Journey stage | Verdict | Evidence |
|---|---|---|
| J6 EV charge | N/A | `[v1.x]`; `CaptureMode.modes(for: .ev)` returns `[.service, .expense]` (`CaptureMode.swift:44-50`), no `ChargeEntryView`; **cited RV.236/RV.237/RV.238** |
| J7 manual door → ServiceEntryView, odometer pre-filled | MET | `HomeView.swift:414-460`; `ScannedFillUpSheet.swift:90-96`; `ServiceEntryView.swift:307-309,:237-239` |
| J7 invoice multi-page + deterministic split + lump-sum fallback | MET | `ServiceEntryView.swift:130-137,:386-397`; `InvoiceSplitter.swift:69-116` (sum invariant `:78-92`) |
| J7 `.other` → real category promotion (Edit entry) | MET | `EditEntryNonFillView.swift:406-492`; write-back `EditEntryView+NonFillSave.swift:60-73` |
| J7 odometer rule (RV.212/RV.214) | MET | `ServiceEntryDraft.swift:81-116`; create `ServiceEntryFormState.swift:210-222`, edit `EditEntryFormState.swift:134-150` |
| J7d post-save offer from item lifetime, suppressed when live exists | MET | `ReminderOffer.swift:209-256,:175-183,:152-157`; staged `ServiceEntryView.swift:455-461`, `ExpenseEntryView.swift:268-272` |
| J7 ОСАГО reminder type | MET | `ReminderOffer.swift:163-168`; `ReminderCompletion.swift:45-51`; `ReminderFormView.swift:274-277` |
| J7b `.parts` purchase + install-from-shelf without re-pricing | MET | `PartsShelf.swift:45-64`; `ServiceEntryView.swift:248-259,:438-444` |
| J7b TireSet from purchase (PJ.26) | MET | `EditEntryView.swift:255-271`; `TireSetPurchase.swift:37-46` |
| J7b seasonal swap (PJ.27) + derived set mileage "–" | MET | `ReminderOffer.swift:212-226`; `TireMileage.swift:27-70`; `TireSetRowFormat.swift:16-21` |
| J7c Complete → "Log the cost?" → pre-filled entry → next cycle at completion | MET | `ReminderCompleteSheet.swift:88-163,:249-259`; `ReminderLifecycle.swift:191-229`; pre-fill `ServiceEntryView.swift:312-324`, `ExpenseEntryView.swift:386-392` |
| J7c Reschedule re-arms; Delete tombstone vs dismiss-with-reason | MET | `ReminderLifecycle.swift:237-250,:289-301`; `RemindersView.swift:107-129,:195-222` |
| J7d permanent Home "Reminders · N due" row | PARTIAL (see §4c) | `HomeView.swift:256` (signed-in `fullLayout` only); `HomeBanners.swift:164-208` |
| J7d empty state's "New reminder" is a filled button | MET | `RemindersEmptyStateView.swift:35-46` |
| J7d form's car is first field | MET | `ReminderFormView.swift:65-68,:110-125` |
| RV.247 "Type amount" → reminder's own car | MET | `ReminderCompletionSession.swift:17-43`; `ReminderCompleteSheet.swift:249-254` |

No untracked gaps in Group B other than §4c below; every other PARTIAL/MISSING maps to an existing row.

---

## 4. The three findings (the guest-Home parity family)

All three are one family: the guest Home is a thin subset that still drops hard-rule surfaces the
signed-in Home has. RV.197 fixed the log and RV.251 (open) files the car switcher; these three are
the *next* omissions, each a distinct surface/decision, so each gets its own row rather than a
catch-all.

### 4a. The guest Home's "Type it" opens only the fill-up form (rule 15)

`HomeGuestLayout.swift:218` is a bare `Button("Type it", action: onTypeIt)` where `onTypeIt` is
`presentSheet(.confirmManual)` (`HomeView.swift:197`) - the fill-up form, no menu. The signed-in
Home's `typeItControl` carries the trailing menu `CaptureEntryForm.doorMenuForms` (fill-up, Service,
Expense) (`HomeView.swift:437-444`). A guest can still reach Service/Expense through the Capture
tab's mode row (`CaptureMode.swift:67-74`), so this is a parity gap, not a dead end - but a no-account
user who wants to log their first service taps "Type it" on Home and lands in a fill-up form. → **PJ.100**.

### 4b. The guest no-car Home card has no Add-car affordance

`HomeGuestLayout.swift:272-284` (`noCarCard`) renders text only ("No car yet / Add your first car"),
while the signed-in no-car layout carries a filled "Add your first car" button (`HomeEmptyStates.swift:72-82`)
and Welcome's root carries "Add your car". RV.197's own verification noted it - *"Noted, not fixed:
the guest no-car Home has no Add-car button (Garage tab reaches it)"* (`TASKS-DONE.md` RV.197) - but
no row tracks it. Reachable: sign out with no car, or a guest archives their only car; the tabbed app
does not re-run `WelcomeGate` mid-session, so the text-only card is what shows. → **PJ.101**.

### 4c. The guest Home has no Reminders entry row (J7d's discovery surface is account-gated)

`HomeRemindersEntryRow` renders only inside the signed-in `fullLayout` (`HomeView.swift:256`); the
guest branch (`HomeView.swift:190-202`) renders `HomeGuestLayout`, whose body is garage card / log /
capture / import / privacy with no reminders row and a non-tappable garage card (`HomeGuestLayout.swift:35-63`).
Reminders are local-first (rule 1) and a guest's only door is Garage → car → Reminders
(`VehicleDetailView.swift:226-230`, four taps) - exactly the "trigger at the bottom of a list four
taps deep" problem J7d was written to fix (`docs/JOURNEYS.md:410-411`). J7d is marked
**Status: implemented 2026-09-12**, so this is a finding against a REVIEWED story (the higher-value
kind). → **PJ.200**.

---

## 5. Proposed rows (fresh range: Group A = PJ.1xx, Group B = PJ.2xx)

### PJ.100 - (J3b "Type it the peer path, every locale"; J7/J7b peer doors) the guest Home's "Type it" opens only the fill-up form

**gap** - a rule-15 parity omission, not a dead end.

The guest Home's `Type it` (`HomeGuestLayout.swift:218`) is a plain button bound to
`presentSheet(.confirmManual)` (`HomeView.swift:197`), while the signed-in Home's `typeItControl`
carries the `CaptureEntryForm.doorMenuForms` menu (fill-up / Service / Expense) (`HomeView.swift:437-444`).
A no-account user who wants to log a service or an expense from Home lands in the fill-up form and
must find the Capture tab's mode row instead. Service and expense are fully local; nothing about
being a guest gates them, so the two layouts should not differ on this.

**Deliverable:** give the guest capture card the same Service/Expense affordance the signed-in Home
has - the same `CaptureEntryForm.doorMenuForms` menu (one control, not a copy), so a guest reaches all
three entry kinds from Home in one tap plus one menu pick.

**Journey stage:** J3b "Type it (the peer path, every locale)" - the two doors at every entry point,
including the guest entry point.

**User-facing consequence today:** a no-account user who wants to log an oil change or an expense taps
"Type it" and gets a fill-up form with litres and price; the Service/Expense door is two hops away
through Capture and not discoverable from Home.

**Check:** L4 `ColdLaunchJourneyUITests` (guest): the guest Home "Type it" exposes Service and Expense
(a menu, same identifiers as the signed-in `typeItMenu`), and picking Service opens `ServiceEntryView`.
EN + RU.

### PJ.101 - (J1 "Add car") the guest no-car Home card has no Add-car affordance

**polish** - a text-only card where the signed-in equivalent is a filled button.

`HomeGuestLayout.noCarCard` (`HomeGuestLayout.swift:272-284`) renders "No car yet / Add your first car"
with no button; the signed-in no-car layout has a filled "Add your first car" button
(`HomeEmptyStates.swift:72-82`). RV.197's verification noted it and never filed it
(`TASKS-DONE.md` RV.197: "Noted, not fixed"). Reachable when a guest signs out with no car, or archives
their only car mid-session (the tabbed app does not re-run `WelcomeGate`).

**Deliverable:** give the guest `noCarCard` the same `Route.addVehicle` button the signed-in no-car
layout carries, so the two no-car states cannot drift.

**Journey stage:** J1 "Add car" - the add-car door stays one tap from a no-car Home in every state.

**User-facing consequence today:** a guest who finds themselves on Home with no car sees an instruction
with no action; the only add-car door is the Garage tab's tile.

**Check:** L4 `ColdLaunchJourneyUITests`: guest, no car, on the tabbed Home - the card's button opens
Add car. EN + RU frame.

### PJ.200 - (J7d "Plan it" / "Discover it") the guest Home has no Reminders entry row, so the discovery surface is account-gated

**gap** - against J7d, a journey marked **implemented 2026-09-12** (reviewed by REVIEW-SCENARIO), so
this is a finding against a reviewed story.

`HomeRemindersEntryRow` renders only in the signed-in `fullLayout` (`HomeView.swift:256`); the guest
branch renders `HomeGuestLayout` with no reminders row and a non-tappable garage card
(`HomeGuestLayout.swift:35-63`). Reminders are local-first (rule 1); J7d's whole point was a permanent,
always-present Home row so the trigger is not "four taps deep" (`docs/JOURNEYS.md:407-419`). For a guest
that trigger is gone - the only door is Garage → car → Reminders (`VehicleDetailView.swift:226-230`).
The sibling of RV.197 (the log) and RV.251 (the switcher), one surface further.

**Deliverable:** render `HomeRemindersEntryRow` (with `Route.remindersAll`) in the guest layout too,
or otherwise give a no-account user a Home-level door into Reminders - the SAME control, not a copy.

**Journey stage:** J7d "Plan it" ("Home's permanent 'Reminders · N due' row, present whether or not
anything is due") and "Discover it" ("the row is always present, count or no count").

**User-facing consequence today:** a no-account user who has never made a reminder has no way to learn
the feature exists from Home; they must already know to open Garage → the car → Reminders.

**Check:** L4 `ColdLaunchJourneyUITests` (guest, one car): the guest Home shows the reminders row and
it opens the merged list; the empty state's "New reminder" is reachable. EN + RU frame of the guest
Home with the row.

---

## 6. Cited, not re-filed

| Observation | Existing row |
|---|---|
| After-save insight one-liner absent | PJ.15 [v1.1] |
| F4 "enhanced reading unavailable" hint absent (timeout branch only) | PJ.18 [v2] |
| F8 `.restricted` camera shows "Type it" only, no Photos/Settings | RV.226 [open] |
| Guest Home has no car switcher with two cars | RV.251 [open] |
| Welcome copy overpromises charging + pump display | RV.241 [open] |
| Guest import card names Fuelio (not a shipped importer) | RV.241 [open] |
| J6 EV charge / two-car chart / tariff | RV.236 / RV.237 / RV.238 [v1.x] |
| Scan-invoice door on ReminderComplete | PJ.24 [v1.x] |
| Invoice pages through `/extract` | PJ.29 [v1.x] |
| Parts shelf v2 | PJ.52 [v2] |
| Seasonal advisory | RV.124 [v1.1] |
| Reminder dismiss-reason read by nothing | RV.248 [open] |
| Expense late-read date / orphan invoice pages | RV.246 / RV.245 [open] |
| Tire-set creation offered only from Edit entry, not at purchase | see §7 |

---

## 7. Looked for and could not settle

- **Tire-set creation is offered only on Edit entry, never at the purchase moment.** J7b's "a tire
  purchase becomes a TireSet" (`docs/JOURNEYS.md:360`) does not specify *when*, and PJ.26's agreed
  deliverable was the edit-door card. A post-save offer (like J7d's) is a product-sequencing question,
  not a PJ.26 gap; left as a note for the owner rather than a row.
- **Screenshots not personally viewed** (no image input). The three guest-Home claims rest on code
  (`HomeGuestLayout.swift`, `HomeView.swift`) plus RV.197/RV.251's own verified notes; the orchestrator
  must open the guest Home frames to confirm the missing row / missing menu visually.
- **Guest reachability of the Garage tab and Vehicle detail** was not re-verified end to end (RV.251's
  row already establishes a guest reaches the Garage). If a guest's Garage were gated, PJ.200's severity
  would rise from gap to bug.

---

## 8. Run history

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows (36 since shipped, 30 open) |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`), 0 ticked-but-not-true |
| 2026-09-09b | `1ec2b1d` | 2 rows (`PJ.56`, `PJ.57`), 0 ticked-but-not-true |
| 2026-09-12 | `42ac5a9e` | 3 rows (`PJ.100`, `PJ.101`, `PJ.200`), 0 ticked-but-not-true; Group A + Group B |
