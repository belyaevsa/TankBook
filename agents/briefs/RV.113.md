# RV.113 - import a Drivvo export

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The file, measured - not assumed

`Spike/ImportFixtures/drivvo/drivvo-ru-3sections.csv` is **committed and validated** (commit
`9e83ac6`); driver names are SHA-256 hashed to `driver-<12 hex>`. It is 324 lines, 60 KB, and
**one file with three sections**, each with its own `##` marker and its own header line:

| Section | Marker line | Header line | Data rows | Columns |
|---|---|---|---|---|
| `##Refuelling` | 1 | 2 | **251** | 29 |
| `##Expense` | 254 | 255 | **12** | 11 |
| `##Service` | 268 | 269 | **55** | 10 |

The row text in `docs/TASKS.md` says 250/11/54. **I measured 251/12/55.** Measure it yourself and
assert what you find; if you also get 251/12/55, fix the row text in the same change.

## Two hazards the row does not mention. Read these before writing the parser.

### 1. The header line is NOT clean CSV, and this will decide your parser choice

Line 2 contains, verbatim:

```
"Объем","Полный бак" 2,"Третье топливо",
```

That is a **quoted field followed by ` 2` before the comma** - `"Полный бак" 2` and, further along,
`"Полный бак" 3`. Drivvo disambiguates its second and third fuel blocks by appending a digit
*outside* the closing quote.

`MfmParser` uses `Microsoft.VisualBasic.FileIO.TextFieldParser` with
`HasFieldsEnclosedInQuotes = true` (`MfmParser.cs:69-74`). **That configuration is likely to throw
`MalformedLineException` on this header.** Python's lenient reader yields `Полный бак 2` and 29
fields; .NET's is stricter.

**Your FIRST action is to measure this** - feed line 2 to the same parser configuration and see what
it does. Do not design around a guess. If it throws, decide and state your fix (a pre-pass that
normalises `" <digit>` before the delimiter, `HasFieldsEnclosedInQuotes` off with manual unquoting,
or a different reader) and say why. **Do not silently swallow a malformed-line exception** - a
parser that skips the header and reports zero rows is the failure this project has already shipped
once (see the RV.103 note below).

### 2. Column names REPEAT inside one header

`"Цена / л"`, `"Общая стоимость"` and `"Объем"` each appear **three times** in the refuelling header -
once per fuel block (primary, second, third). A `Dictionary<string,int>` keyed on the header name
**collapses them to the last occurrence**, which silently reads the third fuel block's price as the
fill's price. Map by **position within the block**, or by occurrence index. Whatever you choose, a
test must prove the primary block's price is what lands on the entry.

## What the columns actually contain

A real refuelling row:

```
"491206.0","2025-08-02 06:55:11","Бензин АИ92","220","6630","30.136","Да",...,"6,414 л/100км","585.0",...,"Газпром","driver-ea23167db8ec",...,"0"
```

- **Dates are `yyyy-MM-dd HH:mm:ss`** - a space, **not** an ISO-8601 `T`. **RV.103 shipped a seed
  that decoded ISO-8601 with the wrong strategy and silently populated ZERO rows**, so every
  screenshot before it was vacuous. Assert a parsed date's value, never that parsing "did not
  throw".
- **Mixed decimal conventions inside ONE row**: volume `30.136` (dot) beside consumption
  `6,414 л/100км` (comma **and** a unit suffix). Distance is `585.0`.
- **`"Полный бак"` is localised Да/Нет**, not a boolean.
- **Odometer `"0.0"` maps to null**, never a zero reading (one row in this file).
- **There is NO currency column anywhere**, in any of the three sections.
- **There is NO vehicle column** - a Drivvo export is one car per file.
- Fuel is a localised grade string (`"Бензин АИ92"`); station is `"Азс"`; `"Водитель"` is the
  driver, Drivvo's fleet feature and its positioning.
- `##Expense` carries `Вид расхода` (kind) and `Заголовок`; `##Service` carries `Вид сервиса` and
  `Название сервиса`.

## Design questions ALREADY CLOSED - do not reopen

1. **One more `format` on the existing `POST /import/parse`.** No new endpoint. `/import/parse` is
   hard rule 9's **named exception** and it explicitly "does not spread" - a second endpoint that
   reads domain meaning needs its own written decision, and you do not have one.
2. **`MfmParser`'s model does not transfer and you must not bend it to fit.** MFM is
   *title-line-names-the-kind*, one kind per file, **semicolon**-delimited (`MfmParser.cs:71`).
   Drivvo is *scan-for-`##`-section-markers*, three kinds in one file, **comma**-delimited. Write a
   `DrivvoParser` beside it. Reuse the *shapes* that are already right - `MfmParseResult`,
   `UnparsedRow`, the stable `Reason*` codes (`MfmParser.cs:55-60`), `ImportProvenance` with
   `source: "drivvo"` - not the parsing.
