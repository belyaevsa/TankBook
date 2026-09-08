# RV.146 - the currency chips are a hardcoded four, and the hint under them is a lie

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** If a file is in your way or a test is
red that is not yours, report it and carry on.

## The defect

Product owner, 2026-09-08, asking for the offer to adapt to where the user is. Three things are
wrong today and they compound:

**1. The list is a literal**, identical for every user in every country
(`ios/App/Sources/ConfirmManual/ManualFillUpSections.swift:16-18`):

```swift
private static let chips: [CurrencyCode] = [.eur, .pln, .czk, CurrencyCode(rawValue: "CHF")!]
```

It **does not include the car's own home currency**, which is why the owner's USD car offers
EUR/PLN/CZK/CHF and not USD - the single most likely choice needs `More…`.

**2. The hint beneath it promises an ordering that does not exist.**
`ManualFillUpCurrencySupport.swift:573-575` renders *"Recent first · a foreign amount converts to %@
automatically"*. **Nothing in that row looks at history** - there is no recency store anywhere in the
codebase. Copy that promises behaviour the code does not have is a hard rule 7 problem in its own
right.

**3. `More…` cannot even reach every chip.** The menu is
`AddVehicleSupport.currencyOptions` (`AddVehicleForm.swift:210-213`):

```swift
[.eur, .usd, .gbp, .pln, .rub, .uah, .kzt, CurrencyCode(rawValue: "BYN")!, .czk, .jpy]
```

**CHF is offered as a chip and is absent from this list**, so a user who taps away from CHF cannot
get back to it. Verify that and fix it here.

## The design is DECIDED - do not re-open it

Ordering happens **on the device**, by the precedence the product owner set for station brands on
2026-09-07 ([RV.115], `docs/API.md` carries its four reasons). Applied to currencies:

1. **The car's home currency** - always present, always first. The common case must never need `More…`.
2. **The user's own history**, most recent first. This is what the existing hint already promises.
3. **The device's region** - `Locale.current.region` -> that country's currency plus its neighbours:
   RU -> RUB, KZT, BYN · KZ -> KZT, RUB, KGS, UZS · a Eurozone country -> EUR, PLN, CZK · and so on.
4. **A `detectedCountry` hint** the server may return **only on an uncacheable response**, if and
   when [RV.115] ships that field. **[RV.115] has NOT shipped** - there is no bundled reference table
   in the codebase to reuse, so you are creating this one. Design it so a `detectedCountry` hint can
   be added later without reshaping it, and do not build the server half.

**The neighbour sets are reference data, not a query and not a network dependency** (hard rule 1):
a table that ships in the bundle and can be corrected by remote config later. **A server endpoint
returning this list would break hard rule 9** - do not add one.

**Hard rule 13 applies**: a region-guessed currency is a default input, never a fact. Once the user
picks a currency, that choice is theirs permanently - no later locale change, catalog update or
curation may reorder over it.

**Cap the row at what fits without truncation** and keep `More…` as the complete list.

**Fix the hint in the same change**: either implement the recency it promises, or stop promising it.
Given that history ordering is step 2 above, implementing it is the expected answer - but if you
implement it, the hint must describe what the code actually does, in EN **and** RU (hard rule 10).

## Explicitly out of scope

- [RV.145]'s symbol/sum work and `LogEntryAmount`. The chips already show "EUR €" via
  `currencyLabel` and that is fine.
- Any server change, any new endpoint, any network call on this path.
- The Garage's home-currency picker and [RV.143]/[RV.140]'s re-homing.

## Docs to read before writing (in order)

1. `docs/SCHEMA.md` -> Money, and Reference data (how curated data is versioned and merged).
2. `docs/SYNC.md` -> Reference data - **the authority for "once a user changes one, that value is
   theirs permanently"**.
3. `docs/DESIGN.md` -> the entry form and chip rows.
4. `CLAUDE.md` hard rules 1, 7, 9, 10, 13.

**Extend the docs in the same change**: the precedence and the neighbour table belong in
`docs/SCHEMA.md` -> Reference data; the corrected hint copy in `docs/ERRORS.md` if it owns that line.

## Checks

Re-measure the baseline yourself and report what you observe. As left, `main` was **1694 tests / 190
suites**, **777** localization keys at 100% RU, `swift build` 0, `swiftlint lint` 0 errors **from the
repo ROOT**.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. (From the root, not `ios/`: the `excluded:`
   paths are root-relative and it reports thousands of phantom errors otherwise.)
3. `cd ios && swift test` - full, never subsetted; report the count.
4. `xcodegen generate`, then these UI suites **by name**, each with its **observed, non-zero** count:
   `TankbookUITests/ConfirmManualUITests`, `TankbookUITests/EditEntryUITests`.
   A filter matching nothing prints "0 tests ... passed" and still exits 0.
5. Localization gate - exit 0; report the key count and RU percentage. New copy is EN **and** RU.
6. Release build only if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), not by skimming output, and report the codes you observed.

### Tests you must add

- **L1**: the car's home currency is offered and is **first**, for every region and every history.
- **L1**: a user with history gets their own most-recent currencies ahead of the region's - **assert
  the ORDER**, not membership.
- **L1**: the region table maps RU, KZ and a Eurozone country to the sets named above, and an
  **unknown** region degrades to the home currency plus a stable default rather than an empty row.
- **L1**: a currency the user picked is not reordered away by a later locale change (hard rule 13).
- **L1**: every chip the row can offer is reachable from `More…` - the test that catches the CHF gap.
- **L3**: the offer is built with **no network call** (hard rule 1).
- **L4**: the chip row in EN and RU at the **largest** accessibility text size. RU currency names run
  longer and the row is already four chips plus `More…`.

### Vacuous traps, named

- Asserting the row **contains** a currency without asserting its **position** - the position is the
  entire request.
- Hardcoding a second literal list for one more country instead of a table.
- A server endpoint or any network fetch for the list (hard rules 1 and 9).
- Implementing region ordering while leaving the "Recent first" hint in place - that keeps the lie.
- A test whose "region" is the machine's actual locale, so it passes only on your machine. Inject the
  region.
- Letting the row truncate at the largest text size, or overflowing off-screen instead of capping.

## Screenshots

The currency chip row, **EN and RU**, **dark** theme, captured **outside** any running test. Commit
as `design/screenshots/RV.146-currency.png` and `RV.146-currency-ru.png`. If you can seed two
different regions cheaply, a second pair showing a different offer is worth more than either alone.
RU: `xcrun simctl launch <device> app.tankbook.Tankbook -AppleLanguages "(ru)" -AppleLocale ru_RU`.
Pass `-homeResetDatabase` alongside any seed. **You cannot see your own screenshots**; state what you
captured and how.

## This brief's reading of the code is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left; verify them, and verify the CHF gap in `currencyOptions`
rather than trusting it.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; how the neighbour table is stored and how a later remote correction would reach
it; what you did about the hint; whether the CHF gap was real; and anything you found and did not fix.

## Never stash, move or `git checkout` to get a "clean baseline"

To show a test fails before the fix: **write the test, run it against the unmodified code, then make
the change.** If the change is already written, prove the test's teeth with a **mutation** - revert
the one line the test is about, run it, restore the line.

**Do not** `git stash`, `git checkout`, or move files out of the tree to get a clean baseline. On
2026-09-08 an agent did exactly that and a bad `mv` loop destroyed three of its own new files; the
same loop would have taken a concurrent session's uncommitted work. Assume you are not alone in this
checkout.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**
