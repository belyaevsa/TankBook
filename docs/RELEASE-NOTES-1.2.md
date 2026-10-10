# Tankbook 1.2 – changes since 1.1

Range: `v1.1..v1.2` (builds 1837 -> 1877). RV.331-333 and RV.335 landed after the `v1.1`
tag but shipped in 1.1 (`docs/RELEASE-NOTES-1.1.md`), so they are not repeated here.

## App Store – What's New (EN)

• AdBlue tracking. Log AdBlue top-ups separately – they no longer distort your fuel consumption. Scan a receipt and the AdBlue line is filled in for you.
• Add a service or an expense straight from the home screen, just as quickly as a fill-up.
• One receipt, two entries: fuel and a car wash on the same receipt can be saved as separate entries from one photo.
• Easier scanning: a flashlight for dark gas stations, a hint when the receipt is too small in the frame, and an optional automatic shot.
• Pump displays and service invoices are read more accurately.
• New here? Try scanning a sample receipt before your own.

## App Store – What's New (RU)

• Учёт AdBlue. Доливки AdBlue записываются отдельно и больше не искажают расход топлива. Если AdBlue есть в чеке, приложение заполнит его само.
• Сервис и затраты добавляются прямо с главного экрана – так же быстро, как заправка.
• Один чек – две записи: топливо и мойку из одного чека можно сохранить отдельно, не переснимая.
• Сканировать проще: фонарик для тёмной заправки, подсказка, если чек слишком мелко в кадре, и автоматический снимок по желанию.
• Табло колонки и счета из сервиса распознаются точнее.
• Впервые в приложении? Попробуйте отсканировать пример чека.

## App Store – Promotional text (170 characters max)

EN (170):
Fuel, AdBlue, service and every other car expense in one log – offline, with no account or subscription. Scan the receipt or type it, and check the figures before saving.

RU (169):
Топливо, AdBlue, сервис и все затраты на машину в одном журнале – офлайн, без аккаунта и подписки. Сканируйте чек или введите вручную, проверьте цифры перед сохранением.

## Detail, with task ids

### New

- AdBlue is its own entry: never in fuel consumption, its own rate and last top-up on the Home card and in Trends; the diesel form has an AdBlue chip. (P1.14)
- AdBlue on a receipt: an AdBlue-only scan opens on the AdBlue chip; a fuel + AdBlue receipt offers the AdBlue line as a top-up. (P1.15)
- Home's typed door is three equal chips – Fill-up, Service, Expense. With the camera denied, the capture screen keeps its mode row and form. (PJ.507, PJ.508)
- "No receipt to hand? Try a sample" on the first-entry card: a bundled receipt through the real reader, nothing saved, on-device only. (PJ.42)
- "Add expense from this receipt" on Edit entry: same photo, same date and car, joined into the purchase group. (PJ.41)
- The car's home city, asked once after its first scanned receipt and editable in car details; a tyre set's season. Tyre-change advice (RV.124e) is not in this release. (RV.124a-d)
- GeoNames CC BY 4.0 credit on About. (RV.124a)

### Better

- Capture readiness: camera starts off the main thread, torch, dark and fill-the-frame hints, opt-in auto-shutter. (PJ.16)
- Pump display reading: a second read at wide margins and a retrained row reader. (PU.108, PU.109)
- An invoice has one currency: service lines keep only their amount. (PJ.300)
- The check screen stays top-aligned while typing. (RV.336)
- Faster strip warp in the pump reader; no reading changes. (PU.75)

### Fixed

- Invoice table cells and colon labels are never the station; the station is best-effort. (RV.321)
- "Page N didn't save" on multi-page invoices with Rescan page / Continue; stale-odometer hint when completing a distance reminder. (PJ.43)
- The launch rate refresh reaches back to the oldest rate-pending entry. (RV.338)

## Owner check

- AdBlue writes a new entity: build 1368 and 1.1 skip it on sync (API.md verdict), so an AdBlue top-up made on 1.2 does not appear on a second device still on an older build.
- The home-city question appears only after the first scanned receipt; tyre-change advice is not shipped yet, so the store text does not promise it.