3. **Header mapping is DATA, not code** (product owner, 2026-09-07: expect exports to be
   multi-language). A table maps a canonical field key to its header text per language, so adding a
   third language is a data edit. **Validate RU and EN both.**
   **Be honest about the EN set**: the file in hand is RU only. Derive the EN headers from Drivvo's
   documented English export and **record in the code and the doc that the EN mapping is unverified
   against a real English file**. Do not present a derived list as measured.
4. **The currency is ASKED, never guessed.** The wizard offers the **destination car's home
   currency** as the default and lets the user choose another (hard rule 13: a default input, never
   a fact; hard rule 3: money is a pair). A Drivvo file cannot say, so guessing silently is the
   decision this row exists to make - and it is the trap that passes every test.
5. **Write the rule down where import mappings live**, in `docs/SCHEMA.md`: *an importer whose
   format has no currency column asks for it at the wizard, defaulting to the destination car's
   home currency.* This applies to every such importer, not only Drivvo.
6. **[RV.93]'s multi-car mapping does NOT apply.** One car per file. Do not wire the vehicle-group
   step.

## Explicitly out of scope

- **[RV.116]** (the unsupported-column notice). Drivvo's `Водитель`, `Метод оплаты`, `Скидка` and
  the EV columns are exactly its subject, and it is a separate row with its own brief. Do not build
  the notice here; just do not pretend the columns are imported.
- The EV columns as a feature (charge type, start/end %, duration) on a liquid fill.
- Second and third fuel blocks as a feature - a bi-fuel import is not this row.
- Changing what `/import/parse` stores, or its 30-day retention.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 1, 3, 9 (**read the named import exception in full**), 10, 12, 13.
2. `docs/API.md` -> "Import parsing" (**the authority**; changes here are a breaking-change review).
3. `docs/SCHEMA.md` -> import mappings, and Money.
4. `docs/COMPETITORS.md` -> the Drivvo seam (it is a fleet product; that is why the driver column
   exists).

## Checks

Baseline: **backend 411 tests**, **iOS 1625 / 181 suites**, `dotnet build`/`format` 0,
`swift build` 0, `swiftlint` 0 errors **from the repo ROOT**, localization gate 0 (770 keys,
100% RU).

1. `cd backend && dotnet build` - 0; `dotnet test` - 0, report the count (must rise).
2. `cd backend && dotnet format --verify-no-changes` - 0.
3. `cd ios && swift build` - 0; `swift test` - **>= 1625**, never subsetted, report the number.
4. `swiftlint lint` from the **repo ROOT** - 0. Root-relative `excluded:` paths.
5. `xcodegen generate` + the UI suites you touched **by name**; report the observed count and
   **check it is non-zero**.
6. Localization gate - 0, 100% RU, report the key count.

### Tests you must add

- **L1 backend**: the three sections parse from **one file** into their own candidate kinds, with
  the row counts you measured.
- **L1 backend**: a **RU** header set and an **EN** header set map to the same canonical fields.
- **L1 backend**: a comma-decimal row and a dot-decimal row both parse - and the consumption field
  with its `л/100км` suffix does not poison the number.
- **L1 backend**: `"0.0"` odometer maps to **null**, not zero.
- **L1 backend**: the header's repeated `"Цена / л"` does not make the fill read the **third** fuel
  block's price. This is hazard 2 and it needs its own test.
- **L1 backend**: a parsed date equals an expected instant - `2025-08-02 06:55:11`, asserted as a
  value.
- **L1**: an export with no currency column produces candidates whose currency comes from the
  user's answer, and **never a hardcoded default**.
- **L4**: the wizard asks the currency question once and the answer reaches every committed row.

### Vacuous traps, named

- **Parsing only the RU headers** - the file in hand, and the reason decision 3 names EN too.
- **Testing one section and calling the file supported.**
- **Defaulting the currency silently to the car's and never asking** - passes every test, and is
  the decision this row exists to make.
- **Asserting a row count rather than what a row became.**
- Asserting a date parsed "without throwing" rather than asserting its value.
- Swallowing a malformed-line exception so the file reports zero rows and the suite stays green.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "dotnet.*test"` matches **you**. Use
`pgrep -x dotnet` / `pgrep -x xcodebuild`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, whether each test was **run or only written**, and
**what `TextFieldParser` actually did with line 2** (hazard 1) - that measurement is the most useful
thing in your report. Name any closed decision you think is wrong and stop there rather than
absorbing it.
