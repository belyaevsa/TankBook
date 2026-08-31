# Tankbook – Localization Governance (RU)

*Single authority for Russian string correctness. Companion to `docs/VISION.md`
(localization is a v1 feature) and `CLAUDE.md` hard rule 10 (all user-facing
strings go through String Catalogs, EN + RU from day one). Written by the
P5.3 pass, which exists because a green gate shipped two broken Russian
sentences; it records the reasoning a future translator needs, not just the
strings.*

## The rule this document serves

Hard rule 10 is met when every key exists with an RU value. Correctness inside
the strings is a different problem, and it has shipped broken twice:

- **P1.4.** `"%@ spend"` translated `"%@ расходы"` rendered **"АВГУСТ
  РАСХОДЫ"** - word-order nonsense. The rule written then: a composed string
  needs a full localised phrase per language, never concatenation.
- **P4.7.** That rule did not prevent the second one, because this *was* a full
  phrase: `"from your %1$@, %2$@"` → `"с вашего %1$@, %2$@"` rendered
  **"с вашего телефон Android"**. `с вашего` governs the genitive; `%1$@`
  receives a server-supplied device name that cannot be declined. No better
  translation fixes it - the sentence shape is wrong.

**The sharper rule, and the core of this pass:**

> **If a `%@` receives runtime data, the surrounding phrase must not govern its
> case.**

Runtime data is anything the app did not write and cannot decline: a station
name, device name, car name, make/model, fuel grade, part title, provider name,
or any user- or server-supplied text. App-formatted numbers and dates are safe:
`117 000 км`, `3 мар.`, `4,27` do not decline.

The fix is always a **shape change**, never a cleverer translation:

- put the slot in the nominative at the head (`«Volvo V60» вернулся…`),
- move it behind a separator or colon (`Срок 4 сент. · через 12 дней`),
- or quote it as a nominative apposition so no preposition reaches it
  (`Установить «Масляный фильтр» от 3 мар.`).

## The 51-key case-governance audit (P5.3)

Every EN key carrying a `%@`-class slot inside a multi-word phrase was audited:
what the slot receives, whether the RU phrase governs it, and the resolution.
The 42 the gate brief named are all here; the 9 extra (interpolated-literal
rows like `%@ %@`) were found the same way and cost nothing to include.

