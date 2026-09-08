# RV.116 - an import must say what it is NOT bringing in

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.

## The promise, in the product owner's own words (2026-09-07)

> "worth to say for this program, what data we don't support (as a notification), such as driver
> and other fields"

Today the parser reads what it understands and **the rest evaporates silently**. A fleet user
importing a driver-per-row history discovers only later that the column they care about is gone.

**This is deliberately NOT hard rule 8.** Nothing is deleted - the source file is untouched and the
rows the app keeps are complete. It is a **completeness promise**: an import that quietly narrows
the data is a migration a user cannot trust. Do not file it as a data-loss bug or reach for
tombstones.

## Design questions ALREADY CLOSED - do not reopen

These are the decisions the row leaves open and I am closing them. Implement them as written; if you
believe one is wrong, say so and stop rather than quietly choosing differently.

1. **The split between declaration and count.** The *names* are static data per format; the
   *counts* are per-file and can only come from a parse. So:
   - `GET /import/formats` -> each format declares its **unsupported field keys** (a stable string
     array). This is the "make it data, not code" half - a new parser cannot forget to declare, and
     the client hardcodes no per-format copy.
   - `POST /import/parse` -> the response carries, for that file, **each declared key that had at
     least one non-empty cell, with its row count**.
2. **Stable KEYS on the wire, localized text on the device.** The server sends
   `["driver", "paymentMethod", "discount", ...]`, never a display string, because hard rule 10 puts
   every user-facing string in the String Catalog with EN and RU. The client maps a key to a
   localized label. **An unknown key falls back to rendering the key's server-supplied English
   label**, so a format added server-side still says something useful on an older client - that
   fallback is the whole reason the format registry also carries a label per key.
3. **Zero-count columns are NOT mentioned.** A column empty in every row of *this* file is omitted.
   The row's author states this preference and the reason is sound: "a notice about nothing is
   noise", and burying the one column that matters is the failure mode. **Assert this decision in a
   test** - the row explicitly asks for the decision to be pinned either way.
4. **Where it goes: `ios/App/Sources/Import/ImportPreviewView.swift`.** That is the screen titled
   **"Review import"** (`:22`) and it is the gate before the commit - `ImportReviewView` is the
   per-row screen that comes *after* it in the wizard (`ImportWizardView.swift:153` `.preview`,
   `:166` `.review`). Putting the notice on the per-row screen is the obvious wrong choice.
5. **It is a card in the scroll content, not a fixed region.** Follow the existing
   `outOfScopeCard(message)` precedent at `ImportPreviewView.swift:52-54` - same placement, same
   non-blocking shape. **Do not use `safeAreaInset`**: RV.84 fixed exactly that mistake on the
   import parse-error card, because that region does not scroll and the content clipped in RU.
6. **Never blocking.** The primary Import action is untouched. This is a notice, not an error and
   not a dialog. Per hard rule 7 it still names what to do instead - the copy below carries that.

## Hard rules this touches, and why none of them block you

- **Rule 9** - the server reads domain meaning here. That is already licensed: `/import/parse` is
  hard rule 9's **named exception**, and counting non-empty cells in a column is squarely inside the
  parse. You are not adding a new domain endpoint. Do not stop to escalate this.
- **Rule 12** - never log domain values. Field *names*, *keys* and *counts* are loggable; a driver's
  name is not. Log shape only.
- **Rule 10** - EN and RU from day one, full localized phrases, never concatenation.

## What to build

### A. Backend: declare the unsupported fields

`backend/src/Tankbook.Api/Import/ImportFormats.cs` - `ImportFormatInfo` gains the declaration.
Model it as a record so a key carries its fallback English label:

```csharp
public sealed record UnsupportedField(string Key, string Label);
```

and `ImportFormatInfo` gains `IReadOnlyList<UnsupportedField> UnsupportedFields`.

For the one format that exists today (`mfm`), declare the columns MFM carries that Tankbook has no
home for. **Read `MfmParser.cs` and derive this from what the parser actually ignores** - do not
invent a list, and do not copy Drivvo's columns (that format does not exist yet; RV.113 adds it).

### B. Backend: count them per file

The parse computes, for the uploaded file, which declared keys had **at least one non-empty cell**
and how many rows carried a value. Add to `ImportParseResponse`
(`backend/src/Tankbook.Api/Import/ImportModels.cs:102-110`) a field carrying
`{key, rowCount}` pairs, **omitting every key whose count is zero** (closed decision 3).

`ImportParseRow` (the stored metadata row, `:88-99`) holds **counts only, never values** - its
existing comment says so. If you persist anything here, keep to that.

### C. iOS: the model and the notice

- `ios/Sources/TankbookCore/Import/ImportModels.swift:12-27` - `ImportFormat` gains the declared
  fields; the parse response type gains the counts. Both `Codable`, matching the wire names.
- `ios/App/Sources/Import/ImportPreviewView.swift` - a card in the `ScrollView`'s `VStack`
  (closed decisions 4 and 5), shown only when the count list is non-empty. Accessibility identifier
  `importPreviewUnsupportedFields`.
- Copy, as **one full localized phrase per language** (EN + RU in `Localizable.xcstrings`). The
  count is what makes it actionable, so it is in the sentence, not implied:
  - Title: EN `"Not imported"` / RU `"Не импортируется"`
  - Per row: the localized field label and its count, e.g. EN `"Driver - 250 rows"` /
    RU `"Водитель - 250 строк"`. **Use a proper plural rule for RU** (строка/строки/строк) via the
    String Catalog's plural variations - Russian has three forms and 250 takes a different one than
    2 or 21. This is the half a naive `"%d строк"` gets wrong.
  - The next step (hard rule 7): EN `"Your file stays on your phone if you need these columns."` /
    RU with equivalent meaning, not a word-for-word calque.

