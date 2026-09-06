# Tankbook – Notifications

*How anything reaches the user outside the app, and the scenario catalog. Companion to `JOURNEYS.md` (J7c, J9), `ERRORS.md` (permission-off states), `SYNC.md` (nudges), `SCHEMA.md` (Preferences), `API.md` (device endpoints).*

## Three delivery mechanisms, deliberately unbalanced

**1 · Local notifications (`UNUserNotificationCenter`) – carry ~everything the user ever reads.**
Scheduled on-device, work with no account and no network, cost nothing server-side. Date-based reminders schedule directly. **Odometer-based reminders can't fire by km in the background** – they arm at data-write time: every save recomputes distance-to-due, and when a threshold is crossed ("within 500 km of the oil change") the device schedules the local notification then. A car that isn't driven never notifies – correct behavior for free.

**2 · Remote push (APNs via our backend) – carries only silence.**
One use in v1.x: the **silent sync nudge** (`content-available`, no alert, no sound, no text – the payload says only "pull"). The device syncs in the background; anything user-visible that results (a conflict badge, a reminder completed elsewhere) surfaces through the normal in-app mechanics. This resolves SYNC.md's open question: **ship silent nudges at v1.x** (the backend exists anyway), with foreground polling as the always-there fallback – nudges are an optimization, never a dependency. **No user-visible remote push exists at all in v1**, and no marketing push will ever exist – written as a hard rule.

**3 · The in-app inbox (the bell on the tab-root header, RV.38) – for work that finished after the user moved on.**
Not a push at all: it is a **home for delayed results**, device-local. The first producer is a cloud reading that lands **after** the entry was saved (`docs/JOURNEYS.md` F4, amended): the answer becomes an inbox item the user accepts, edits or declines – "leave it as it is" is the default, and an accepted update fills blank fields only (hard rule 13). The entry keeps its own badge, so the bell is a second route, never the only place a problem is visible (hard rule 8). Later producers (a due reminder surfaced here too) are planned, not shipped; the Reminders screen remains the management home and the inbox **links** to it, never replaces it. Durability is now a backend matter, and it is **not** a ledger read: a cloud answer the device never received is queued in the per-device delivery outbox (`docs/API.md` "Delivery outbox", `docs/SECURITY.md` "The delivery outbox") and drained into this same inbox on launch and foreground – a durable re-read with no second rule-9 reversal, because the server holds opaque bytes addressed to the device, never a field it reads.

The drain is launch/foreground only for now: the silent-APNs wake (mechanism 2) is the natural fit to make the drain prompt, and it is **deferred** – a queued answer still reaches the inbox on the next launch, which is complete, shippable behaviour on its own.

Device tokens register via `PUT /account/devices/{id}/push-token` (API.md); token invalidation (APNs feedback) just clears the row – the device falls back to polling.

## Scenario catalog

| Scenario | Mechanism | Timing & tone | Tap lands on | User control (Preferences) |
|---|---|---|---|---|
| Reminder due (date: insurance, TÜV, tire season) | Local | Morning of the due-window start (09:00 local), one line: "Insurance renews in 12 days." | Reminders screen | `notifications.reminders` (default on) |
| Reminder due (odometer: oil change) | Local, armed at write time | Scheduled the evening after the save that crossed the threshold: "Oil change within 500 km." | Reminders screen | same |
| Overdue follow-up | Local | Exactly one, 7 days after due: "Still pending: insurance renewal." Never a nag loop | Reminders screen | same |
| Anomaly insight (J9) | **In-app card only** by default – "never a push alarm" | Amber card in the Log; optional local notification is opt-in | The evidence view | `notifications.anomalies` (in-app on; push opt-in) |
| Monthly summary (J8) | Local | 1st of month, 10:00: "August: 212 € on the Volvo." Opt-in, **one notification per car** (see below) | Trends | `notifications.monthlySummary` (default off) |
| Sync nudge | Silent APNs | Invisible, throttled server-side (max ~1/15 min per device) | – (background pull) | none – it's invisible |
| Config nudge | Silent APNs (`config: true` hint on the same payload) | Invisible; used to propagate an urgent change such as a kill switch in minutes rather than the normal 6-hour poll | – (background config fetch, `CONFIG.md`) | none – it's invisible |
| Post-outage batch result (S7) | In-app toast, not a notification | "Synced. 2 entries need a look" on next open | Log filtered to flagged | – |
| Cloud reading lands after save (RV.38) | **In-app inbox** (the bell) | Quiet badge on the bell AND on the entry; the item asks "update from the receipt · leave it as it is · replace the receipt" with leave the default | The inbox → the entry (Edit entry) | none – it is in-app, never a push |
| Shared-vehicle activity (v2) | Silent nudge only | Partner's fill-up just appears via sync; no "X logged a fill-up" alert unless v2 research says otherwise | – | (v2) |

Explicit non-scenarios: no "you haven't logged in a while" re-engagement, no feature announcements, no rating prompts via push, nothing from the LLM/quota system. The notification channel spends trust; only the user's own deadlines may draw on it.

