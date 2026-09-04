# RV.6 – INVESTIGATION ONLY: is `GET /v1/account/devices` still polled repeatedly?

You are an **investigator, not a builder**. Produce a diagnosis and evidence. **Do not fix
anything.**

Filed from production: `GET /v1/account/devices` called **four times in 14 seconds** (21:07:23, :28,
:30, :37), then more — *"looks like a screen refetching on every appearance rather than on change.
Cheap per call, but it is the shape that becomes a battery and rate-limit problem, and the per-IP
limits key on it."*

**It may already be fixed.** Several things landed since it was filed, and the product owner's
explicit suspicion is that one of them closed it. **Establishing "already fixed, here is the proof"
is a complete and valuable result** — it is not a failure to find work.

## Rules

Repo: `/Users/sbelyaev/repos/fuel-counter-ios`. Work only inside it.

- **Change no source file.** No fix, no refactor, no "small tidy".
- **Do not run `git add`, `git commit`, `git stash` or `git checkout`.**
- **Do not touch `docs/TASKS.md`.**
- **Never move, rename or delete a file you did not create.** Another agent (RV.49, camera
  orientation) and a second Claude session are working in this checkout right now. If something is
  broken and is not yours, **report it and carry on** — a currently-known example is
  `CorpusScorerFuelKindCurrencyTests`, red from in-flight corpus fixtures.
- You may run read-only commands (`grep`, `git log`, `swift build`) freely. **Do not run the UI
  suite** — another agent holds a simulator.

## What changed since RV.6 was filed — check each, do not assume

- **RV.18** added `OpportunisticSyncPolicy`: a 30 s minimum interval that gates *opportunistic*
  (launch/foreground) sync only. It deliberately does **not** gate `syncNow()`, the retry backoff,
  or the Low Power drain. **Does the devices fetch go through a gated path or an ungated one?**
- **RV.26** wired a refresher into the gateway transport and added a persisted `authExpired` mark.
  A 401 → refresh → retry can *double* a request; check whether a devices call retries.
- **RV.22** added the sync state chip reading `AppSync.surfaceState` on all three tab roots. It
  publishes `fetchedDeviceCount`. **Does rendering the chip trigger a devices fetch, and does it now
  do so on three tab roots instead of one screen?** That would have made this worse, not better.
- **RV.39/40/41** changed `AuthService`, `AuthEndpoints` and added a sign-out path.

## The questions to answer, with evidence

1. **Where is `account/devices` requested from?** List every call site and what triggers it —
   `.task`, `.onAppear`, `onChange`, a timer, a refresh() fan-out. Quote the code.
2. **Is it de-duplicated or cached at all?** Is there an in-flight guard, a minimum interval, a
   stored `fetchedDeviceCount` that is reused, or does every caller hit the network?
3. **Does it still fire on every appearance?** `AccountDevicesView` is a pushed screen; `AppSync`
   is `@Observable` and shared. Does `refresh()` fetch devices, and how many things call `refresh()`?
4. **Could the four-in-14-seconds shape still occur today?** Reason from the trigger paths, and say
   which sequence would produce it. If the shape is now impossible, **name the specific change that
   made it impossible** — that is the "already fixed" proof.
5. **Is there a rate limit that keys on this endpoint**, and how close does the observed pattern come
   to it? (`docs/API.md`, and the per-IP limits in the backend.)

## Where to look

`ios/App/Sources/Settings/AppSync.swift` (`refresh`, `fetchedDeviceCount`),
`ios/App/Sources/Settings/AccountDevicesView.swift`, `ios/App/Sources/Settings/SettingsView.swift`,
`ios/App/Sources/Navigation/SyncStateChip.swift` and `TabRootHeader.swift` (RV.22's new readers),
`ios/Sources/TankbookCore/Auth/`, and `backend/src/Tankbook.Api/Account/` plus `docs/API.md` for the
endpoint and its limits.

`git log --oneline -- <path>` will tell you what moved recently and why.

## What a good answer looks like

**One of these three, stated plainly:**

- **"Still reproduces."** Name the exact trigger sequence that produces repeated calls, quote the
  code, and say what the minimal fix would be — **describe it, do not build it.**
- **"Already fixed by X."** Name the change, quote the code that now prevents it, and say what the
  behaviour is today (e.g. "one fetch per push, reused from `fetchedDeviceCount` thereafter").
- **"Cannot tell from the code."** Say exactly what evidence would settle it — the log line to look
  for, or the instrumentation to add — and stop. **This is an acceptable answer; guessing is not.**

**Do not pad.** If the honest answer is three paragraphs, write three paragraphs.

## Traps, named

- **Do not conclude "fixed" because you could not find a call site.** Search for the path string,
  the typed endpoint, and any wrapper that builds it — the request may be assembled from a constant.
- **Do not conclude "still broken" from the RV.6 log alone.** That log predates four changes; it is
  the symptom that started this, not evidence about today's code.
- **A single `.task` is not automatically safe.** `AppSync` is shared and `@Observable`; a `.task`
  on a view that remounts, or a `refresh()` called from several observers, produces the same shape.
- Remember RV.18's measurement lesson: **the premise that something is timer-driven is usually
  wrong** — look for activity-driven fan-out before assuming a poll.

## Report back

- The call-site inventory with triggers, quoted.
- Your verdict: still reproduces / already fixed by X / cannot tell — with the evidence for it.
- If it still reproduces: the minimal fix **described**, and which test would prove it (the
  assertion should be a **request count**, not "the screen loaded").
- Anything you noticed in passing that is not RV.6 — named separately, not folded in.
- Confirmation you changed no file and ran no UI suite.
