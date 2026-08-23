# Competitor Profiles

*Store-page research, August 2026. Sources: App Store and Google Play listings, review excerpts. Companion to `VISION.md`.*

## Global apps

### Fuelio
- **iOS:** 4.5★ / 142 ratings, v2.7.4, updated days ago. **Play:** 4.2★ / 135K reviews, 5M+ installs, actively updated.
- Features: fuel log, crowd gas prices, CarPlay + nearby stations, widgets, expenses, reminders, multiple fuel types incl. electric and bi-fuel, CSV import/export, iCloud backup, **offline receipt scanning** ("improved receipt recognition algorithms" in recent release notes).
- Pricing: free core + Premium $4.99/mo or $17.99/yr.
- Complaints: feature creep into Premium – "with every remotely interesting feature behind a pro plan now, I no longer have any reason" (user moved to Google Sheets).
- Takeaway: our closest feature competitor on iOS and moving in our direction. Weak spots: small iOS review base (Android-first heritage), no pump-photo capture, no multi-currency story, subscription resentment.

### Drivvo
- **iOS:** 4.7★ / 952 ratings, v10 (fresh). **Play:** 4.4★ / 114K reviews.
- Features: refueling, maintenance, expenses, income, routes, reminders; many vehicle types; checklists with photos; fleet mode with driver profiles; EV/hybrid charging with kWh and mi/kWh; importers from aCar, Fuelio, Fuel Manager; cloud sync (Pro).
- Pricing: free with ads; personal subs ~$0.99–$49.90; fleet $29.99–$119.99/mo.
- Complaints: "the font is TINY and the ads are HUGE"; export paywalled ("can't download a paper version without paying"); no custom service types; historically wrong economy math.
- Takeaway: broadest feature set, worst-monetized experience. No OCR of any kind.

### Fuelly
- **iOS:** 4.7★ / 29K ratings – the biggest US review base, but v3.3.7 from June 2024; updates sporadic. Android counterpart is aCar.
- Features: MPG tracking, community benchmarks via Fuelly.com, service logs, reminders, photo/PDF attachments (premium), Excel reports.
- Pricing: $0.99/mo or $7.99/yr (ad removal + attachments).
- Complaints: startup upsell nags; **users lost years of data in a forced account-login migration**.
- Takeaway: a large, under-served install base of exactly our target users; their data-loss trauma is our local-first, no-login-wall pitch.

### Spritmonitor
- **iOS:** 4.7★ / 40 US ratings (large German community, small US footprint), v26.08.1, actively updated (iOS 18, iPad multitasking).
- Features: fuel/costs/mileage across diesel, petrol, LPG, electric; **invoice scanning that auto-detects date, price, quantity**; **deep EV support** – AC/DC charging analysis, partial charges, even negative electricity prices; peer-comparison community database; PDF/image attachments; offline + sync.
- Pricing: free + small IAPs ($0.99–$8.49).
- Takeaway: the most technically serious competitor on both OCR and EV – but web-era UX, community-account-centric, DACH-focused. Validates that our feature bets are real user needs.

### Simply Auto
- **iOS:** 4.1★ / ~820 ratings, updates lag Android. **Play:** 4.4★ / 24.2K reviews, updated this month.
- Features: fuel + maintenance + expenses, GPS/Bluetooth auto trip logging, business-vs-personal mileage for tax deduction, cloud backup, aCar import.
- Pricing: free / Gold $5.99 / Platinum $9.99/yr.
- Takeaway: differentiates on business mileage tax logging (US-centric) – a lane we're not taking; iOS app is the neglected sibling.

## CIS / Russian-language apps

Two camps: payment/station apps (Яндекс Заправки, ЛУКОЙЛ, Газпромнефть АЗС, Татнефть – pay at pump, loyalty; no ownership-cost tracking) and the trackers below.

### Авто Расходы / Car Expenses (kb2soft)
- **Play only** – no iOS version found. 4.3★ / 9.4K reviews, updated Sep 2025. Pro variant: $6.99 one-time, 4.5★ / 1.2K.
- Features: fuel (incl. petrol+gas dual fuel), parts/consumables lifetime tracking, service, insurance, parking, reminders, charts.
- Complaints: unclear help/docs, broken camera-photo upload, awkward recurring expenses, cluttered reminder fields, manual-only entry.
- Takeaway: solid Android-only manual tracker; its user base has no iOS home – that's addressable audience for us.

