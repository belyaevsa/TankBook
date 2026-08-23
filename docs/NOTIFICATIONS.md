# Tankbook – Notifications

*How anything reaches the user outside the app, and the scenario catalog. Companion to `JOURNEYS.md` (J7c, J9), `ERRORS.md` (permission-off states), `SYNC.md` (nudges), `SCHEMA.md` (Preferences), `API.md` (device endpoints).*

## Two delivery mechanisms, deliberately unbalanced

**1 · Local notifications (`UNUserNotificationCenter`) – carry ~everything the user ever reads.**
Scheduled on-device, work with no account and no network, cost nothing server-side. Date-based reminders schedule directly. **Odometer-based reminders can't fire by km in the background** – they arm at data-write time: every save recomputes distance-to-due, and when a threshold is crossed ("within 500 km of the oil change") the device schedules the local notification then. A car that isn't driven never notifies – correct behavior for free.

**2 · Remote push (APNs via our backend) – carries only silence.**
One use in v1.x: the **silent sync nudge** (`content-available`, no alert, no sound, no text – the payload says only "pull"). The device syncs in the background; anything user-visible that results (a conflict badge, a reminder completed elsewhere) surfaces through the normal in-app mechanics. This resolves SYNC.md's open question: **ship silent nudges at v1.x** (the backend exists anyway), with foreground polling as the always-there fallback – nudges are an optimization, never a dependency. **No user-visible remote push exists at all in v1**, and no marketing push will ever exist – written as a hard rule.

Device tokens register via `PUT /account/devices/{id}/push-token` (API.md); token invalidation (APNs feedback) just clears the row – the device falls back to polling.

## Scenario catalog

| Scenario | Mechanism | Timing & tone | Tap lands on | User control (Preferences) |
|---|---|---|---|---|
| Reminder due (date: insurance, TÜV, tire season) | Local | Morning of the due-window start (09:00 local), one line: "Insurance renews in 12 days." | Reminders screen | `notifications.reminders` (default on) |
| Reminder due (odometer: oil change) | Local, armed at write time | Scheduled the evening after the save that crossed the threshold: "Oil change within 500 km." | Reminders screen | same |
| Overdue follow-up | Local | Exactly one, 7 days after due: "Still pending: insurance renewal." Never a nag loop | Reminders screen | same |
| Anomaly insight (J9) | **In-app card only** by default – "never a push alarm" | Amber card in the Log; optional local notification is opt-in | The evidence view | `notifications.anomalies` (in-app on; push opt-in) |
| Monthly summary (J8) | Local | 1st of month, 10:00: "August: €212 on the Volvo." Opt-in | Trends | `notifications.monthlySummary` (default off) |
| Sync nudge | Silent APNs | Invisible, throttled server-side (max ~1/15 min per device) | – (background pull) | none – it's invisible |
| Config nudge | Silent APNs (`config: true` hint on the same payload) | Invisible; used to propagate an urgent change such as a kill switch in minutes rather than the normal 6-hour poll | – (background config fetch, `CONFIG.md`) | none – it's invisible |
| Post-outage batch result (S7) | In-app toast, not a notification | "Synced. 2 entries need a look" on next open | Log filtered to flagged | – |
| Shared-vehicle activity (v2) | Silent nudge only | Partner's fill-up just appears via sync; no "X logged a fill-up" alert unless v2 research says otherwise | – | (v2) |

Explicit non-scenarios: no "you haven't logged in a while" re-engagement, no feature announcements, no rating prompts via push, nothing from the LLM/quota system. The notification channel spends trust; only the user's own deadlines may draw on it.

## Multi-device behavior

Local notifications schedule on **every signed-in device** (each device knows the reminders via sync). Acceptable and honest – Apple's own Reminders does the same. The cleanup contract matters more: **any change that resolves a notification's reason cancels it everywhere** – completing/rescheduling a reminder syncs, and each device cancels its pending local notification for it on merge. A user who did the oil change never hears about it again from the iPad.

## Permission & quiet behavior

- System permission is requested **at the first moment it's needed** (creating the first reminder), never at onboarding.
- Permission denied → the one-time card from ERRORS.md ("Reminders can't notify you – they'll only show here"), deep link, no nag loop.
- All content categories live in synced `Preferences` (SCHEMA.md); the system permission itself is per-device.
- Quiet by scheduling, not by feature: everything user-visible fires at humane fixed times (09:00/10:00 local) – there is nothing time-critical in a fuel log, so nothing ever needs to buzz at night.
