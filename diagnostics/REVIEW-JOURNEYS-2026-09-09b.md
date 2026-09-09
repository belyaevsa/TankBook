# REVIEW-JOURNEYS run, 2026-09-09b (Group A + Group B)

*Second run of the day. Tree `1ec2b1d`. Single read-only agent covering Group A and Group B
(`agents/briefs/REVIEW-JOURNEYS.md`). Nothing edited, built, or tested. This run took the half the
morning run (`4cc801a`, `diagnostics/REVIEW-JOURNEYS-2026-09-09.md`) left untouched - Group A and
Group B - and settled the three trigger items the four rows shipped since that run fire. Group A and
Group B findings both draw from one fresh range (`PJ.56`+) per the dispatch.*

---

## 1. Ticked rows found to be untrue

**None.** Every ticked row in this run's cluster was checked against its commit and cited seam:

| Row | Claim | Holds at |
|---|---|---|
| RV.141 | the excluded count reaches its entries and states each reason | `ExcludedEntriesFootnote.swift:24-33` (NavigationLink) → `ExcludedEntriesView.swift:104-107` (`L10n.excludedReason`); count and list share `ExcludedEntries.derive` (`HomeStats.swift:153-156`, `ExcludedEntriesView.swift:190`) |
| RV.166 | a `.partial` group prints the known sum marked pending, never a bare total | `LogStreamGroupTotalTests.swift:95-126`; `HomeSections+LogStream.swift:273-288` |
| RV.167 | test-only guard | `MoneyHomeSideSumGuardTests` (no journey consequence) |

The two findings below (`PJ.56`, `PJ.57`) are gaps in **sibling states/cases** those rows did not
claim to fix, not untrue ticks. Stated explicitly: *no `PJ.n` is ticked but lacking its behaviour.*

---

## 2. Group A walk (acquisition and capture)

| Journey stage | Verdict | Evidence |
|---|---|---|
| J1 Welcome root, three peer paths + restore line | MET | `WelcomeView.swift:127-185`, `:191-201`; shown only with no vehicle AND no session `WelcomeGate.swift:92-95` |
| J1 GuestHome landing (Add car continues with no account) | MET | `WelcomeRootView.swift:65-72`, `GuestHome` per SCREENMAP |
| J3 capture review (photo before OCR, Use/Re-take/Type it) | MET | `CaptureReviewView.swift:75-118`; OCR only on Use this `CaptureView.swift:260-272` |
| J3 cross-check lock, dimming, tap-to-verify crop | MET | `ManualFillUpSections.swift:267-319`, dim 0.6 `ConfirmPrefill.swift:38`, `VerifyCropSheet.swift:36-72` |
| J3 live odometer delta, never blocks save | MET | `ManualFillUpSections.swift:399-434`; `saveEnabled` `ManualFillUpView.swift:541-544` |
| J3 mixed-receipt "Also on this receipt" + shared `purchaseGroupId` | MET | `MixedReceiptSection.swift:26-36`; `ReceiptGroupPlanner.plan` `MixedReceipt.swift:304-315`; one attachment `ManualFillUpView.save` `:569-596` |
| J3 mixed fallback "add expense from this receipt later" | MISSING (tracked) | no affordance found on Edit entry; **cited PJ.41 [v1.x]** |
| J3 AdBlue variant (second fill, `.adBlue`) | N/A | `FuelKind` has no `.adBlue`; **cited P1.14 [v1.1]** |
| J3b "Type it" one tap in every state | MET | `HomeView.swift:403-441` (RV.61 split), `HomeGuestLayout.swift:192`, `HomeEmptyStates.swift:25,:95-98`, `CaptureReviewView.swift:106-113`; `CaptureEntryForm.doorMenuForms` `ScannedFillUpSheet.swift:105-107` |
| J5 QR decodes total+date; QR total > fuel line = mixed signal | MET | `FiscalQR.swift:253-299`; `FiscalQRCrossCheck.classify` `:340-346` |
| F1 all-nil scan: photo kept, keyboard on Total, inkSoft caption | MET | `ConfirmPrefill.swift:239-254`; `EmptyScanCaption.swift:34-52` |
| F2 mismatch: amber underline + crop | MET | `ManualFillUpSections.swift:268-276`, `:354-362`, `:244-256` |
| F3 offline identical + rate-pending chip | MET | local pipeline (rule 1); `CurrencyConversionCard.swift:144-149` "≈ – converts when online"; `HomeSections+LogStream.swift:218` |
| F4 3s budget copy | MET | `GatewayBudget.swift:19-21`; `GatewayScanSession.swift:145-152`; `ManualFillUpGatewayBanner.swift:24` |
| F4 quota-spent note in Settings | N/A (tracked) | only blob quota card exists; **cited PJ.18 [v2]** + deferred Pro tier |
| F5 QR anchor never claims "exact"; litres/price stay OCR-editable | MET | `FiscalQR.swift:256-265` (litres/price/kind nil); no "exact" copy anywhere |
| F8 denied-camera card + deep link + "add from photos" | MET | `CaptureView.swift:372-426`, `:548-567` |