### D. The doc

`docs/API.md` is the authority for the HTTP contract and **changes here are a breaking-change
review**. Update the "Import parsing" section for both `GET /import/formats` and
`POST /import/parse` in the same change - the new fields, the zero-count omission rule, and the
keys-not-strings decision with its reason. `CLAUDE.md` says keeping the docs reconciled is part of
every task's definition of done.

## Explicitly out of scope

- **RV.113** (the Drivvo importer). Do not add a `drivvo` format, do not read
  `Spike/ImportFixtures/drivvo/`.
- Making any currently-unsupported column supported. This row reports the gap; it does not close it.
- The per-row review screen, the commit path, or anything after the gate.
- Changing what `/import/parse` stores or its 30-day retention.

## Docs to read before writing (in order)

1. `CLAUDE.md` - hard rules 7, 9 (**read the named import exception in full**), 10, 12, 13.
2. `docs/API.md` -> "Import parsing" (**the authority for this task**).
3. `docs/ERRORS.md` -> the severity vocabulary, to confirm this is a **notice**, not a warning or an
   error, and that it needs no dismissal state.
4. `docs/JOURNEYS.md` -> F6a, the failure journey this sits in.

## Checks

Baseline on the tree you are handed: **iOS 1625 tests / 181 suites**, **backend 411**, `swift build`
0, `swiftlint` 0 errors **from the repo ROOT**, `dotnet build`/`format` 0, localization gate 0
(770 keys, 100% RU).

1. `cd backend && dotnet build` - 0; `dotnet test` - 0, report the observed count (must rise).
2. `cd backend && dotnet format --verify-no-changes` - 0.
3. `cd ios && swift build` - 0.
4. `swiftlint lint` from the **repo root** - exit 0. Root-relative `excluded:` paths; running it
   from `ios/` gives a wrong answer.
5. `cd ios && swift test` - full suite, **never subsetted**, **>= 1625** and report the number.
6. `xcodegen generate`, then the UI suite you touched **by name**:
   `-only-testing:TankbookUITests/ImportCarsUITests` plus any import suite your change reaches.
   Report the observed count and **check it is non-zero** - a filter matching nothing prints
   "0 tests ... passed".
7. Localization gate - 0, 100% RU, and report the new key count.
8. Release build **not required** unless you touch a `#if DEBUG` seam. Say which applies.

### Tests you must add

- **L1 backend**: a format declares its unsupported fields; a file with values in two of them
  reports exactly those two **with their row counts**; a column empty in every row is **absent**
  from the response (closed decision 3, asserted).
- **L1 backend**: the counts are row counts of **non-empty** cells, not total rows - a column with
  3 values in a 250-row file reports **3**.
- **L1 iOS**: an unknown key renders the server's fallback label rather than the raw key or an
  empty string.
- **L1 iOS**: the RU plural form is correct for 1, 2, 5 and 250 rows.
- **L4**: the gate shows the notice with its counts, and the primary Import action is **still
  enabled and still works** with the notice present.

### Vacuous traps, named

- **Hardcoding the copy in the client per format** - the thing that rots, and the reason decision 1
  puts the declaration on the server.
- **Listing every unsupported column including the empty ones** - buries the one that matters.
- **Asserting the notice exists without asserting the COUNT** - the count is what makes it
  actionable, and a notice with a wrong number is worse than none.
- **Blocking the import on it.**
- Asserting a localization key exists rather than what it renders.
- A single RU plural form for every number.

## Screenshots

The gate with the notice visible, dark theme, EN and RU:
`design/screenshots/RV.116-import-preview.png` and `RV.116-import-preview-ru.png`.

- Seeds are idempotent and silently do nothing on a populated database - pass the reset flag
  alongside the seed.
- RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
- Take them **outside** a test run - `simctl` and `xcodebuild test` fight over the device.
- **OCR your own capture and read the text back** before reporting it. A committed screenshot has
  twice shown the opposite of the row's claim because it was taken before the screen settled.
- RU runs 20-30% longer and short strings expand worst. If a label truncates, fix the layout - do
  not shorten the Russian.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **you**. Use
`pgrep -x xcodebuild` / `pgrep -x dotnet`. Never `pkill -f`.

## Report back

Every check with the **exit code you observed**, and whether each test was **run or only written**.
Name any closed decision above you think is wrong, and stop there rather than absorbing it - four
of the orchestrator's diagnoses have been wrong and every one was caught by an agent pushing back.

---

## AMENDED 2026-09-08: drivvo is now IN scope, and it is the sharper case

The out-of-scope line above excluded `drivvo` because [RV.113] had not landed when this brief was
written. **[RV.113] has since landed** (`01ae3fa`), and a previous run of this brief found the
consequence before it was killed - confirm it yourself, then act on it:

`DrivvoParser.BuildIndex` looks up **known headers only**, so a column whose header is not in the
mapping is never read and its data is **silently dropped**. On the real export that is `Водитель`
(the driver - Drivvo's whole fleet positioning), `Метод оплаты`, `Тип расхода` and `Скидка`.

So the format this row exists to describe honestly is the one that drops the most, and it now
exists. **Declare `drivvo`'s unsupported fields alongside `mfm`'s.** Everything else in this brief
is unchanged - the same declaration-plus-count split, the same stable keys with localized labels on
the device, the same zero-count omission rule.

Still out of scope: changing `DrivvoParser` to start importing any of those columns. This row
reports the gap; it does not close it.

**Baselines have moved** - `main` is green at **1644 tests / 184 suites**, backend **423**, **774**
localization keys. Re-measure and report what you observe.
