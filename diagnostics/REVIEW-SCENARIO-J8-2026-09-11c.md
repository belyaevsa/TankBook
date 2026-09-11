# REVIEW-SCENARIO run: J8 – 2026-09-11c (first walk)

- **Scenario:** `J8` (`docs/JOURNEYS.md`)
- **Run id:** REVIEW-SCENARIO-J8-2026-09-11c
- **Context:** First walk. RV.148, RV.118, RV.119, RV.120, PJ.30, PJ.31 are deferred to v1.1 by the owner (2026-09-11) and not blocking - marked N/A here. RV.228/RV.229 are other scenarios' rows. Trends was hand-verified today (four poses, 18 UI tests).

## Verdict

**IMPLEMENTED** - every concrete promise in J8's text is MET or deferred-to-v1.1 by an existing row (PJ.30, PJ.31), and the trigger (the opt-in monthly-summary notification) is MET end to end.

## Ticked rows found to be untrue

None. No row naming this scenario is ticked-but-false. P6.2 (monthly summary) and P1.10 (Trends grid) are the closed rows behind the surface, and both are accurate against the tree.

## Promise-to-code map

| Journey promise (J8) | Status | Citation |
|---|---|---|
| Trigger: "August: €212 on the Volvo" notification, opt-in | MET | `MonthlySummaryNotification.swift:16-66` (type + stable id), `MonthlySummaryPlanner.plan` `:118-147` / `summary` `:156-194`, body `ReminderNotificationCoordinator.swift:274-283` (`MonthlySummaryNotificationText.body`), opt-in default OFF `Entities.swift:616-618`, fire 1st @ 10:00 `MonthlySummaryNotification.swift:44-47` + `fireHour` `:106` |
| Opt-in toggle lives on Trends | MET | `TrendsView.swift:50-52` (`MonthlySummaryToggle`), toggle def `TrendsView.swift:253-272`, flip persists + reschedules `TrendsView.swift:72-74` -> `ReminderNotificationCoordinator.setMonthlySummaryEnabled` `:495-511` |
| Summary re-armed on launch/foreground | MET | `TabRoots.swift:518-520` (`AutomaticPassRunner.Step(code: .summary)` -> `reconcileMonthlySummary`) |
| Tapping the notification opens Trends | MET | `NotificationRoute.swift:44-49` (`monthly-summary.*` -> `.trends`); UI test `TrendsUITests.swift:235-250` |
| open Trends (idle curiosity / end of month) | MET | `AppTabBar.swift` (Trends tab); `TrendsView.swift:16` + `TabRootHeader` `:47-48` |
| hero consumption metric | MET | `TrendsView.swift:136-144` (consumption tile from `stats.home.headline`), `StatTile.swift` (DIN value + unit + sparkline) |
| hero consumption metric **with trend arrow** | **N/A** | `PJ.30` `[v1.1]` deferred. Today `trend:` reaches StatTile as VoiceOver only (`StatTile.swift:44-48`); the sole visible `▲/▼` is the price tile's caption (`TrendsSections.swift:31-39`) |
| monthly spend bars | MET | `TrendsView.swift:184-193` (`spendTile` with `bars: true`), `Sparkline.swift:21-26` (`barChart`), `TrendsStats.spendSeries` `:83`, `:157-180` |
| price-per-liter line **per station brand** ("Shell costs you 4% more than Neste") | **N/A** | `PJ.31` `[v1.1]` deferred. Today `Price / L` = last unit price + per-fill % caption (`TrendsView.swift:164-171`, `TrendsSections.swift:31-39`); no per-station grouping exists |
| control, not accounting homework / no chart junk | MET | honest span labels `TrendsView.swift:141` (`L10n.honestSpanLabel`); tile omitted, never "N/A/–/0.0" (`TrendsView.swift:9-15`, `StatTile.swift:10-12`); gaps never bridged (`Sparkline.swift:36-51`, RV.112) |
| exit within 60 seconds / success metric (≥40% MAU) | N/A | metric, not code - no screen or row can own it |

## Deferred rows (N/A, owner-deferred to v1.1, not re-filed)

| Row | Promise it would close | Status |
|---|---|---|
| PJ.30 | hero trend arrow | `[v1.1]` deferred |
| PJ.31 | per-station-brand price series | `[v1.1]` deferred |
| RV.118 | a derived figure explains its provenance | `[v1.1]` deferred |
| RV.119 | month divider carries distance/consumption/delta | `[v1.1]` deferred |
| RV.120 | fill-pattern card (range left, month forecast) | `[v1.1]` deferred |
| RV.148 | monthly-summary push sums a partial month | `[v1.1]` deferred |

## Sequence trace (one user, end of month, the Volvo)

1. End of month: the Volvo's monthly summary fires ("August: 212 € on the Volvo."), armed by the launch reconcile (`TabRoots.swift:518-520`), body rendered by `MonthlySummaryNotificationText.body` (`ReminderNotificationCoordinator.swift:274-283`).
2. Tap -> `NotificationRouteParser.resolve("monthly-summary.<id>.2026-08")` -> `.trends` (`NotificationRoute.swift:44-49`) -> Trends tab selected.
3. Trends loads the **selected** car, not the notification's car (`TrendsView.swift:232-239`, `carSelection.selectedVehicle`). **This is where the car named in the notification stops being carried** - a documented-deliberate choice (`NotificationRoute.swift:44-47`; `NOTIFICATIONS.md:138-142`), not a defect in this walk.
4. `TrendsStats` derives once from that car and its entries (`TrendsStats.swift:101-143`): hero consumption + sparkline + honest span, cost/km, spend bars, price/L.
5. No per-station-brand series (PJ.31 deferred) and no visible hero arrow (PJ.30 deferred; the trend is VoiceOver-only).
6. Opt-in toggle sits at the foot of the scroll (`TrendsView.swift:50-52`).
7. Exit - the glance is complete. No fact is lost after step 3, and the only cross-step carry (which car) is dropped at the notification tap by a written decision.

## Proposed rows

None. Every concrete promise is MET or owned by an already-filed `[v1.1]` row (PJ.30/PJ.31/RV.118/119/120/148). No `PJ.23`-shaped unowned promise exists.

## Not settled

- **The monthly-summary tap does not pre-select the notification's car.** It lands on the selected car, so a two-car household tapping "on the Volvo" sees the EV's Trends if the EV was last selected. This is documented as deliberate in two places (`NotificationRoute.swift:44-47`, `NOTIFICATIONS.md:138-142`) and the journey text only promises "open Trends", so it does not block IMPLEMENTED - but it is worth a product-owner confirmation, since it is the one place the story's named car is discarded.
- **J8's text (`JOURNEYS.md:418`) carries no inline `[v1.1]` marker on the two deferred phrases** ("with trend arrow", "per station brand"), even though PJ.30/PJ.31 defer them to v1.1. Under the version-scope convention an unmarked journey sentence is a v1 commitment, so the journey text overreaches v1 on those two phrases while the rows that own them are deferred. Not re-filed (the work is already owned); the reconciliation is a doc-edit that folds into the next change touching this file - add the `[v1.1]` marker to those two phrases, or the owner confirms the deferral in prose.
