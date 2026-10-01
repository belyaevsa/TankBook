# RV.124 – Seasonal tyre change advisory

The advisory should be a **local notification decided on the device** from a public reference pack. The backend may fetch forecasts and publish regional weather facts and curated legal windows, but it must not select users, inspect their tyre sets, or send a visible push. Ship a small, verified geography first. The data needed to launch does not yet exist: a commercial forecast agreement, a maintained legal table, a region catalogue, and evidence that the proposed temperature rule produces useful prompts.

## 1. Forecast data

| Provider | Fit for this design | Commercial terms and scale |
|---|---|---|
| **Open-Meteo – recommended** | Its forecast API exposes `temperature_2m_mean` by local day and supports up to **16 forecast days**. It combines models with global coverage, so it is the best candidate for RU, EU, and the broader receipt corpus. A 10–14 day sequence of daily means is available, though forecast quality that far out needs measurement by region. | The free endpoint excludes commercial use. A paid subscription supplies the commercial licence and server-side key. Standard includes **1 million charged calls/month**; calls covering over two weeks or many variables can cost more than one unit. Attribution is required. At an illustrative 100 weather regions fetched four times daily, the load is about **12,000 location forecasts/month**, well under that allowance. The actual monthly price was not verifiable from the published page. [Forecast API](https://open-meteo.com/en/docs), [pricing and licence](https://open-meteo.com/en/pricing). |
| **MET Norway – fallback for shorter-horizon weather** | Locationforecast covers the world but only **up to nine days**. It cannot provide the requested 10–14 day sequence. It can support the same rule with a shorter look-ahead after the rule is revalidated. | Open data under NLOD 2.0/CC BY 4.0, with attribution and no API fee found. Identify the backend in `User-Agent`, honour cache headers, and arrange special agreement above **20 requests/second**. There is no SLA. Its terms favour a caching backend over direct mobile requests. [Forecast horizon](https://docs.api.met.no/doc/locationforecast/HowTO.html), [terms](https://docs.api.met.no/doc/TermsOfService.html), [licence](https://docs.api.met.no/doc/License.html). |
| **Yandex Weather – procurement alternative, especially for RU** | Its documented commercial forecast is **10 days**, so it cannot supply day 11–14. Its own description emphasizes forecasting for Russian coordinates; coverage and comparable quality across every intended country need confirmation. | Commercial API pricing shown includes a **₽30,000/month** legacy/basic offer with 1.5 million requests/month, while the current plan table presents different entry plans. The contract, redistribution rights for a public derived pack, and applicable price require a sales quote. [API pricing](https://yandex.com/dev/weather/doc/en/concepts/pricing), [API overview](https://yandex.com/dev/weather). |

**Before procurement:** obtain written permission to publish *derived regional signals* in a public, cached pack, confirm attribution placement, price, retention limits, and coverage for the chosen region list. The server stores the provider key, as [SECURITY.md](/Users/sbelyaev/repos/fuel-counter-ios/docs/SECURITY.md) requires.

## 2. The rule

**Treat +8 °C as a candidate advisory threshold, not a legal or universal safety boundary.** Estonia’s transport authority recommends changing to winter tyres when the **daily average falls below +7 °C**. That supports a daily-mean concept, but neither that source nor the provider documentation establishes that a 10–14 day average crossing +8 °C predicts the right change date. Tyre and road conditions still matter. [Estonian Transport Administration](https://transpordiamet.ee/mootorsoidukijuht).

Proposed rule for a measured pilot:

- Use the **forecast daily mean of 2 m air temperature**, in the region’s local time zone. Do not substitute the daily high, low, or a mean across all 14 days.
- On each daily pack calculation, inspect days 2–10. A **winterward** candidate is the first run of **three consecutive daily means at or below +7 °C** after a preceding seven-day baseline above +9 °C. A **summerward** candidate is three consecutive daily means at or above +9 °C after a preceding seven-day baseline below +7 °C. The +7/+9 gap is proposed hysteresis around the owner’s approximate +8 °C.
- Require the candidate to persist in **two successive daily forecast runs**, with the run starting within the next seven days. Carry only a signal and expected window in the pack. This avoids treating a single distant forecast as settled.
- Gate winterward delivery to **1 September–31 December** and summerward delivery to **1 March–30 June** in the northern pilot regions. A warm January week cannot create a summerward notification. Region-specific season gates will be needed before wider coverage.
- Fire **once per vehicle per direction per season year**, with a hard cap of **two advisory notifications per vehicle per rolling 12 months** across forecast and statute. A statutory deadline takes precedence when both qualify; it does not create a second banner.
- A forecast alone cannot prove ice, road grip, tyre suitability, or compliance. Copy says “consider” or “check”, and shows the forecast basis when opened.

These numerical choices are **design hypotheses**. Replay historical forecasts against observed weather and, in a small beta, compare prompts with drivers’ actual swap timing before enabling notifications broadly.

## 3. Statutory windows

The table must distinguish an **unconditional date mandate** from a **weather-conditional requirement inside a date range**, and from limits on studded tyres. The dates below concern ordinary passenger cars; vehicle class, tyre marking, and regional exceptions belong in the verified source record.

| Country | Initial classification for the legal table |
|---|---|
| **RU** | Winter tyres required in **December–February** for M1/N1 under the published Russian vehicle rules. Regional extensions need checking before a region-specific claim. [Russian government regulation](https://government.ru/docs/all/147878/). |
| **EE** | Winter tyres required **1 December–1 March**. The authority also gives a daily-mean recommendation below +7 °C. [Transport Administration](https://transpordiamet.ee/mootorsoidukijuht). |
| **LV** | Winter tyres required **1 December–1 March** for vehicles up to 3.5 t. Recheck the current regulation and tyre-marking details before publication. [CSDD](https://www.csdd.lv/en/jaunumi/ziemas-riepas-%E2%80%93-obligatas-no-1-decembra). |
| **LT** | Winter-suitable tyres required **10 November–31 March** for the stated light-vehicle classes. Qualifying all-season markings matter. [Lithuanian Police](https://policija.lrv.lt/lt/veiklos-sritys/eismo-saugumas-1/naudingi-patarimai/). |
| **KZ** | Winter tyres required during **December–February**, according to the government’s explanation of the technical regulation. Confirm vehicle classes and current regional variation. [Kazakhstan government](https://www.gov.kz/memleket/entities/mvd-vko/press/news/details/875341?lang=ru). |
| **FI** | **Conditional:** 1 November–31 March **if weather or road conditions require** winter tyres. No unconditional “by 1 November” banner. [Traficom](https://www.traficom.fi/fi/autoilijat/vinkkeja-liikenteeseen/auton-kesa-ja-talvirenkaat). |
| **SE** | **Conditional:** 1 December–31 March **when winter road conditions exist**. [Swedish Transport Agency](https://www.transportstyrelsen.se/en/road/vehicles/winter-tyres/). |
| **NO** | Sufficient grip is required year-round; winter tread-depth and studded-tyre periods have dates and northern regional differences. Do not turn these into a nationwide tyre-change deadline. [Norwegian Public Roads Administration](https://www.vegvesen.no/en/vehicles/own-and-maintain/tyre-requirements/). |
| **DE** | **Situational** winter-tyre duty under winter road conditions, without a national change-by date. Verify against the current regulation before shipping copy. [ADAC explanation](https://www.adac.de/rund-ums-fahrzeug/ausstattung-technik-zubehoer/reifen/sicherheit/winterreifenpflicht-deutschland/). |
| **AT** | **Conditional:** 1 November–15 April, when winter road conditions exist and the vehicle is used. [Austrian government](https://www.oesterreich.gv.at/en/themen/mobilitaet/kfz/10/2/Seite.063100). |
| **BY** | **Unverified here.** Do not publish a dated Belarusian legal notification until a current primary legal source, exceptions, and effective dates are checked. |

Use a **versioned, signed-off data file** as the source for the published legal rows. Each row needs `country`, optional jurisdiction, vehicle class, obligation kind, start and end dates, qualifying tyre criteria or exception code, effective dates, source URL, source checked date, reviewer, and status (`verified`, `reviewDue`, `withdrawn`). A dated obligation is publishable only while verified. A data correction creates a new pack version and ETag, without an app or backend deploy. Review before each autumn and spring season, on a legal change, and after a source reaches its review date.

## 4. Region granularity and location

**Country is adequate for a nationwide statute and too coarse for weather.** Use a curated set of weather regions keyed by a stable opaque ID such as `EE-TALLINN-01`, each mapped server-side to a representative forecast coordinate and time zone. Publish the **region label and a coarse polygon or grid index** so the device can match locally. Avoid exposing a per-user query such as `?lat=…` or `?country=…`.

The device should let the user choose and edit the advisory region per car. It may *suggest* a country from the existing RV.115 chain – receipt in hand, own history, device region, then `detectedCountry` – but none of those proves where a car is kept. Receipt station coordinates or history can suggest a city **on-device only**, after the user sees and confirms it. An imported old receipt, border purchase, or trip must not silently relocate the car. Precise location permission is unnecessary. A missing or ambiguous region means no forecast notification.

The pack is small if it carries **signals and legal rows**, rather than raw hourly forecasts: as a planning estimate, 300 regions × roughly 200–400 bytes of compact signal data is **60–120 KB before compression**, plus boundaries and law rows. The actual boundary representation and compressed size need measurement; target a few hundred KB, with a documented maximum and an offline cached copy.

**Privacy qualification:** the advisory endpoint receives no account, region parameter, tyre fields, or user coordinates. The repository already permits synced station coordinates in other workflows, so the broader statement “the server never learns any user location” would be inaccurate as a description of the existing product. [SECURITY.md](/Users/sbelyaev/repos/fuel-counter-ios/docs/SECURITY.md) records that existing exception. RV.124 must add no new disclosure.

## 5. Architecture

Add **`GET /v1/reference/seasonal-advisories`**, public and unauthenticated, with no user-specific query parameters. It returns a versioned pack, `ETag`, `Cache-Control`, generation time, expiry time, region catalogue version, per-region forecast signals, and sourced legal rows. This follows the [fuel-price-bands contract](/Users/sbelyaev/repos/fuel-counter-ios/docs/API.md) and is an additive endpoint under hard rule 16.

A backend job fetches the chosen provider at region coordinates **twice daily, staggered**, computes signals, validates completeness and age, and atomically publishes a new pack only when valid. Store the last good pack for serving within its stated validity. CDN caching can be about **six hours**; the device checks on foreground and an opportunistic background refresh, using `If-None-Match`. iOS background execution is not guaranteed, so copy and scheduling cannot promise a specific minute of warning. Provider failure, expired forecast data, malformed rows, or unknown region all produce **no new forecast notification**. An older app ignores the new endpoint entirely and keeps syncing.

On-device planning uses a **separate advisory notification type and stable identifier**, while reusing the existing coordinator’s authorization, scheduling, cancellation, and routing seams. It must cancel a pending request when the region, settings, fitted set, legal row, or pack validity changes. It must not reuse Reminder status: this is a suggestion, whereas a Reminder is a user-owned scheduled task. A missing network can still allow a previously cached, still-valid legal deadline; stale forecast signals fall silent. The ordinary tyre log and user-created reminders remain usable offline.

## 6. The tyres

For a useful, specific prompt, add **optional `TireSet.season`** with known values `summer`, `winter`, `allSeason`, and an unset state. **Do not store `currentlyFitted` on TireSet.** The fitted set is already derivable from the latest live mounting `ServiceRecord.tireSetId`; a second mutable flag would disagree with swap history. If no reliable latest mount exists, treat fitted status as unknown and use generic copy.

The new field is optional in the sync payload and registry. Hard rule 16’s verdict is **additive**, with `schemaVersion` unchanged, provided build 1368’s unknown-field round trip is checked again. Do **not** add a new raw-value case to an existing shipped enum: [API.md’s P1.14 finding](/Users/sbelyaev/repos/fuel-counter-ios/docs/API.md) shows that an unknown raw value can break that build’s decode and stall sync. The current TireSet has six optional tyre properties added since RV.124 was written, but still no season; see [Entities.swift](/Users/sbelyaev/repos/fuel-counter-ios/ios/Sources/TankbookCore/Domain/Entities.swift:371).

A tap opens the car’s tyre sets and recent swap history with three clear choices:

- **Swapped** – choose or create the set mounted, confirm date and odometer, then save the normal tyre-swap ServiceRecord. Do not infer which set went on.
- **Not yet** – dismiss this advisory for this direction and season, without creating a Reminder or a repeat notification. Offer the existing user-created reminder path if they want a date.
- **I use all-season** – let the user mark the relevant set `allSeason` and, if appropriate, record it as mounted. This is the user’s statement, not a claim that every all-season tyre meets local law. A legal note can still ask the user to check its marking.

If the fitted set is unknown, generic copy asks the driver to **check the tyres**, never asserts that summer tyres are fitted.

## 7. The notification

Schedule at **10:00 local time**, no earlier than the next day after the qualifying signal. One per direction and season, with the two-per-year cap above. Make **Seasonal tyre advice** a separate Settings switch, default **off for the first pilot**, and ask system notification permission only when the user turns it on. Toggling off cancels pending advisory requests. A tap opens the relevant car’s tyre screen with the reason, source date, and actions. A stale tap opens that screen without a dead end.

| Reason | English | Russian |
|---|---|---|
| Forecast, winterward | “Colder days are forecast near Tallinn – check whether it’s time for winter tyres.” | “В районе Таллинна ожидается похолодание – проверьте, пора ли перейти на зимние шины.” |
| Forecast, summerward | “Warmer days are forecast near Tallinn – check whether it’s time for summer tyres.” | “В районе Таллинна ожидается потепление – проверьте, пора ли перейти на летние шины.” |
| Verified, unconditional legal deadline | “In Estonia, winter tyres are required from 1 December – check your car before then.” | “В Эстонии зимние шины обязательны с 1 декабря – проверьте автомобиль заранее.” |

The legal sentence is available only for a **verified unconditional** row and suitable vehicle class. For conditional laws, say “winter tyres may be required in winter road conditions” in the detail view, without a false change-by deadline. The region and country in these examples are substituted only after on-device confirmation.

## 8. Measurement

First measure the **weather rule offline**: replay archived forecast runs, record candidate changes and reversals, compare predicted runs with observed daily means, and manually review apparent false prompts across representative mild, maritime, continental, and northern regions. The goal is to set the threshold and persistence rule from evidence.

For a consented pilot, log **shape only** under hard rule 12: pack fetch outcome and age bucket, number of regions/rows, eligibility decision code, scheduling/cancellation/delivery counts, tap, choice (`swapped`, `notYet`, `allSeason`), opt-out, and time-to-action bucket. Do not log coordinates, region IDs, tyre names, dates of a person’s swap, or record payloads. Aggregate locally where possible; server job metrics concern provider success, pack age, size, and request count, never users.

Proposed pilot gates, to agree before launch: **zero duplicate banners** in replay tests; **zero legal claims from unverified or conditional rows**; at least **80% of forecast prompts still supported by the next two forecast runs**; fewer than **10% “not relevant” responses** in pilot feedback; and no sustained rise in notification opt-outs. “Swapped” is useful engagement evidence, not proof of safety or legal compliance.

## 9. Phasing

**Phase 0 – Obtain evidence and data before a user-visible build.**

| Proposed task row | Checks |
|---|---|
| **RV.124a [v1.1] – Provider and geography contract.** Obtain commercial redistribution terms, price, a fixed pilot region list, and real forecast samples. | L2: licence and attribution recorded; 14 local-day daily means verified for pilot coordinates; measured call budget and compressed pack size; missing model coverage recorded. |
| **RV.124b [v1.1] – Legal source table.** Curate the pilot countries with source, reviewer, effective and review dates. | L1: unconditional, conditional, expired, withdrawn, and regional-exception fixtures produce the correct publish/suppress decision; each dated claim has a current primary source. |
| **RV.124c [v1.1] – Rule calibration.** Replay archived forecasts and observed temperatures. | L5: named regions and seasons, candidate count, reversals, lead time, and manually reviewed false alarms reported; owner approves the final threshold before notification copy is enabled. |

**Phase 1 – Smallest useful release:** verified **EE, LV, and LT legal windows**, plus forecast advice only for a curated set of pilot weather regions whose forecasts and boundaries passed Phase 0. Region is user-confirmed; the feature is opt-in. This ships the intended combination where the inputs are trustworthy, and is silent elsewhere.

| Proposed task row | Checks |
|---|---|
| **RV.124d [v1.1] – Public pack and publisher.** Add the new endpoint and scheduled fetch/publish job. | L2: public 200/304, stable ETag, no account or region query, atomic last-good publication, stale forecast excluded, key absent from app and response. |
| **RV.124e [v1.1] – Local region, tyre context, and planner.** Add editable per-car region choice, optional set season, and local decisions. | L1: both directions, January warm spell, no match, unknown fitted set, all-season choice, statute precedence, two-per-year cap, old-client sync round trip. Named mutation: change the three-day persistence gate to one day – its January and transient-week fixtures must turn red, then green when restored. |
| **RV.124f [v1.1] – Local notice and actions.** Add Settings control, EN/RU copy, tap destination, swap entry path. | L4: opt-in and opt-out cancel, 10:00 fire, forecast and legal copy differ, tap opens the car, stale tap remains useful; EN/RU UI and notification screenshots. |

**Phase 2 – Broader coverage.** Add countries and regions only as sources and forecast performance clear the same checks; support conditional-law detail without deadline copy; compare provider fallback behaviour; revisit whether opt-in should become default-on from pilot evidence.

## 10. Open questions for the owner

1. **Pilot scope:** approve **EE/LV/LT with a small set of confirmed weather regions**, adding RU and KZ after legal and forecast review. This keeps the first legal claims auditable.
2. **Notification default:** approve **opt-in for the pilot**, then decide default from relevance and opt-out results. The existing notification channel is deliberately quiet.
3. **Threshold:** approve **+7/+9 °C daily-mean hysteresis as a test hypothesis**, with a measured calibration gate before release. The cited Estonian guidance supports +7 °C daily average; it does not validate an exact +8 °C, 10–14 day algorithm.
4. **Commercial purchase:** authorize procurement only after Open-Meteo confirms public redistribution of derived signals and provides a price for the measured region budget. MET Norway is the technical fallback with a shorter horizon.

## Facts not verified

- Open-Meteo’s exact payable monthly amount, contract-specific redistribution permission for this public pack, and 10–14 day forecast skill in each intended region.
- Current Yandex plan eligibility, cross-border coverage and redistribution terms; its published pricing page contains differing plan generations.
- A current primary Belarusian legal source and the full set of regional, vehicle-class, marking, and exception details for every listed country.
- The actual number of useful weather regions, boundary dataset licence, compressed pack size, and whether receipt history yields a reliable *home* region.
- A scientific or regulator-backed basis for this exact three-day, two-run hysteresis rule. It requires the Phase 0 replay and pilot before it can be treated as a product fact.

This was a **read-only design review**. No repository files were changed, and no builds or tests were run.