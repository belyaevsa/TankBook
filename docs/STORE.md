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

## 1 · Findability: how a Russian speaker and an English speaker each arrive

The two audiences do not search the same way, and the difference is not translation.

**English-speaking searchers** use the category's own vocabulary - *fuel log, mileage tracker, mpg,
gas mileage, car expenses*. The field is crowded (Fuelio, Drivvo, Fuelly, Spritmonitor), so we do
not fight for `fuel log` head-on; we take the qualifiers those apps' reviews complain about:
**offline, no account, free export, multi-currency, EV and petrol together**.

**Russian-speaking searchers** use *расход топлива, бензин, заправки, расходы на авто, техобслуживание*
- and, unlike the English field, they search **расход** (consumption) far more than they search
"log", because the number they want is L/100 km. Two further facts shape the RU listing:

- **The App Store's RU-language storefronts are not only Russia.** Payment restrictions make
  subscriptions impractical inside RU (`VISION.md` §1), so the RU listing must earn installs from
  the diaspora and from KZ/AM/GE storefronts too. Nothing in the copy assumes a country.
- **Receipts in RU/KZ carry a fiscal QR**, which improves our reading - but naming it is
  forbidden, so the RU page shows the benefit (the total is right) and never the mechanism.

**Localise, do not translate.** The RU subtitle is not a translation of the EN one: English leads
with *log* (what you do), Russian leads with *расход* (what you get).

### Keywords

Apple's 100-character keyword field, comma-separated, no spaces, no word repeated from the name or
subtitle (those are already indexed).

**English (`en-US`, 98 chars):**

```
mpg,gas,mileage,odometer,receipt,scanner,vehicle,expenses,maintenance,offline,ev,diesel,economy
```

**Russian (`ru`, 99 chars):**

```
расход,бензин,дизель,заправка,чек,сканер,пробег,одометр,авто,машина,техобслуживание,каско,офлайн
```

Rationale for the non-obvious picks:

- `odometer` / `одометр` - the field users type most; high intent, low competition.
- `offline` / `офлайн` - the incumbents cannot claim it; it is also the top complaint tag against
  apps that lost data behind a login wall.
- `ev` and `diesel` - the household with both is our differentiator, and neither word appears in
  the name or subtitle.
- `каско` (RU motor insurance) - Russian drivers search insurance and service renewals in the same
  breath as fuel; we ship reminders, so the word is honest.
- Deliberately **absent**: `AI`, `нейросеть`, `автоматически`. They would index against the promise
  the copy rule forbids.

---

## 2 · The listing, English

**Name (30):** `Tankbook: Fuel Log & Costs`

**Subtitle (30):** `Snap or type. Costs that add up`

**Promotional text (170, changeable without review):**

> Every fill-up in seconds - scan the receipt or type it, whichever is faster. Litres x price is
> checked in front of you, so the numbers you keep are the right ones.

**Description:**

```
Tankbook is a fuel and running-cost log for people who actually keep one.

TWO DOORS, ALWAYS
Snap the receipt or type the entry - both take seconds, and neither is the
"failure" path. A scan fills in what it can read and you correct the rest;
the app remembers your station, fuel and currency for next time.

THE ARITHMETIC, SHOWN
Litres x price per litre = total. Tankbook checks it in front of you and says
plainly when the three numbers disagree. No silent "smart" correction: every
value is a suggestion you can edit, before and after saving.

WHAT IT TRACKS
- Fuel-ups with litres, price, total, odometer and station
- Consumption in L/100 km or MPG, cost per kilometre, monthly spend
- Service, repairs, parts, tyres, insurance and taxes
- Petrol, diesel, hybrid and electric - in one history, per car
- Several cars, switched in a tap. Free, on every tier

MONEY IN ANY CURRENCY, KEPT HONEST
Fill up abroad and the entry keeps both amounts: what you paid, and what it was
worth in your car's home currency at that day's rate. Rates are snapshotted at
entry time, so your history never shifts under you.

NO ACCOUNT NEEDED
The app is fully usable with no sign-in at all - the database lives on your
phone and every screen works offline. Sign in only if you want sync, restore on
a new phone, or cloud-assisted reading. Export is always free, in a format you
can open elsewhere. No ads.

WHAT WE DO NOT CLAIM
A scan is a head start, not an answer. On our own test set of real receipts,
about a third still need a field corrected - which is exactly why every field is
editable and why typing is a first-class door, not a punishment.

English and Russian throughout.
```

**What's New (first release):**

```
First release. Fuel-ups, service records and expenses; consumption and cost
trends; multi-currency with historical rates; receipt scanning with the
arithmetic cross-check shown; full offline use with no account.
```

