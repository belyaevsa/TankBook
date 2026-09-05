# Tankbook - the App Store listing

*Single authority for the App Store product page in **English and Russian**: name, subtitle,
keywords, description, screenshots and review notes. Companion to `SITE.md` (the same claims on
the web, and the copy rule both obey), `VISION.md` (what may be claimed at all), `COMPETITORS.md`
(what the incumbents' pages say) and `DESIGN.md` (the visual language the screenshots use).
Written 2026-09-05.*

## The copy rule applies here first, not last

`SITE.md`'s rule is that **the page may not promise what the corpus says we cannot deliver**, and
the store page is where an over-promise costs most: it is read by someone deciding, it is quoted
back in one-star reviews, and Apple's reviewers check it against the build. The measured position,
re-measured 2026-09-05:

- receipts resolve **188 of 220 asserted cells (85%)**, but only **33 of 48 receipts (69%) come
  out with every field right** - so about a third of scans still need a correction;
- **pump-display capture ships OFF** (24 of 178 numeric cells committed, 13% coverage against a
  60% floor) - it may appear on a roadmap, never in the listing;
- a fiscal QR is present on **22 of 48** receipts and carries 2 of the 5 fields;
- Vision misreads a digit at **confidence 1.00**, which is why every value is editable.

**85% is a good number and it is not a promise that a scan finishes the job.** The listing
therefore leads with *"snap it or type it"*, never with "zero typing", and never says "automatic".

| Never on the page | What we say |
|---|---|
| "Zero typing", "just snap and you're done" | "Snap it or type it - both take seconds" |
| "AI reads any receipt perfectly" | "A scan fills in what it can read. You fix the rest" |
| "Automatic" as the headline verb | "Fast", and the cross-check as visible proof |
| Anything naming the fiscal QR as a feature | nothing - the QR is part of the receipt (product owner, 2026-08-30) |
| "Pump display scanning" | nothing until the gate passes (P2.7) |

---

## 1 · What the two audiences are actually angry about

Researched 2026-09-05 across App Store, Google Play and RuStore reviews dated 2025-2026, plus
Drive2/Дром/Telegram. **The two audiences are not the same market with different words - they are
angry about different things**, so the listings are not translations of each other and neither are
the screenshots.

### English-speaking: the phone change destroys the history

The strongest low-star trigger in 2025-2026 is **data portability failure**, not accuracy.

| App | Dated review | What happened |
|---|---|---|
| Simply Auto | Google Play, 2026-04-10 | New phone forced a choice between cloud and local with **no merge**; one attempt erased months, the second erased everything: *"lost all my data... I had a few years of data logged"* |
| Simply Auto | Google Play, 2026-06-20 | A decade-long user: every new phone loses something despite cloud **and** manual backups; scanned receipts *"nearly always"* fail to restore |
| Fuelly | App Store | A non-dismissable login appeared **mid-road-trip**; after creating the account, *"ALL MY DATA IS GONE"* - no path to migrate the local history in |
| Drivvo | Google Play, 2026-03-19 | After a forced update an active subscriber was told it had expired, saw ads, and could not view records without creating an account |
| Drivvo | Apple AU | Pro stopped being recognised, restore failed, reinstalling *"wiped all data"* |
| Fuelly | App Store | Export produces the records but not the attached images: *"All the images are lost"* |
| Drivvo | 2026 pricing | A six-year Premium user reported a **4x** increase plus repeated "ABOUT TO EXPIRE" notices with six months left |

**The finding that changes our copy: OCR accuracy is NOT a recurring complaint** in this set. The
adjacent ones are worse - scanning is paywalled (Fuelio Pro), receipt images vanish from exports
(Fuelly) and from migrations (Simply Auto). So the EN page must **not** lead on reading quality. It
leads on *your history survives*, and it can say something none of them can: our export archive
carries the receipt image bytes under `attachments/<sha256>` (`SCHEMA.md` -> Backup format), not
just the rows.

### Russian-speaking: the app stops being yours

The RU complaints are sharper and land somewhere else - **the product becomes unusable or
unpayable through no fault of the user.**

| App | Dated review | What happened |
|---|---|---|
| Мой Авто | App Store | *"По-видимому, отключили сервера... само приложение теперь тупо висит при входе"* - the server went away and the LOCAL log could not be opened |
| Мой Авто | App Store | *"Пользуюсь более 10 лет"*, then it stopped responding after an update |
| Drivvo | Google Play, 2026-05-10 | The app said 12.2 L/100 km where the driver's own arithmetic gave 11 - *"после этого удалил"* |
| Моя машина | Google Play, 2025-03-01 | A receipt photo is only **referenced** in the gallery: rename or delete it there and *"картинка в приложении удалится"* |
| Fuel Manager | RuStore, 2025-06-26 | *"В бесплатной версии ни чего не считает"* |
| Fuel Manager | RuStore, 2025-02-20 | *"Нет синхронизации с гугл"* |
| Car Scanner | RuStore, 2026-08-09 | *"Оплатил подписку, данные не показывает... деньги на ветер"* |
| Мой Авто | App Store | *"Платная версия у многих активируется через одно место"* |
| Моя машина | App Store | *"Перестали создаваться напоминания"* |
| Мой Автомобиль | App Store | *"НЕТ возможности редактирования записей по дате"* - old service history cannot be entered |
| Топливомер | RuStore | Pro cannot be bought at all: the purchase redirects to Google Play, which cannot be paid from Russia |
| Fuelio | Drive2 | Removed from the RU store; users install an APK from forums, losing updates and restore |

Two RU-only conclusions:

1. **Payment is a feature.** *"Функциональность приложения уже не гарантирует возможность им
   пользоваться полностью"* - an app can be installable and still unusable because its Pro cannot
   be paid for. We have **no subscription in v1** (P6.16), so "всё бесплатно, ничего не нужно
   оплачивать" is a differentiator in RU that means little in EN.
2. **The consumption number itself is distrusted.** A driver who recomputes 11 against the app's
   12.2 deletes the app. Our arithmetic cross-check is a *nice-to-have* in EN and an *answer to a
   dated one-star review* in RU - so it is panel 2 in Russian and panel 4 in English.

Both audiences also search **"how do I move my data from Fuelio/Drivvo/the old phone"**, which our
importers answer directly.

## 2 · Findability

**English** searchers use the category's vocabulary - *fuel log, mileage tracker, mpg, gas mileage*
- in a crowded field. We do not fight for `fuel log` head-on; we take the qualifiers the
incumbents' own reviews complain about: offline, no account, complete export, no subscription.

**Russian** searchers search **расход** far more than "log", because the number they want is
L/100 km. The RU listing also assumes **no country**: payment limits inside RU mean it must earn
installs from the diaspora and the KZ/AM/GE storefronts too.

### Keywords

**English (`en-US`, 98 chars):**

```
mpg,gas,mileage,odometer,receipt,scanner,vehicle,expenses,maintenance,offline,ev,diesel,economy
```

**Russian (`ru`, 99 chars):**

```
расход,бензин,дизель,заправка,чек,пробег,одометр,авто,машина,техобслуживание,напоминания,офлайн
```

Non-obvious picks: `odometer`/`одометр` (high intent, low competition); `offline`/`офлайн`, which
no incumbent can claim and which RU reviews show is the difference between opening your log and
not; `ev`+`diesel`, the household nobody serves; `напоминания`, because "перестали создаваться
напоминания" is a live RU complaint. **Deliberately absent**: `ai`, `нейросеть`, `автоматически` -
they would index against the promise the copy rule forbids.

## 3 · The listing, English - *your history survives*

**Name (30):** `Tankbook: Fuel Log & Costs`

**Subtitle (30):** `Your log. Yours to keep.`

**Promotional text:**

> No account, no subscription, no ads. Your history lives on your phone, and the export takes the receipt photos with it - so the next phone is not where the last five years go missing.

**Description:**

```
Tankbook is a fuel and running-cost log built around one promise: the history
you keep is yours, and you can take it out whole.

WHAT USUALLY GOES WRONG, AND WHAT WE DID ABOUT IT
Read the reviews of any fuel app and the same story repeats - a new phone, a
forced login, a sync that overwrites instead of merging, and years of records
gone. So:

- No account is needed. Ever. The database is on your phone and every screen
  works offline, with our servers down or unreachable.
- Export is free, complete and includes the receipt IMAGES, not just the rows.
  Most exports leave the photos behind; ours puts them in the archive.
- Nothing is behind a subscription. There is no paid tier in this version.
- No ads.

TWO DOORS, ALWAYS
Snap the receipt or type it - both take seconds, and typing is not the failure
path. A scan fills in what it can read and you correct the rest; the app
remembers your station, fuel and currency for next time.

THE ARITHMETIC, SHOWN
Litres x price per litre = total, checked in front of you, with a plain warning
when the three numbers disagree. Nothing is silently "corrected": every value is
a suggestion you can edit before and after saving.

WHAT IT TRACKS
- Fuel-ups: litres, price, total, odometer, station
- Consumption in L/100 km or MPG, cost per kilometre, monthly spend
- Service, repairs, parts, tyres, insurance and taxes, with photos attached
- Petrol, diesel, hybrid and electric in one history, per car
- Several cars, free, on every tier

COMING FROM ANOTHER APP
Import from Fuelio, Drivvo, Fuelly/aCar, Spritmonitor, CarScope and My Fuel
Manager. You see what was read before anything is written.

MONEY IN ANY CURRENCY
Fill up abroad and the entry keeps both amounts - what you paid, and what it was
worth in your car's currency at that day's rate, snapshotted so your history
never shifts.

WHAT WE DO NOT CLAIM
A scan is a head start, not an answer. On our own test set of real receipts,
about a third still need one field corrected - which is why every field is
editable and why typing is a first-class door.
```

## 4 · The listing, Russian - *приложение, которое не отберут*

Not a translation of the English. The English page answers "will I lose my history when I change
phones"; the Russian page answers "будет ли оно работать и смогу ли я им пользоваться вообще".

**Name (30):** `Tankbook: расход и расходы`

**Subtitle (30):** `Без подписки. Работает офлайн`

**Promotional text:**

> Без аккаунта, без подписки, без рекламы. Журнал лежит у вас в телефоне и открывается, даже если
> наши серверы недоступны - и цифры можно проверить самому.

**Description:**

```
Tankbook - журнал расхода топлива и трат на машину. Работает у вас в телефоне,
без аккаунта и без подписки.

ПОЧЕМУ ЭТО ВАЖНО ИМЕННО СЕЙЧАС
В отзывах на другие приложения повторяется одно и то же: "отключили серверы -
приложение висит при входе", "оплатил подписку, данные не показывает",
"в бесплатной версии ничего не считает", покупка Pro ведёт в магазин, где её
нельзя оплатить. Поэтому:

- Аккаунт не нужен вообще. База лежит в телефоне, все экраны работают офлайн -
  и открываются, даже если наши серверы недоступны.
- Подписки нет. В этой версии нет платного уровня.
- Рекламы нет.
- Экспорт бесплатный и полный: вместе с записями выгружаются сами фотографии
  чеков, а не только строки.

ЦИФРЫ МОЖНО ПРОВЕРИТЬ
Литры x цена за литр = сумма. Проверка показана прямо на экране, и если три
числа не сходятся, приложение говорит об этом прямо. Ничего не правится
втихую: любое значение - предложение, которое вы можете изменить, и до
сохранения, и после. Расход считается по вашим заправкам, а не "как-то".

ЧЕК ОСТАЁТСЯ В ПРИЛОЖЕНИИ
Фотография чека копируется в приложение, а не просто ссылается на файл в
галерее: удалите или переименуйте снимок в галерее - в журнале он останется,
и уедет вместе с экспортом.

НЕ ТОЛЬКО ЗАПРАВКИ
- Заправки: литры, цена, сумма, пробег, АЗС
- Расход в л/100 км, стоимость километра, траты за месяц
- ТО, ремонты, запчасти, шины, страховка и налоги - с фотографиями
- Напоминания по пробегу и датам
- Бензин, дизель, гибрид и электро в одной истории по каждой машине
- Несколько машин - бесплатно
- Записи можно вносить задним числом: старое ТО и прошлые заправки

ПЕРЕХОД ИЗ ДРУГОГО ПРИЛОЖЕНИЯ
Импорт из Fuelio, Drivvo, Fuelly/aCar, Spritmonitor, CarScope и My Fuel
Manager. Сначала показываем, что распозналось, и только потом записываем.

ЛЮБАЯ ВАЛЮТА
Заправились за границей - запись хранит обе суммы: сколько заплатили и сколько
это в валюте машины по курсу того дня. Курс фиксируется в момент записи.

ЧЕГО МЫ НЕ ОБЕЩАЕМ
Съёмка чека - это фора, а не готовый ответ: примерно в трети случаев одно поле
всё-таки приходится поправить. Именно поэтому любое поле редактируется, а
ручной ввод равноправен.
```

## 4b · Screenshots: two different sets, not one translated set

Five panels per language, 1290 x 2796, built by `design/store/build.py`. **The subjects and their
ORDER differ**, because the first three panels are what search results show and the two audiences
need different first three.

| # | English | Russian |
|---|---|---|
| 1 | Your log. Yours to keep. *(no account, offline)* | Открывается, даже когда серверы лежат |
| 2 | The export takes the photos too | Цифры можно проверить *(арифметика на экране)* |
| 3 | Snap it or type it | Без подписки. Без рекламы. |
| 4 | Litres x price, checked in front of you | Чек остаётся в приложении |
| 5 | Bring your history with you *(importers)* | ТО, страховка и напоминания |

Panel 2 EN and panels 1-3 RU are **feature proposals**, not screen tours: they answer a specific
dated complaint rather than showing a screen. Every device image is a committed screenshot in the
device's own language.

## 5 · Review notes and metadata

- **Support URL** `https://tankbook.live/support/`, **privacy policy** `https://tankbook.live/privacy/`,
  support contact **to@belyaev.live** - the same address the site shows (`SITE.md`), and they must
  never disagree.
- **Sign-in is optional and the reviewer must be told so**: the review note states that the app is
  fully functional with no account, and that Sign in with Apple is offered alongside Google, which
  is what Apple's guideline 4.8 requires.
- **Age rating** 4+; no user-generated content, no ads, no tracking.
- **Privacy nutrition labels** must match `SECURITY.md` and `LOGGING.md`: identifiers and the
  synced record stream are collected **only with an account**, linked to the account, and never
  used for tracking; images sent to cloud reading are processed transiently. Nothing is collected
  for a signed-out user.
- **Data deletion**: `DELETE /account` purges, and the store's account-deletion requirement points
  at the in-app control, not an email.
- **No subscription in v1** - Pro is cut (P6.16), so no in-app purchases are declared. The free
  tier includes cloud reading at 50 reads a day (RV.4).

## 6 · App Store Connect: the exact answers (2026-09-05)

Every field on the App Information and age-rating screens, with the reason. These are answers to
Apple's questions about **this build**, so a change to the build can invalidate one - the paywall
row at the end is exactly that case.

### App Information

| Field | Answer | Why |
|---|---|---|
| Primary language | English (U.S.) | Russian ships as a localisation of the same listing; both sets of copy live in `STORE-COPY.md` |
| Primary category | **Travel** | Where the incumbents sit (`COMPETITORS.md`); iOS has no automotive category, that is an Android one |
| Secondary category | **Finance** | The listing leads on cost. Utilities is a dumping ground and Productivity reads as work software; Navigation would invite a review expecting maps |
| Content rights | **Does not contain, show or access third-party content** | No third-party artwork ships: `Assets.xcassets` holds only the app icon and `BrandMark`. Car makes and models are plain text in `VehicleCatalog.seed.json` ("VW Golf") - nominative use, not content. Station names come from the user's own typing or their receipt. The one arguable item is central-bank reference rates (`Rates.seed.json`, `source: "ecb"`): published facts, reusable with acknowledgement, which is why the conversion card should name its source |
| License agreement | Apple's standard EULA | Nothing in the app needs custom terms |

### Regulations and permits

- **Digital Services Act - must be set up, or the app is removed from sale in the EU.** v1 is free,
  has no in-app purchase, no ads and sells nothing, so **non-trader** is the accurate declaration
  and no personal contact details are published. **This changes at v2**: the Pro tier makes the
  developer a trader, and Apple then publishes name, address, phone and email on the listing. Decide
  the publishing entity before that release, not during it.
- **Vietnam game license** - not a game. Leave empty.
- **Regulated medical devices** - nothing medical; the category is Travel, not Health & Fitness.
  Leave empty.
- **App Store server notifications** and the **app-specific shared secret** - both exist to service
  in-app purchases. v1 has none, and the notification URL would need a backend endpoint that does
  not exist. Leave unset until the v2 paywall.

### Age rating - capabilities

All six are **No**, and each is checkable in the code rather than assumed:

| Capability | Answer | Evidence |
|---|---|---|
| Unrestricted web access | No | No `WKWebView` and no `SFSafariViewController` anywhere in `ios/App/Sources` or `ios/Sources` |
| User-generated content | No | Nothing a user writes is distributed to anyone. Sync carries a user's records to **their own** devices |
| Social media | No | There is no feed, no discovery and no redistribution |
| Social media disabled under 13 | No | Nothing to disable |
| Messaging and chat | No | Users cannot reach each other; there is no shared surface |
| Advertising | No | No ad SDK, no promotion of anything - and the listing claims this, so it must stay true |

Rating stays **4+**.

### One thing that contradicts the answers, and must be fixed before submission

Settings shows a **"Tankbook Pro" card** (`SettingsView.swift:418`, and again on the quota card at
`:569`) whose route resolves to `LeafContent()` - `Color.clear` (`Destinations.swift:40`, `:174`).
Tapping it pushes an **empty screen**. That is a guideline 2.1 rejection waiting to happen, and it
contradicts both the "no paid tier in this version" line in the description and the no-IAP
declaration above. Registered as **RV.70**.
