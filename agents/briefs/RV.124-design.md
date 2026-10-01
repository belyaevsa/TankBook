# RV.124 design - the seasonal tyre-change advisory (a design conversation, no code)

Journey: J7b (tires - the seasonal advisory). **Product owner, 2026-10-02:** this needs design before
anyone builds it, and **we do not have the data yet** - no forecast source, no statutory-window
table, no region model. Your job is to design it and say plainly what has to be obtained, decided or
measured first. You write **no code and edit no file in the repo**; your deliverable is your final
message (it is saved to `/tmp/agentlogs/RV.124-design.last.md`).

## Read first

- `docs/TASKS.md` -> the RV.124 row (search `RV.124`) - the owner's request and the constraints the
  backlog already wrote down, including **why the obvious shape is forbidden**.
- `CLAUDE.md` hard rules 1, 7, 9, 12, 13, 16.
- `docs/NOTIFICATIONS.md` (no user-visible remote push, ever), `docs/API.md` -> reference data
  (`/reference/fuel-price-bands` and the station-brands contract are the model), `docs/SECURITY.md`
  (keys stay server-side), `docs/CONFIG.md` (remote config, experiments), `docs/SCHEMA.md` ->
  TireSet and Reminder, `docs/JOURNEYS.md` J7b, `docs/VISION.md` positioning, `docs/COMPETITORS.md`.
- The code as it is: `ios/Sources/TankbookCore/Domain/Entities.swift` (TireSet - it has gained
  fields since the row was written), the reminder + local-notification path
  (`ReminderNotificationCoordinator`), how the country is derived today (RV.115's chain), and the
  backend's reference-data endpoints and any scheduled jobs.

## Questions the design must answer

1. **Forecast data.** Which provider(s) - e.g. Open-Meteo, MET Norway, Yandex Weather, others you
   find - with licence/terms for commercial use, cost at our scale, coverage of RU/EU/the corpus
   countries, rate limits, and whether a 10-14 day mean temperature is actually available. Recommend
   one and a fallback. Note anything you could not verify.
2. **The rule.** Is "+8 °C mean crossing" the right trigger? Define it precisely: which mean (daily
   mean, max, min), over how many days, hysteresis, both directions, once per season per direction,
   and what suppresses a false alarm (a warm week in January). Cite sources for the rule if you can.
3. **Statutory windows.** Which countries mandate winter tyres by date (Russia, Estonia, Finland,
   Latvia, Lithuania, Sweden, Norway, Belarus, Kazakhstan, ...) versus situational laws (Germany,
   Austria). Propose the table's shape and how it is maintained (a data file, not a deploy - hard
   rule 9's "schema evolution is a data change" spirit). Mark what you are unsure of.
4. **Region granularity and location.** Country only, or a city/grid cell? How does the device know
   its region without asking for precise location (receipt station, odometer history, device
   region, coarse location)? Privacy: the server must never learn where a user is or what tyres they
   own. How big is the pack if it carries per-region rows, and how is "region" keyed?
5. **Architecture.** The inverted shape the row describes - a backend job polls the provider and
   publishes a public, ETag'd reference pack; the device matches its region and schedules a LOCAL
   notification. Confirm or improve it: job schedule, storage, endpoint shape (rule 16: additive,
   new endpoint), cache lifetime, what an older app build does with it, offline behaviour (degrade
   to silence, rule 1).
6. **The tyres.** Does the advisory need `TireSet.season` and "currently fitted"? If yes, the
   schema/payload change and its rule-16 verdict (an old client must keep syncing - note P1.14's
   lesson: a new raw-value enum value breaks build 1368, an optional field does not). If no, what
   the generic message says. How the user answers ("Swapped" / "Not yet" / "I use all-season") and
   how that feeds the swap history.
7. **The notification.** Copy (EN + RU, en-dashes only), when it fires (hour, not at night), how
   often (at most twice a year - RV.121's lesson), opt-out in Settings, what tapping it opens, and
   how it differs for a statutory deadline ("by 1 December") versus a forecast crossing.
8. **Measurement.** How do we know it works and is not noise - what shape-only events (hard rule
   12) to log, and what success looks like.
9. **Phasing.** The smallest first version worth shipping, then what follows. For each phase: the
   tasks (rows) it implies with their checks, in the style of `docs/TASKS.md`.
10. **Open questions for the owner** - only the decisions that are genuinely theirs, each with your
    recommendation.

## Fences

Read-only: do not edit, create, move or delete any file in the repo, do not run builds or tests,
git is read-only. Web lookups are fine; cite URLs for facts about providers, laws and the rule.
En-dashes only in prose, never em-dashes.

## Report back

One structured design document as your final message: the answers to 1-10 under those headings, a
one-paragraph summary at the top, and a list of facts you could not verify.