## The tap deep link (PJ.5)

Tapping a notification goes where the catalog's "Tap lands on" column promised. The
identifier itself carries the destination, so the tap routes without the app storing any
"which notification" bookkeeping:

- **`reminder.<uuid>.<kind>`** lands on the **Reminders screen with that reminder's
  completion sheet surfaced** – the reminder the notification was about is the thing in
  frame. The kind (`date` / `odometer` / `overdue`) is part of the identifier format but
  never the destination: every reminder notification lands on the same screen, for the same
  reminder.
- **`monthly-summary.<uuid>.<year>-<month>`** lands on the **Trends tab**.

The identifier -> destination mapping is a **pure value type in core** (`NotificationRoute`
+ `NotificationRouteParser`, unit-tested L1) precisely because the app has no unit-test
target: `UNUserNotificationCenter` is only reachable through XCUITest, which asserts
behaviour and never values. `didReceive` resolves the tapped identifier through the parser
and hands the route to the app's `NotificationRouter`, which drives the tab switch / push.

**An unknown or malformed identifier is inert** – no dots, a bad UUID, a kind the installed
app does not produce: the app opens normally and routes nowhere. This is not paranoia: a
notification is attacker-adjacent input in the sense that it can be STALE. A reminder
deleted since its notification was scheduled must land on the Reminders list – not a dead
end, and never somewhere arbitrary (hard rule 7). The parser is strict deliberately: an
identifier the app itself cannot produce is treated as unknown, never guessed at.

## The fired-reminder actions (RV.78)

The three reminder rows in the scenario catalog share one banner, and since RV.78 that banner
can be acted on (`design/screens/ReminderNotification.dc.html`, `docs/SCREENMAP.md`). One
notification category (`reminder.actions`) with **two actions** is registered at launch and
attached to every reminder request, so a fired banner offers them without opening the app:

| Action | Identifier | What it does | Why this shape |
|---|---|---|---|
| **Mark done** | `reminder.action.complete` | Opens the app on that reminder's **completion sheet** (foreground action) | **Never a silent `.done(nil)`.** J7c makes declining the cost log first-class, but it has to be a *choice the user made* – the sheet is where that choice already lives. Mark done lands exactly where a tap lands: same route, same sheet, no second completion implementation to drift from `ReminderLifecycle.complete` |
| **Push a week** | `reminder.action.snooze` | Defers the fired reminder by **7 days** and re-arms it, in the background – the one action that needs no screen | "Snoozing beats ignoring" (J7c): at a red light the snooze must cost one tap, not the four taps of open-app → find-car → open-sheet → Reschedule |

**What "a week" defers is the DATE.** `ReminderLifecycle.snooze` is a reschedule with a fixed
7-day delta (`ReminderLifecycle.snoozeDays`, a compiled number – the banner has two buttons,
no pickers): the due date moves forward seven days, and a fired `.attention` resets to
`.scheduled` so the planner re-arms from the new due – the notification comes back a week
later instead of staying quiet. **A reminder due only by odometer has no time dimension to
push**: moving its km threshold by "a week" would require the app to guess how far the driver
travels in a week (hard rule 13 forbids exactly that unasked derivation), so the odometer is
left untouched and only the fired state resets – the odometer rule re-arms it on its own
schedule (armed at write time, so the next time the app reconciles a still-due reminder it
notifies again).

The two actions are the *user's* verbs; the cost-log decision and the exact new due stay the
screen's. **The response routes through the same lifecycle the Reminders screen uses** – the
core `NotificationResponseParser` resolves (action, identifier) to a decision, the delegate
handles it, and both Mark done's completion sheet and Push a week's
`ReminderNotificationCoordinator.snooze` reach the same `ReminderLifecycle` transitions and the
same reconcile that arms every notification. A **dismissal**, an **unknown action identifier**
(a banner scheduled by an older build) or a **stale notification** (the reminder deleted since
scheduling) is inert: the app opens normally, routes nowhere and mutates nothing (hard rule 7).
This is the second reason the (action, identifier) mapping is a pure value type in core,
alongside `NotificationRouteParser`: the app has no unit-test target, and the mapping must not
drift from the registered strings.

## Reminders & archiving (RV.81)

The three reminder rows above are the decisions; archiving (J13) is the lifecycle event that
strips them (product-owner decision 2026-09-06: *"archived cars strip the reminders"*). The rule
is recorded here because NOTIFICATIONS.md is the authority for what archiving does to armed
requests:

- **Archiving cancels the car's pending reminder notifications.** `VehicleDetailView.toggleArchive`
  archives the car and reconciles it; the reconcile is archive-aware - `ReminderNotificationPlanner`
  schedules nothing for an archived car and cancels every identifier its rows own. A sold car can
  never fire a banner for work nobody will do.
