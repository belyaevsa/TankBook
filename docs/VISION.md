# Tankbook – Product Vision

*iOS-first fuel & car-cost tracker · working title · August 2026*

A car cost log where you never fill in a form. Point the camera at the receipt or the pump – the app reads it, converts it, and files it. Fuel, charging, service, and everything your car costs you, in one private on-device history.

## 1 · The gap in the market

The category is crowded but stale. Fuelio, Drivvo, Fuelly, Spritmonitor, and Simply Auto all rely on hand-typed forms, dated UI, and ads. Recurring review complaints: intrusive ads, subscription fatigue, inaccurate consumption math, painful backup/export. Almost none of the consumer apps do receipt scanning – it exists only in fleet products like AUTOsist.

| App | Strength | Receipt OCR | EV support | Multi-currency | Top complaint |
|---|---|---|---|---|---|
| Fuelio | Fuel log, crowd gas prices, CarPlay, widgets | Yes (offline, receipts only) | Yes | Basic | Feature creep into Premium ("no reason to stay") |
| Drivvo | Broad expense + maintenance, EV kWh logs | No | Yes (bolted-on) | Basic | Huge ads / tiny font, export paywalled, wrong economy math |
| Fuelly | Community MPG benchmarks, 29k ratings | Photo attachments only, no OCR | No | No | Upsell nags, data loss after account migration, sporadic updates |
| Spritmonitor | Huge consumption dataset (DE), deepest EV analytics | Yes (invoice scan: date/price/qty) | Yes (AC/DC, partial charges) | Basic | Web-era UX, account-centric, DACH niche |
| CarScope (RU-origin, iOS) | Modern UX, importers from all majors | Photo attach only | No | No | Subscription rug-pull locked users to 1 vehicle |
| AUTOsist | Fleet workflows, receipt scan | Yes | No | No | Fleet pricing, not consumer |

**The opening (revised after reading current App Store listings):** the field is converging on us faster than the blog-level research suggested – Fuelio already ships offline receipt OCR and EV support, Drivvo ships EV kWh logs and importers. Receipt scanning alone is no longer the moat. What remains genuinely unowned: **pump-display and dashboard photo capture** (nobody does it), **the arithmetic cross-check as visible trust**, **true multi-currency with historical rates**, **the household EV-vs-petrol cost comparison**, and **no-account privacy** (every incumbent pushes logins, and Fuelly reviewers report losing years of data to forced account migration). The incumbents' shared weakness is also strategic: all of them are ratcheting features into subscriptions and burning goodwill (top reviews on all three complain about it) – a generous free tier with export always free is a differentiator by itself.

### CIS and Russian markets

The Russian-language segment splits into two camps, neither of which competes with us directly: **payment/station apps** (Яндекс Заправки, ЛУКОЙЛ, Газпромнефть АЗС, Татнефть – pay at the pump, find stations, loyalty perks) and **expense trackers** (Авто Расходы / Car Expenses, Car Expenses Pro, Мой Авто – manual-entry logs, dated UI, same form-filling model as the Western apps).

