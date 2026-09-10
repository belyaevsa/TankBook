# RV.161 [v1.1] - a scanned fuel receipt drops the station it names

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create** - assume you are not alone in this
checkout. **Another session is actively editing `Spike/ReceiptSpike/fixtures/`** (adding corpus
images). Touch `expected.csv` and the fixtures directory **only** as this brief requires, re-read
before you write, and if a fixture appears or changes under you, report it and carry on.

**Agents never tick `docs/TASKS.md` and never commit.** An agent ticked its own row on 2026-09-10
and the orchestrator reverted it. Leave both task files alone.

## The defect

Every receipt in the corpus prints its station identity plainly, and OCR reads those lines at
confidence 1.00:

- `ООО "Газпромнефть-центр" … Место расчетов АЗС №12089`
- `Circle K Sikupilli teenindusjaam, Tartu mnt 86, Tallinn`

**The fuel path throws it away.** `FuelExtractor` never mentions a station; `ConfirmPrefill` carries
total, liters, price, kind and currency only.

**The service-invoice path already does this**: `InvoiceSplitter.detectVendor`
(`ios/Sources/TankbookCore/Extraction/InvoiceSplitter.swift:126-142`) takes the first line that has
letters, is not a date, is not a total/VAT/payment line, has at most six tokens and at most one
numeric token, and is not on `vendorDenyList`. Fuel receipts got nothing.

Until [RV.156] shipped there was nowhere to put the answer. Now there is, and
`Repository.createStation(named:)` (`Persistence/Repository+StationCreate.swift:30`) makes a scanned
name and a typed one resolve to the **same** station, because the id is a deterministic function of
the name.

## The product decision is MADE - do not relitigate it

Product owner, 2026-09-09: **save the BRAND and display it; when a SITE is identifiable, save it
next to the brand together with the geo; the user can change either.**

`Station` already carries `brand`, `name` and `location`, so **this needs no new shape**:

- the **brand** is what a Log row and a picker show;
- the **site** is what distinguishes two forecourts of the same chain;
- the **geo** is what [PJ.19]'s ranking and [RV.150]'s stamp already consume.

## This brief's reading is a hypothesis - confirm it before you change anything

Line numbers were read on the tree as left. Confirm `FuelExtractor` really carries no station and
that `detectVendor` is still shaped as described.

## What to build

**Reuse `detectVendor`'s heuristic rather than inventing a second one.** If the fuel case genuinely
needs different rules, **extract the shared part and say exactly what differs and why** - two
independent "find the company name" rules will drift, and the drift will be invisible.

**Resolve through [RV.156]'s resolver, never a fresh UUID.** A random id manufactures precisely the
duplicates [RV.115] exists to clean up.

**Everything extracted is a default input the user edits** (hard rule 13), at the moment it is
offered and again afterwards in the Garage. A wrong station name is a domain value written onto a
**synced** entity, so **it must never be written silently**: it reaches the entry only through the
prefill the user can see and change.

**Do not confuse the two levels.** Treating the brand line as the site gives a new station every
visit; treating the site as the brand gives one station for a whole chain. Both are wrong and the
row names them.

## The corpus, and the oracle problem - read this before writing a single expected value

Add a `station` column to `Spike/ReceiptSpike/fixtures/receipts/expected.csv` (today:
`filename,liters,unitPrice,total,fuelKind,currency`, 60 fixtures). Today the corpus **cannot say**
whether extraction gets the station right.

**Where the ground truth comes from, and where it must NOT:**

- **NOT from your extractor's output.** Writing the expected value by running your own code and
  pasting the result is circular, scores 100%, and proves nothing. The row names this trap.
- **The filenames are a human-written, image-derived oracle** and are the best source you have:
  `receipt-058-circlek-peetri-98e0-pump7-4353l-ee.jpg`,
  `receipt-060-gazpromneft-azs12089-95-fuelcard-pair-ru.jpeg`. The product owner named these while
  looking at the receipts, before any station extractor existed.
- **The raw OCR text is a legitimate cross-check** (`swift run ReceiptSpike <folder> --dump-text`) -
  it is the extractor's *input*, not its output. Use it to confirm what the receipt actually prints.

**Where the filename and the OCR text disagree, say so in your report and leave that fixture's
expected value blank rather than guessing.** A wrong ground truth is worse than a missing one: it
freezes a defect as the standard, which is exactly what `MoneyBackfillServiceTests` did before
[RV.147] removed it.

**Re-measure and re-record every mark this moves.** The L5 gate (`corpusScoresDoNotRegress`,
`everyClassIsScored`) will see a new class; report the before and after numbers.

## Explicitly out of scope