- **Unarchiving re-arms.** The same reconcile arms a live car, so the archive toggle is one code
  path for both directions: archive strips, unarchive re-arms. A car that comes back is never
  silently mute. No stored `.attention` transition is written while the car is archived - a
  put-away car must not accumulate "already notified" state it never earned, or an odometer
  reminder unarchived inside its km window could not re-arm (the odometer entry only arms from
  `.scheduled`).
- **The strip is not a delete.** The reminder rows are never tombstoned or dismissed (hard rule 8:
  archiving is "put it away", and the Garage row's "history preserved" promise depends on it).
- **A delivered or racing notification still lands.** Nothing can recall a notification the system
  already presented, or one handed over a moment before the archive action. The tap resolve
  (`liveReminder(id:)`) stays live for archived cars, so those taps still surface the reminder's
  completion over the merged list - a landing, never a dead end (hard rule 7).
- **While archived, the rows are hidden on every screen.** The merged list already excludes them
  (RV.75: history, not work); the per-car management row is removed from an archived car's Vehicle
  detail (RV.81), so no surface presents a sold car's tasks. The rows return - on the per-car
  screen, this list and its notifications - when the car is unarchived. The exclusion and the
  arming are both read-time derivations from `Vehicle.archived`, never a stored state.

Multi-device: this section states the LOCAL action's contract. A car archived on one device
stops firing on that device immediately. A second device learns of the archive only when it
syncs, and the merge-time strip for reminders is the sync layer's half of the same decision,
**not yet wired** - see the last paragraph of "Multi-device behavior" for what that means for a
stale armed request on another device.

## Monthly summary (J8) – the decisions (P6.2)

The catalog row names the shape; these are the decisions implementation forced, so they are
written down rather than implied by code:

- **One notification PER CAR, not one aggregate and not just the selected car.** Money is a pair
  whose `homeCurrency` is the vehicle's own (SCHEMA.md), so a household's cars can carry
  different currencies and an aggregate would silently mix them; and Trends – where the toggle
  lives and where the tap lands – is per-car. The doc's own format is per-car ("…on the Volvo.").
  Each car that spent that month gets its own notification, in its own currency; a car that
  spent nothing gets none.
- **A month with nothing to say produces NO notification** – a push that tells the user nothing
  happened is a nag. No entries in the month, only rate-pending entries (F9, no `homeAmount`
  snapshot yet), or a zero total all mean silence.
- **The amount is the sum of the month's stored `homeAmount` snapshots** (hard rule 3) – each
  entry's conversion written when its rate was known, at `rateDate` = the entry's date. The
  summary never re-converts at a later rate. Rate-pending entries contribute nothing until
  their snapshot exists.
- **The fire date is the 1st of the month FOLLOWING the summarized month, at 10:00 local** – a
  reconcile on 20 August arms "August" to fire 1 September. The plan is recomputed on every
  launch, foreground and toggle change, and re-arms by a stable per-(car, month) identifier, so
  a later launch with fresher data replaces rather than stacks. On the 1st itself, the
  about-to-fire previous-month summary coexists with the newly armed one.
- **Turning the toggle OFF cancels the pending request**, not merely stopping new ones – the
  toggle-off plan cancels every car's pending identifier. An archived (J13) or deleted car stops
  summarizing: its reason is gone, so its pending notification is cancelled.
- **Copy uses the app's money convention** – "August: 212 € on the Volvo." (amount then symbol,
  the same `HomeFormat.spend` the Trends tiles use) – so the notification and the tile it lands
  on can never disagree about a figure.
- **Permission follows the one rule, applied to this feature's own moment of need:** requested
  when the toggle is first flipped ON (never at launch, never a repeat once decided). A denial
  is only answered from Settings, exactly like the reminders; the summary is simply not
  delivered until then.

## Multi-device behavior

Local notifications schedule on **every signed-in device** (each device knows the reminders via sync). Acceptable and honest – Apple's own Reminders does the same. The cleanup contract matters more: **any change that resolves a notification's reason cancels it everywhere** – completing/rescheduling a reminder syncs, and each device cancels its pending local notification for it on merge. Archiving is the same contract for the whole car, with one half shipped: RV.81 makes the LOCAL archive action strip immediately (the reconcile that cancels the car's armed requests runs on the device where the user archived); the OTHER device's strip when the `Vehicle.archived` change arrives through sync is the sync-layer half and is **not yet wired** - an archived car's armed reminder on a second device stays pending until that device's own reconcile of the car (e.g. a later unarchive, or the same cleanup hook on merge) strips it. A user who did the oil change never hears about it again from the iPad.

## Permission & quiet behavior

- System permission is requested **at the first moment it's needed** (creating the first reminder), never at onboarding.
- Permission denied → the one-time card from ERRORS.md ("Reminders can't notify you – they'll only show here"), deep link, no nag loop.
- All content categories live in synced `Preferences` (SCHEMA.md); the system permission itself is per-device.
- Quiet by scheduling, not by feature: everything user-visible fires at humane fixed times (09:00/10:00 local) – there is nothing time-critical in a fuel log, so nothing ever needs to buzz at night.