| Key (EN) | What the slot receives | Governed? | Resolution |
|---|---|---|---|
| `%1$@ in %2$@` | `%1$@` reminder title (user text, nominative head); `%2$@` app-formatted "in N days/months" | No | `«Заправка» через 5 дней` - title is the subject, `через` reaches only the formatted phrase. No change |
| `%1$@ within %2$@` | `%1$@` title; `%2$@` "N km" | No | `в пределах 1 500 км` reaches a number. No change |
| `%1$@ · signed in with %2$@` | `%1$@` email (after separator); `%2$@` provider name | No | `вход через Apple` is the standard undeclinable-brand construction. No change |
| `%@ · %lld devices` | `%@` app-composed `syncedAgo` text; `%lld` a count | No | PJ.13: `Синхронизировано только что · 1 устройство` - the `%@` slot receives the app's own composed age string (never server text), the `%lld` a number, and the phrase after the separator governs nothing. Plural key: RU устройство/устройства/устройств at 1/2/5/11/21, pinned in `deviceCountPluralRendersInBothLanguages` |
| `%1$@ – done` | title, nominative head | No | `Замена масла – выполнено`. No change |
| `%@ %@` | formatted number + localized unit (`42,3 л`) | No | interpolated-literal row; numbers/units. No change |
| `%@ %@ · %@` | number + unit + relative-day | No | same. No change |
| `%@ already recorded %d km.` | `%@` app-formatted day; `%d` odometer | No | `«17 авг.» уже зафиксирован пробег 119 486 км` - the day is quoted, the subject is `пробег`. No change |
| `%@ came back with 1 new entry – stays archived.` | **car name** (user text) | No (nominative subject), but the verb `вернулся` agrees in masculine | **Fixed**: `«%@» вернулся с 1 новой записью – остаётся в архиве.` - quotes make the name a cited nominative; the masculine default is the accepted convention for an undeclinable car name |
| `%@ spend` | month name (app-localized, wide) | `за` governs accusative = nominative for all Russian months | `Расходы за август`. No change |
| `%@ this month` | amount (`€212`) | No | `212 € за месяц`. No change |
| `%@ · %@` | month name · amount (accessibility label) | No (separator) | No change |
| `Add %@` | (no call site in the tree today) | `Добавить %@` governs the object case | Flagged: when a call site lands, the slot must not be an accusative object. No current fix |
| `Added %@` | app-formatted day | No | `Добавлен 5 авг.`. No change |
| `added %@` | app-formatted day | No | `добавлен 5 авг.`. No change |
| `Adds as expense · %@` | category label (localized) | No (separator) | No change |
| `Archived · %1$@ · history kept` | month-year (DateFormatter, nominative) | No (separator) | No change |
| `bought %1$@, %2$@` | date · amount | No | `куплено 3 мар., 12,40 €`. No change |
| `Changed by sync · %@, %@` | device name · date | No (separator) | No change |
| `Completed today at %1$@ km` | odometer number | No | `Завершено сегодня на 119 486 км`. No change |
| `Consumption updated: %1$@ → %2$@ %3$@` | numbers · units | No | `Расход обновлён: 6,9 → 6,8 L/100км`. No change |
| `Deleted %@` | app-formatted day | No | `Удалено 3 авг.`. No change |
| `downloading · %@` | percent | No | No change |
| `Due %1$@ · %2$@` | date · "in N days" | No (separator) | `Срок 4 сент. · через 12 дней`. No change |
| `Due at %1$@ km` | odometer number | No | `Срок 119 486 км`. No change |
| `Due at %1$@ km or %2$@` | odometer · date | No | No change |
| `every %1$@ km` | number | No | `каждые 15 000 км`. No change |
| `from your %1$@, %2$@` | **device name** (server text) | Was `с вашего` (genitive) | **Already fixed after P4.7**: `%1$@, %2$@` - device name in nominative head, then the relative day. Verified in this pass |
| `In %1$@ km` | number | No | `Через 8 400 км`. No change |
| `In %1$@ km or %2$@` | number · date | No | No change |
| `In %@` | currency code | `в` governs, but a code is declension-free by design | `В EUR` (documented at `CurrencyConversionCard.swift:74`). No change |
| `Install %1$@ from %2$@?` | **%1$@ part title** (user text); %2$@ date | Yes: `установить %1$@` makes the title an accusative object | **Fixed**: `Установить «%1$@» от %2$@?` - the title is a quoted nominative apposition; `от %2$@` reaches a date, which does not decline |
| `Next cycle scheduled: %1$@ – counted from today, not the old due date.` | due-line (app-composed) | No (after colon) | No change |
| `Nothing is stored under this %1$@. Last time, did you sign in with %2$@?` | **%1$@ provider account name** ("Apple ID"/"Google"); %2$@ provider | Yes: `под этим %1$@` governed the instrumental | **Fixed**: `Под этой учётной записью «%1$@» ничего не сохранено. В прошлый раз вы входили через %2$@?` - `под этой учётной записью` governs the localized, declinable phrase; `«%1$@»` is a nominative apposition (matches the existing `Под этой учётной записью не найдено…` string) |
| `Overdue by %1$@` | number | No | `Просрочено на 3 дня`. No change |
| `Overdue by %1$@ km` | number | No | No change |
| `Overdue by %1$@ km or %2$@` | number · date | No | No change |
| `Page %1$@ of %2$@` | numbers | No | `Страница 1 из 3`. No change |
| `Possible duplicate – %@, %@ logged twice` | amounts | No (after dash) | `Возможный дубликат – 68,46 €, 390 € внесены дважды`. No change |
| `Receipt total %1$@ · logging %2$@` | amounts | No | No change |
| `Recent first · a foreign amount converts to %@ automatically` | currency code | No | No change |
| `removed on %@` | **device name** (server text) | Yes: `удалено на %@` put the name under `на` | **Fixed**: `устройство: %@` - nominative after a colon, no preposition reaches the slot |
| `Replaced %@` | app-formatted day | No | `Заменено 2 дн. назад`. No change |
| `Scanned %@` | date stamp | No | `Отсканировано 17 авг., 21:47`. No change |
| `Set %@ tank` | fraction/percent glyph (`¾`, `63%`) | No | `Бак на ¾`. No change |
| `signed in with %@` | provider name | No | `вход через Apple`. No change |
| `Spend · %@` | month name | No (separator) | No change |
| `Still pending: %1$@` | title | No (after colon) | No change |
| `Updated %@` | app-formatted day | No | `Обновлено 5 авг.`. No change |
| `updated %@` | app-formatted day | No | No change |
| `Use %@ instead` | provider name | No (undeclinable brand as object is standard) | `Использовать Google вместо этого`. No change |
| `· %@ %@` | number + unit (interpolated literal) | No | No change |