The standout opportunity: **fiscal receipt QR codes**. Every Russian receipt carries an FNS QR code with the full purchase machine-readable (Kazakhstan's ОФД system is similar); a QR scan yields 100%-accurate data with zero OCR. Only Мой Авто touches QR at all – paywalled behind its top tier, inside an app whose recent reviews call it "completely broken" (hangs, broken sync, dead website). Detailed store-page profiles for all of these are in `COMPETITORS.md`. For CIS users this beats our OCR pipeline entirely – scan the QR, done – and it's nearly free to build. Constraint to plan around: App Store payment restrictions in Russia make subscriptions impractical there; the RuStore/regional strategy is a later decision, but the QR feature also serves the diaspora and travelers on the regular App Store.

## 2 · Vision and principles

> Logging a fill-up should take five seconds and zero typing. Your car's entire financial history lives on your phone, readable by you and no one else.

- **Capture beats forms.** Camera is the primary input; the form is the fallback, not the default.
- **Local-first, private, portable.** OCR and analytics run on-device; the local database is always authoritative and the app is fully usable with no account at all (single device, everything local). Optional sign-in with Apple ID or Google attaches a **neutral identity email** and turns on multi-device sync through our backend (`SYNC.md`) – which is also restore on a new phone or on Android later – plus the cloud-LLM fallback gateway. We store the account identifier, email, and the synced record stream (TLS + encrypted at rest, per the signed-off stance in `SYNC.md`) – no content analytics; images sent to the LLM fallback are processed transiently, never retained. No ads, no server-side analytics, and never a login wall (Fuelly's forced-login migration destroyed user data and trust – see COMPETITORS.md); if our servers are down, everything except LLM fallback and cross-device restore still works.
- **Powertrain-agnostic.** Petrol, diesel, hybrid, EV – one app, one history. EV charging is a first-class citizen, not a retrofit.
- **Borders don't break the log.** Fill up in Poland, pay in złoty, see it in your home currency at that day's rate – both amounts preserved.
- **Own your data.** One-tap CSV/JSON export – always free (Drivvo paywalls even paper reports, and its reviews resent it). Importers for Fuelio, Drivvo, and Spritmonitor formats are table stakes (Drivvo ships them too), but we need them to open the switching path.

## 3 · Do we need an LLM?

Short answer: **not on the primary path, yes as a thin layer**. The extraction problem splits into "read the pixels" (OCR) and "understand the fields" (semantics). Apple's stack now covers both on-device.

Pipeline:

1. **Capture** – VisionKit document camera, or photo of the pump display
2. **OCR** – Vision framework document recognition (on-device, free, offline)
3. **Parse** – deterministic rules: currency, decimals, `liters × price ≈ total` cross-check
4. **Normalize** – Apple Foundation Models (on-device LLM) resolves ambiguity: "DIESEL B7", station name, fuel grade
5. **Fallback** – cloud multimodal LLM (Haiku-class) only if confidence is low – opt-in, Pro feature

**Decision:** Apple-first hybrid. On-device Vision + Foundation Models handle ~90% of receipts at zero marginal cost and full privacy. The cloud LLM fallback handles crumpled thermal paper and glare-heavy pump displays – opt-in, clearly labeled, part of the paid tier so API costs are covered by revenue. The arithmetic cross-check gives a built-in confidence signal that competitors' "inaccurate calculations" complaints show they lack.

## 4 · Feature set

| Feature | Phase | Notes |
|---|---|---|
| Multi-vehicle garage | MVP | Multiple cars per account from day one – vehicle switcher, per-vehicle stats and history, all tied to the one identity/backup. Every competitor gates this behind Pro; CarScope even revoked it retroactively and paid for it in reviews. |
| Fill-up log (manual quick-form) | MVP | Odometer, volume, price, station, fuel type/quality. Partial fills via optional tank-level-after-fillup (% or liters) instead of a bare flag – the My Fuel Manager approach, it keeps consumption computable between partials. Smart defaults per favorite station (station, fuel type, quality pre-filled from last visit). Show "+N km since last" beside the odometer field as a live typo check. |
| Receipt scan | MVP | The hero feature. On-device pipeline above; user confirms pre-filled card. |
| Pump display photo | MVP | For stations without receipts. Reads liters / price / total off the pump. |
| Fiscal QR scan (RU/KZ receipts) | MVP | FNS/ОФД QR codes carry the full purchase machine-readable – 100% accuracy, no OCR needed. Cheap to build, unowned in the CIS market. |
| Multi-currency | MVP | Each vehicle has a **default (home) currency**; any entry can be logged in any currency and stores both the original amount and the conversion into the vehicle's currency at that date's historical rate (ECB + supplementary feed for RUB/CIS currencies). Rates snapshot at entry time – history never shifts. All stats and trends render in the vehicle's currency. |
| Localization: English + Russian | MVP | Full RU + EN from day one – UI, App Store listing, receipt-parser vocabularies (already multilingual in the spike). Architecture rule: every string goes through String Catalogs from the first commit; no hardcoded text, so adding languages later is translation work, not engineering. |
| Trends dashboard | MVP | L/100km (or MPG), cost/km, price-per-liter over time, monthly spend. |
| Import from Fuelio / Drivvo / Fuelly (aCar) / Spritmonitor / CarScope / My Fuel Manager | MVP | CSV/backup importers. Table stakes (Drivvo and CarScope import from everyone), and My Fuel Manager's export doubles as our first real-data test fixture. |
| Service & maintenance records | v1.x | Repairs, parts, tires, insurance, taxes – with receipt scan and photo attachments. |
| Reminders | v1.x | By date or odometer: oil, inspection (TÜV/MOT), insurance, tire swap. |
| EV charging sessions | v1.x | kWh, tariff, home vs public, session screenshots OCR'd from charging apps. |
| Widgets, Shortcuts, Siri | v1.x | "Log fill-up" from lock screen; Shortcut fires when CarPlay disconnects near a gas station. |
| Multi-device sync (optional sign-in, Apple ID / Google) | v1.x | Our backend as the sync hub (`SYNC.md`): sign in on any device, the full garage follows. Strictly optional – no login wall; without an account the app is fully functional on one device. The same identity meters the cloud-LLM fallback and yields backups/restore for free. |
| Family sharing (one car, two drivers) | v2 | Vehicle-scoped sharing over the same sync protocol; entries attributed per member; odometer validation handles out-of-order merges (F9a). |
| Anomaly insights | Later | "Consumption up 12% over 3 months – check tire pressure / air filter." |
| Document wallet | Later | Insurance card, registration, with expiry reminders. |
| Trip cost calculator | Later | "Berlin → Warsaw costs you ~€68 in this car at current prices." |
| Android app | Later | After iOS product-market fit. See platform strategy below. |

## 5 · Core user flows

### Flow A – The 5-second fill-up

1. **Open** – lock-screen widget or app; camera is one tap away
2. **Snap** – receipt or pump display; auto-crop, auto-shutter
3. **Confirm** – pre-filled card: 42.3 L · 1.679 €/L · €71.02 ✓. Odometer is the only manual field (or photo of the dash)
4. **Done** – haptic tick, updated consumption shown immediately: "6.8 L/100km – your best this year"

The confirm screen doubles as the trust-builder: every extracted field shows a confidence tint, and the `liters × price = total` check runs live. Editing a field is one tap. The receipt photo is kept, attached to the entry – useful for expense reports.

### Flow B – Service visit

1. **Scan invoice** – multi-page workshop invoice via document camera
2. **Categorize** – on-device model suggests: "Oil service + brake pads front" → two line items
3. **Remind** – app proposes the next reminder: "Oil change in 15,000 km or 12 months?"

### Flow C – EV charge

1. **Screenshot** – share a charging-app receipt screenshot to the app (share extension)
2. **Extract** – kWh, duration, cost, provider – same OCR pipeline
3. **Compare** – home tariff entries logged by kWh × your electricity price; dashboard shows €/100km vs the household's petrol car

That last comparison – *your EV vs your petrol car, in real money per 100 km* – is a genuinely differentiating insight no mainstream competitor offers, and it matters to exactly the audience (mixed-powertrain households) growing fastest right now.

## 6 · Trends worth tracking

- **Consumption:** full-to-full correctness (partial fills merge into the next full segment – the math Drivvo gets wrong; tank-level entries refine it). The headline average is **time-based, not fill-based**: rolling 90 days of closed segments, because fill cadence varies wildly between users (1–2 full tanks/month vs small top-ups weekly). Floor: fewer than 3 segments in the window auto-extends it backward until 3, with the UI labeling the real span ("last 5 months"). Lifetime average is the secondary stat; anomalies compare the rolling value against the trailing-12-month (seasonally fair) baseline. Per-season and per-fuel-grade splits.
- **Money:** cost per km all-in (fuel + service + insurance), monthly burn, price-per-liter trend per station brand – "Shell costs you 4% more than Orlen for identical consumption."
- **Health signals:** consumption drift as an early-warning proxy; service cost trajectory by age/mileage; resale-relevant, exportable history.
- **EV specifics:** kWh/100km, home vs public charging mix, effective €/kWh, charging-curve cost efficiency by provider.

## 7 · Platform & tech strategy

- **iOS:** SwiftUI; persistence GRDB or SwiftData (open question 1 in `SCHEMA.md` – GRDB recommended); sync client implementing the `SYNC.md` protocol against our backend (`API.md`); VisionKit + Vision for OCR, Foundation Models framework for normalization. Minimum target iOS 18, with the on-device LLM path gated to iOS 26+ devices and a rules-only parser below that.
- **Currency:** rates served by our backend's public `/rates` endpoint (daily job: ECB + a CIS source for RUB/KZT/AMD/GEL/BYN – see `SCHEMA.md` Reference data), cached ~2 years on device with an app-bundle seed pack; rates snapshotted per entry so history never shifts. The vehicle's default currency is the reporting currency for all its stats.
- **Localization:** English and Russian ship in v1. String Catalogs from the first commit, localized number/date formatting via the user's locale (comma decimals in RU), and pseudo-localization checks in CI so untranslated or clipped strings fail before release.
- **Backend (three jobs):** a **C# / ASP.NET Core + PostgreSQL** service providing (1) **multi-device sync** – the account's data as an ordered record stream, one protocol serving iOS now and Android later (full design: `SYNC.md`; this replaces CloudKit as the sync engine – one sync system, not two), (2) **backups/restore** as snapshots of that same stream, and (3) the **LLM gateway** (API keys server-side; per-user quotas; images transient, never retained). Auth via Sign in with Apple or Google token verification; the account email is the neutral recovery identity. Hard rule learned from Мой Авто's dead servers and Fuelly's login migration: the app is **local-first** – no account means a fully working single-device app, and with the backend unreachable everything except sync and LLM fallback still works; the documented export format always remains in the user's own hands.
- **Android later:** keep the domain layer (models, consumption math, parsers) portable – either Kotlin Multiplatform from the start or a cleanly isolated Swift core to re-implement. Don't compromise the iOS experience for sharing; the parser rules and data schema are the truly reusable assets.
- **Monetization:** free tier fully usable – multiple vehicles (e.g. up to 3), on-device OCR, export always free; data hostage-taking and vehicle-count rug-pulls are the competitor sins we won't repeat (CarScope retroactively locked users to 1 vehicle and its reviews still bleed from it). Pro subscription or lifetime: unlimited vehicles/fleet, cloud OCR fallback, family sharing, document wallet, advanced insights.

## 8 · Risks and open questions

- **OCR trust:** if the first three scans misread, users revert to typing forever. Mitigation: confidence gating – never silently accept a low-confidence field; the arithmetic cross-check; ship the pump-photo path only when it clears ~95% on a test set of real photos.
- **Odometer friction:** the one field no receipt contains. Options: dash photo OCR, CarPlay/Bluetooth-disconnect prompts, or accepting one typed number per fill-up. Needs prototyping.
- **Crowd price data:** Fuelio's community prices are a moat we can't replicate at launch – decide whether to license a price API per region or skip prices-nearby entirely in v1 (recommended: skip).
- **Naming:** "Tankbook" is a working title; needs trademark and App Store search check ("fuel log", "car log", "tanken" localization angle for DACH).

---

**Next steps:** validate the OCR pipeline with a spike (50 real receipts + 20 pump photos through Vision framework), sketch the confirm-screen UI, and define the v1 data schema.