Doc drift noted, not filed: J3 says wash is pre-categorized "`.wash`" but `ExpenseCategory`
(`Enums.swift:128-137`) has no `.wash` case - `MixedReceipt.suggestCategory` returns
`.other("wash")` (`MixedReceipt.swift:242`, comment admits it). Functionally identical (the title is
"wash" either way); a one-word doc reconciliation, not a behaviour gap.

---

## 3. Group B walk (service, parts, reminders, EV)

| Journey stage | Verdict | Evidence |
|---|---|---|
| J6 EV charge (share extension, home charge, tariff) | N/A | `[v1.x]`; `ChargeSession`/`Tariff` dormant, no entry form (`CaptureMode.swift:32-66`); **cited PJ.12/PJ.49/PJ.51** |
| J7 manual door (RV.61): Type it → Service, odometer pre-filled | MET | `HomeView.swift:395-437`; `ServiceEntryView.swift:256-258` |
| J7 invoice split (deterministic), lump-sum fallback, `.other` | MET | `InvoiceSplitter.swift:69-99,:126-142,:273-288`; UI `ServiceEntryView.swift:108-115` |
| J7 ".other promoted later without data loss" | PARTIAL (tracked) | `.other` exists, no promotion path; **cited PJ.23** |
| J7 odometer required only for km-lifetime / tire set | MET | `ServiceEntryDraft.swift:76-82`; `ServiceEntryView.swift:160-198` |
| J7d next-reminder offer (anchored at record, suppressed when live exists) | MET | `ReminderOffer.swift:129-137,:230-258`; wired `ServiceEntryView.swift:407`, `ExpenseEntryView.swift:241` |
| J7 ОСАГО reminder type | MET | `ReminderCategory.insurance` `Enums.swift:242`; `ReminderFormView.swift:273-310` |
| J7b parts shelf "install from shelf" without re-pricing | MET | `PartsShelf.swift:45-64` (invariant `:8-12`); `ServiceEntryView.swift:217-228` |
| J7b TireSet creation from a tire purchase | PARTIAL (tracked) | `purchaseExpenseId` written nowhere (`TireSetDraft.build:35`); **cited PJ.26** |
| J7b seasonal swap + derived set mileage "–" when unknown | MET | `ServiceRecord.tireSetId` `ServiceEntrySections.swift:75`; `TireMileage.swift:14-70` → "–" `TireSetRowFormat.swift:18-21` |
| J7b seasonal swap reminder | MISSING (tracked) | **cited PJ.27** |
| J7c Complete → "Log the cost?" → pre-filled entry, next cycle at completion | MET | `ReminderCompleteSheet.swift:114-153`; `ReminderCompletion.prefill` `:70-75`; `ReminderLifecycle.complete` `:191-229` |
| J7c ReminderComplete "scan invoice" door | MISSING (tracked) | **cited PJ.24** |
| J7c Reschedule re-arms; Delete (tombstone/30-day) vs dismiss-with-reason | MET | `ReminderLifecycle.reschedule` `:237-250`, `snooze` `:276-285`; `RemindersView.swift:124,195-213`; `RecentlyDeletedView.swift:104-108` |