### The four shape changes, called out

1. **`%@ came back with 1 new entry – stays archived.`** → `«%@» вернулся с 1
   новой записью – остаётся в архиве.` The car name stays the nominative
   subject (it cannot move anywhere else in the sentence), but quotes turn it
   into a cited name so the masculine-default verb reads as a convention, not
   an agreement error.
2. **`Install %1$@ from %2$@?`** → `Установить «%1$@» от %2$@?` The part title
   is no longer the accusative object of `установить`; the quoted nominative
   apposition receives no case.
3. **`Nothing is stored under this %1$@. …`** → `Под этой учётной записью
   «%1$@» ничего не сохранено. …` The governing phrase attaches to
   `учётная запись` (declinable, already the app's own term), and the
   undeclinable account name rides in quotes.
4. **`removed on %@`** → `устройство: %@` The device name moves behind a colon
   in the nominative.

Each is pinned by a regression test
(`LocalizationGateP53Tests.reshapedKeysDoNotGovernTheSlot`) that asserts the
exact RU string and that no governing preposition (`с на в от до у под за для
про о`) sits immediately before the slot.

## Plural selection is not 1/2/5

Russian selection: 1/21/31 → `one`; 2-4/22-24 → `few`; 5-20, 11-14 → `many`.
**11-14 are the trap**: they end in 1-4 but take `many`, so a 1/2/5 test passes
an implementation that gets 11 and 21 wrong. Every plural key the app renders
is asserted on its RENDERED string at 1, 2, 5, 11 and 21
(`russianPluralsSelectTheRightFormAtTheEdges`) - e.g. `21 запись` but
`11 записей`, `21 день` but `11 дней`.

### One plural defect found and fixed

`Synced %lld hours ago` / `Synced %lld days ago` rendered **without the verb**:
the RU forms were `3 часа назад`, `3 дня назад` - "3 hours ago", not "Synced 3
hours ago". The status line's reassurance lost its meaning (a bare age reads as
a fact, not a sync state). Fixed to `Синхронизировано %lld часа назад` /
`Синхронизировано %lld дней назад`, and pinned by
`syncedAgoKeepsItsVerb`.

### The `литр` row in `docs/TASKS.md`

TASKS.md P5.3 once named `1 литр / 2 литра / 5 литров` as the plural fixture.
**The app never renders a count with the spelled-out unit**: volume renders as
`42,3 л` (the `л` abbreviation does not decline), and the word `литр` appears
only in count-free labels (`Литры`, `Проверьте литры на чеке`). No surface
renders `1 литр / 2 литра / 5 литров`, so inventing that plural to tick the
row would satisfy a checklist no screen displays. The row is corrected in the
same change; if a screen ever renders a spelled-out litre count, it needs its
own three-form plural key.

### The PJ.10/PJ.9 import plurals (added 2026-08-29)

Three new count strings joined the import wizard, each pinned in
`LocalizationGateP53Tests.pluralCases` at 1/2/5/11/21:

- `Date format matters – %lld dates read either way.` → RU
  `Формат дат важен – %lld дата/даты/дат читается двояко.` - 21 takes `one`
  (дата), 11 takes `many` (дат). This is the `dateFormat` question's subtitle;
  the count is the number of rows whose day is also ≤ 12.
- `This file has %lld income rows; income isn't imported in v1.` (RU
  строка/строки/строк) and `This file has %lld reminders; reminders aren't
  imported in v1.` (RU напоминание/напоминания/напоминаний) - the `outOfScope`
  notices.

All three are `%lld`-only slots (counts), so no case governs a `%@`; the
`%@`-slot rules above do not apply to them.

## The `Text(_: String)` blind spot

`Text(_: LocalizedStringKey)` localises; `Text(_: String)` does not. Any
expression that produces a `String` renders its English text in Russian even
when the catalogue holds the translation, and the P0.3 key-membership gate
cannot see it - the key is present, so nothing is missing to report.

