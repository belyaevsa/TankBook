# REVIEW-JOURNEYS run, 2026-09-19 - Groups A, B, C, D (the rows since the 2026-09-18 walk)

**Walked by:** the orchestrator · **Tree:** `787cda7a` · **Since:** the 2026-09-18 walk (`dc76405d`); **10 rows shipped** in nine commits - `PJ.301`, `PJ.302`, `PJ.303` (multi-page invoices and the line offers), `RV.115` + `RV.180` (station brands), `PR.20` (APNs registration, Low Data Mode uploads), `RV.122` (reminder chips), `RV.118`, `RV.119`, `RV.120` (the monthly glance's three figures). The re-run shape: each row against the four event shapes, the ticked rows re-checked, Pass 1 and Pass 2 over the new surfaces.

## 1. Re-check of what the previous run left open

| Item | Then | Now |
|---|---|---|
| `Station.brand` has no production writer (2026-09-18 §3, shape 2) | cited, `RV.115` | **closed** - `ImportStationResolver.station(for:)` sets it at minting, `setStationBrand` on the user's pick; `SchemaFieldWriterGuardTests` dropped its exception |
| J4 without a status line (`RV.114`, `RV.179`, `RV.288`-`RV.290`) | open | unchanged; `RV.180` shipped without `RV.179` landing first - the row says why (a name kept verbatim leaves no split to be wrong about) |
| J8b / J13 on `RV.181` | open | unchanged |
| `PJ.300` (a service line's home money) | owner | unchanged |
| `RV.296` (a MPG car prints L-based figures) | owner's priority call | unchanged, and it now also covers `RV.119`'s divider consumption and `RV.120`'s inputs - noted on both rows |

## 2. Ticked rows whose behaviour the code does not have

**None.** Re-checked by grep: `PJ.303` (`startGateway(pages:)`, `pageCapExceeded`, the strip's `serviceEntryLineOfferTake_` ids in production code), `RV.115` (`GET /v1/reference/station-brands` mapped in `Program.cs`, migration 025 present, `StationBrandMatcher` called from the resolver), `PR.20` (`AppDelegate` is the adaptor in `TankbookApp.swift`, `AppLaunchWiring` installs the nudge, `aps-environment` in `project.yml`), `RV.122` (`HomeReminderChips` in `HomeBanners`, `ReminderBanner.swift` gone), `RV.118`/`RV.119`/`RV.120` (the three derivations in `HomeStats`/`LogStream`, rendered from `HomeHeadlineBlock`, `HomeSections+LogStream`, `HomeFillPatternCard`). Every row was mutation-gated at ship and its captures opened the same night.

## 3. The four event shapes over the 10 rows

| Shape | Rows it applies to | Finding |
|---|---|---|
| 1 · a screen or route ships | `RV.115`/`RV.180` (the **station brand picker** - a sheet from Confirm's and Edit entry's station menu and from Station settings), `RV.122` (the strip's two routes), `PJ.303` (the offer strip and the new-line card on ServiceEntry; the inbox card's new labels) | **The picker was a screen `SCREENMAP.md` did not list** - the RV.162 guard protects the index's contents and is blind to what it forgot, which is exactly the check the brief says the walk is. **Fixed in this walk**: the sheet is in the mermaid (two doors) and the inventory, and `ScreenRouteBindings` binds it to `StationBrandPickerSheet(` - the guard now proves its production door. `RV.122`'s edges were added at ship. None of the three is under `#if DEBUG` (grep: only the seeds and the `-screenshotLineOffers` scroll) |
| 2 · a reader of an entity ships | `RV.115` reads `Station.brand` (writers now exist, §1); `PR.20` writes `devices.push_token` on the server, which **nothing reads** - the sender is `PR.37`, filed at ship; `RV.120` reads `Vehicle.tankCapacityL` (Add car writes it; the card refuses an uncorroborated one by design); `RV.118`-`RV.120` read segments and fills (creators exist); `StationBrandRegistry.detectedCountry` is written by the import parse and read by the picker's ordering | One efficiency defect found reading the reader: `StationBrandRegistry.brands` **decoded the bundled pack on every call** before the app's store was installed - an import resolves hundreds of names through it. **Fixed in this walk** (decoded once) |
| 3 · copy naming a destination or outcome ships | "Check the lines" (`PJ.303`'s flag and page-cap note → the lines are on the same form), "All reminders" (`RV.122` → `Route.remindersAll`), "Change brand" / "No brand" / "Use “…”" (`RV.115` → the picker's three rows), "on a 50 L tank" (`RV.120` → the vehicle's capacity, editable in Vehicle detail), "25% lower than July" (`RV.119` → the month before, in the Log) | Every phrase names something that exists. `ERRORS.md`'s new rows carry a `→ Reminders` route and the route guard passes |
| 4 · a row ships PARTIALLY | `PR.20` (device side only - the backend sends nothing) → `PR.37`; `RV.115`'s `detectedCountry` rides `/import/parse` only (the doc names the other three uncacheable responses as "may add later"); `PJ.303` offers lines in `.service` mode only (Tires has no line rows - by design, said in `offerLines`); `RV.122` strips the SELECTED car's reminders (the RV.76 row carries the cross-car count - `ERRORS.md` says "of the selected car") | `PR.37` is the one true remainder and it is filed. The other three are scope decisions written where the code makes them |

## 4. Pass 1 - reachability from a cold launch, no debug flag

- The offers: `applyGatewayAnswer` runs from `gatewayRevision`'s `onChange` on the production sheet; the strip renders from `lineOffers` with no flag. The page-cap note renders from `pageCapExceeded`, set by `startGateway` on the real capture path.
- The brand: matched inside the ONE creation seam every door uses (typed, scanned, imported); the picker opens from a menu item on the station row and a card in the Garage. A guest gets the bundled vocabulary (the refresh needs no session - the endpoint is public).
- The chips: derived on every Home render from the live reminders; a tap is a `NavigationLink` to `reminderDeepLink`.
- The push seam: `AppLaunchWiring.attach` runs from the root's `.task`; registration is gated on a session, not a flag.
- The three glance figures: derived in `HomeStats`/`LogStream` on every render.

## 5. Pass 2 - sequence

| Chain | Status | Evidence |
|---|---|---|
| scan a station → change its brand on Confirm → Save | MET | a not-yet-persisted station changes in memory and `persistScannedStation` carries the pick into the minted row; an existing station is written at once (`ManualFillUpStationRow.setBrand`) |
| change a brand → cancel the Confirm sheet | MET, by design | the brand is a station edit, not part of the entry: it persists like the Garage's own write. The sheet's discard guard covers the entry's typed input only (`SCREENMAP.md` rule) |
| mint a station → a newer pack renames the chain | MET | the resolver matches only at minting; `StationBrandTests` pins a cleared and a renamed brand surviving a newer pack (hard rule 13) |
| sign in → token PUT → sign out → sign in again | MET | `signedOut` forgets the acknowledgement; the pair (token, account) sends again (`PushTokenRegistrationTests`) |
| a chip's reminder completed from its landing | MET | `.done` rows never re-derive; the chip is gone on the next Home render (`ReminderBannerTests`, ported) |
| take a line offer → Save → a late reading arrives | MET | the inbox pairs against the SAVED items, which now carry the taken line; the pairing is by amount/title so the taken line pairs with itself (no offer) |
| a rate-pending fill in the month delta / cost per km / forecast | MET | every one of the three is gated on `.complete` (`MonthGlanceTests`, `FillPatternTests`) |
| the user corrects the tank capacity after a range showed | MET | derived on every render; a capacity the fills refute (>105%) removes the range (`FillPatternTests`) |
| the MPG car through the divider and the pattern card | **GAP, tracked** | `per100` under the car's unit label - `RV.296`, both rows note it |

## 6. Proposed rows

None new. The two things the walk found were fixed in the walk (the unlisted picker screen; the per-call pack decode); the one remainder (`PR.37`) was filed at ship.

## 7. Cited, not re-filed

`PR.37` (the nudge sender) · `RV.296` (units) · `RV.300` (timing-flaky tests) · `RV.297`-`RV.299` · `RV.181` (J8b, J13) · `RV.114`, `RV.179`, `RV.288`-`RV.290` (J4) · `PJ.300` (owner) · `RV.295` (iOS 27 OCR measurement).

## 8. Could not settle

- J8's status line was cleared by `RV.118` (the story changed three times this tranche - `RV.118`, `RV.119`, `RV.120`); its `REVIEW-SCENARIO` is due once the owner ranks nothing else for J8. The walk did not run it: a scenario review is the other brief.
- Whether the Push Notifications capability is enabled on the App ID is not knowable from the tree; `HANDOVER.md` carries the owner step.
