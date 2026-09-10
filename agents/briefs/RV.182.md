# RV.182 - the catalogue row promises a tank volume the edit screen does not fill

You are working in `/Users/sbelyaev/repos/fuel-counter-ios`. **Write only inside that repo.**
Write code first, explore second. Do not commit; the orchestrator commits after verifying.
**Never move, rename or delete a file you did not create.** **Agents never tick `docs/TASKS.md` and
never commit.**

## The defect, already diagnosed - both halves confirmed in code

Product owner, 2026-09-10: *"when I add a car and pick it up from the list, list has a tank volume
and it's not filled up automatically when I selected it from the list."*

- The suggestion row is a **shared** component ([RV.137],
  `Shared/VehicleCatalogSuggestionsArea.swift:66-69`) and renders `· 71 L` on **both** Add car and
  Vehicle detail.
- **Add car fills it** (`AddVehicleView.swift:121-128`), covered by passing L4s asserting `"71"` and
  the gallons `"13.2"`.
- **Vehicle detail does not**: `VehicleDetailFormState.applyMakeModelSuggestion`
  (`VehicleDetailFormState.swift:81-86`) copies make, model and year and nothing else - pinned
  deliberately by `VehicleEditSuggestionTests.testSuggestionPickStoresOnlyMakeModelYearAndNoCatalogIdentifier`.

**The omission's reasoning is RIGHT and you must not simply undo it.** Hard rule 13: a value the
user set is theirs permanently, and a catalogue pick must never overwrite capacity, fuel kinds,
powertrain or units. **The defect is that the row still PROMISES the number** while the screen
silently declines to use it.

**A wrong theory was already checked and discarded** - do not re-derive it: a locale decimal bug is
impossible here, `VehicleCapacity.formattedText` pins `en_US_POSIX` so the dot round-trips.

## The decision, made by the product owner - implement it, do not re-open it

**Fill it ONLY when the field is empty.** Blank-fields-only. An empty field is not a user value, so
hard rule 13 is **satisfied rather than bent**: a field the user has filled is never touched, and an
empty one takes the catalogue's suggestion.

**Reuse the existing seam.** `ReceiptAttachMerge` (`ios/Sources/TankbookCore/Extraction/ReceiptAttachMerge.swift`)
already applies exactly this rule when a receipt is attached to a typed entry ([PJ.48]) - read it
first. If the shapes genuinely differ, **extract the shared part rather than writing a second
blank-fields-only rule**; two implementations of one policy is how `RV.169`/`RV.170`/`RV.171` were
filed.

## This brief's diagnosis is a hypothesis - confirm it before you change anything

Four of the orchestrator's diagnoses were wrong in one session and an agent caught every one.
Confirm the two halves above by reading the lines, and in particular:

**Decide, and state, which fields are in scope.** The row is about the tank volume the row
ADVERTISES. Does the suggestion row promise anything else - fuel kinds, powertrain, units? **Whatever
the row displays is what it promises**, so the scope is "every value the suggestion row shows",
not "capacity" - check what it actually renders and say what you found. Filling a field the row does
NOT display would be a different defect in the opposite direction.

## What the existing test means, and what to do with it

`testSuggestionPickStoresOnlyMakeModelYearAndNoCatalogIdentifier` will fail on your change, and
**that is correct** - it pins the behaviour this row is deliberately changing. **Do not delete it.**
Narrow it to what still holds - *a pick stores no catalogue identifier, and never overwrites a
NON-EMPTY field* - and write the reason in the test. Its sibling promise (no catalog id for a later
pack to rewrite) is untouched by this row and must stay pinned.

## Explicitly out of scope