No untracked gaps in Group B: every PARTIAL/MISSING maps to an existing row.

---

## 4. The three settlements

### 4a. RV.141's footnote (trigger 3) - reachable and explains, but the tap is invisible

The row's claim **holds**: the footnote reaches its entries and states why. N == 1 opens the entry
(`HomeSections.swift:407-412`), N > 1 opens the list whose rows state the reason
(`ExcludedEntriesView.swift:104-107`), and count and list derive once (`HomeStats.swift:153-156`).

**The affordance is a comprehension defect.** The footnote renders as amber `Text` with no chevron,
no action colour, no underline (`ExcludedEntriesFootnote.swift:22-42`) - byte-identical to the
passive caption it was before RV.141. The affordance directly above it (load-more,
`HomeSections+LogStream.swift:73-92`) and the sibling footnote's action (`PendingRatesFootnote.swift:76-83`)
both advertise their taps with a chevron / `.action`. **Amber is correct and must stay** - hard rule
5 makes it a warning, not an action. The defect is the *missing non-colour* affordance, not the
colour: a tap target that reads as a label, same class as RV.159 (cited, not re-filed). → **PJ.57**.

### 4b. RV.166's four states (trigger 2) - `.mixed` and `.pending` print no figure and no reason

`.complete` and `.partial` are correct and tested (`LogStreamGroupTotalTests.swift:95-179`;
`HomeSections+LogStream.swift:273-288`). `.mixed` and `.pending` both render `EmptyView()`
(`:285-287`). **Reachable**: a foreign-currency mixed receipt logged offline has every member
rate-pending, so the accumulator classifies the group `.pending`
(`LogStream+Accumulator.swift:70-74`). In that state the group card shows title + "N items on this
receipt" and **no total and no explanation** - the member rows (expanded by default) show dimmed
original amounts, but nothing says the receipt's home total is waiting on a rate. The month divider
over the same data shows the pending phrase (`.pending`) or the per-currency breakdown (`.mixed`)
(`HomeSections+LogStream.swift:132-157`), and `docs/ERRORS.md:137-141` documents only the `.partial`
group case - the `.pending`/`.mixed` group rendering is undocumented. This is the "group card with
no total and no reason" state the brief asked about - a mild hard-rule-7 / F9 honesty gap on one
surface. → **PJ.56**. `.mixed` reachability for a *group* I could not trace to a concrete production
sequence (one receipt = one original currency); `.pending` is the clearly reachable case.

### 4c. Trigger 1 - RV.156 station creation and PJ.25 parts shelf are reachable cold

Both production routes exist, no debug flag:

| Door | Route | Evidence |
|---|---|---|
| Station from entry row | ConfirmManual → station row | `ManualFillUpStationRow.swift:53-57` (empty) + `:92-123` (menu "Add station"), `createStation(named:)` `:142-169` |
| Station from Garage | Garage → Stations → add card | `GarageView.swift:288` → `StationsListView.swift:60,:80-103`, `createStation(named:)` `:144-164` |
| Parts shelf door | Vehicle detail → pushed shelf | `VehicleDetailView.swift:167-173` → `Destinations.swift:38` `PartsShelfView(vehicleID:)` |

No PJ.4-class defect (a screen whose only route is DEBUG) in this cluster.

---

## 5. Proposed rows (fresh range, run 2026-09-09b)

### PJ.56 - a `.pending`/`.mixed` purchase-group header prints no figure and no reason

**gap** - one surface of the money pair states nothing where every sibling surface states something.

A purchase group whose members are all rate-pending (a foreign-currency mixed receipt logged
offline) classifies `.pending` (`LogStream+Accumulator.swift:70-74`), and the header renders
`EmptyView()` for `.pending` and `.mixed` (`HomeSections+LogStream.swift:285-287`). The user sees a
receipt card with no total and no "why", while the month divider above it prints the pending phrase
(`:132-139`) and the F9 footnote explains - the two surfaces use the same `MonthTotal` but render it
differently. `docs/ERRORS.md:137-141` documents only the `.partial` group case.