**What the P5.3 sweep found.** The four recorded instances (the capture
"checks as you type", the odometer-timeline warning, the "Nearby suggestion"
fallback, the `hintText` wrapper) are all fixed in the tree. A full sweep of
`ios/App/Sources` found **two live instances**: the Edit entry screen's
`TextField(charge.provider ?? "Provider", …)` and `TextField(service.vendor ??
"Vendor", …)` - `String? ?? "literal"` pins the expression to `String`, so the
English placeholder rendered in Russian. Both now route the fallback through
`L10n.localize`. Every other `Text(<variable>)` site feeds user data (car
names, amounts - which must NOT be localised) or an already-localised producer
(`L10n.*`, `String(localized:)`, `DateFormatter` output, wrapper parameters
typed `LocalizedStringKey`).

**Empirically settled: an interpolated literal is NOT the blind spot.**
`Text("\(value) literal")` resolves to `Text(_: LocalizedStringKey)` - the
`String` initialiser is `@_disfavoredOverload`, and an interpolated literal
forms a `LocalizedStringKey` whose key is `%@ literal`. Verified against the
iOS 26.5 SwiftUI interface and by rendering the key. The blind spot is a
`String`-typed *value* sharing an expression with copy, never an interpolated
literal.

**The gate extension.** `LocalizationGate` now runs a compound-argument pass
(`SourceScanner.compoundStringLiterals`) over the same call-site prefixes. It
flags a string literal that sits at parenthesis depth 0 inside a non-literal
first argument - a direct operand of `??`, a mixed ternary, or a concatenation
- unless it is a pure-literal ternary branch (`cond ? "A" : "B"`, which SwiftUI
treats as a runtime key and is membership-checked like any other key). The
boundary is documented in code: a literal inside a nested call (an
`accessibilityLabel(Text("…"))`, a `String(format:)` argument, a
`joined(separator: ", ")`) is either already-scanned key or data; and
`Text(someVariable)` with no literal at all needs value-flow analysis, so only
a human reading rendered Russian can judge it. The pass is mutation-checked in
`LocalizationGateP53Tests`: it flags `Text(x ?? "…")`, a mixed ternary, and a
concatenation; the recorded split fix clears it; an interpolated literal does
not trip it; and the current tree passes with zero violations.


## Two shapes that are legal Russian and still wrong (added 2026-08-28, from P6.1b)

Both were found by reading a rendered screen, not by any test, and both are the same family as
P4.7's «с вашего телефон Android» - the grammar is fine and the meaning is not.

### A past-tense verb assumes the user's gender

`Changed tyres` was translated **«Поменял шины»** - masculine past. A woman dismissing the card
reads a form that misgenders her, and **Russian has no genderless past tense**, so no better
translation exists. The fix is to change the part of speech: a **noun phrase** (**«Замена шин»**)
carries the same meaning and has no gender.

**Rule: user-facing Russian never puts the user in a past-tense verb.** Prefer a noun phrase, an
infinitive, or an imperative. This applies to every option list, every log entry the user authors,
and every confirmation that echoes what they just did.

**Resolved in P6.17** with «Замена шин» - a noun phrase that matches the sibling options
(`Зима`, `Буксировка`, `Прочее` are all nouns) and carries no gender. Pinned by
`AnomalyInsightUITests.testDismissSheetRussianShapesAreGenderlessAndDomainSafe`, which asserts the
shape, not the taste: no dismiss option's RU value contains a whole word ending in a past-tense
verb suffix (`-л`/`-ла`/`-ло`/`-ли`). The guard enumerates the class, so a "better" gendered verb
would still fail it - only a shape change passes.

### A word that collides with the domain vocabulary

`Dismissing with a reason keeps it quiet for this period.` was translated **«Отклонение с
причиной…»**. «Отклонение» is a correct translation of *dismissal* in the formal sense - and in a
fuel app it is also the ordinary word for **deviation**, sitting directly under a card about a
consumption deviation. The sentence reads as "a deviation with a cause".

**Rule: check a translated term against the app's own domain vocabulary, not only against the
dictionary.** The words that break this way are exactly the ones that look most correct.

**Resolved in P6.17** with «Если укажете причину, подсказка скроется на этот период.» - the word
«отклонени» is gone in every form, and the reason is the user's, not the card's. Pinned by the
same guard: the dismiss subtitle must not contain «отклонени» in any form.