- **[RV.115]** station normalisation and merging - two spellings of one forecourt is its problem.
- **[PJ.19]**'s ranking rules and [RV.150]'s stamp - they consume what you write; do not change them.
- Pump-display capture (`pump/`) - that mode ships off (hard rule 15's re-measurement).
- The service/invoice path you are borrowing from.

## Docs to read before writing (in order)

1. `docs/EXTRACTION.md` - the recognition pipeline, role assignment and the named failure modes.
   **The authority**; extend it in the same change with the station role and its fixtures.
2. `docs/SCHEMA.md` -> **Station** (`brand`, `name`, `location`) and hard rule 13's permanence rule -
   once a user changes a value it is theirs, and no re-scan may overwrite it.
3. `Spike/ReceiptSpike/README.md` - the accuracy-gate workflow and how a mark is recorded.
4. `CLAUDE.md` hard rules 12 (never log a domain value), 13, 15.

## Environment axes this crosses

**Locale** - the Confirm pre-fill is user-facing; EN and RU, gate at 100%. **Screenshots: EN and RU**
of the Confirm sheet showing the extracted brand as an **editable** pre-fill. No offline path, no
signed-out difference. Release build if you touch a `#if DEBUG` seam.

## If this adds a failure path, what makes it visible in production?

Extraction that finds nothing is the ordinary case, not a failure - do not log it as one. **Hard rule
12 is the sharp edge here**: a station name, brand or address is a **domain value and must never be
logged**, at any level, in any build. Counts and confidence are shape and may be. The row requires a
**source-scan gate** proving it, as [PJ.19] used - build it, and make it fail on a deliberate
violation before you trust it.

## Tests you must add

- **L1, and it FAILS TODAY**: the brand is extracted from each corpus receipt's own OCR text.
  **Assert the VALUE, not that something was found.** **Oracle**: the filename's station token,
  cross-checked against the OCR dump.
- **L1**: a receipt with **no** identifiable station yields `nil` and **nothing is written**.
- **L1**: a scanned station and a **typed** one with the same name resolve to **one** station id -
  [RV.156]'s convergence, now across two entry paths.
- **L1**: nothing extracted is written without passing through the prefill the user can edit -
  assert the write path, not the UI.
- **L1**: **no station name, brand or address is ever logged** - the source-scan gate, and **prove
  its teeth** by adding a deliberate violation, watching it fail, and reverting.
- **L4**: the Confirm sheet shows the extracted brand as an **editable** pre-fill, EN and RU.
- **L5**: the receipts corpus scores the new column and the mark is recorded.

Report the observed, **non-zero** count for every suite, and **run app-target iOS suites separately**
- a combined `xcodebuild` invocation silently dropped a `TankbookTests` filter on 2026-09-10.

## The mutation you must run - I am naming it, do not choose your own

**Make the extractor return the FIRST OCR line unconditionally** (skip the heuristic's guards, keep
the plumbing). The L1 value assertions **must go red naming the wrong station**, and the corpus mark
must drop. Then restore and re-run. Report both outputs verbatim.

That is the mutation because "a station was found" is the assertion this row most easily degrades
into, and it passes on garbage. The claim is *which* station.

## Vacuous traps, named

- **Asserting a station was found without asserting WHICH.**
- Writing the extracted station straight onto the entry without the user seeing it (hard rule 13).
- **A second minting rule or a random UUID**, which manufactures [RV.115]'s duplicates.
- Treating the brand line as the site, or the site as the brand.
- **Scoring the new column against ground truth written from your own output.**
- Logging a station name to "help debug" it.

## Never stash, move or `git checkout` to get a "clean baseline"

Write the test, run it against the unmodified code, then make the change. **Do not** `git stash`,
`git checkout`, or move files out of the tree: an agent did that on 2026-09-08 and a bad `mv` loop
destroyed three of its own new files.

## Never `pgrep -f` for a build process

Your brief is part of your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**.
Use `pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Check
what is BEHIND your subject** - on 2026-09-10 a correct toast was photographed over a screen no user
can reach, and it looked like a successful capture.

## Standing checks

Re-measure the baseline yourself and report what you observe. As left, `main` is **1857 tests / 219
suites**, **829** localization keys at 100% RU, backend **451**.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0. From the root, **not** `ios/`: the `excluded:`
   paths are root-relative and from `ios/` it exits 2 with ~5000 phantom errors.
3. `cd ios && swift test` - full, never subsetted; report the count **and the corpus marks**.
4. `cd Spike/ReceiptSpike && swift test` - the harness's own suite; report it.
5. **`xcodebuild ... build` for the app target** - `swift build` compiles only the SwiftPM package
   ([RV.174], 2026-09-10).
6. `xcodegen generate`, then the UI suite you touched by name with an observed, **non-zero** count.
7. Localization gate - exit 0; report keys and RU percentage.
8. Release build if you touch a `#if DEBUG` seam. Say which applies.

Verify by **exit code** (`echo $?`), and report the codes you observed.

## Report back

Every check with the **exit code you observed** and the observed counts; whether each test was **run
or only written**; **the named mutation's red-then-green output, verbatim**; **the corpus mark before
and after**; **every fixture where the filename and the OCR text disagreed**, and what you left
blank; whether the fuel case needed different rules from `detectVendor` and exactly what differs; and
**anything you found and did not fix**.