### Мой Авто (com.moiavto)
- **iOS (RU storefront):** 4.2★ / 3.2K ratings, v5.7.8 (Apr 2025 – release note: "Synchronization error fixed").
- Features: multi-vehicle, dual-fuel (gas + petrol), cost/km, consumables/parts resource tracking, tire sets with mileage, document storage, reminders (service, OSAGO renewal), multi-device sync via MoiAvto.club web account; **fiscal receipt QR scanner – still in beta, auto-creates expense entries**; premium tier adds traffic-fine checking and income/profitability; ecosystem plays: tow-truck calling (CarTaxi.io), OSAGO/CASCO insurance purchase.
- Pricing: PRO 299–499 ₽/yr or 1,190 ₽ lifetime; PREMIUM 99 ₽/mo / 999 ₽/yr; BUSINESS 299–599 ₽/mo.
- Complaints (recent): "app hangs on iPhone and doesn't respond", "servers disabled; app freezes at login" – the backend appears to be dying, and the sync-fix release note confirms chronic sync trouble. Praise, notably: "simple logic, no unnecessary functions."
- Takeaway: the one competitor that validated fiscal-QR demand – but shipped it as a paywalled beta on a server-dependent architecture that is now failing. Its RU-specific service hooks (fines, OSAGO, tow truck) show what local users expect; its collapse shows why our log must never depend on our servers.

### CarScope
- **iOS:** 4.5★ / 623 US ratings (4.4★ / 5.1K in GB listing), but **2.5★ / 6 in Finland** – small storefronts expose the cracks. v2.7.63, iOS 26 supported. RU-origin (carscope.io), 15 languages (incl. Russian, Ukrainian), web app companion.
- Features: fuel/MPG in all unit systems, expenses incl. fines and taxes, income tracking, multi-vehicle with sharing, auto trip logging, receipt *photo attachment* (no OCR), **CSV importers from Fuelio, Fuelly, Drivvo, and Spritmonitor**, cloud sync.
- Pricing: Pro $0.99/mo or $6.49/yr in the US but **€2.49/mo or €18.99/yr in the EU** (~3× regional markup); assorted IAPs to $47.99.
- Complaints: subscription rug-pull – existing users suddenly "locked to only 1 vehicle"; EU review reports **data loss** – "conflict between local and account data. Then it crashed."
- Takeaway: the most modern CIS-origin competitor and the closest UX benchmark, but fragile where it counts – sync integrity and pricing trust. No OCR, no fiscal QR, and despite Nordic distribution, no EV support at all – a gap exactly where EV penetration is highest.

### My Fuel Manager (from user screenshots, Aug 2026)
- The reference tracker we have real screenshots of (and live user data in). Dark theme, red chrome, condensed uppercase numerals – coincidentally close to our design direction, executed without hierarchy (red is navbar paint, not meaning; "last" and lifetime Σ mixed in one tile; N/A tiles are dead ends).
- Home: multi-vehicle photo carousel; tiles for last fill-up / last cost / last trip with lifetime totals; average price + consumption with trend arrows. Tabs: Home, Fuel, Finance, Trips, Stats.
- Fill-up form (11 manual fields): date, total, per-entry currency, volume, derived price/unit, odometer, **"Runned" (distance since last fill)**, fuel type, fuel **quality**, **tank status after fill-up (% + filled/free liters)**, station, note.
- Settings: units, per-entry currency with system default, auto sync, custom categories, **"My Gas Stations" favorites**.
- Takeaway: the best manual-entry form in the set – tank-level % is the mature partial-fill answer, "Runned" is an instant odometer sanity check, favorite stations enable smart defaults. And still: eleven fields typed at a pump is the friction our capture flow exists to delete.

## What the sweep changes for us

1. **OCR is contested, not open.** Fuelio (receipts, offline) and Spritmonitor (invoices) both scan already. Our capture edge must be the *whole* system: pump-display and dashboard photos, fiscal QR (RU/KZ), the visible arithmetic cross-check, and best-in-class confirm UX – not "we have scanning".
2. **Fiscal QR is still unowned as a free feature.** Only Мой Авто touches QR at all, and it paywalls it inside a decaying app.
3. **Every incumbent has burned pricing goodwill** (Fuelio's Premium creep, Drivvo's export paywall, Fuelly's nags, CarScope's vehicle lock). "Free tier that stays free + export always free" is a real, marketable differentiator.
4. **No competitor owns the mixed-household EV-vs-petrol comparison.** Spritmonitor has the deepest EV data but no household framing.
5. **Migration is expected.** Drivvo and CarScope both ship importers from everyone; we need parity (Fuelio, Drivvo, Fuelly/aCar, Spritmonitor, CarScope, My Fuel Manager formats) at launch. My Fuel Manager has confirmed export/import, and a real export from it is our first import test fixture and consumption-math dataset.