- Add car's behaviour. It already fills; do not "unify" the two paths by changing that one.
- The catalogue's contents, and `RV.137`'s picker mechanics.
- Storing a catalogue identifier. The no-catalog-id decision stands (`VehicleDetailView`'s header).

## Docs to read before writing (in order)

1. `CLAUDE.md` **hard rule 13** end to end - it is the rule this row lives inside, and the reason
   blank-fields-only is the answer rather than "just fill it".
2. `docs/SCHEMA.md` -> **Vehicle**, the fields a catalogue pick could touch.
3. `ios/Sources/TankbookCore/Extraction/ReceiptAttachMerge.swift` - the seam to reuse.
4. `docs/DESIGN.md` -> the per-car settings on Vehicle detail.

## Environment axes this crosses

**Units**: the row renders litres or gallons, and the Add-car L4 already asserts both `"71"` and
`"13.2"` - your edit-screen test must cover the same pair, or a gallons user gets a litres number.
**Locale**: a user-facing behaviour change on an existing screen, so **EN and RU screenshots**, dark
theme, with capture lines added ([RV.176] now fails CI on a frame no line produces).

## If this adds a failure path, what makes it visible in production?

None expected - this is a pre-fill decision with no new error. Say so, unless your implementation
adds a branch that silently declines to fill; then it needs the shape-only event that answers *"was
a suggestion declined because the field was already set?"* - **counts only** (hard rule 12).

## Tests you must add

- **L1, and it FAILS TODAY**: picking a catalogue row on Vehicle detail with an **empty** capacity
  fills it. Oracle: the value the suggestion row displays for that catalogue entry.
- **L1, the other half, and it must stay green**: picking a catalogue row with a capacity the user
  already typed leaves it **byte-identical**. This is hard rule 13 and it is the more important of
  the two.
- **L1**: the narrowed `VehicleEditSuggestionTests` still pins "no catalogue identifier is stored".
- **L4 `VehicleDetailUITests`, EN and RU**: pick a row on an empty car, see the volume; pick again on
  a car whose volume the user typed, see it unchanged. **Both units** (`71` and `13.2`).

Every expectation names its ORACLE. Report each suite's observed, **non-zero** count, filtered
**by suite name, not the file's**.

## The mutation you must run - I am naming it, do not choose your own

**Make the blank check always false** - so the pick fills nothing, exactly as it does today - and
show the empty-field L1 goes red. Then restore byte-identical and re-run. Report both outputs
verbatim.

Then **the second mutation, and it matters as much**: make the blank check always TRUE, so a pick
overwrites a user's typed capacity, and show the hard-rule-13 test goes red. A change that only
proves half of a blank-fields-only rule has proven the easy half.

## Vacuous traps, named

- **Deleting `testSuggestionPickStoresOnlyMakeModelYearAndNoCatalogIdentifier`** instead of narrowing
  it. It pins two promises and only one of them is changing.
- Filling a NON-empty field - that is hard rule 13, and the row's own decision text says so.
- A second blank-fields-only implementation beside `ReceiptAttachMerge`.
- Testing litres only.
- Asserting the field is "not empty" after a pick rather than asserting the catalogue's actual value.

## Never stash, move or `git checkout` to get a "clean baseline"

An agent's `git stash` + `mv` loop destroyed three of its own new files on 2026-09-08.

## Never `pgrep -f` for a build process

Your brief is in your command line, so `pgrep -f "xcodebuild.*test"` matches **this agent**. Use
`pgrep -x xcodebuild`. **Never `pkill -f`.**

## `simctl launch` on a running app ignores new arguments - `terminate` first

**You cannot see your own screenshots**: state what you captured, never that it looks right. **Never
pass `SKIP_BUILD=1` after changing the source.**

## Standing checks

As left, `main` is **1899 tests / 227 suites**, **831** localization keys at 100% RU.

1. `cd ios && swift build` - exit 0.
2. `swiftlint lint` from the **repo ROOT** - exit 0 (from `ios/` it exits 2 with ~5000 phantom errors).
3. `cd ios && swift test` - full; report the count. **Run it alone** - on 2026-09-10 four
   `SyncWriteTriggerTests` failed purely from contention with a parallel build.
4. **`xcodebuild ... build` for the app target** ([RV.174]).
5. `xcodegen generate`, then each UI suite touched **by suite name**, non-zero count.
6. Localization gate - exit 0; report keys and RU percentage.
7. `bash scripts/check-screenshot-manifest.sh` - exit 0, after adding your capture lines.

Verify by **exit code** (`echo $?`).

## Report back

Which fields the suggestion row actually displays, and therefore what you filled; how you narrowed
the existing test and the reason you wrote into it; every check with its **exit code observed** and
counts; **both mutations' red-then-green output verbatim**; what you captured in both locales and
both units; and **anything you found and did not fix**.