**Deliverable:** render the group header's `.pending` and `.mixed` the same way the divider renders
them (pending phrase for `.pending`, per-currency breakdown for `.mixed`) - reuse `dividerFigure`
rather than a second implementation - and document the two cases in `docs/ERRORS.md`. The member rows
still state each amount as today; the header just stops being silent.

**Journey stage:** J3 mixed-receipt variant / F3-F9 (rate-pending receipt) - the group header states
the receipt total exactly as honestly as the divider does.

**User-facing consequence today:** a driver who logs a foreign mixed receipt offline sees a group
card with no total and no explanation, unlike the divider and footnote on the same screen.

**Check:** L1 (a `.pending` group and a `.mixed` group render the pending phrase / breakdown, reusing
the divider's rendering). L4 `HomeUITests`: a pending group's header shows the pending phrase; EN +
RU.

### PJ.57 - the excluded-entries footnote is a tap target with no visual affordance

**polish** - a comprehension defect, not a hard-rule-5 violation (amber is correct).

The footnote is now a `NavigationLink` but renders as a bare amber `Text` with no chevron, no action
colour, no underline (`ExcludedEntriesFootnote.swift:22-42`) - identical to the passive caption it
replaced. A user who saw "8 entries excluded" before RV.141 sees the same pixels and no reason to
tap. The load-more row (`HomeSections+LogStream.swift:73-92`) and the pending-rates footnote's action
(`PendingRatesFootnote.swift:76-83`) both advertise their taps. Same class as RV.159 (a control that
reads as a label); amber stays (hard rule 5).

**Deliverable:** add a non-colour affordance to the footnote - a chevron (the load-more row's idiom)
or equivalent - so it reads as tappable, keeping `Theme.Palette.warn`.

**Journey stage:** F9a/S2 - the "N entries excluded" footnote's next step is discoverable, not just
reachable.

**User-facing consequence today:** the tap works but is undiscoverable, so RV.141's fix is
half-undone for a sighted user.

**Check:** L4 `HomeUITests` / `TrendsUITests`: the footnote carries a tappable-affordance identifier
in both screens, EN + RU.

---

## 6. Cited, not re-filed

| Observation | Existing row |
|---|---|
| Mixed-receipt fallback "add expense from this receipt later" absent from Edit entry | PJ.41 [v1.x] |
| AdBlue mixed line never a second fill | P1.14 [v1.1] |
| F4 quota-spent note in Settings absent (only blob quota) | PJ.18 [v2] |
| `.other` promotion / line-item edit frozen | PJ.23 |
| ReminderComplete "scan invoice" door absent | PJ.24 |
| TireSet creation from purchase (`purchaseExpenseId` unwritten) | PJ.26 |
| Seasonal swap reminder absent | PJ.27 |
| J6 EV deferral | PJ.12 / PJ.49 / PJ.51 |
| Station ranking `favorite` rung dead | PJ.55 |
| Identical-looking consents (same-class precedent for PJ.57) | RV.159 |
| Feedback send invisible | RV.160 |

---

## 7. Looked for and could not settle

- **Screenshots not personally viewed** (no image input). The amber/no-chevron claim rests on the
  code (`ExcludedEntriesFootnote.swift`) and the dispatch note, not on opening
  `design/screenshots/RV.141-home-excluded.png`. The orchestrator must open it to confirm the
  affordance gap visually.
- **`.mixed` group reachability** in production: the accumulator produces it (`:83`), but I found no
  concrete same-receipt sequence where known members span home currencies (one receipt = one original
  currency). Settled by a seed or a targeted L1 test with two same-group members in different home
  currencies.

---

## 8. Run history

| Run | Tree | Yield |
|---|---|---|
| 2026-08-29 | `93d2619` | 66 `PJ` rows (36 since shipped, 30 open) |
| 2026-09-09 | `4cc801a` | 1 row (`PJ.55`), 0 ticked-but-not-true; deep on J4 / J7b / money+rates / feedback |
| 2026-09-09b | `1ec2b1d` | 2 rows (`PJ.56`, `PJ.57`), 0 ticked-but-not-true; Group A + Group B, three trigger settlements |