---

## 3 · The listing, Russian

**Name (30):** `Tankbook: расход и расходы`

Two senses of one root, deliberately: *расход топлива* (consumption) and *расходы на авто*
(spending). It reads as a play on words to a native speaker and indexes both stems.

**Subtitle (30):** `Заправки, ТО и деньги на авто`

**Promotional text:**

> Заправка заносится за секунды - сфотографируйте чек или введите вручную. Литры x цена сверяются
> у вас на глазах, поэтому в истории остаются верные числа.

**Description:**

```
Tankbook - журнал расхода топлива и трат на машину для тех, кто ведёт его всерьёз.

ДВА ПУТИ, ВСЕГДА
Сфотографируйте чек или введите вручную - и то и другое занимает секунды, и
ручной ввод не "запасной вариант". Распознавание заполняет то, что смогло
прочитать, остальное вы поправляете; заправка, топливо и валюта запоминаются
на следующий раз.

АРИФМЕТИКА - НА ВИДУ
Литры x цена за литр = сумма. Tankbook проверяет это при вас и прямо говорит,
когда три числа не сходятся. Никаких "умных" исправлений втихую: любое значение
- предложение, которое можно изменить, и до сохранения, и после.

ЧТО ВЕДЁТ
- Заправки: литры, цена, сумма, пробег, АЗС
- Расход в л/100 км, стоимость километра, траты за месяц
- ТО, ремонты, запчасти, шины, страховка и налоги
- Бензин, дизель, гибрид и электро - в одной истории по каждой машине
- Несколько машин, переключение одним касанием. Бесплатно

ДЕНЬГИ В ЛЮБОЙ ВАЛЮТЕ
Заправились за границей - запись хранит обе суммы: сколько заплатили и сколько
это в валюте машины по курсу того дня. Курс фиксируется в момент записи, и
история потом не "поедет".

БЕЗ АККАУНТА
Приложением можно пользоваться вообще без регистрации - база лежит на вашем
телефоне, и все экраны работают офлайн. Вход нужен только для синхронизации,
переноса на новый телефон и облачного распознавания. Экспорт всегда бесплатный.
Без рекламы.

ЧЕГО МЫ НЕ ОБЕЩАЕМ
Съёмка чека - это фора, а не готовый ответ. На нашем наборе реальных чеков
примерно в трети случаев одно поле всё-таки приходится поправить - именно
поэтому любое поле редактируется, а ручной ввод равноправен.

Полностью на русском и английском.
```

**What's New:**

```
Первый выпуск. Заправки, ТО и расходы; графики расхода и стоимости; несколько
валют с историческим курсом; распознавание чеков с показанной проверкой
арифметики; полная работа офлайн без аккаунта.
```

---

## 4 · Screenshots: the plan

Ten panels, five per language, 1290 x 2796 (6.9"). Apple shows the first three in search results,
so those three carry the positioning; the rest carry proof.

**They are not bare screenshots.** Each panel is a composite: a headline that states the benefit, a
real device screenshot as evidence, and a caption naming the mechanism. Two of the five are
**feature panels** whose subject is a capability no single screen shows (the cross-check as trust;
no-account/offline). Built with `imagegen compose` from `design/store/*.yaml`; sources are the
committed screenshots in `design/screenshots/`, so a panel can never show a screen the build does
not have.

| # | Panel | Screenshot | EN headline | RU headline |
|---|---|---|---|---|
| 1 | Two doors | `RV.57-capture-prefill` | Snap it or type it | Сфотографируйте или введите |
| 2 | The cross-check, shown | `P2.3-confirm` | Litres x price, checked in front of you | Литры x цена - проверка при вас |
| 3 | What it costs to drive | `P1.10-trends` | Consumption and cost, per car | Расход и стоимость по каждой машине |
| 4 | Any currency | `P2.5-confirm-foreign` | Fill up abroad, keep both amounts | Заправка за границей - обе суммы |
| 5 | Yours to keep | `P6.5-home-log` | No account. Works offline. Export free | Без аккаунта, офлайн, экспорт бесплатно |

Panels 2 and 5 are the feature proposals: panel 2 turns an invisible guarantee into the page's
strongest claim, and panel 5 answers the complaint every incumbent's reviews carry.

**Rules the panels obey:** dark theme (the brand's home theme, `DESIGN.md`); headline in the
device's own language, never a translation of the other; numbers in DIN with `tabular-nums`; no
claim on a panel that is not in the description; no mock screen - every device image is a
committed screenshot.

---

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
